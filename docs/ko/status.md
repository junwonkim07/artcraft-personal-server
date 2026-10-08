# 기능 지원 & 검증 상태 & 미디어/CDN

모든 근거는 업스트림 고정 커밋 `d950e57352a1b28c9296f69f8ae4eff43877de21` 기준 경로:줄 번호임 (코드는 복사하지 않음).
`storyteller_web/`는 `crates/service/web/storyteller_web/`, `frontend/`는 업스트림 `frontend/`를 뜻함.

> **아직 아무것도 런타임으로 확인되지 않았음.** 아래 "목표"는 설계상 의도이고, 로그인/목록/보기가 실제로 동작한다는 증거는 없음.

## 기능 지원

| 기능 | 상태 | 근거 / 이유 |
| --- | --- | --- |
| API 부팅, `/_status` | 목표, **런타임 미검증** | `storyteller_web/src/http_server/routes/service_routes.rs:26` |
| 웹앱 (`artcraft-webapp`) | 목표, **런타임 미검증** | `webapp` 서비스 = 업스트림 웹앱 프로덕션 빌드 + nginx, `http://localhost:4201` |
| 회원가입 / 비밀번호 로그인 | 목표, **런타임 미검증** | 아래 "회원가입/로그인" |
| 내 파일 목록 / 파일 보기 | 목표, **런타임 미검증** | 아래 "파일 목록/보기" |
| 이미지 업로드 → 표시 | 목표, **런타임 미검증** | 아래 "미디어/CDN" |
| 검색 (search_*) | ❌ 사실상 빈 결과 | Elasticsearch 사용, 색인 워커(`es-update-job`) 없음 |
| 이미지/비디오/오디오 생성 | ❌ | 제공자 키 + 공개 웹훅 URL + 워커 필요 |
| 결제 (Stripe), 이메일 (Resend) | ❌ | 키 없음 |
| Google 로그인 | ❌ | `VITE_GOOGLE_CLIENT_ID` 없음 (`frontend/apps/artcraft-webapp/src/main.tsx:16`) |
| 썸네일/비디오 미리보기 | ❌ | `video-thumbnail-job` 미포함 (개발 모드에선 이미지 썸네일 = 원본: `storyteller_web/src/http_server/common_responses/media/media_links_builder.rs:128-131`) |
| 업스트림 CDN에만 있는 기본 에셋 (기본 커버, 3D 샘플 등) | ❌ 예상 | 미디어 오리진을 로컬로 바꿨기 때문 |
| 데스크톱 앱 연결 | 지원 경로 있음, **미검증** | 아래 "데스크톱 앱" |

## 패치 (`patches/`, ArtCraft License)

빌드할 때 고정 커밋에 `git apply --check` 후 `git apply`로 적용됨. 실패하면 빌드가 멈춤. `APPLY_PATCHES=false`면 원본 그대로.

| 패치 | 내용 | 기본값 |
| --- | --- | --- |
| `backend/0001-media-cdn-base-url-override.patch` | 환경변수 `MEDIA_CDN_BASE_URL`(오리진만, 경로 없음)을 시작 시 한 번 읽어서, 미디어 링크 호스트를 그 값으로 바꿈 | **미설정/빈 값이면 업스트림과 동일** (하드코딩된 CDN 호스트) |
| `frontend/0001-api-and-cdn-origin-build-overrides.patch` | 빌드 시 `VITE_API_ORIGIN`(`same-origin` 또는 URL), `VITE_CDN_ORIGIN`을 반영 | **미설정/빈 값이면 업스트림과 동일** (`https://api.storyteller.ai`, `https://cdn-2.fakeyou.com`) |

백엔드 패치가 바꾸는 곳:
- `storyteller_web/src/http_server/common_responses/media/cdn_link.rs:15-21`의 `get_cdn_host` / `new_cdn_url`.
  미디어 링크를 만드는 코드는 사실상 전부 이 두 함수를 거침:
  `media_links_builder.rs:55,113,126,143`, `cover_image_links_builder.rs:65,76`, `cover_image_links.rs:77,88`,
  `weights_cover_image_details.rs:73`, `media_file_cover_image_details.rs:125`,
  `http_server/web_utils/bucket_urls/bucket_url_from_media_path.rs:17`, `bucket_url_from_str_path.rs:14`, `bucket_url_string_from_media_path.rs:14`
- `media_domain.rs:12-22` (`MediaDomain::new_cdn_url` / `cdn_url_str`, 현재 호출처 없음, 일관성 위해 포함)
- `storyteller_web/src/startup/build_dependencies.rs:180` 직후에서 환경변수 읽음. 잘못된 값(경로 포함 등)이면 부팅 실패
- 서버가 직접 미디어를 내려받는 `maybe_media_cdn_override_url`(`build_dependencies.rs:218`)은 건드리지 않음 (생성 기능 전용)

## 미디어/CDN: 링크 경로 ↔ MinIO 객체 키

| 단계 | 내용 | 근거 |
| --- | --- | --- |
| 업로드 | 이미지 업로드는 `public_bucket_client`로 씀 = `W2L_PUBLIC_DOWNLOAD_BUCKET_NAME` = `artcraft-public` | `storyteller_web/src/http_server/endpoints/media_files/upload/upload_image_media_file_handler.rs:249,253`, `storyteller_web/src/startup/build_dependencies.rs:134-136` |
| 객체 경로 | `/media/<a>/<b>/<c>/<d>/<e>/<hash>/<prefix><hash><ext>` | `crates/schema/buckets/bucket_paths/src/legacy/typified_paths/public/media_files/bucket_directory.rs:8,31`, `bucket_file_path.rs:37-48` |
| S3 키 | rust-s3가 앞의 `/`를 떼므로 키는 `media/...` | rust-s3 0.36.0-beta.2 (`Cargo.lock` 체크섬 일치) `src/request/request_trait.rs:369` |
| 링크 | `MEDIA_CDN_BASE_URL` + 같은 경로 → `http://localhost:4201/media/...` | `cdn_link.rs` (패치), `media_links_builder.rs:55-56` |
| 서빙 | nginx가 `/media/...` → `minio:9000/artcraft-public/media/...` 로 전달 | `docker/nginx-webapp.conf` |
| 권한 | `artcraft-public/media/*`만 익명 `s3:GetObject`. ListBucket 없음. 다른 버킷/경로는 비공개 | `config/minio/public-media-read.json`, `minio-init` |

`url.set_path()`가 경로 전체를 덮어쓰기 때문에(`media_links_builder.rs:56`) 베이스에 `/artcraft-public` 같은 경로를 넣을 수 없음.
그래서 nginx가 같은 오리진에서 `/media/`를 버킷으로 연결하는 구조를 씀.
자동 GC 버킷(`artcraft-public-gc`)은 테스트에서만 쓰여서(`storyteller_web/src/state/server_state.rs:95`) 비공개로 둠.

검증 스크립트 `scripts/verify-storage-policy.sh` (실제 스택에서 실행): 비공개 버킷 익명 403, 공개 버킷 `media/` 밖 403,
ListBucket 403, `media/` 안 GetObject 200, 웹앱 오리진 `/media/` 200을 확인함. **아직 실행된 적 없음.**

## 회원가입 / 로그인

- 웹앱 회원가입은 `POST /v1/create_account` (`frontend/libs/api/src/lib/UsersApi.ts:226`, 라우트 `storyteller_web/src/http_server/routes/application_routes/user_routes.rs:43`),
  로그인은 `POST /v1/login` (`UsersApi.ts:126`, `user_routes.rs:59`)
- 두 핸들러에는 캡차/이메일 인증/Resend 호출이 없음 (`storyteller_web/src/http_server/endpoints/users/create_account_handler.rs`, `login_handler.rs`). 그래서 이메일 키 없이도 동작할 것으로 예상
- 세션 쿠키는 Domain 속성 없이(호스트 전용) 설정됨 (`crates/lib/actix_artcraft/src/sessions/user_sessions/http_user_session_manager.rs:78-84`).
  `COOKIE_DOMAIN`에 `localhost`가 들어있으면 Secure 없이 SameSite=Lax (`:69-75`) → `http://localhost` 터널에서 필요한 설정
- 웹앱과 API가 같은 오리진(`http://localhost:4201`, nginx `/v1/` 프록시)이라 CORS/서드파티 쿠키 문제가 없음.
  그래도 브라우저는 `Origin` 헤더를 보내는데, 개발 모드 CORS는 모든 `localhost`/`127.0.0.1` 오리진을 허용함
  (`crates/lib/actix_cors_configs/src/configs/development_only.rs:21-24`, 불일치 시 400: `cors.rs:70-77`) → CORS 패치 불필요
- 브라우저 주소는 **`http://localhost:4201`** 로 열 것. `127.0.0.1:4201`로 열면 미디어 링크(`localhost`)와 오리진이 달라짐

## 파일 목록 / 보기

| 화면 동작 | 엔드포인트 | 저장소 |
| --- | --- | --- |
| 사용자 파일 목록 | `GET /v1/media_files/list/user/{username}` (`MediaFilesApi.ts:278`, 라우트 `media_files_routes.rs:115-116`) | MySQL만 (`endpoints/media_files/list/list_media_files_for_user_handler.rs`) |
| 파일 보기 | `GET /v1/media_files/file/{token}` (`MediaFilesApi.ts:143`, `media_files_routes.rs:61-62`) | MySQL만 (`endpoints/media_files/get/get_media_file_handler.rs`) |
| 세션 검색 | `GET /v1/media_files/search_session` (`media_files_routes.rs:139-140`) | Elasticsearch (`search_session_media_files_handler.rs:10,204`) → 색인 워커가 없어 결과 없음 |

ES 인덱스는 `es-init`이 만들어 두므로 검색 요청이 인덱스 없음 오류로 실패하지는 않을 것으로 예상 (미검증).

## 데스크톱 앱

조사 기준: storytold/artcraft @ `3e5793b6934b51536606720e5d56bcfd1fe7cc2d` (`UPSTREAM.lock`의 `DESKTOP_REFERENCE_SHA`, 2026-10-07 커밋)

- 지원되는 방법: 앱 데이터 폴더의 `settings/env_configs.json`
  (`crates/desktop/artcraft/src/core/state/data_dir/app_settings_dir.rs:35-36`)
  ```json
  { "version": "1", "storyteller_host": "localhost", "storyteller_port": 12345 }
  ```
  → API 주소가 `http://localhost:12345`가 됨 (`crates/desktop/artcraft/src/core/state/app_env_configs/app_env_configs.rs:21-28`,
  `crates/desktop/artcraft/src/core/state/app_env_configs/app_env_configs_serializeable.rs:9-21`, `crates/api_clients/artcraft/artcraft_client/src/utils/api_host.rs:24-29`).
  웹뷰도 이 값을 받아 씀 (`frontend/apps/artcraft/app/src/api/SyncStorytellerApiConfig.ts:50-59`)
- 호스트는 `localhost`만 고를 수 있음 (임의 호스트 불가) → 노트북에서 SSH 터널(`-L 12345:127.0.0.1:12345 -L 4201:127.0.0.1:4201`)로 연결
- 데스크톱은 `Origin: http://localhost`를 보냄 (`crates/lib/artcraft_client_identity/src/origins.rs:7`) → 개발 모드 CORS 허용 범위
- **미검증.** 로그인 방식, 미디어 표시(링크는 `http://localhost:4201/media/...`), 데스크톱 전용 기능은 확인하지 않았음. 데스크톱 재빌드는 하지 않음

## 검증 상태

| 항목 | 상태 |
| --- | --- |
| 패치가 고정 커밋에 깨끗하게 적용됨 | ✅ 로컬: `patch -p1 -F0 --dry-run` (fuzz 0) + 적용 결과 비교. CI: `git apply --check` (정적 잡) |
| 프론트 패치 타입 검사 | ✅ 로컬: TypeScript 5.8.3 strict + `vite/client` 타입. 기본값 동작 시뮬레이션 (미설정/빈 값 → 업스트림 값) |
| 백엔드 패치 컴파일 (`cargo check -p storyteller-web`) | **미검증** (로컬에 Rust 없음). CI `patched_checks` 수동 잡에 포함 |
| 웹앱 프로덕션 빌드 | **미검증**. CI `patched_checks` / `build_images` 수동 잡에 포함 |
| 셸 `bash -n`, compose/워크플로 YAML, 포트 `127.0.0.1` 전용 | ✅ 정적 |
| 비밀값 스캔 | ✅ 로컬 스크립트, CI gitleaks |
| backup/restore 로직 | ✅ 가짜 `docker`로 로직만 |
| `docker compose build` / `up`, `/_status`, 로그인, 업로드, 목록, 미디어 표시, 스토리지 정책 | **런타임 미검증** |
| 287개 마이그레이션, 역할 시드, 빈 제공자 값 동작 | **런타임 미검증** |
