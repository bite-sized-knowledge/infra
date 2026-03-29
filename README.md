# Bite infra

This directory contains the home-server Docker Compose stack for Bite.

## Services

- `mysql`: primary relational database
- `qdrant`: vector database
- `recsys-api`: FastAPI recommendation/search service
- `bite-api`: Go API server
- `harvester-go`: always-on RSS harvester (internal ticker via `HARVEST_INTERVAL`)
- `cloudflared`: public tunnel for `api.bite-sized.xyz`
- `backup`: nightly MySQL dumps
- `dynamodb-local` (batch profile): local DynamoDB dependency for recommender batch runs
- `recommender` (batch profile): offline profile/batch recommendation job

## Health endpoints

- `bite-api`: `http://localhost:8080/actuator/health`
- `recsys-api`: `http://localhost:8001/health`

## Running profiles

- Default (always-on stack):

```bash
docker-compose up -d
```

- Batch profile (includes recommender + local DynamoDB):

```bash
docker-compose --profile batch up --build recommender
```

## Local verification

Run:

```bash
docker-compose config --services
docker-compose --profile batch config --services
bash ./verify.sh
```
