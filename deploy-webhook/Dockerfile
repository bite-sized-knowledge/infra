FROM golang:1.26-alpine AS builder
WORKDIR /app
COPY main.go .
RUN CGO_ENABLED=0 go build -o deploy-webhook main.go

FROM docker:27-cli
# openssh-client: the wake-and-rebuild deploy strategy (used by harvest-post
# which runs on the WoL-gated GPU machine) SSHs from this container into
# the Mac host via host.docker.internal, so we need an ssh binary.
RUN apk add --no-cache openssh-client

COPY --from=builder /app/deploy-webhook /usr/local/bin/deploy-webhook
CMD ["deploy-webhook"]
