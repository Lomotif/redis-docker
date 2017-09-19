#!/bin/sh
#
# Borrowed shamelessly from https://hub.docker.com/r/kubernetes/redis/

set -o errexit


export REDIS_MASTER_HOST=${REDIS_MASTER_HOST}
export REDIS_MASTER_HOST_FILE=/tmp/REDIS_MASTER_HOST
export REDIS_MASTER_NAME=${REDIS_MASTER_NAME:-redismaster}
export PORT=${REDIS_PORT:-6379}
export MAXMEMORY=${REDIS_MAXMEMORY:-1000000000}

# Evaluating variable indirection in sh
# Ref: http://stackoverflow.com/a/1014604
export REDIS_SENTINEL_HOST=${REDIS_SENTINEL_HOST}
if [ ! ${REDIS_SENTINEL_HOST} ] && [ ${REDIS_SENTINEL_SERVICE_NAME} ]; then
  SENTINEL_HOST=$(echo "${REDIS_SENTINEL_SERVICE_NAME}_SERVICE_HOST" | tr '[a-z]' '[A-Z]' | tr '-' '_')
  REDIS_SENTINEL_HOST=$(eval "echo \$${SENTINEL_HOST}")
fi

export REDIS_SENTINEL_PORT=${REDIS_SENTINEL_PORT}
if [ ! ${REDIS_SENTINEL_PORT} ] && [ ${REDIS_SENTINEL_SERVICE_NAME} ]; then
  SENTINEL_PORT=$(echo "${REDIS_SENTINEL_SERVICE_NAME}_SERVICE_PORT" | tr '[a-z]' '[A-Z]' | tr '-' '_')
  REDIS_SENTINEL_PORT=$(eval "echo \$$SENTINEL_PORT")
fi

# Taken from this StackOverflow: https://stackoverflow.com/questions/3524978/logging-functions-in-bash-and-stdout
# Ref: https://stackoverflow.com/a/3525065
log() {
    echo 1>&2 "Log message: $1"
  }

# Function that attempts to contact, and return an IP address pointing to a redis master node
seekmaster() {

  # First, attempt to contact other sentinels
  NODE=$(redis-cli -h ${REDIS_SENTINEL_HOST} -p ${REDIS_SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} | tr ',' ' ' | cut -d' ' -f1)

  # If sentinels aren't alive/responding, fallback to a hardcoded file, or environment variable
  # This is a hail mary play to bootstrap a sentinel cluster without introducing an explicit master redis/sentinel
  # Bear in mind that these values are _only to bootstrap_ the sentinel. When this master goes down, or the network changes,
  # the sentinel cluster may reconfigure themselves to recognise a different master node
  if $(echo ${NODE} | grep -qvE "^\d+.\d+.\d+.\d+$"); then

    # If this node is stuck and unable to contact a sentinel cluster, exec into this container, and
    # echo IP of desired master redis into the file pointed to by REDIS_MASTER_HOST_FILE
    # We should then be able to pick it up in the next iteration of this loop.
    if [ -f ${REDIS_MASTER_HOST_FILE} ]; then
      log "Using REDIS_MASTER_HOST_FILE at ${REDIS_MASTER_HOST_FILE}"
      NODE=$(cat ${REDIS_MASTER_HOST_FILE})

    # If you know beforehand which redis node should be used as master, simply pass its IP as an environment
    # variable when running this container. If we can't contact other sentinels, and can't find a file at
    # REDIS_MASTER_HOST_FILE, we'll check this environment variable instead.
    elif [[ ${REDIS_MASTER_HOST} ]]; then
      log "Using REDIS_MASTER_HOST environment variable: ${REDIS_MASTER_HOST}"
      NODE=${REDIS_MASTER_HOST}
    fi

    # In either case above, the cluster configuration may have changed by the time we pick up this setting, so
    # we want to confirm who exactly master is, via the ROLE command
    # The "ROLE" command output returns like so for a slave,
    #     slave 100.96.3.2 6379 connected 517221566468
    # The IP indicated is the IP of the master node.
    #
    # The return looks like this for a master
    #     master 517226770470 100.96.7.4 6379 517226722552 100.96.6.65 6379 517226722552
    # The 2 (or more) IPs being the addresses of the connected slave nodes
    ROLE=$(redis-cli -h ${NODE} ROLE)

    # If node's ROLE is slave, we want to know who its master is.
    # If the node's ROLE is master, we don't have to do anything
    if $(echo ${ROLE} | grep -q "slave"); then
      NODE=$(echo ${ROLE} | cut -d " " -f 2)  # From the "slave" role output above, we want the second field
    elif $(echo ${ROLE} | grep -q "master"); then
      NODE=${NODE}
    else
      NODE=""
    fi
  fi

  if [[ "${NODE}" ]]; then
    NODE="${NODE//\"}"  # Strip quotes
  else
    NODE=$(hostname -i)   # Attempt looking at localhost, if everything else has failed to set $NODE
  fi

  echo "${NODE}"
}

launchmaster() {
  if [[ ! -e /data/redis ]]; then
    echo "Redis master data doesn't exist, data won't be persistent!"
    mkdir /data/redis/
  fi

  IPADDR=$(ifconfig eth0 | grep 'inet addr' | cut -d ':' -f 2 | cut -d ' ' -f 1)
  IPADDR="${IPADDR} 127.0.0.1"
  sed -i "s/^bind .*$/bind ${IPADDR}/" /etc/redis/redis.conf
  sed -i "s/%maxmemory%/${MAXMEMORY}/" /etc/redis/redis.conf
  redis-server /etc/redis/redis.conf
}

launchsentinel() {
  echo "Launching as SENTINEL"

  while true; do
    MASTER=$(seekmaster)
    if $(redis-cli -h ${MASTER} INFO > /dev/null); then
      break
    fi
    echo "Connecting to MASTER failed.  Waiting..."
    sleep 10
  done

  sentinel_conf=/etc/redis/sentinel.conf
#  curl http://${KUBERNETES_RO_SERVICE_HOST}:${KUBERNETES_RO_SERVICE_PORT}/api/v1beta1/endpoints/redis-master | python /sentinel.py > ${sentinel_conf}

  IPADDR=$(ifconfig eth0 | grep 'inet addr' | cut -d ':' -f 2 | cut -d ' ' -f 1)
  IPADDR="${IPADDR} 127.0.0.1"

  echo "bind ${IPADDR}" > ${sentinel_conf}
  echo "sentinel monitor ${REDIS_MASTER_NAME} ${MASTER} ${PORT} 2" >> ${sentinel_conf}
  echo "sentinel down-after-milliseconds ${REDIS_MASTER_NAME} 10000" >> ${sentinel_conf}
  echo "sentinel failover-timeout ${REDIS_MASTER_NAME} 20000" >> ${sentinel_conf}
  echo "sentinel parallel-syncs ${REDIS_MASTER_NAME} 1" >> ${sentinel_conf}

  redis-sentinel ${sentinel_conf}
}

launchslave() {
  echo "Launching as SLAVE"

  MASTER=''
  if [[ ! -e /data/redis ]]; then
    echo "Redis slave data doesn't exist, data won't be persistent!"
    mkdir /data/redis/
  fi

  while true; do
    MASTER=$(seekmaster)

    if $(redis-cli -h "${MASTER}" INFO > /dev/null); then
      break
    fi
    echo "Connecting to master failed.  Waiting..."
    sleep 5
  done

  IPADDR=$(ifconfig eth0 | grep 'inet addr' | cut -d ':' -f 2 | cut -d ' ' -f 1)
  IPADDR="${IPADDR} 127.0.0.1"

  sed -i "s/^bind .*$/bind ${IPADDR}/" /etc/redis/slave.conf
  sed -i "s/%master-ip%/${MASTER}/" /etc/redis/slave.conf
  sed -i "s/%master-port%/${PORT}/" /etc/redis/slave.conf
  sed -i "s/%maxmemory%/${MAXMEMORY}/" /etc/redis/slave.conf
  redis-server /etc/redis/slave.conf
}

if [[ "${MASTER}" == "true" ]]; then
  launchmaster
  exit 0
fi

if [[ "${SENTINEL}" == "true" ]]; then
  launchsentinel
  exit 0
fi

launchslave
