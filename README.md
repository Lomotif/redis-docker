
# Setup

Ensure the necessary directories are set up

    $ bin/bootstrap redis      # Create /etc/redis
    $ bin/bootstrap redis_db   # Create /mnt/data/redis/db

# Configuration

Copy the provided redis configuration file to the (newly created?) `/etc/redis`, and edit as necessary

    $ sudo cp redis/redis.conf /etc/redis

If needed, copy a redis `.rdb` file into the data directory

    $ sudo cp /path/to/dump.rdb /mnt/data/redis/db/dump.rdb

These two folders will be mounted in the container at run time

# Running

We set two special options on the `docker run` command

    --ulimit nofile=10032

    We bump the number of file descriptors in order to bump the number of open connections

    --cpuset-cpus="2,3"

    Set the CPU affinity to two specific CPUs. While Redis is single-threaded, we set affinity
    to two CPUs since Redis will spin up background threads/process for flushing to disk.
    Through this, we attempt to avoid conflict with other containers/apps on the system.


    $ docker run -d -v /etc/redis:/etc/redis:ro -v /mnt/data/redis/db:/var/redis/db --ulimit nofile=10032 --cpuset-cpus="2,3" --name redis lomotif/redis


# Sentinels and Slaves

In a simple replicated Redis setup (3 data nodes – 1 of which being a master, 3 sentinels), it sometimes
can be tricky to bootstrap a cluster from scratch. Previously, what this entailed was booting an explict
master Redis + sentinel node, spinning up the replicas around the initial masters, failing over the original
master node, then once the replicas have taken over, remove the original masters.

Those are very many steps that need to be performed in sequence, and sometimes failing which, resulted in
the entire process needing to be restarted from scratch.

We've introduced a couple of configuration options to this image that might make the above process easier.


## Bootstrapping a Replica Cluster

In previous versions of this container, containers booted as slaves (ie. with neither `-e MASTER=true` nor
`-e SENTINEL=true`) _absolutely required_ to contact an existing Redis master node before they would even
boot. This often necessitated spinning up a node that was explicitly configured as a master, having the slave
nodes connect to that _first_, then gradually failing over and removing the master node.

We now introduce the `REDIS_MASTER_SWITCH`.

While the slave node is looping and looking for a master Redis node, if it [detects the presence](https://github.com/Lomotif/redis-docker/blob/feat_redis_ha/redis/run.sh#L147) of the `/tmp/REDIS_MASTER_SWITCH`
file, it will boot itself as a master by [not setting the SLAVEOF directive](https://github.com/Lomotif/redis-docker/blob/feat_redis_ha/redis/run.sh#L166)

With this in place, there is no longer a need for explicitly configured master nodes. Operators can simply
spin up a cluster of slave nodes, `exec` into any one of them, issue `touch /tmp/REDIS_MASTER_SWITCH` to switch
that node into a master node, then have the other nodes follow the new master.


## Bootstrapping a Sentinel Cluster

Similarly, when bootstrapping a sentinel cluster, we initially had a hard requirement on needing an existing
sentinel set up in order to find the right master to monitor.

When bootstrapping a sentinel cluster from the ground up, we don't always have an existing sentinel cluster to
follow, so we've introduced a mechanism to explicitly point any sentinel node at an existing master, so that
it may configure itself to monitor that master.

We introduce the `REDIS_MASTER_HOST`.

This option takes two forms, one as a file, pointed to by the environment variable `REDIS_MASTER_HOST_FILE`, and defaulting to `/tmp/REDIS_MASTER_HOST`, and one as the environment variable `REDIS_MASTER_HOST`.

With a known master node IP (or in a Kubernetes setup, a Service IP), we can use `REDIS_MASTER_HOST` to point
the sentinel to that IP for reference.

When using the `/tmp/REDIS_MASTER_HOST` file, simply write the IP to the file, and the initialisation script
[should pick it up](https://github.com/Lomotif/redis-docker/blob/feat_redis_ha/redis/run.sh#L50). We can do this by `exec`'ing into the container and issuing, for eg. `echo '1.2.3.4' > /tmp/REDIS_MASTER_HOST`.

The same can be done with the environment variable by passing it to the container when it starts, eg. `docker run -d --name sentinel -e REDIS_MASTER_HOST=1.2.3.4 lomotif/redis-docker:latest`.
The script will similarly [detect the environment variable](https://github.com/Lomotif/redis-docker/blob/feat_redis_ha/redis/run.sh#L57) and configure the sentinel accordingly.


## Seeking Master

The thing about Redis replica clusters and sentinels, is that masters may failover at any time. This means that
for a running cluster, the node that you once thought was the master might not actually be the master by the
time the other nodes are initialised.

The [initialisation function](https://github.com/Lomotif/redis-docker/blob/feat_redis_ha/redis/run.sh#L36) (called when booting slave and sentinel nodes), [attempts to verify](https://github.com/Lomotif/redis-docker/blob/feat_redis_ha/redis/run.sh#L71) if the node it's currently
communicating with, is indeed a master node, and if not, attempts to find out who the current master is.

This way, in the face of a cluster in flux, we make a serious attempt to always boot a node up with a proper
configuration, and speaking with a proper Redis master.

