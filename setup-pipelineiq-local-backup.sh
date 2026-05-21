#!/usr/bin/env bash
#
# setup-pipelineiq.sh
# One-command setup: creates the full PipelineIQ repository structure in ./pipelineiq
# Usage:
#   ./setup-pipelineiq.sh                # creates ./pipelineiq
#   ./setup-pipelineiq.sh </custom/path>  # creates at the provided path
#
set -euo pipefail

ROOT="${1:-./pipelineiq}"
echo "==> Creating PipelineIQ repo at: ${ROOT}"

mkdir -p "${ROOT}"/{configs,scripts,docs}
mkdir -p "${ROOT}/.github/workflows"
mkdir -p "${ROOT}/infra/terraform"
mkdir -p "${ROOT}/db/migrations"
mkdir -p "${ROOT}/services/api-gateway/cmd"
mkdir -p "${ROOT}/services/auth-service/cmd"
mkdir -p "${ROOT}/services/pipeline-orchestrator/cmd"
mkdir -p "${ROOT}/services/deployment-tracker/cmd"
mkdir -p "${ROOT}/services/notifications/app"
mkdir -p "${ROOT}/services/notifications/tests"
mkdir -p "${ROOT}/services/analytics-worker/app"
mkdir -p "${ROOT}/services/analytics-worker/tests"
mkdir -p "${ROOT}/frontend/dashboard/src/api"
mkdir -p "${ROOT}/frontend/dashboard/src/components"
mkdir -p "${ROOT}/frontend/dashboard/src/pages}"

write() {
  local path="$1"
  mkdir -p "$(dirname "${ROOT}/${path}")"
  cat > "${ROOT}/${path}"
  echo "    wrote ${path}"
}

# ---------------------------------------------------------------------------
# Root files
# ---------------------------------------------------------------------------
write README.md <<'EOF'
# PipelineIQ

PipelineIQ is a multi-service platform for CI/CD observability, deployment
tracking, and DORA metrics reporting.

## Architecture

- **api-gateway** (Go) — reverse proxy, auth verification, rate limiting
- **auth-service** (Go) — SSO/OIDC, JWT, RBAC, user/team/API key management
- **pipeline-orchestrator** (Go) — pipeline CRUD, run lifecycle, VCS webhooks
- **deployment-tracker** (Go) — deployment lifecycle, canary/blue-green, rollback
- **notifications** (Python/FastAPI) — alert rules engine, multi-channel delivery
- **analytics-worker** (Python) — streaming ETL, DORA metrics, reporting
- **frontend/dashboard** (React 18 + TS + Vite + Tailwind)

## Quick Start

bash
cp configs/.env.example .env
make up           # docker-compose up: Postgres, Redis, Kafka, OpenSearch + services
make migrate      # apply db/migrations
make seed         # optional: load demo data
```

Open http://localhost:3000 for the dashboard.

## Testing

bash
make test         # runs Go, Python, and frontend test suites
make lint         # runs golangci-lint, ruff, eslint
```

See `docs/api-reference.md` for the full API catalog.
EOF

write Makefile <<'EOF'
.PHONY: up down build test lint migrate seed docker-build fmt

up:
\tdocker-compose up -d

down:
\tdocker-compose down -v

build:
\tcd services/api-gateway && go build ./...
\tcd services/auth-service && go build ./...
\tcd services/pipeline-orchestrator && go build ./...
\tcd services/deployment-tracker && go build ./...
\tcd frontend/dashboard && npm run build

test:
\tcd services/api-gateway && go test ./...
\tcd services/auth-service && go test ./...
\tcd services/pipeline-orchestrator && go test ./...
\tcd services/deployment-tracker && go test ./...
\tcd services/notifications && pytest
\tcd services/analytics-worker && pytest
\tcd frontend/dashboard && npm test

lint:
\tgolangci-lint run ./...
\truff check services/notifications services/analytics-worker
\tcd frontend/dashboard && npm run lint

migrate:
\t@for f in db/migrations/*.sql; do \\
\t\techo "applying $$f"; \\
\t\tpsql "$$DATABASE_URL" -f $$f; \\
\tdone

seed:
\tpsql "$$DATABASE_URL" -f db/seeds/demo.sql

docker-build:
\tdocker-compose build

fmt:
\tgofmt -w services/
\truff format services/notifications services/analytics-worker
\tcd frontend/dashboard && npm run format
EOF

write docker-compose.yml <<'EOF'
version: "3.9"

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: pipelineiq
      POSTGRES_PASSWORD: pipelineiq
      POSTGRES_DB: pipelineiq
    ports: ["5432:5432"]
    volumes: ["pgdata:/var/lib/postgresql/data"]

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

  kafka:
    image: bitnami/kafka:3.6
    environment:
      KAFKA_CFG_NODE_ID: 1
      KAFKA_CFG_PROCESS_ROLES: controller,broker
      KAFKA_CFG_CONTROLLER_QUORUM_VOTERS: 1@kafka:9093
      KAFKA_CFG_LISTENERS: PLAINTEXT://:9092,CONTROLLER://:9093
      KAFKA_CFG_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_CFG_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
    ports: ["9092:9092"]

  opensearch:
    image: opensearchproject/opensearch:2.13.0
    environment:
      discovery.type: single-node
      DISABLE_SECURITY_PLUGIN: "true"
    ports: ["9200:9200"]

  api-gateway:
    build: ./services/api-gateway
    ports: ["8080:8080"]
    depends_on: [auth-service, pipeline-orchestrator, deployment-tracker]

  auth-service:
    build: ./services/auth-service
    environment:
      DATABASE_URL: postgres://pipelineiq:pipelineiq@postgres:5432/pipelineiq?sslmode=disable
    depends_on: [postgres]

  pipeline-orchestrator:
    build: ./services/pipeline-orchestrator
    environment:
      DATABASE_URL: postgres://pipelineiq:pipelineiq@postgres:5432/pipelineiq?sslmode=disable
      KAFKA_BROKERS: kafka:9092
    depends_on: [postgres, kafka]

  deployment-tracker:
    build: ./services/deployment-tracker
    environment:
      DATABASE_URL: postgres://pipelineiq:pipelineiq@postgres:5432/pipelineiq?sslmode=disable
      KAFKA_BROKERS: kafka:9092
    depends_on: [postgres, kafka]

  notifications:
    build: ./services/notifications
    environment:
      DATABASE_URL: postgres://pipelineiq:pipelineiq@postgres:5432/pipelineiq?sslmode=disable
      KAFKA_BROKERS: kafka:9092
    depends_on: [postgres, kafka]

  analytics-worker:
    build: ./services/analytics-worker
    environment:
      DATABASE_URL: postgres://pipelineiq:pipelineiq@postgres:5432/pipelineiq?sslmode=disable
      KAFKA_BROKERS: kafka:9092
      OPENSEARCH_URL: http://opensearch:9200
    depends_on: [postgres, kafka, opensearch]

  dashboard:
    build: ./frontend/dashboard
    ports: ["3000:80"]
    depends_on: [api-gateway]

volumes:
  pgdata:
EOF

write .gitignore <<'EOF'
# Binaries / build output
bin/
dist/
build/
*.exe
*.test
*.out

# Go
vendor/
*.coverprofile

# Node / frontend
node_modules/
.next/
.cache/
.parcel-cache/

# Python
__pycache__/
*.py[cod]
.venv/
venv/
.pytest_cache/
.mypy_cache/
.ruff_cache/

# Terraform
.terraform/
*.tfstate
*.tfstate.*
crash.log
terraform.tfvars

# Env / secrets
.env
.env.*
!.env.example

# Editors / OS
.DS_Store
.idea/
.vscode/
*.swp
EOF

write configs/.env.example <<'EOF'
# Core
ENV=development
LOG_LEVEL=info

# Database
DATABASE_URL=postgres://pipelineiq:pipelineiq@localhost:5432/pipelineiq?sslmode=disable

# Cache / queue
REDIS_URL=redis://localhost:6379/0
KAFKA_BROKERS=localhost:9092

# Search
OPENSEARCH_URL=http://localhost:9200

# Auth
JWT_SECRET=change-me-in-production
JWT_ISSUER=pipelineiq
OIDC_PROVIDER_URL=
OIDC_CLIENT_ID=
OIDC_CLIENT_SECRET=

# Integrations
SLACK_WEBHOOK_URL=
PAGERDUTY_ROUTING_KEY=
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
EOF

# ---------------------------------------------------------------------------
# CI / CD
# ---------------------------------------------------------------------------
write .github/workflows/ci.yml <<'EOF'
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  go:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [api-gateway, auth-service, pipeline-orchestrator, deployment-tracker]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: "1.22" }
      - name: Lint
        uses: golangci/golangci-lint-action@v6
        with: { working-directory: services/${{ matrix.service }} }
      - name: Test
        run: cd services/${{ matrix.service }} && go test ./...

  python:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [notifications, analytics-worker]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install -r services/${{ matrix.service }}/requirements.txt -r services/${{ matrix.service }}/requirements-dev.txt
      - run: ruff check services/${{ matrix.service }}
      - run: cd services/${{ matrix.service }} && pytest

  frontend:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: frontend/dashboard } }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: "20" }
      - run: npm ci
      - run: npm run lint
      - run: npm test -- --run
      - run: npm run build

  docker:
    needs: [go, python, frontend]
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: us-east-1
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE }}
      - uses: aws-actions/amazon-ecr-login@v2
      - run: docker compose build
      - run: docker compose push
EOF

write .github/workflows/deploy.yml <<'EOF'
name: Deploy

on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, staging, prod]
      image_tag:
        type: string
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - uses: actions/checkout@v4
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: us-east-1
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE }}
      - name: Argo CD sync
        run: |
          argocd login ${{ secrets.ARGOCD_SERVER }} --auth-token ${{ secrets.ARGOCD_TOKEN }} --grpc-web
          argocd app set pipelineiq-${{ inputs.environment }} \
              -p image.tag=${{ inputs.image_tag }}
          argocd app sync pipelineiq-${{ inputs.environment }} --prune
          argocd app wait pipelineiq-${{ inputs.environment }} --health --timeout 600
EOF

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------
write infra/terraform/main.tf <<'EOF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.50" }
  }
}

provider "aws" {
  region = var.region
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.project}-vpc"
  cidr = "10.0.0.0/16"
  azs  = ["${var.region}a", "${var.region}b", "${var.region}c"]

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false
}

resource "aws_kms_key" "main" {
  description             = "PipelineIQ data key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.project}-postgres"
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = var.db_instance_class
  allocated_storage      = 100
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.main.arn
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  username               = "pipelineiq"
  password               = var.db_password
  skip_final_snapshot    = false
  deletion_protection    = true
  backup_retention_period = 14
}

resource "aws_security_group" "db" {
  name   = "${var.project}-db"
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project}-cache"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${var.project}-redis"
  description                = "PipelineIQ Redis"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = var.redis_node_type
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  subnet_group_name          = aws_elasticache_subnet_group.main.name
}

resource "aws_msk_cluster" "main" {
  cluster_name           = "${var.project}-kafka"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = 3
  broker_node_group_info {
    instance_type   = var.kafka_instance_type
    client_subnets  = module.vpc.private_subnets
    storage_info {
      ebs_storage_info { volume_size = 200 }
    }
    security_groups = [aws_security_group.kafka.id]
  }
  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.main.arn
  }
}

resource "aws_security_group" "kafka" {
  name   = "${var.project}-kafka"
  vpc_id = module.vpc.vpc_id
}

resource "aws_opensearch_domain" "main" {
  domain_name    = "${var.project}-search"
  engine_version = "OpenSearch_2.13"
  cluster_config {
    instance_type            = var.opensearch_instance_type
    instance_count           = 3
    zone_awareness_enabled   = true
    zone_awareness_config { availability_zone_count = 3 }
  }
  ebs_options { ebs_enabled = true, volume_size = 100 }
  encrypt_at_rest { enabled = true }
  node_to_node_encryption { enabled = true }
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project}-ecs"
  setting { name = "containerInsights", value = "enabled" }
}

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project}-waf"
  scope       = "CLOUDFRONT"
  default_action { allow {} }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-waf"
    sampled_requests_enabled   = true
  }
}
EOF

write infra/terraform/variables.tf <<'EOF'
variable "project"                  { type = string  default = "pipelineiq" }
variable "region"                   { type = string  default = "us-east-1" }
variable "db_instance_class"        { type = string  default = "db.r6g.large" }
variable "db_password"              { type = string  sensitive = true }
variable "redis_node_type"          { type = string  default = "cache.r7g.large" }
variable "kafka_instance_type"      { type = string  default = "kafka.m7g.large" }
variable "opensearch_instance_type" { type = string  default = "r6g.large.search" }
EOF

write infra/terraform/outputs.tf <<'EOF'
output "vpc_id"              { value = module.vpc.vpc_id }
output "postgres_endpoint"   { value = aws_db_instance.postgres.endpoint }
output "redis_endpoint"      { value = aws_elasticache_replication_group.redis.primary_endpoint_address }
output "kafka_bootstrap"     { value = aws_msk_cluster.main.bootstrap_brokers_tls }
output "opensearch_endpoint" { value = aws_opensearch_domain.main.endpoint }
output "ecs_cluster"         { value = aws_ecs_cluster.main.name }
EOF

write infra/terraform/terraform.tfvars.example <<'EOF'
project     = "pipelineiq"
region      = "us-east-1"
db_password = "REPLACE_ME"
EOF

# ---------------------------------------------------------------------------
# Go: api-gateway
# ---------------------------------------------------------------------------
write services/api-gateway/cmd/main.go <<'EOF'
package main

import (
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
)

func proxy(target string) http.Handler {
	u, err := url.Parse(target)
	if err != nil {
		log.Fatalf("bad upstream %s: %v", target, err)
	}
	return httputil.NewSingleHostReverseProxy(u)
}

func main() {
	r := chi.NewRouter()
	r.Use(middleware.RequestID, middleware.RealIP, middleware.Logger, middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins: []string{"*"},
		AllowedMethods: []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
	}))

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })

	r.Mount("/auth",         proxy(env("AUTH_URL",       "http://auth-service:8081")))
	r.Mount("/pipelines",    proxy(env("PIPELINES_URL",  "http://pipeline-orchestrator:8082")))
	r.Mount("/deployments",  proxy(env("DEPLOYMENTS_URL","http://deployment-tracker:8083")))
	r.Mount("/notifications",proxy(env("NOTIFY_URL",     "http://notifications:8084")))
	r.Mount("/analytics",    proxy(env("ANALYTICS_URL",  "http://analytics-worker:8085")))

	addr := ":" + env("PORT", "8080")
	log.Printf("api-gateway listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, r))
}

func env(k, def string) string { if v := os.Getenv(k); v != "" { return v }; return def }
EOF

write services/api-gateway/Dockerfile <<'EOF'
FROM golang:1.22-alpine AS build
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/api-gateway ./cmd

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/api-gateway /api-gateway
USER nonroot:nonroot
EXPOSE 8080
HEALTHCHECK CMD ["/api-gateway", "-healthcheck"]
ENTRYPOINT ["/api-gateway"]
EOF

write services/api-gateway/go.mod <<'EOF'
module github.com/pipelineiq/api-gateway

go 1.22

require (
	github.com/go-chi/chi/v5 v5.0.12
	github.com/go-chi/cors v1.2.1
)
EOF

# ---------------------------------------------------------------------------
# Go: auth-service
# ---------------------------------------------------------------------------
write services/auth-service/cmd/main.go <<'EOF'
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/golang-jwt/jwt/v5"
)

type loginReq struct{ Email, Password string }
type tokenResp struct{ Token string `json:"token"` }

func main() {
	r := chi.NewRouter()
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })

	r.Post("/login", func(w http.ResponseWriter, req *http.Request) {
		var in loginReq
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, err.Error(), 400); return
		}
		claims := jwt.MapClaims{
			"sub": in.Email,
			"iss": os.Getenv("JWT_ISSUER"),
			"exp": time.Now().Add(8 * time.Hour).Unix(),
		}
		tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
		s, _ := tok.SignedString([]byte(os.Getenv("JWT_SECRET")))
		json.NewEncoder(w).Encode(tokenResp{Token: s})
	})

	r.Get("/me", func(w http.ResponseWriter, req *http.Request) {
		w.Write([]byte(`{"id":"demo","roles":["admin"]}`))
	})

	addr := ":" + envOr("PORT", "8081")
	log.Printf("auth-service listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, r))
}

func envOr(k, d string) string { if v := os.Getenv(k); v != "" { return v }; return d }
EOF

write services/auth-service/Dockerfile <<'EOF'
FROM golang:1.22-alpine AS build
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/auth-service ./cmd

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/auth-service /auth-service
USER nonroot:nonroot
EXPOSE 8081
ENTRYPOINT ["/auth-service"]
EOF

write services/auth-service/go.mod <<'EOF'
module github.com/pipelineiq/auth-service

go 1.22

require (
	github.com/go-chi/chi/v5 v5.0.12
	github.com/golang-jwt/jwt/v5 v5.2.1
)
EOF

# ---------------------------------------------------------------------------
# Go: pipeline-orchestrator
# ---------------------------------------------------------------------------
write services/pipeline-orchestrator/cmd/main.go <<'EOF'
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
)

type Pipeline struct {
	ID, Name, Repo, Branch string
}

var pipelines = map[string]Pipeline{}

func main() {
	r := chi.NewRouter()
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })

	r.Get("/", func(w http.ResponseWriter, _ *http.Request) {
		json.NewEncoder(w).Encode(pipelines)
	})

	r.Post("/", func(w http.ResponseWriter, req *http.Request) {
		var p Pipeline
		if err := json.NewDecoder(req.Body).Decode(&p); err != nil {
			http.Error(w, err.Error(), 400); return
		}
		pipelines[p.ID] = p
		w.WriteHeader(201)
	})

	r.Post("/{id}/trigger", func(w http.ResponseWriter, req *http.Request) {
		id := chi.URLParam(req, "id")
		log.Printf("trigger pipeline %s", id)
		w.Write([]byte(`{"status":"queued"}`))
	})

	r.Post("/webhooks/{provider}", func(w http.ResponseWriter, req *http.Request) {
		log.Printf("webhook from %s", chi.URLParam(req, "provider"))
		w.WriteHeader(202)
	})

	addr := ":" + envOr("PORT", "8082")
	log.Printf("pipeline-orchestrator listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, r))
}

func envOr(k, d string) string { if v := os.Getenv(k); v != "" { return v }; return d }
EOF

write services/pipeline-orchestrator/Dockerfile <<'EOF'
FROM golang:1.22-alpine AS build
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/pipeline-orchestrator ./cmd

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/pipeline-orchestrator /pipeline-orchestrator
USER nonroot:nonroot
EXPOSE 8082
ENTRYPOINT ["/pipeline-orchestrator"]
EOF

write services/pipeline-orchestrator/go.mod <<'EOF'
module github.com/pipelineiq/pipeline-orchestrator

go 1.22

require github.com/go-chi/chi/v5 v5.0.12
EOF

# ---------------------------------------------------------------------------
# Go: deployment-tracker
# ---------------------------------------------------------------------------
write services/deployment-tracker/cmd/main.go <<'EOF'
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/go-chi/chi/v5"
)

type Deployment struct {
	ID, Service, Version, Env, Status string
	Strategy                          string // canary | bluegreen | rolling
	StartedAt                         time.Time
}

var deployments = []Deployment{}

func main() {
	r := chi.NewRouter()
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })

	r.Get("/", func(w http.ResponseWriter, _ *http.Request) {
		json.NewEncoder(w).Encode(deployments)
	})

	r.Post("/", func(w http.ResponseWriter, req *http.Request) {
		var d Deployment
		if err := json.NewDecoder(req.Body).Decode(&d); err != nil {
			http.Error(w, err.Error(), 400); return
		}
		d.StartedAt = time.Now().UTC()
		d.Status = "in_progress"
		deployments = append(deployments, d)
		w.WriteHeader(201)
	})

	r.Post("/{id}/rollback", func(w http.ResponseWriter, req *http.Request) {
		id := chi.URLParam(req, "id")
		log.Printf("rollback deployment %s", id)
		w.Write([]byte(`{"status":"rolled_back"}`))
	})

	r.Post("/{id}/approve", func(w http.ResponseWriter, req *http.Request) {
		id := chi.URLParam(req, "id")
		log.Printf("approve deployment %s", id)
		w.Write([]byte(`{"status":"approved"}`))
	})

	addr := ":" + envOr("PORT", "8083")
	log.Printf("deployment-tracker listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, r))
}

func envOr(k, d string) string { if v := os.Getenv(k); v != "" { return v }; return d }
EOF

write services/deployment-tracker/Dockerfile <<'EOF'
FROM golang:1.22-alpine AS build
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/deployment-tracker ./cmd

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/deployment-tracker /deployment-tracker
USER nonroot:nonroot
EXPOSE 8083
ENTRYPOINT ["/deployment-tracker"]
EOF

write services/deployment-tracker/go.mod <<'EOF'
module github.com/pipelineiq/deployment-tracker

go 1.22

require github.com/go-chi/chi/v5 v5.0.12
EOF

# ---------------------------------------------------------------------------
# Python: notifications
# ---------------------------------------------------------------------------
write services/notifications/app/main.py <<'EOF'
from fastapi import FastAPI
from .config import settings
from .delivery import deliver

app = FastAPI(title="PipelineIQ Notifications")

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.post("/alerts/test")
async def test_alert(channel: str = "slack"):
    await deliver(channel, {"title": "Test alert", "body": "Hello from PipelineIQ"})
    return {"sent": True, "channel": channel}

@app.get("/policies")
def list_policies():
    return settings.policies
EOF

write services/notifications/app/config.py <<'EOF'
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    database_url: str = "postgres://localhost/pipelineiq"
    kafka_brokers: str = "localhost:9092"
    slack_webhook_url: str | None = None
    pagerduty_routing_key: str | None = None
    smtp_host: str | None = None
    smtp_port: int = 587
    policies: list[dict] = []

settings = Settings()
EOF

write services/notifications/app/consumer.py <<'EOF'
import asyncio, json, logging
from aiokafka import AIOKafkaConsumer
from .config import settings
from .delivery import deliver

log = logging.getLogger(__name__)

async def run():
    consumer = AIOKafkaConsumer(
        "alerts",
        bootstrap_servers=settings.kafka_brokers,
        group_id="notifications",
        value_deserializer=lambda v: json.loads(v.decode()),
    )
    await consumer.start()
    try:
        async for msg in consumer:
            evt = msg.value
            log.info("alert event: %s", evt)
            await deliver(evt.get("channel", "slack"), evt)
    finally:
        await consumer.stop()

if __name__ == "__main__":
    asyncio.run(run())
EOF

write services/notifications/app/delivery.py <<'EOF'
import httpx, smtplib, ssl
from email.mime.text import MIMEText
from .config import settings

async def deliver(channel: str, payload: dict):
    if channel == "slack" and settings.slack_webhook_url:
        async with httpx.AsyncClient() as c:
            await c.post(settings.slack_webhook_url, json={"text": payload.get("title", "")})
    elif channel == "pagerduty" and settings.pagerduty_routing_key:
        async with httpx.AsyncClient() as c:
            await c.post(
                "https://events.pagerduty.com/v2/enqueue",
                json={
                    "routing_key": settings.pagerduty_routing_key,
                    "event_action": "trigger",
                    "payload": {
                        "summary": payload.get("title", "PipelineIQ alert"),
                        "severity": payload.get("severity", "warning"),
                        "source": "pipelineiq",
                    },
                },
            )
    elif channel == "email" and settings.smtp_host:
        msg = MIMEText(payload.get("body", ""))
        msg["Subject"] = payload.get("title", "PipelineIQ alert")
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as s:
            s.starttls(context=ssl.create_default_context())
            s.send_message(msg)
EOF

write services/notifications/tests/test_alerts.py <<'EOF'
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_healthz():
    assert client.get("/healthz").json() == {"status": "ok"}

def test_policies():
    r = client.get("/policies")
    assert r.status_code == 200
    assert isinstance(r.json(), list)
EOF

write services/notifications/Dockerfile <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN adduser --disabled-password --no-create-home appuser
USER appuser
EXPOSE 8084
HEALTHCHECK CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8084/healthz').status==200 else 1)"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8084"]
EOF

write services/notifications/requirements.txt <<'EOF'
fastapi==0.111.0
uvicorn[standard]==0.30.0
pydantic-settings==2.3.0
httpx==0.27.0
aiokafka==0.10.0
EOF

write services/notifications/requirements-dev.txt <<'EOF'
pytest==8.2.0
ruff==0.4.0
EOF

# ---------------------------------------------------------------------------
# Python: analytics-worker
# ---------------------------------------------------------------------------
write services/analytics-worker/app/main.py <<'EOF'
from fastapi import FastAPI
from .config import settings

app = FastAPI(title="PipelineIQ Analytics")

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.get("/metrics/dora")
def dora():
    # Stub — real impl reads from analytics tables.
    return {
        "deployment_frequency_per_day": 4.2,
        "lead_time_hours": 8.1,
        "change_failure_rate": 0.07,
        "mttr_minutes": 27,
    }

@app.get("/reports/{name}")
def report(name: str):
    return {"report": name, "url": f"s3://{settings.report_bucket}/{name}.csv"}
EOF

write services/analytics-worker/app/config.py <<'EOF'
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    database_url: str = "postgres://localhost/pipelineiq"
    kafka_brokers: str = "localhost:9092"
    opensearch_url: str = "http://localhost:9200"
    report_bucket: str = "pipelineiq-reports"

settings = Settings()
EOF

write services/analytics-worker/tests/test_analytics.py <<'EOF'
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_healthz():
    assert client.get("/healthz").json() == {"status": "ok"}

def test_dora():
    r = client.get("/metrics/dora")
    assert r.status_code == 200
    body = r.json()
    for k in ["deployment_frequency_per_day", "lead_time_hours",
              "change_failure_rate", "mttr_minutes"]:
        assert k in body
EOF

write services/analytics-worker/Dockerfile <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN adduser --disabled-password --no-create-home appuser
USER appuser
EXPOSE 8085
HEALTHCHECK CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8085/healthz').status==200 else 1)"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8085"]
EOF

write services/analytics-worker/requirements.txt <<'EOF'
fastapi==0.111.0
uvicorn[standard]==0.30.0
pydantic-settings==2.3.0
opensearch-py==2.6.0
aiokafka==0.10.0
EOF

write services/analytics-worker/requirements-dev.txt <<'EOF'
pytest==8.2.0
ruff==0.4.0
EOF

# ---------------------------------------------------------------------------
# Frontend
# ---------------------------------------------------------------------------
write frontend/dashboard/package.json <<'EOF'
{
  "name": "pipelineiq-dashboard",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "lint": "eslint src --max-warnings 0",
    "format": "prettier --write src",
    "test": "vitest"
  },
  "dependencies": {
    "axios": "^1.7.2",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-router-dom": "^6.23.1"
  },
  "devDependencies": {
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.1",
    "autoprefixer": "^10.4.19",
    "eslint": "^9.4.0",
    "postcss": "^8.4.38",
    "prettier": "^3.3.2",
    "tailwindcss": "^3.4.4",
    "typescript": "^5.4.5",
    "vite": "^5.2.13",
    "vitest": "^1.6.0"
  }
}
EOF

write frontend/dashboard/tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["DOM", "DOM.Iterable", "ES2022"],
    "jsx": "react-jsx",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "resolveJsonModule": true
  },
  "include": ["src"]
}
EOF

write frontend/dashboard/vite.config.ts <<'EOF'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: { port: 5173, proxy: { "/api": "http://localhost:8080" } },
});
EOF

write frontend/dashboard/tailwind.config.js <<'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: { extend: {} },
  plugins: [],
};
EOF

write frontend/dashboard/Dockerfile <<'EOF'
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK CMD wget -qO- http://localhost/ || exit 1
EOF

write frontend/dashboard/nginx.conf <<'EOF'
server {
  listen 80;
  root /usr/share/nginx/html;
  index index.html;
  location /api/ { proxy_pass http://api-gateway:8080/; }
  location / { try_files $uri /index.html; }
}
EOF

write frontend/dashboard/src/main.tsx <<'EOF'
import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import App from "./App";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <BrowserRouter><App /></BrowserRouter>
  </React.StrictMode>,
);
EOF

write frontend/dashboard/src/App.tsx <<'EOF'
import { Routes, Route, Navigate } from "react-router-dom";
import DashboardPage from "./pages/DashboardPage";
import PipelinesPage from "./pages/PipelinesPage";
import DeploymentsPage from "./pages/DeploymentsPage";
import AlertsPage from "./pages/AlertsPage";
import ReportsPage from "./pages/ReportsPage";
import Layout from "./components/Layout";
export default function App() {
  return (
    <Layout>
      <Routes>
        <Route path="/" element={<navigate to="/dashboard" replace >}>
        <Route path="/dashboard" element={<dashboardpage >}>
        <Route path="/pipelines" element={<pipelinespage >}>
        <Route path="/deployments" element={<deploymentspage >}>
        <Route path="/alerts" element={<alertspage >}>
        <Route path="/reports" element={<reportspage >}>
      </Routes>
    </Layout>
  );
}
EOF

write frontend/dashboard/src/index.css <<'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

:root { color-scheme: light dark; }
body { margin: 0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, Apple Color Emoji, Segoe UI Emoji; }
EOF

write frontend/dashboard/src/api/client.ts <<'EOF'
import axios from "axios";
export const api = axios.create({ baseURL: "/api" });
EOF

write frontend/dashboard/src/components/Layout.tsx <<'EOF'
import { Link, useLocation } from "react-router-dom";
function NavLink({ to, children }: { to: string; children: React.ReactNode }) {
  const loc = useLocation();
  const active = loc.pathname.startsWith(to);
  return (
    <link classname="{"px-3" py-2 rounded _ + (active ? _bg-blue-600 text-white_ : _text-blue-700 hover:bg-blue-50_)} to="{to}">
      {children}
    
  );
}
export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <div classname="min-h-screen bg-gray-50">
      <header classname="bg-white border-b">
        <div classname="mx-auto max-w-6xl px-4 py-3 flex gap-4 items-center">
          <div classname="font-bold">PipelineIQ</div>
          <nav classname="flex gap-2">
            <NavLink to="/dashboard">Dashboard</NavLink>
            <NavLink to="/pipelines">Pipelines</NavLink>
            <NavLink to="/deployments">Deployments</NavLink>
            <NavLink to="/alerts">Alerts</NavLink>
            <NavLink to="/reports">Reports</NavLink>
          </nav>
        </div>
      </header>
      <main classname="mx-auto max-w-6xl px-4 py-6">{children}</main>
    </div>
  );
}
EOF

write frontend/dashboard/src/components/DORAMetricCard.tsx <<'EOF'
type Props = { label: string; value: string; tooltip?: string };
export default function DORAMetricCard({ label, value }: Props) {
  return (
    <div classname="rounded border bg-white p-4">
      <div classname="text-sm text-gray-500">{label}</div>
      <div classname="text-2xl font-semibold mt-1">{value}</div>
    </div>
  );
}
EOF

write frontend/dashboard/src/components/PipelineHealthCard.tsx <<'EOF'
export default function PipelineHealthCard() {
  return (
    <div classname="rounded border bg-white p-4">
      <div classname="text-sm text-gray-500">Pipeline Health</div>
      <div classname="mt-2 text-green-700 font-medium">All systems nominal</div>
    </div>
  );
}
EOF

write frontend/dashboard/src/components/DeploymentActivityFeed.tsx <<'EOF'
const items = [
  { time: "09:12", text: "Deploy api-gateway v1.2.4 to staging" },
  { time: "08:47", text: "Rollback notifications v0.9.1 from prod" },
  { time: "07:33", text: "Deploy orchestrator v1.10.0 to prod (canary 20%)" },
];
export default function DeploymentActivityFeed() {
  return (
    <div classname="rounded border bg-white p-4">
      <div classname="text-sm text-gray-500 mb-2">Recent Activity</div>
      <ul classname="space-y-2">
        {items.map((i, idx) => (
          <li key="{idx}" classname="text-sm text-gray-700">
            <span classname="text-gray-400">{i.time}</span> — {i.text}
          </li>
        ))}
      </ul>
    </div>
  );
}
EOF

write frontend/dashboard/src/pages/DashboardPage.tsx <<'EOF'
import DORAMetricCard from "../components/DORAMetricCard";
import PipelineHealthCard from "../components/PipelineHealthCard";
import DeploymentActivityFeed from "../components/DeploymentActivityFeed";
export default function DashboardPage() {
  return (
    <div classname="grid grid-cols-12 gap-4">
      <div classname="col-span-12 md:col-span-3"><DORAMetricCard label="Deployments/day" value="4.2" /></div>
      <div classname="col-span-12 md:col-span-3"><DORAMetricCard label="Lead time (hrs)" value="8.1" /></div>
      <div classname="col-span-12 md:col-span-3"><DORAMetricCard label="Change failure rate" value="7%" /></div>
      <div classname="col-span-12 md:col-span-3"><DORAMetricCard label="MTTR (min)" value="27" /></div>
      <div classname="col-span-12 md:col-span-8"><PipelineHealthCard /></div>
      <div classname="col-span-12 md:col-span-4"><DeploymentActivityFeed /></div>
    </div>
  );
}
EOF

write frontend/dashboard/src/pages/PipelinesPage.tsx <<'EOF'
export default function PipelinesPage() {
  return (
    <div classname="rounded border bg-white p-4">
      <div classname="font-medium">Pipelines</div>
      <p classname="text-sm text-gray-600 mt-1">Create, edit, and trigger pipelines. VCS webhooks supported.</p>
    </div>
  );
}
EOF

write frontend/dashboard/src/pages/DeploymentsPage.tsx <<'EOF'
export default function DeploymentsPage() {
  return (
    <div classname="rounded border bg-white p-4">
      <div classname="font-medium">Deployments</div>
      <p classname="text-sm text-gray-600 mt-1">Track in-flight and historical deployments across environments.</p>
    </div>
  );
}
EOF

write frontend/dashboard/src/pages/AlertsPage.tsx <<'EOF'
export default function AlertsPage() {
  return (
    <div classname="rounded border bg-white p-4">
      <div classname="font-medium">Alerts & Notifications</div>
      <p classname="text-sm text-gray-600 mt-1">Manage alert rules and delivery channels (Slack, Email, PagerDuty).</p>
    </div>
  );
}
EOF

write frontend/dashboard/src/pages/ReportsPage.tsx <<'EOF'
export default function ReportsPage() {
  return (
    <div classname="rounded border bg-white p-4">
      <div classname="font-medium">Reports</div>
      <p classname="text-sm text-gray-600 mt-1">Generate and download periodic analytics exports.</p>
    </div>
  );
}
EOF

# ---------------------------------------------------------------------------
# Database migrations (stubs)
# ---------------------------------------------------------------------------
write db/migrations/001_auth_schema.sql <<'EOF'
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
EOF

write db/migrations/002_pipelines_schema.sql <<'EOF'
CREATE TABLE IF NOT EXISTS pipelines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  repo TEXT NOT NULL,
  branch TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
EOF

write db/migrations/003_deployments_schema.sql <<'EOF'
CREATE TABLE IF NOT EXISTS deployments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service TEXT NOT NULL,
  version TEXT NOT NULL,
  env TEXT NOT NULL,
  status TEXT NOT NULL,
  strategy TEXT NOT NULL DEFAULT 'rolling',
  started_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
EOF

write db/migrations/004_notifications_schema.sql <<'EOF'
CREATE TABLE IF NOT EXISTS alert_policies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  channel TEXT NOT NULL,
  severity TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
EOF

write db/migrations/005_analytics_schema.sql <<'EOF'
CREATE TABLE IF NOT EXISTS dora_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date DATE NOT NULL,
  deployment_frequency_per_day NUMERIC NOT NULL,
  lead_time_hours NUMERIC NOT NULL,
  change_failure_rate NUMERIC NOT NULL,
  mttr_minutes NUMERIC NOT NULL
);
EOF

# ---------------------------------------------------------------------------
# Scripts
# ---------------------------------------------------------------------------
write scripts/setup-local.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Bootstrapping local dev environment..."
docker-compose up -d
sleep 5
echo "Apply migrations..."
for f in db/migrations/*.sql; do
  echo "applying $f"
  psql "$DATABASE_URL" -f "$f"
done
echo "Done."
EOF

# ---------------------------------------------------------------------------
# Docs
# ---------------------------------------------------------------------------
write docs/api-reference.md <<'EOF'
# PipelineIQ API Reference

High-level catalog of service endpoints. For detailed OpenAPI/Swagger, see each service.

## api-gateway
- GET /healthz

## auth-service
- POST /login
- GET /me
- GET /healthz

## pipeline-orchestrator
- GET / (list pipelines)
- POST / (create pipeline)
- POST /{id}/trigger
- POST /webhooks/{provider}
- GET /healthz

## deployment-tracker
- GET / (list deployments)
- POST / (create deployment)
- POST /{id}/rollback
- POST /{id}/approve
- GET /healthz

## notifications
- POST /alerts/test
- GET /policies
- GET /healthz

## analytics-worker
- GET /metrics/dora
- GET /reports/{name}
- GET /healthz
EOF

echo "==> PipelineIQ repository created at: ${ROOT}"
echo "Next steps:"
echo "  cd ${ROOT}"
echo "  git init && git add ."
echo "  git commit -m 'Initial PipelineIQ repository — full service architecture'"
echo "  git branch -M main"
echo "  git remote add origin https://github.com/mroberts-PipelineIQ/PipelineIQ-Demo.git"
echo "  git push -u origin main"
</reportspage></alertspage></deploymentspage></pipelinespage></dashboardpage></navigate>
