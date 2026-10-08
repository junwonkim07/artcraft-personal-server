# 업데이트 / 제거

## 업스트림 고정 커밋 올리기

업스트림 버전은 두 곳에 고정돼 있음. **둘 다 같은 값으로** 바꿔야 함.

- `UPSTREAM.lock`의 `UPSTREAM_SHA`
- `docker-compose.yml`의 `x-storyteller-build.args.UPSTREAM_SHA` (이미지 태그 `:d950e573` 같은 짧은 SHA도 같이 바꾸면 구분이 쉬움)

절차:

1. 업스트림 변경 검토: `https://github.com/storytold/artcraft-services/compare/<현재SHA>...<새SHA>`
   - 특히 `_database/sql/migrations/` (새 마이그레이션), `crates/service/web/storyteller_web/src/startup/` (새 필수 환경변수),
     `build/service_cpu.Dockerfile` (Rust 버전 변경 → `RUST_TOOLCHAIN` 갱신), `LICENSE.md` (라이선스 변경)
2. **먼저 백업:** `scripts/backup.sh`
3. SHA 수정 후 `scripts/fetch-upstream.sh` (선택, 로컬 검토용)
4. `docker compose build`
5. `docker compose up -d` → `migrate`가 새 마이그레이션을 적용함. `docker compose logs migrate`로 확인
6. `scripts/status.sh`, `scripts/verify-storage-policy.sh`

패치(`patches/`)는 특정 커밋 기준이라 커밋을 올리면 안 맞을 수 있음. 빌드가 `PATCH DOES NOT APPLY`로 멈추면
패치를 새 커밋에 맞게 다시 만들어야 함 (임시로 `APPLY_PATCHES=false`도 가능하지만 미디어 표시가 안 됨).
`docker compose build webapp`은 `WEBAPP_ORIGIN`을 바꿨을 때도 다시 해야 함 (빌드에 들어감).

새 필수 환경변수가 생기면 `config/storyteller-web.env`(비밀 아님) 또는 `config/providers.env`(비밀)에 추가해야 부팅됨.

## 템플릿 자체 업데이트

```bash
git pull
docker compose build && docker compose up -d
```

`.env`, `config/providers.env`, `backups/`는 gitignore돼 있어서 `git pull`이 건드리지 않음.
`config/providers.env.example`에 새 변수가 생겼다면 `config/providers.env`에 직접 추가할 것.

## 롤백

1. SHA를 이전 값으로 되돌리고 `docker compose build`
2. 마이그레이션은 자동으로 되돌려지지 않으므로 업데이트 전 백업으로 복구: `scripts/restore.sh backups/<업데이트 전 시각>`
3. `docker compose up -d`

## 제거

```bash
docker compose down            # 컨테이너/네트워크만 삭제. 데이터 볼륨은 남음
docker compose down -v         # ⚠️ 볼륨까지 삭제 = MySQL/MinIO/ES/Redis 데이터 영구 삭제
docker image rm artcraft-personal/storyteller-web:d950e573 artcraft-personal/migrate:d950e573 artcraft-personal/webapp:d950e573
docker builder prune           # (선택) 빌드 캐시 정리
```

비밀값과 백업도 지우려면 (복구 불가):

```bash
rm -f .env config/providers.env
rm -rf backups/ upstream/
```
