#!/bin/sh
# docker/entrypoint.sh
set -e

# подставляем секреты из файлов в переменные окружения
for var in DB_PASSWORD APP_KEY CRM_KEY DIRECTORY_KEY; do
    file_var="${var}_FILE"
    file_path=$(eval echo "\$$file_var")

    if [ -n "$file_path" ] && [ -r "$file_path" ]; then
        export "$var=$(cat "$file_path")"
    fi
done

php artisan config:cache
php artisan route:cache
php artisan event:cache

exec "$@"
