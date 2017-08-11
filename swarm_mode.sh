#!/bin/bash
docker service create \
  --name cassandra \
  --network mynetwork \
  -e HEAP_NEWSIZE=12M \
  -e MAX_HEAP_SIZE=64M \
  webscam/cassandra:swarm_test

