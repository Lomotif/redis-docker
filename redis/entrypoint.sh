#!/bin/sh
set -e

if [ "$1" = '/run.sh' ]; then
  chown -R redis .
  exec su-exec redis "$@"
fi

exec "$@"
