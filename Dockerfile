# the different stages of this Dockerfile are meant to be built into separate images
# https://docs.docker.com/compose/compose-file/#target

ARG PHP_VERSION=7.3
ARG NODE_VERSION=10
ARG NGINX_VERSION=1.16

FROM scratch as scratch

COPY . /code/

FROM php:${PHP_VERSION}-fpm-alpine AS application_php

# persistent / runtime deps
RUN apk add --no-cache \
		acl \
		file \
		gettext \
		git \
		mariadb-client \
		shadow \
	;

ARG APCU_VERSION=5.1.17
RUN set -eux; \
	apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		coreutils \
		freetype-dev \
		icu-dev \
		libjpeg-turbo-dev \
		libpng-dev \
		libtool \
		libwebp-dev \
		libzip-dev \
		mariadb-dev \
		zlib-dev \
	; \
	\
	docker-php-ext-configure gd --with-jpeg-dir=/usr/include/ --with-png-dir=/usr/include --with-webp-dir=/usr/include --with-freetype-dir=/usr/include/; \
	docker-php-ext-configure zip --with-libzip; \
	docker-php-ext-install -j$(nproc) \
		exif \
		gd \
		intl \
		pdo_mysql \
		zip \
	; \
	pecl install \
		apcu-${APCU_VERSION} \
		redis \
	; \
	pecl clear-cache; \
	docker-php-ext-enable \
		apcu \
		opcache \
		redis \
	; \
	\
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --no-cache --virtual .application-phpexts-rundeps $runDeps; \
	\
	apk del .build-deps

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
COPY --from=scratch code/docker/php/php.ini /usr/local/etc/php/php.ini
COPY --from=scratch code/docker/php/php-cli.ini /usr/local/etc/php/php-cli.ini
COPY --from=scratch code/docker/php/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

ARG USER_UID=1000

RUN usermod -u $USER_UID www-data -s /bin/sh

USER www-data
WORKDIR /home/www-data

RUN set -eux; \
	composer global require "hirak/prestissimo:^0.3" --prefer-dist --no-progress --no-suggest --classmap-authoritative; \
	composer clear-cache

ENV PATH="${PATH}:/home/www-data/.composer/vendor/bin"

# build for production
ARG APP_ENV=prod

RUN mkdir /home/www-data/application

WORKDIR /home/www-data/application

# prevent the reinstallation of vendors at every changes in the source code
COPY --from=scratch --chown=www-data:www-data code/composer.json code/composer.lock code/symfony.lock ./
RUN set -eux; \
	composer install --prefer-dist --no-autoloader --no-scripts --no-progress --no-suggest; \
	composer clear-cache

# copy only specifically what we need
COPY --from=scratch --chown=www-data:www-data code/.env code/.env.test ./
COPY --from=scratch --chown=www-data:www-data code/webpack.config.js ./
COPY --from=scratch --chown=www-data:www-data code/assets assets/
COPY --from=scratch --chown=www-data:www-data code/bin bin/
COPY --from=scratch --chown=www-data:www-data code/config config/
COPY --from=scratch --chown=www-data:www-data code/config config/
COPY --from=scratch --chown=www-data:www-data code/public public/
COPY --from=scratch --chown=www-data:www-data code/templates templates/
COPY --from=scratch --chown=www-data:www-data code/translations translations/

RUN set -eux; \
	mkdir -p var/cache var/log; \
	composer dump-autoload --classmap-authoritative; \
	APP_SECRET='' composer run-script post-install-cmd; \
	chmod +x bin/console; sync;

VOLUME /home/www-data/application/var

ENTRYPOINT ["docker-entrypoint"]
CMD ["php-fpm"]

FROM node:${NODE_VERSION}-alpine AS application_nodejs

RUN set -eux; \
	apk add --no-cache --virtual .build-deps \
		g++ \
		gcc \
		git \
		make \
		python \
		shadow \
	;

COPY --from=scratch code/docker/nodejs/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

ARG USER_UID=1000

RUN usermod -u $USER_UID node

USER node

RUN mkdir /home/node/application
RUN mkdir /home/node/application/public

WORKDIR /home/node/application

COPY --from=scratch --chown=node:node code/package.json code/yarn.lock code/webpack.config.js ./
COPY --from=scratch --chown=node:node code/assets assets/
RUN set -eux; \
	yarn install; \
	yarn cache clean

#COPY --from=scratch --from=application_php --chown=node:node /home/www-data/application/public public/
COPY --from=application_php --chown=node:node /home/www-data/application/vendor/sylius/ui-bundle/Resources/private/ vendor/sylius/ui-bundle/Resources/private/

RUN set -eux; \
	NODE_ENV=prod yarn build

ENTRYPOINT ["docker-entrypoint"]
CMD ["yarn", "dev"]

FROM nginx:${NGINX_VERSION}-alpine AS application_nginx

COPY --from=scratch code/docker/nginx/conf.d/default.conf /etc/nginx/conf.d/

WORKDIR /home/www-data/application/

COPY --from=application_php /home/www-data/application/public public/
COPY --from=application_nodejs /home/node/application/public public/

FROM application_php as application_php_runtime

USER www-data

WORKDIR /home/www-data/application

COPY --from=application_nodejs --chown=www-data:www-data /home/node/application/public public/

ENTRYPOINT ["docker-entrypoint"]
CMD ["php-fpm"]
