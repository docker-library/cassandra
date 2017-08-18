
# Deal with containers scaling down and up,
# when they will scale up with the same IP as before,
# they will exit with an error because they need --replace-address while booting to take back their seat inside the cluster
seeds=$(echo $CASSANDRA_SEEDS | tr "," "\n")

# dont replace_address if node allready bootstraped
if [ ! -d "/var/lib/cassandra/data" ]; then
  for seed in $seeds; do
    echo "Trying to reach $seed"

    ping -c 1 $seed >/dev/null 2>/dev/null
    PingResult=$?

    if [ "$PingResult" -eq 0 ]; then
        if [ $CASSANDRA_BROADCAST_ADDRESS = $seed ];
        then
            echo "Current node match seed to evaluate, skip !"
            continue
        fi

        echo "$seed found, connecting to database to check if current node needs --replace_address"

        # Connect to seed to investigate node status
        QUERY_RESPONSE=$(cqlsh $seed -e "select peer, host_id, rpc_address from system.peers where peer='$CASSANDRA_BROADCAST_ADDRESS';")
        echo $QUERY_RESPONSE

        NODE_FOUND=`echo $QUERY_RESPONSE | grep -c "1 rows"`

        if [ $NODE_FOUND = 0 ]; then
            echo "Current node IP NOT FOUND in cluster, node will bootstrap and join normally"
        else
            echo "Current node ip FOUND in cluster, node will bootstrap with replace_address option and then join the cluster"
            JVM_OPTS="$JVM_OPTS -Dcassandra.replace_address=$CASSANDRA_BROADCAST_ADDRESS"

        fi

        break

    elif [ "$PingResult" -eq 1 ]; then
        echo "$seed not reachable, NEXT"
    elif [ "$PingResult" -eq 2 ]; then
        echo "$seed not reachable, service not activated yet, NEXT"
    else
        echo "Unknown status, NEXT"
    fi
  done
#else
#  echo "node allready bootstraped try to boot normally"
fi

