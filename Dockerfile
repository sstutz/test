FROM php:7.3-fpm-alpine AS base

RUN apk --no-cache add nginx supervisor
# mpdecimal is needed for php-decimal and is not yet in the main repository
RUN apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing mpdecimal

FROM base AS deps
RUN apk add --no-cache $PHPIZE_DEPS coreutils
RUN pecl install decimal-1.3.0
RUN echo "$(curl -sS https://composer.github.io/installer.sig) -" > composer-setup.php.sig \
    && curl -sS https://getcomposer.org/installer | tee composer-setup.php | sha384sum -c composer-setup.php.sig \
    && php composer-setup.php --install-dir=/usr/bin --filename=composer \
    && rm composer-setup.php; rm composer-setup.php.sig;

FROM base AS release
COPY --from=deps /usr/bin/composer /usr/bin/composer
COPY --from=deps \
    /usr/local/lib/php/extensions/no-debug-non-zts-20180731/decimal.so \
    /usr/local/lib/php/extensions/no-debug-non-zts-20180731/decimal.so

RUN docker-php-ext-install pdo_mysql
RUN docker-php-ext-enable decimal

# Use the default production configuration
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# Use these to override defaults
COPY .docker/config/fpm-pool.conf /usr/local/etc/php-fpm.d/zzz_custom.conf
COPY .docker/config/php.ini $PHP_INI_DIR/conf.d/zzz_custom.ini

# Configure supervisord
COPY .docker/config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Configure nginx
COPY .docker/nginx/conf.d /etc/nginx/conf.d
COPY .docker/nginx/nginx.conf /etc/nginx/nginx.conf

# Add custom error pages
COPY --chown=www-data:www-data .docker/nginx/error-pages /var/www/errors

# Add application
COPY --chown=www-data:www-data . /var/www/html

WORKDIR /var/www/html

EXPOSE 80
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
