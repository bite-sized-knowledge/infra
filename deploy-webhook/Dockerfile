FROM golang:1.26-alpine AS builder
WORKDIR /app
COPY main.go .
RUN CGO_ENABLED=0 go build -o deploy-webhook main.go

FROM docker:27-cli
COPY --from=builder /app/deploy-webhook /usr/local/bin/deploy-webhook
CMD ["deploy-webhook"]
