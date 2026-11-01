# Локальные команды CourseFlow (Глава 22.8). Требуется make (Linux/macOS, Git Bash или WSL на Windows).
.PHONY: infra infra-down run test test-unit test-integration build docker migrate

infra:              ## PostgreSQL, Redis, RabbitMQ, Jaeger, Prometheus в Docker
	docker compose up -d

infra-down:
	docker compose down

run:                ## API на http://localhost:8080 (нужен infra)
	dotnet run --project src/CourseFlow.Api

aspire:             ## Всё через Aspire AppHost с Dashboard
	dotnet run --project src/CourseFlow.AppHost

build:
	dotnet build CourseFlow.slnx -c Release

test-unit:
	dotnet test tests/CourseFlow.Tests.Unit -c Release

test-integration:   ## Нужен Docker (Testcontainers)
	dotnet test tests/CourseFlow.Tests.Integration -c Release

test: test-unit test-integration

docker:             ## Образ API из Dockerfile
	docker build -t courseflow-api:local .

migrate:            ## Новая миграция: make migrate NAME=AddSomething
	dotnet ef migrations add $(NAME) --project src/CourseFlow.Api --startup-project src/CourseFlow.Api --output-dir Infrastructure/Data/Migrations
