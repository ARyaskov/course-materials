# Makefile
.PHONY: up down fresh test check

up:
	docker compose up -d
	docker compose exec app composer install
	docker compose exec app php artisan migrate --seed

down:
	docker compose down

fresh:
	docker compose exec app php artisan migrate:fresh --seed

test:
	docker compose exec app php artisan test --parallel

check:
	docker compose exec app ./vendor/bin/pint --test
	docker compose exec app ./vendor/bin/phpstan analyse --memory-limit=512M
	docker compose exec app php artisan test --parallel
