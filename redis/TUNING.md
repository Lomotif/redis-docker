
# Tuning Redis for Performance

## References
 - http://shokunin.co/blog/2014/11/11/operational_redis.html
 - https://russ.garrett.co.uk/2009/01/01/linux-kernel-tuning/
 - https://wiki.mikejung.biz/Sysctl_tweaks

## Kernel network parameters

We configure a couple of these to help boost redis' performance

### `net.ipv4.tcp_tw_reuse`
Ref: http://serverfault.com/questions/342741/what-are-the-ramifications-of-setting-tcp-tw-recycle-reuse-to-1

Essentially allows the server to reuse a TCP socket that's in `TIME_WAIT`, without waiting for it to expire. For
a redis server that's expecting many short-lived connections for a few sources, this could help reduce the latency
in waiting for a socket to free up

Some sites recommend using `tcp_tw_recycle`, which is a more aggressive reusing setting, but that seems to cause
problems with external clients behind a NAT. Since each connection from behind the NAT looks like it comes from the same
public IP, the kernel with `tcp_tw_recycle` on may reuse sockets for different clients behind same NAT, which ends up
confusing both client and server (Ref: http://serverfault.com/a/715883)

### `vm.overcommit_memory`
Ref: http://redis.io/topics/faq#background-saving-is-failing-with-a-fork-error-under-linux-even-if-i39ve-a-lot-of-free-ram

Allows the server to optimistically allocate memory for expensive operations like `fork()`, particularly when there
isn't enough free RAM when persisting a DB to disk.
