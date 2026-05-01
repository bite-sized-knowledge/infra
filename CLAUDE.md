# infra — Claude 작업 메모

홈 서버 Docker Compose 스택 모음. 단일 git repo 아님 (compose + init script 모음).

## Docker 컨텍스트

- Apple Silicon: **`colima` 컨텍스트 사용**. `docker context use colima` 확인 필수.
- Cloudflare tunnel 통해 외부 접근.
- **컨테이너 내부 listen은 `0.0.0.0`** (cloudflared가 docker network 안에서 hostname:port로 접근하기 때문).
- **호스트 포트 매핑은 모두 `127.0.0.1:`로 좁힘** (mysql/qdrant/bite-api/bite-web 모두). cloudflared는 host port를 거치지 않고 docker network DNS(`bite-api:8080` 등)로 직접 붙으므로 외부에 host port를 열 필요 없음. 콜리마/Mac에서 직접 디버깅하려면 `127.0.0.1:` 통해 접근.

## 시크릿 관리 (Doppler 강제)

- `.env`는 **결과물**이며 **직접 수정 금지**. Doppler 프로젝트 `infra/prd`가 source of truth.
- 모든 시크릿 변경은 Doppler 대시보드(또는 `doppler secrets set`) 후 `scripts/doppler-sync.sh` 실행 → `.env` 재생성.
- `.env`는 `.gitignore` 등재 + git history에 들어간 적 없음 (검증 완료). 회전 작업 불필요. private repo 유지.
- 비-시크릿 config(DB_HOST, ENVIRONMENT 등)는 `doppler-sync.sh`의 heredoc에 추가.

## Docker 로깅 정책

- `docker-compose.yml` 상단 `x-logging` anchor로 모든 서비스에 일괄 적용.
- json-file 드라이버, `max-size: 50m`, `max-file: 5`, compress 활성. 컨테이너당 최대 ~250MB 보존.
- 새 서비스 추가 시 `logging: *default-logging` 한 줄 잊지 말 것.

## MySQL 운영 튜닝 (`mysql/conf.d/tuning.cnf`)

- `innodb_buffer_pool_size = 1G` (호스트 16GB, 다른 서비스와 공존하는 환경 고려).
- `max_connections = 200`, `max_allowed_packet = 64M`.
- `slow_query_log = 1`, `long_query_time = 1`, `slow_query_log_file = /var/lib/mysql/slow.log` (mysql_data 볼륨에 영속).
- `default_time_zone = '+09:00'` (KST 기본).
- charset만 utf8mb4 강제, **collation은 강제하지 않음** (article 테이블이 utf8mb4_bin 사용 중이라 충돌 회피).

## ⚠️ MySQL 마이그레이션 (반복 실수)

- `mysql/init/*.sql`은 **신규 컨테이너 첫 부팅에서만 자동 실행**. 기존 운영 컨테이너에는 자동 적용 안 됨.
- 운영 컨테이너에는 수동 ALTER:
  ```
  docker exec -i bite-mysql mysql -u root -p"$PW" < mysql/init/0XX_xxx.sql
  ```
- **`bite` (운영) + `bite_dev` (개발) 양쪽 모두 동일 마이그레이션 적용**. 한쪽만 하면 dev 검증 결과와 prod가 안 맞아서 디버깅 시간 낭비함.
- 멱등성 필수: `IF NOT EXISTS`, `ALTER ... ADD COLUMN IF NOT EXISTS`. 재실행 안전하게.
- host에서 직접 mysql client로 접속 시 docker bridge IP(예: 172.18.0.1) 인증 거부될 수 있음 → `docker exec` 안에서 실행이 안전.

## ⚠️ deploy-webhook의 mount source path-mirror (반복 실수)

deploy-webhook 컨테이너는 자기 안에서 `docker compose config --format json`을
실행해 서비스 정의를 풀어낸 뒤, 그 결과(image / env / volumes / healthcheck)를
**호스트 docker daemon**에 `docker run --mount source=<path>,...`로 전달한다.
docker socket을 통해 host daemon이 명령을 실행하므로 mount source는 **호스트
파일시스템에서 valid**해야 한다.

함정: compose의 상대 경로 mount(예 `./mysql/ca.pem`)는 `docker compose config`가
**컨테이너의 cwd 기준**으로 절대 경로로 풀어낸다. 컨테이너 cwd가 `/infra`이고
호스트 실제 경로가 `/Users/bite-server/projects/infra`라면, 풀린 경로
`/infra/mysql/ca.pem`는 호스트에 없다 → docker daemon이
`bind source path does not exist` 로 거부 → blue-green이 `green start failed:
exit status 125`로 실패.

원인이 추가된 시점: ca.pem 마운트가 추가된 security hardening commit. 그 이전
에는 host-absolute path만 마운트로 쓰여서 우연히 동작했다.

영향 범위: 상대 경로 mount(`./mysql/ca.pem`, `./backup`, `./logs`,
`./cloudflared/config.yml` 등)를 가진 모든 서비스의 webhook 배포가 깨진다 —
recsys-api / bite-api / bite-web / bite-monitor / bite-metric / harvester-go /
recommender / backup 등 거의 전부. webhook 우회로 호스트에서
`docker compose up -d --force-recreate <svc>`만 하면 동작은 하지만 blue-green이
아니라 다운타임이 생긴다.

해결: deploy-webhook의 volumes/COMPOSE_PATH를 **호스트 절대 경로와 동일하게
mirror** 한다.

```yaml
deploy-webhook:
  environment:
    - COMPOSE_PATH=/Users/bite-server/projects/infra
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
    - /Users/bite-server/projects/infra:/Users/bite-server/projects/infra:ro
    - ...
```

이렇게 두면 컨테이너 cwd와 호스트의 실제 infra 디렉토리 경로가 같아져, compose가
풀어낸 절대 경로(예 `/Users/bite-server/projects/infra/mysql/ca.pem`)가 호스트
daemon 입장에서도 그대로 valid하다.

새 mount source가 추가될 때마다 점검할 것:
- 새 mount가 host-absolute path인지, compose-relative path인지 확인.
- relative라면 path-mirror가 깨지지 않는지 (`/Users/bite-server/projects/infra` 하위인지) 확인.
- 디버깅 시: `docker run --rm --network infra_bite-network curlimages/curl -s -X POST
  "http://deploy-webhook:9000/deploy?service=<svc>" -H "Authorization: Bearer $TOKEN"`
  의 응답 body를 보면 docker daemon 에러 원문이 그대로 들어있다.

## ⚠️ deploy-webhook의 docker context 우회 (반복 실수)

webhook 컨테이너는 `/var/run/docker.sock`을 직접 마운트해 host daemon에
붙는다. 그런데 컨테이너 안 docker CLI는 명령 실행 전에 먼저
`/root/.docker/config.json`의 `currentContext`를 해석하려 시도한다. 호스트
설정이 `currentContext: "colima"`라면 CLI는 colima context의 metadata 파일
(`/root/.docker/contexts/meta/<hash>/meta.json`)을 찾는데 컨테이너 안에는
존재하지 않으므로 모든 docker 명령이 다음 에러로 실패한다:

```
unable to resolve docker endpoint: context "colima": context not found:
open /root/.docker/contexts/meta/<hash>/meta.json: no such file or directory
```

증상: webhook 통한 모든 deploy가 `pull failed: exit status 1` 또는
`green start failed`로 깨짐. 호스트에서 `docker pull ...`은 정상 동작
(호스트 daemon은 본인의 콘텍스트 metadata가 있음).

해결: `DOCKER_HOST=unix:///var/run/docker.sock`을 webhook environment에
명시해 currentContext 해석 자체를 우회. socket이 곧 endpoint가 된다.

```yaml
deploy-webhook:
  environment:
    - DOCKER_HOST=unix:///var/run/docker.sock
```

부가 함정 (같은 사고에서 드러남): `/Users/bite-server/.docker/config.json`을
readonly bind mount로 받는데, 호스트에서 atomic replace(예: `mv` 또는
`cat > file`)로 토큰을 회전하면 새 inode가 생기고 컨테이너는 옛 inode를
계속 들고 있어 truncated/stale view를 본다 ("unexpected EOF" → unauthorized).
config.json을 갱신한 뒤에는 `docker compose up -d --force-recreate
deploy-webhook`으로 컨테이너만 재기동해 inode를 다시 잡아야 한다.

진단 명령:
- `docker exec bite-deploy-webhook docker pull ghcr.io/bite-sized-knowledge/<svc>:latest`
  으로 webhook 안에서 직접 재현하면 위 두 에러 중 어느 것인지 즉시 갈린다.
- `docker exec bite-deploy-webhook wc -c /root/.docker/config.json`을
  호스트의 `wc -c ~/.docker/config.json`과 비교해 stale inode인지 확인.

## 컨테이너 매트릭스

- `bite-mysql`: **MySQL 8.0**. 단일 인스턴스에 `bite`(prod) + `bite_dev`(dev) DB 공존. host port `127.0.0.1:3306`.
- `bite-qdrant`: 6333(REST)/6334(gRPC), host port 모두 `127.0.0.1`.
- `bite-api` (8080 latest) / `bite-api-dev` (8081 dev). host port `127.0.0.1:`.
- `bite-web` (3000 latest) / `bite-web-dev` (3001 dev). host port `127.0.0.1:`.
- `recsys-api` (8001), host port `127.0.0.1:8001`.
- `bite-redis` (6379), host port `127.0.0.1:6379`.
- `bite-monitor` (3002→3000), `bite-metric` (3003→3000) — 둘 다 `127.0.0.1:`.
- `bite-tunnel` (cloudflared) — host port 노출 없음 (docker network 내부 호출만).

## 배포 흐름

- dev image 빌드: `docker compose -f docker-compose.dev.yml build <svc>` 또는 해당 repo에서 `docker build -t <name>:dev .`.
- 운영 배포: 사용자 명시적 요청 있을 때만. dev에서 검증 후.

## 백업

- `backup/` nightly MySQL dump.

## 스케줄 (launchd)

- **recommender daily**: `scripts/com.bite.recommender.daily.plist` → `~/Library/LaunchAgents/`. 매일 01:00 (host TZ) `scripts/recommender-cron.sh` 실행 → `docker compose --profile batch run --rm recommender`. 로그: `~/logs/recommender/<date>.log` + launchd stdio: `~/logs/recommender/launchd.{out,err}`.
- 등록/해제:
  - `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.bite.recommender.daily.plist`
  - `launchctl bootout gui/$(id -u)/com.bite.recommender.daily`
- 즉시 1회 트리거 검증: `launchctl kickstart -k gui/$(id -u)/com.bite.recommender.daily`
- plist 변경 후엔 bootout → bootstrap 재등록 필수.
