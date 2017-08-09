#!/bin/bash
set -eo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
  echo True
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

travisEnv=
for version in "${versions[@]}"; do
	(
		set -x
		cp docker-entrypoint.sh "$version/"
		cp replace_node_patch.sh "$version/"
		sed 's/%%CASSANDRA_VERSION%%/'$version'/g' Dockerfile.template > "$version/Dockerfile"
	)
done

