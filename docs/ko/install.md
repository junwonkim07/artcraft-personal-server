# 사전요건 & Ubuntu 24.04 VPS 설치

> Ubuntu 24.04, 4 vCPU, RAM 8GB + 스왑 8GB VPS에서 핵심 배포 흐름을 검증했습니다. 아래 권장 용량은 여유를 둔 추정치이며, 완료 범위는 [검증 상태](status.md)를 확인하세요.

호스팅 업체를 선택하려면 [배포 옵션](../deployment.md)을 먼저 보세요. `scripts/deploy.sh` 메뉴와 Vultr/Hetzner Cloud용 cloud-init 생성기를 제공합니다. Hetzner Auction은 Ubuntu 설치 후 같은 설치기를 사용하며, Vercel/Neon은 아직 전체 스택 설치 대상이 아닙니다.

## 사전요건

| 항목 | 권장 (추정) | 비고 |
| --- | --- | --- |
| CPU | 4코어 이상 | Rust 릴리스 빌드가 무거움 |
| RAM | **16GB 권장, 최소 8GB + 스왑** | 웹앱 빌드에 업스트림이 Node heap 8GB 한도를 씀 (`frontend/apps/artcraft-webapp/script/netlify_build.sh:9`), Rust 빌드 + ES + MySQL. 부족하면 스왑 추가 |
| 디스크 | **40GB 이상 여유** | Rust 빌드 캐시, `node_modules`, 이미지가 큼 |
| OS | Ubuntu 24.04 LTS (64-bit) | 다른 Linux/macOS도 Docker만 있으면 가능하지만 이 문서는 Ubuntu 기준 |
| Docker | Docker Engine + Compose 플러그인 v2.20 이상 | `docker compose up --wait` 사용 |
| 도구 | `git`, `openssl`, `curl` | |
| 네트워크 | 외부로 나가는 접속: GitHub, Docker Hub, crates.io, static.rust-lang.org, registry.npmjs.org | 빌드 중 업스트림 소스, 이미지, Rust 크레이트, npm 패키지 다운로드 |

## 1. 사용자 / SSH / 방화벽

root로 접속한 상태에서:

```bash
adduser deploy                 # 이름은 자유
usermod -aG sudo deploy
# 내 노트북의 공개키를 등록 (노트북에서: ssh-copy-id deploy@<your-server> 도 가능)
mkdir -p /home/deploy/.ssh && cp ~/.ssh/authorized_keys /home/deploy/.ssh/
chown -R deploy:deploy /home/deploy/.ssh && chmod 700 /home/deploy/.ssh && chmod 600 /home/deploy/.ssh/authorized_keys
```

새 터미널에서 `ssh deploy@<your-server>` 키 로그인이 되는 걸 **확인한 뒤에**, 비밀번호 로그인과 root 로그인을 끔:

```bash
sudo tee /etc/ssh/sshd_config.d/00-hardening.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T | grep -E "^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin) "
```

방화벽은 **SSH만** 허용함. `12345`, `9000`, `9001`은 **열지 말 것**.

```bash
sudo ufw allow OpenSSH
sudo ufw enable
sudo ufw status
```

> Docker로 게시한 포트는 ufw 규칙을 **우회함** ([Docker 문서](https://docs.docker.com/engine/network/packet-filtering-firewalls/#docker-and-ufw)).
> 그래서 이 템플릿은 모든 포트를 `127.0.0.1`에만 바인딩함. compose 파일의 `127.0.0.1:`을 지우면 ufw와 상관없이 인터넷에 열릴 수 있음.

## 2. Docker Engine 설치 (공식 apt 저장소)

**반드시 최신 공식 문서를 기준으로 할 것:** https://docs.docker.com/engine/install/ubuntu/
아래는 작성 시점(2026-10) 공식 문서의 절차를 옮긴 것임.

```bash
# 충돌하는 비공식 패키지 제거
sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc | cut -f1)

# Docker 공식 GPG 키와 저장소 추가
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update

# 설치 및 확인
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker run hello-world
docker compose version
```

`sudo` 없이 쓰려면 ([post-install 문서](https://docs.docker.com/engine/install/linux-postinstall/)):

```bash
sudo usermod -aG docker "$USER"   # 다시 로그인해야 적용
```

> 주의: `docker` 그룹은 사실상 **root 권한**과 같음. 신뢰하는 사용자만 넣을 것.

## 3. 스왑 (RAM 16GB 미만이면 권장, 추정치)

```bash
sudo fallocate -l 8G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 4. Elasticsearch 커널 설정

```bash
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-elasticsearch.conf
sudo sysctl --system
```

## 5. 템플릿 설치 / 빌드 / 실행

```bash
git clone https://github.com/junwonkim07/artcraft-personal-server.git
cd artcraft-personal-server

scripts/generate-secrets.sh        # .env, config/providers.env 생성 (권한 600). 비밀값은 출력되지 않음
scripts/fetch-upstream.sh          # (선택) 고정 커밋을 ./upstream에 받아서 직접 검토. 빌드에는 필요 없음

docker compose build               # 검증 VPS에서 약 30분, 사양/네트워크에 따라 달라짐
docker compose up -d               # mysql/redis/es/minio -> 버킷+정책 -> 마이그레이션+역할 시드 -> ES 인덱스 -> API -> webapp
docker compose ps
scripts/status.sh                  # GET http://127.0.0.1:12345/_status
scripts/verify-storage-policy.sh   # MinIO 익명 접근 범위 확인 (공개 media/만 읽기)
```

`docker compose logs -f migrate storyteller-web webapp`로 진행 상황을 볼 수 있음.
빌드 로그의 `patches applied:` 줄에서 적용된 패치를 확인할 수 있음 (`APPLY_PATCHES=false`면 원본 업스트림).

그 다음 [접근 방법](access.md)대로 브라우저에서 `http://localhost:4201` → 회원가입(`/signup`) → 로그인 순서로 시도.
지원 기능과 실제 확인 범위는 [검증 상태](status.md)를 확인하세요. 실패하면 비밀값을 지운 로그와 함께 이슈로 남겨 주세요.

다음: [접근 방법](access.md)
