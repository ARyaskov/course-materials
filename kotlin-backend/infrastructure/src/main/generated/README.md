Сгенерированные jOOQ-классы (`dev.atrium.infrastructure.jooq.generated.*`).

Каталог заполняется командой `scripts/jooq-codegen.sh`: поднимает PostgreSQL 18 в Docker,
применяет миграции из `src/main/resources/db/migration` и запускает `generateJooq`.
Результат коммитится — сборка не зависит от базы, diff схемы виден в pull request.
