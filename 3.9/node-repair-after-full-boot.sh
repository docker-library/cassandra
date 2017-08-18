#!/bin/bash

# wait till node is up booted and joined (UN)
until nodetool status | grep $1 | grep -q "UN";
do
  sleep 10
done

echo "REPAIR"
nodetool repair

echo "CLEANUP"
nodetool cleanup -j 2

