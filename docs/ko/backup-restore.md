# 백업 / 복구

```bash
scripts/backup.sh                                        # backups/<UTC시각>/ 생성
scripts/restore.sh backups/20261008T120000Z              # 대화형: 'restore' 입력해야 진행
RESTORE_CONFIRM=restore scripts/restore.sh backups/<ts>  # 비대화형
```

> 실제 Docker 환경에서 백업/복구를 돌려본 적은 없음. 서비스 상태 처리와 실패 처리 로직만 가짜 `docker`로 테스트했음.

## 포함 / 제외

| 항목 | 포함 | 비고 |
| --- | --- | --- |
| MySQL `storyteller` DB | ✅ | `mysqldump --single-transaction --add-drop-database` (gzip) |
| MinIO 버킷 3개 | ✅ | `mc mirror` |
| `MANIFEST`, `UPSTREAM.lock`, `SHA256SUMS` | ✅ | 고정 커밋/버킷/체크섬 기록 |
| Redis | ❌ | 캐시/진행상황뿐이라 제외 |
| Elasticsearch | ❌ | 검색 인덱스. 재색인 워커는 이 템플릿에 없음 |
| `.env`, `config/providers.env` | ❌ | 비밀값. 따로 안전하게 보관할 것 (없으면 기존 볼륨에 접속 불가) |

## backup.sh 동작

1. 현재 실행 중인 compose 서비스를 기록
2. 꺼져 있는 `mysql`/`minio`는 임시로 켜고, 실행 중인 쓰기 서비스(`storyteller-web`)는 멈춤 → DB와 버킷이 같은 시점
3. `backups/.<시각>.partial`에 쓰고, 전부 성공했을 때만 `backups/<시각>`으로 이름 변경
4. 성공/실패/Ctrl-C/종료 신호 상관없이 서비스를 **원래 상태 그대로** 되돌림 (원래 꺼져 있던 건 켜지 않음)
5. 실패하면 0이 아닌 종료코드, 미완성 디렉터리 삭제 (`KEEP_PARTIAL=1`이면 남김)

**보존기간은 옵트인임.** 기본은 아무것도 지우지 않음. `.env`나 환경변수에 `BACKUP_RETENTION_DAYS=30`처럼
설정한 경우에만, 완료된(`SHA256SUMS` 있는) 백업 중 그보다 오래된 것을 지움.

## 오프사이트 복사 (권장)

서버가 날아가면 같은 디스크의 백업도 같이 날아감. 백업 디렉터리를 다른 곳으로 복사할 것. 예:

```bash
rsync -a --chmod=go-rwx backups/ <backup-host>:artcraft-backups/
```

백업에는 계정 정보 같은 민감 데이터가 들어있음. 암호화된 저장소를 쓰는 걸 권장함.

## restore.sh 동작

1. 파일, 버킷 디렉터리, 체크섬, gzip을 검증함. **이 단계에선 아무 서비스도 멈추지 않음.** `.partial` 디렉터리는 거부함
2. 확인 입력 (`restore`), 비대화형이면 `RESTORE_CONFIRM=restore` 필요
3. 쓰기 서비스 중지 → DB 삭제 후 재생성 + 덤프 적용 → 버킷 `mc mirror --overwrite --remove` (백업 이후 생긴 객체는 **삭제됨**)
4. 성공하면 원래 상태로 되돌림

**복구 실패 시 기본 동작 (안전 우선):** `storyteller-web`을 **멈춘 채로 둠**. 반쯤 복구된 DB에 API가 붙지 않게 하기 위함.
임시로 켠 mysql/minio는 다시 끔. 원인을 해결하고 복구를 다시 실행하거나, 직접 `docker compose start storyteller-web`.
실패해도 원래 상태로 되돌리고 싶으면 `RESTORE_RESTART_ON_FAILURE=1`.
