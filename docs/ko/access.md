# 접근 방법

기본 구성은 **서버 자기 자신(127.0.0.1)에서만** 접속 가능함.

| 대상 | 주소 |
| --- | --- |
| **웹앱 (브라우저는 이 주소 사용)** | **`http://localhost:4201`** (같은 오리진에서 `/v1/` = API, `/media/` = 공개 미디어) |
| API 직접 | `http://127.0.0.1:12345` (헬스체크 `/_status`, 데스크톱 앱/스크립트용) |
| MinIO 콘솔 | `http://127.0.0.1:9001` (로그인: `.env`의 `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`) |
| MinIO S3 API | `http://127.0.0.1:9000` |

## 같은 컴퓨터에서 실행한 경우

브라우저에서 `http://localhost:4201`을 열면 됨. **`127.0.0.1`이 아니라 `localhost`로 열 것**
(미디어 링크와 쿠키가 `localhost` 기준, [기능 문서](status.md#회원가입--로그인)).

## VPS에서 실행하고 노트북에서 접속 (SSH 터널, 권장)

노트북에서:

```bash
ssh -N -L 4201:127.0.0.1:4201 -L 12345:127.0.0.1:12345 -L 9001:127.0.0.1:9001 deploy@<your-server>
```

연결을 유지한 채로 노트북 브라우저에서 **`http://localhost:4201`** (웹앱), `http://localhost:9001` (MinIO 콘솔)에 접속.

- 노트북 쪽 포트(앞쪽 숫자)는 **서버의 `WEBAPP_ORIGIN`과 같아야 함** (기본 4201). 미디어 링크와 웹앱 빌드에 이 오리진이 들어가기 때문.
  노트북에서 4201을 못 쓰면 서버 `.env`의 `WEBAPP_ORIGIN`을 예: `http://localhost:14201`로 바꾸고
  `docker compose build webapp && docker compose up -d` 후 `-L 14201:127.0.0.1:4201`로 연결.
- 데스크톱 앱을 쓸 경우 `12345`도 터널에 포함 ([데스크톱 앱](status.md#데스크톱-앱)).

## 하지 말 것

- `docker-compose.yml`의 `127.0.0.1:` 바인딩을 지우거나 `0.0.0.0:`으로 바꾸지 말 것.
- `ufw allow 12345` 같은 규칙을 추가하지 말 것. **Docker로 게시한 포트는 ufw를 우회함**
  ([Docker and ufw](https://docs.docker.com/engine/network/packet-filtering-firewalls/#docker-and-ufw)) → 방화벽을 믿고 바인딩을 넓히면 인터넷에 그대로 노출될 수 있음.
- 이 구성은 공개 서비스용 보안 검토를 받지 않았음 (development 모드, `COOKIE_SECURE=false`, Elasticsearch 보안 끔).

원격에서 계속 써야 한다면 SSH 터널이나 WireGuard/Tailscale 같은 **VPN**을 쓰고, 공개 포트는 열지 말 것.
