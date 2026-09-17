# Dockerfile
# ---------- общая основа ----------
FROM php:8.5-fpm-alpine AS base

RUN apk add --no-cache \
        postgresql-dev \
        icu-dev \
        oniguruma-dev \
        libzip-dev \
        freetype-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        linux-headers \
        $PHPIZE_DEPS \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" \
        pdo_pgsql \
        intl \
        bcmath \
        zip \
        gd \
        opcache \
        pcntl \
 && pecl install redis \
 && docker-php-ext-enable redis \
 && apk del $PHPIZE_DEPS \
 && rm -rf /tmp/pear

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# пользователь с тем же UID, что у разработчика на хосте
ARG UID=1000
ARG GID=1000
RUN addgroup -g ${GID} app \
 && adduser -u ${UID} -G app -s /bin/sh -D app

# ---------- зависимости ----------
FROM base AS vendor

COPY composer.json composer.lock ./

RUN composer install \
        --no-dev \
        --no-scripts \
        --no-autoloader \
        --prefer-dist \
        --no-interaction \
        --no-progress

# ---------- локальная разработка ----------
FROM base AS dev

RUN pecl install xdebug && docker-php-ext-enable xdebug

COPY docker/php/php.dev.ini /usr/local/etc/php/conf.d/99-app.ini
COPY docker/php/xdebug.ini /usr/local/etc/php/conf.d/98-xdebug.ini

USER app
CMD ["php-fpm"]

# ---------- production ----------
FROM base AS prod

COPY docker/php/php.prod.ini /usr/local/etc/php/conf.d/99-app.ini
COPY docker/php/opcache.ini /usr/local/etc/php/conf.d/97-opcache.ini

# сначала зависимости из отдельной ступени
COPY --from=vendor /var/www/html/vendor ./vendor

# потом исходники
COPY --chown=app:app . .

RUN composer dump-autoload --optimize --classmap-authoritative --no-dev \
 && php artisan config:cache \
 && php artisan route:cache \
 && php artisan event:cache \
 && chown -R app:app storage bootstrap/cache \
 && chmod -R 775 storage bootstrap/cache

USER app

EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD php -r 'exit(@fsockopen("127.0.0.1", 9000) ? 0 : 1);'

CMD ["php-fpm"]
