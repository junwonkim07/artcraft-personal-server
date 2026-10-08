# 문제 해결

| 증상 | 원인 / 해결 |
| --- | --- |
| `elasticsearch`가 계속 재시작, 로그에 `max virtual memory areas vm.max_map_count [65530] is too low` | 호스트에서 `vm.max_map_count=262144` 설정 ([설치 문서](install.md) 4단계) |
| `docker compose build` 중 `signal: killed`, `ld terminated with signal 9`, 서버가 멈춤 | 메모리 부족(OOM). 스왑 추가, 다른 컨테이너 중지(`docker compose down`) 후 빌드, 더 큰 서버에서 빌드 |
| 웹앱 빌드 중 `JavaScript heap out of memory` / `Reached heap limit` | 업스트림 웹앱 번들이 큼. RAM/스왑 늘리기 (Node heap 한도 8GB로 설정됨) |
| 빌드 중 `PATCH DOES NOT APPLY` | 고정 커밋을 바꿨는데 패치가 안 맞음. 패치를 갱신하거나 `APPLY_PATCHES=false` (미디어 표시 불가) |
| 부팅 시 `MEDIA_CDN_BASE_URL must be an origin without path` | `.env`의 `WEBAPP_ORIGIN`에 경로/끝 슬래시 외 문자가 있음. `http://localhost:4201` 형태로 |
| 웹앱은 뜨는데 로그인 후 바로 로그아웃됨 / API 400 | `http://localhost:4201`로 열었는지 확인 (`127.0.0.1`·다른 호스트명 X). 개발 모드 CORS는 localhost 계열만 허용 |
| 이미지가 깨짐 (업로드는 성공) | 터널의 노트북 포트와 `WEBAPP_ORIGIN`이 같은지, `scripts/verify-storage-policy.sh` 결과 확인 |
| 빌드 중 `no space left on device` | 디스크 30GB+ 여유 확보, `docker builder prune` |
| `port is already allocated` / `address already in use` | 호스트의 같은 포트를 다른 프로그램이 사용 중. `.env`의 `API_PORT`, `MINIO_API_PORT`, `MINIO_CONSOLE_PORT` 변경 (바인딩은 계속 `127.0.0.1`) |
| `required variable ... is missing a value: run scripts/generate-secrets.sh` | `.env`가 없음. `scripts/generate-secrets.sh` 실행 |
| `env file .../config/providers.env not found` | `scripts/generate-secrets.sh` 실행 (이미 `.env`가 있어도 providers.env는 만들어 줌) |
| `migrate`가 실패하고 API가 안 뜸 | `docker compose logs migrate`. 마이그레이션 호환성은 미검증 영역임. 로그와 함께 이슈로 남겨주면 도움 됨 |
| `storyteller-web` 부팅 실패, 환경변수 관련 오류 | 업스트림에 새 필수 변수가 생겼을 수 있음 → [업데이트 문서](update-uninstall.md) |
| MinIO 빌드 실패 | 공식 이미지 배포가 중단되어 고정 소스로 빌드함. `docker compose build minio minio-init` 로그와 GitHub/Go 모듈 다운로드 연결 확인 |
| 복구 실패 후 API가 꺼져 있음 | 의도된 안전 동작. 원인 해결 후 복구 재실행, 또는 `docker compose start storyteller-web` |
