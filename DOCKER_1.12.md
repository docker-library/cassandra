# Docker 1.12 configuration

Docker 1.12 has introduced automatic service orchestration through the docker engine swarm mode. This help with service scaling, and service discovery however the default configuration is to have the container traffic routed and load balanced through a virtual ip and a mesh network. This introduces two problems for deploying a cluster of cassanda machines using swarm mode:
1. It is hard to get the containers to seed of the virtual IP in the dns record.
2. A new interface is introduced fo rhte default `ingress network` which breaks the advertised hostname functions using `hostname -i` as you may get one of the 3 interfaces.

In order to get this working we need to set the docker swarm endpoint mode to DNS round robbin `--endpoint-mode dnsrr` and have scripting to determine the seed addressed of the containers from a reverse dns lookup.

```bash
export CASSANDRA_VERSION=3.7
export JVM_OPTIONS=''

###############################################################################
###############################################################################
docker service create --name cassandra \
  --network 'your_overlay_network' \
  --endpoint-mode dnsrr \
  --mode global \
  --constraint 'node.role	!= manager' \
  --constraint 'node.labels.network	== private' \
  --constraint 'node.labels.storage	== ssd' \
  -e "SEEDS_COMMAND=nslookup tasks.cassandra | awk '/^Address: / {print \$2}' | paste -d, -s -" \
  -e 'CASSANDRA_SEEDS=auto' \
  -e 'CASSANDRA_BROADCAST_ADDRESS=auto' \
  -e "CASSANDRA_LISTEN_ADDRESS_COMMAND=hostname -i" \
  -e "CASSANDRA_BROADCAST_ADDRESS_COMMAND=hostname -i" \
  --mount type=volume,target=/var/lib/cassandra,source=/mnt/c/cassandra \
  webscam/cassandra:$CASSANDRA_VERSION
```

You'll notice that we set the orchestration to global mode, so that there is only one cassandra container per node in the swarm. Here we also mounted an ssd partition on the host machine for the containers data directory for improved performance.
