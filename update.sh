#!/bin/bash
set -eo pipefail

current_system=$(uname)
if [[ "${current_system}" == 'Linux' ]]; then
	platform='linux'
elif [[ "${current_system}" == 'Darwin' ]]; then
	platform='osx'
fi

if [[ "${platform}" == 'linux' ]]; then
	cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"
else
	cd "$(dirname "$(greadlink -f "$BASH_SOURCE")")"
fi

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )


for version in "${versions[@]}"; do
	dist="${version//./}"
	packagesUrl="http://www.apache.org/dist/cassandra/debian/dists/${dist}x/main/binary-amd64/Packages.gz"
	fullVersion="$(curl -fsSL "$packagesUrl" | gunzip | grep -m2 -A10 "^Package: cassandra\$" | grep -m1 '^Version: ' | cut -d' ' -f2)"
	
	(
		set -x
		cp docker-entrypoint.sh Dockerfile.template "$version/"
		mv "$version/Dockerfile.template" "$version/Dockerfile"
		if [[ "${platform}" == 'linux' ]]; then
			sed -i 's/%%CASSANDRA_DIST%%/'$dist'/g; s/%%CASSANDRA_VERSION%%/'$fullVersion'/g' "$version/Dockerfile"
		else
			sed -i '' 's/%%CASSANDRA_DIST%%/'$dist'/g; s/%%CASSANDRA_VERSION%%/'$fullVersion'/g' "$version/Dockerfile"
		fi

	)
done
exit 0
