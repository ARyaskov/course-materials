# syntax=docker/dockerfile:1.7

# ---------- этап 1: зависимости ----------
FROM php:8.5-fpm-alpine AS vendor

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# composer.json несёт секцию extra.config-plugin — плагин yiisoft/config
# читает её при установке, поэтому оба файла нужны до composer install
COPY composer.json composer.lock ./

# config/ нужен на этапе установки: плагин пишет config/.merge-plan.php
COPY config/ ./config/

RUN --mount=type=cache,target=/tmp/composer-cache \
    COMPOSER_CACHE_DIR=/tmp/composer-cache \
    composer install \
        --no-dev \
        --no-interaction \
        --no-progress \
        --prefer-dist \
        --no-scripts

# исходники нужны до dump-autoload: classmap строится по src/
COPY src/ ./src/
COPY migrations/ ./migrations/

RUN composer dump-autoload --no-dev --classmap-authoritative \
 && composer yii-config-rebuild

# ---------- этап 2: рантайм ----------
FROM php:8.5-fpm-alpine AS runtime

RUN apk add --no-cache postgresql-libs icu-libs \
 && apk add --no-cache --virtual .build-deps $PHPIZE_DEPS postgresql-dev icu-dev \
 && docker-php-ext-install -j"$(nproc)" pdo_pgsql intl opcache \
 && apk del .build-deps

COPY docker/php/php.ini /usr/local/etc/php/conf.d/99-helpdesk.ini
COPY docker/php/www.conf /usr/local/etc/php-fpm.d/zz-helpdesk.conf

WORKDIR /app

COPY --from=vendor /app/vendor/ ./vendor/
COPY --from=vendor /app/config/ ./config/
COPY --from=vendor /app/src/ ./src/
COPY --from=vendor /app/migrations/ ./migrations/
COPY public/ ./public/
COPY composer.json composer.lock ./

# runtime/ создаётся в образе и отдаётся www-data: воркеры FPM пишут туда логи и кеш
RUN mkdir -p runtime/logs runtime/cache \
 && chown -R www-data:www-data runtime

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    YII_ENV=prod \
    YII_DEBUG=0

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD php -r 'exit(@fsockopen("127.0.0.1", 9000) ? 0 : 1);'

EXPOSE 9000
CMD ["php-fpm", "--nodaemonize"]
