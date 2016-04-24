#!/bin/bash

# Create redis config directory
function create_redis () {
  if [ ! -d /etc/redis ]; then
    sudo mkdir -p /etc/redis
    echo "/etc/redis created"
  else
    echo "/etc/redis already present"
  fi
}

# Create redis db location
function create_redis_db_location () {
  if [ ! -d /mnt/data/redis/db ]; then
    sudo mkdir -p /mnt/data/redis/db
    echo "/mnt/data/redis/db created"
  else
    echo "/mnt/data/redis/db already present"
  fi
}

case "$1" in
  redis)
    create_redis
    ;;

  redis_db)
    create_redis_db_location
    ;;

  *)
    echo 'Usage: bootstrap  redis|redis_db'
    exit 1
esac



