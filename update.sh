#!/bin/bash
set -eo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )


travisEnv=
for version in "${versions[@]}"; do
	dist="${version//./}"
	packagesUrl="http://www.apache.org/dist/cassandra/debian/dists/${dist}x/main/binary-amd64/Packages.gz"
	fullVersion="$(curl -fsSL "$packagesUrl" | gunzip | grep -m1 -A10 "^Package: cassandra\$" | grep -m1 '^Version: ' | cut -d' ' -f2)"
	
	(
		set -x
		cp docker-entrypoint.sh "$version/"
		sed 's/%%CASSANDRA_DIST%%/'$dist'/g; s/%%CASSANDRA_VERSION%%/'$fullVersion'/g' Dockerfile.template > "$version/Dockerfile"
	)
	
	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
