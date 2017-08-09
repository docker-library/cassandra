#!/bin/bash
docker service create -d \
  --name cassandra \
  --network mercury \
  -e HEAP_NEWSIZE=12M \
  -e MAX_HEAP_SIZE=64M \
  webscam/cassandra:swarm_test

