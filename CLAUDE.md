# infra — Claude 작업 메모

홈 서버 Docker Compose 스택 모음. 단일 git repo 아님 (compose + init script 모음).

## Docker 컨텍스트

- Apple Silicon: **`colima` 컨텍스트 사용**. `docker context use colima` 확인 필수.
- Cloudflare tunnel 통해 외부 접근. 모든 서비스는 `0.0.0.0` 바인딩.

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

## 컨테이너 매트릭스

- `bite-mysql` / `bite-mysql-dev`: 5.7. 두 인스턴스 별도. dev DB 이름은 `bite_dev`.
- `bite-qdrant` (6333/6334) / `bite-qdrant-dev` (6335/6336).
- `bite-api` (8080 latest) / `bite-api-dev` (8081 dev).
- `bite-web` (3000 latest) / `bite-web-dev` (3001 dev).
- `recsys-api` (8001).
- `bite-tunnel` (cloudflared).

## 배포 흐름

- dev image 빌드: `docker compose -f docker-compose.dev.yml build <svc>` 또는 해당 repo에서 `docker build -t <name>:dev .`.
- 운영 배포: 사용자 명시적 요청 있을 때만. dev에서 검증 후.

## 백업

- `backup/` nightly MySQL dump.
