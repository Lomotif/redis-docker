#!/bin/sh
set -e

IPADDR=$(ifconfig eth0 | grep 'inet addr' | cut -d ':' -f 2 | cut -d ' ' -f 1)

if [ "$1" = 'redis-server' ]; then
  chown -R redis .
  sed "s/^bind .*$/bind ${IPADDR}/" /etc/redis/redis.conf > /tmp/redis.conf
  exec su-exec redis "$1" /tmp/redis.conf
fi

exec "$@"
