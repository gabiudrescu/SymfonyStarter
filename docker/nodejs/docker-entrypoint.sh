#!/bin/sh
set -e

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- node "$@"
fi

if [ "$1" = 'node' ] || [ "$1" = 'npm' ]; then

	>&2 echo "Waiting for PHP to be ready..."
	until nc -z "$PHP_HOST" "$PHP_PORT"; do
		sleep 1
	done
fi

if [ "$APP_ENV" != 'prod' ]; then
    yarn install
fi

exec "$@"
