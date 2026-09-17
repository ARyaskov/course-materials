COMPOSE = docker compose

.PHONY: up down restart install fresh seed test check shell logs queue

up:            ## поднять стенд и подготовить приложение
	$(COMPOSE) up -d
	$(COMPOSE) exec app composer install
	$(COMPOSE) exec app php artisan key:generate
	$(COMPOSE) exec app php artisan migrate --seed

down:          ## остановить стенд (данные в томах сохраняются)
	$(COMPOSE) down

restart:
	$(COMPOSE) restart app queue-default queue-notifications scheduler

install:
	$(COMPOSE) exec app composer install

fresh:         ## пересоздать схему и накатить сиды
	$(COMPOSE) exec app php artisan migrate:fresh --seed

seed:
	$(COMPOSE) exec app php artisan db:seed

test:
	$(COMPOSE) exec app php artisan test --parallel

check:         ## стиль, статический анализ, тесты
	$(COMPOSE) exec app ./vendor/bin/pint --test
	$(COMPOSE) exec app ./vendor/bin/phpstan analyse --memory-limit=512M
	$(COMPOSE) exec app php artisan test --parallel

shell:
	$(COMPOSE) exec app sh

logs:
	$(COMPOSE) logs -f --tail=100 app

queue:
	$(COMPOSE) logs -f --tail=100 queue-default
