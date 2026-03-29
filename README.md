# Bite infra

This directory contains the home-server Docker Compose stack for Bite.

## Services

- `mysql`: primary relational database
- `qdrant`: vector database
- `recsys-api`: FastAPI recommendation/search service
- `bite-api`: Go API server
- `cloudflared`: public tunnel for `api.bite-sized.xyz`
- `backup`: nightly MySQL dumps

## Health endpoints

- `bite-api`: `http://localhost:8080/actuator/health`
- `recsys-api`: `http://localhost:8001/health`

## Notes about harvester

`harvest_post` / harvester work is intentionally **not** managed from this Compose file in the current session.
It is being handled separately, so this stack keeps the integration surface stable without modifying harvester code.

## Local verification

Run:

```bash
docker-compose config --services
bash ./verify.sh
```
