# artcraft-personal-server

> **⚠️ 상태 안내 (먼저 읽기)**
> - ArtCraft 백엔드(`storyteller-web`)를 개인 서버에 올리기 위한 **비공식 커뮤니티 템플릿**임. ArtCraft/Storyteller와 무관하며 공식 지원 없음.
> - **런타임 미검증**: 템플릿 작성자는 이 구성을 실제로 빌드하거나 부팅해 본 적이 없음. 정적 검사와 가짜 `docker` 로직 테스트만 거침.
> - **목표 (런타임 미검증)**: 웹앱으로 회원가입/로그인, 내 파일 목록/보기, 업로드한 이미지 표시. 업스트림에 작은 패치 2개를 빌드 시 적용함.
> - **지원 안 됨**: 이미지/비디오 생성, 결제(Stripe), 이메일, 검색, 썸네일, 백그라운드 워커.
> - 호스팅된 ArtCraft를 대체하지 않음. "설치하면 바로 된다"는 보장 없음.

[English summary](#english-summary) · 라이선스: 템플릿 파일은 MIT, ArtCraft 코드는 ArtCraft License ([LICENSE-NOTICE.md](LICENSE-NOTICE.md))

## 이게 뭔가

- 업스트림 [storytold/artcraft-services](https://github.com/storytold/artcraft-services)를 `UPSTREAM.lock`에 고정된 커밋(`d950e57352a1b28c9296f69f8ae4eff43877de21`)으로 **빌드할 때 받아서** 빌드하는 Docker Compose 구성.
- 이 저장소에는 ArtCraft 소스, SQL, 설정 파일이 **들어있지 않음** (재배포 안 함). 예외: `patches/`의 작은 diff 2개 (ArtCraft License, MIT 아님).
- 업스트림 웹앱(`frontend/apps/artcraft-webapp`)도 같은 커밋에서 빌드해서 nginx로 서빙함.
- 데스크톱 앱은 별도: [storytold/artcraft](https://github.com/storytold/artcraft). 설정 파일로 localhost API를 가리킬 수 있지만 미검증 ([상태 문서](docs/ko/status.md)).
- 모든 공개 포트는 `127.0.0.1`에만 바인딩됨. MySQL/Redis/Elasticsearch는 호스트에 열리지 않음.

| 서비스 | 이미지 | 역할 | 호스트 노출 |
| --- | --- | --- | --- |
| mysql | `mysql:8.4.7` | 계정, 미디어 메타데이터, 작업 | 없음 |
| redis | `redis:7.4.7` | 캐시, 레이트리밋, 진행상황 | 없음 |
| elasticsearch | `elasticsearch:8.19.4` | 검색 인덱스 (single-node) | 없음 |
| minio | 공식 소스 `9e49d5e7`에서 빌드 | S3 호환 스토리지 | `127.0.0.1:9000`, 콘솔 `127.0.0.1:9001` |
| minio-init | 공식 소스 `7394ce0d`에서 빌드 | 버킷 생성 (1회성) | 없음 |
| migrate | 로컬 빌드 | 마이그레이션 + 시스템 역할 시드 (1회성) | 없음 |
| es-init | 로컬 빌드 | ES 인덱스 생성 (1회성) | 없음 |
| storyteller-web | 로컬 빌드 (패치 적용) | HTTP API, `GET /_status` | `127.0.0.1:12345` |
| webapp | 로컬 빌드 (`node:22.23.3-bookworm-slim` → `nginx:1.30.5-alpine`) | 웹앱 + 같은 오리진 프록시 (`/v1/` → API, `/media/` → 공개 버킷) | `127.0.0.1:4201` |

## 빠른 시작 (Docker가 이미 있는 경우)

```bash
git clone https://github.com/<your-account>/artcraft-personal-server.git
cd artcraft-personal-server
scripts/generate-secrets.sh      # .env + config/providers.env 생성 (권한 600, 덮어쓰지 않음)
docker compose build             # 첫 빌드는 오래 걸림 (추정 40~120분, RAM 16GB 권장)
docker compose up -d
scripts/status.sh                # http://127.0.0.1:12345/_status 확인
scripts/verify-storage-policy.sh # MinIO 공개 범위 확인
# 브라우저: http://localhost:4201  (원격 서버면 SSH 터널, docs/ko/access.md)
```

## 문서 (한국어)

| 문서 | 내용 |
| --- | --- |
| [사전요건 & Ubuntu 24.04 VPS 설치](docs/ko/install.md) | 하드웨어, Docker 공식 저장소 설치, 사용자/SSH/ufw, 빌드/실행 |
| [접근 방법](docs/ko/access.md) | 로컬 직접 접속, SSH 터널, 공개 노출 금지 이유 (Docker는 ufw를 우회함) |
| [백업 / 복구](docs/ko/backup-restore.md) | 포함/제외 항목, 보존기간(옵트인), 오프사이트 복사, 복구 실패 시 기본 동작 |
| [업데이트 / 제거](docs/ko/update-uninstall.md) | 고정 커밋 올리기, 템플릿 업데이트, 롤백, `down` vs `down -v` |
| [기능 지원 & 패치 & 검증 상태 & 미디어/CDN](docs/ko/status.md) | 무엇이 되고 안 되는지, 패치 내용, 로그인/목록/보기 경로, 데스크톱, 업스트림 소스 근거 |
| [문제 해결](docs/ko/troubleshooting.md) | ES `vm.max_map_count`, 빌드 OOM, 포트 충돌 |

## 설정 파일

| 파일 | git 추적 | 내용 |
| --- | --- | --- |
| `.env` | ❌ | 랜덤 비밀번호, `COOKIE_SECRET`, `SORT_KEY_SECRET`, 포트, `AUTO_SEED_ROLES`, (선택) `BACKUP_RETENTION_DAYS` |
| `config/providers.env` | ❌ | Resend / 생성 제공자 / Stripe 키. 기본 전부 빈 값 |
| `.env.example`, `config/providers.env.example` | ✅ | 변수 이름과 설명만 |
| `config/storyteller-web.env` | ✅ | 비밀 아닌 설정만. 각 변수 옆에 업스트림 소스 위치 표기 |

실제 키는 `config/providers.env`에만 넣고 절대 커밋하지 말 것. 공개 전에는 `scripts/secret-scan.sh`를 실행할 것 (CI는 gitleaks도 실행).

## English summary

Unofficial, community-maintained Docker Compose template for running the ArtCraft backend (`storyteller-web`) on your own machine or server, for private personal use only. Not affiliated with ArtCraft/Storyteller. **Never built or booted by the author** (static checks only). Goal (runtime-unverified): sign up / log in, list and view your files, and display uploaded images through the upstream web app, using two small build-time patches (media CDN base URL override; build-time API/CDN origins) that keep upstream defaults when unset. Generation, billing, email, search, thumbnails and background workers are not supported. Upstream source is fetched at build time from the pinned commit and is not redistributed here. Template files are MIT; ArtCraft code and the files in `patches/` are under the ArtCraft License (fair source: personal use, no selling, no competing products, keep community/donation/paid-model links, no name/logo for promotion). All ports bind to 127.0.0.1; use an SSH tunnel or VPN for remote access, never public ports. Docs are in Korean under `docs/ko/`.
