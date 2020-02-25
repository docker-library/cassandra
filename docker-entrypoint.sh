#!/bin/bash
set -e

# first arg is `-f` or `--some-option`
# or there are no args
if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
	set -- cassandra -f "$@"
fi

# allow the container to be started with `--user`
if [ "$1" = 'cassandra' -a "$(id -u)" = '0' ]; then
	find /var/lib/cassandra /var/log/cassandra "$CASSANDRA_CONFIG" \
		\! -user cassandra -exec chown cassandra '{}' +
	exec gosu cassandra "$BASH_SOURCE" "$@"
fi

_ip_address() {
	# scrape the first non-localhost IP address of the container
	# in Swarm Mode, we often get two IPs -- the container IP, and the (shared) VIP, and the container IP should always be first
	ip address | awk '
		$1 == "inet" && $NF != "lo" {
			gsub(/\/.+$/, "", $2)
			print $2
			exit
		}
	'
}

# "sed -i", but without "mv" (which doesn't work on a bind-mounted file, for example)
_sed-in-place() {
	local filename="$1"; shift
	local tempFile
	tempFile="$(mktemp)"
	sed "$@" "$filename" > "$tempFile"
	cat "$tempFile" > "$filename"
	rm "$tempFile"
}

if [ "$1" = 'cassandra' ]; then
	: ${CASSANDRA_RPC_ADDRESS='0.0.0.0'}

	: ${CASSANDRA_LISTEN_ADDRESS='auto'}
	if [ "$CASSANDRA_LISTEN_ADDRESS" = 'auto' ]; then
		CASSANDRA_LISTEN_ADDRESS="$(_ip_address)"
	fi

	: ${CASSANDRA_BROADCAST_ADDRESS="$CASSANDRA_LISTEN_ADDRESS"}

	if [ "$CASSANDRA_BROADCAST_ADDRESS" = 'auto' ]; then
		CASSANDRA_BROADCAST_ADDRESS="$(_ip_address)"
	fi
	: ${CASSANDRA_BROADCAST_RPC_ADDRESS:=$CASSANDRA_BROADCAST_ADDRESS}

	if [ -n "${CASSANDRA_NAME:+1}" ]; then
		: ${CASSANDRA_SEEDS:="cassandra"}
	fi
	: ${CASSANDRA_SEEDS:="$CASSANDRA_BROADCAST_ADDRESS"}

	_sed-in-place "$CASSANDRA_CONFIG/cassandra.yaml" \
		-r 's/(- seeds:).*/\1 "'"$CASSANDRA_SEEDS"'"/'

	for yaml in \
		broadcast_address \
		broadcast_rpc_address \
		cluster_name \
		endpoint_snitch \
		listen_address \
		num_tokens \
		rpc_address \
		start_rpc \
	; do
		var="CASSANDRA_${yaml^^}"
		val="${!var}"
		if [ "$val" ]; then
			_sed-in-place "$CASSANDRA_CONFIG/cassandra.yaml" \
				-r 's/^(# )?('"$yaml"':).*/\2 '"$val"'/'
		fi
	done

	for rackdc in dc rack; do
		var="CASSANDRA_${rackdc^^}"
		val="${!var}"
		if [ "$val" ]; then
			_sed-in-place "$CASSANDRA_CONFIG/cassandra-rackdc.properties" \
				-r 's/^('"$rackdc"'=).*/\1 '"$val"'/'
		fi
	done

	if [ -d /docker-entrypoint-initdb.d ]; then
		#start cassandra executable in background
		echo "BOOTSTRAP  $(date +%H-%M-%S) start cassandra in the background"
		cassandra -p /var/run/cassandra/cassandra.pid &

		#wait for cluster init
		for i in {60..0}; do
			if [ $(nmap -sT ${CASSANDRA_BROADCAST_ADDRESS} -p 9042,9160 | { grep 'tcp open' || true; } | wc -l) -eq 2 ]; then
				break
			fi
			echo "BOOTSTRAP  $(date +%H-%M-%S) cassandra init process in progress..."
			sleep 1
		done

		if [ "$i" = 0 ]; then
			echo >&2 "BOOTSTRAP  $(date +%H-%M-%S) cassandra init process failed."
			exit 1
		fi

		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)     echo "BOOTSTRAP  $(date +%H-%M-%S) $0: running $f"; . "$f" ;;
				*.cql)    echo "BOOTSTRAP  $(date +%H-%M-%S) $0: running $f"; cqlsh -e "$(cat $f)"; echo ;;
				*.cql.gz) echo "BOOTSTRAP  $(date +%H-%M-%S) $0: running $f"; cqlsh -e "$(zcat $f)"; echo ;;
				*)        echo "BOOTSTRAP  $(date +%H-%M-%S) $0: ignoring $f" ;;
			esac
			echo
		done

		sleep 5
		pid=$(cat /var/run/cassandra/cassandra.pid)

		if ! kill -s TERM "$pid"; then
			echo >&2 "BOOTSTRAP  $(date +%H-%M-%S) cassandra init process failed."
			exit 1
		fi
        sleep 5
        echo "BOOTSTRAP  $(date +%H-%M-%S) cassandra init process done. Ready for start up."
    fi
fi

exec "$@"
