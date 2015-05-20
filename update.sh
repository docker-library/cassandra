#!/bin/bash
set -eo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )


for version in "${versions[@]}"; do
	dist="${version//./}"
	packagesUrl="http://www.apache.org/dist/cassandra/debian/dists/${dist}x/main/binary-amd64/Packages.gz"
	fullVersion="$(curl -fsSL "$packagesUrl" | gunzip | grep -m1 -A10 "^Package: cassandra\$" | grep -m1 '^Version: ' | cut -d' ' -f2)"
	
	(
		set -x
		cp docker-entrypoint.sh Dockerfile.template "$version/"
		mv "$version/Dockerfile.template" "$version/Dockerfile"
		sed -i 's/%%CASSANDRA_DIST%%/'$dist'/g; s/%%CASSANDRA_VERSION%%/'$fullVersion'/g' "$version/Dockerfile"
	)
done

