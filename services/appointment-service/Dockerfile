# ── Stage 1: build ───────────────────────────────────────────
FROM golang:1.24-alpine AS builder

WORKDIR /app

# download dependencies first (cached unless go.mod/go.sum change)
COPY services/appointment-service/go.mod services/appointment-service/go.sum ./
RUN go mod download

# copy source and compile a static binary
COPY services/appointment-service/ .
RUN CGO_ENABLED=0 GOOS=linux go build -o appointment-service .

# ── Stage 2: run ─────────────────────────────────────────────
FROM alpine:3.20

WORKDIR /app

COPY --from=builder /app/appointment-service .

EXPOSE 3001

CMD ["./appointment-service"]
