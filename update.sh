#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

# -slim is automatically added
defaultDebianSuite='buster'
declare -A debianSuite=(
	#[2.2]='jessie'
)

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

travisEnv=
for version in "${versions[@]}"; do
	dist="${version//./}"
	packagesUrl="https://www.apache.org/dist/cassandra/debian/dists/${dist}x/main/binary-amd64/Packages.gz"
	fullVersion="$(
		curl -fsSL "$packagesUrl" \
			| gunzip \
			| awk -F ': ' '
				$1 == "Package" { pkg = $2 }
				pkg == "cassandra" && $1 == "Version" { print $2 }
			'
	)"

	echo "$version: $fullVersion"

	versionSuite="${debianSuite[$version]:-$defaultDebianSuite}-slim"
	cp -a docker-entrypoint.sh "$version/"
	sed \
		-e 's/%%CASSANDRA_DIST%%/'$dist'/g;' \
		-e 's/%%CASSANDRA_VERSION%%/'$fullVersion'/g' \
		-e 's/%%SUITE%%/'$versionSuite'/g;' \
		Dockerfile.template > "$version/Dockerfile"

	# remove the "/docker-entrypoint.sh" backwards-compatibility symlink in Cassandra 3.12+
	case "$version" in
		2.*|3.0|3.11) ;;
		*) sed -i '/^RUN .* \/docker-entrypoint.sh # backwards compat$/d' "$version/Dockerfile" ;;
	esac
	# TODO once Cassandra 2.x and 3.x are deprecated, we should remove this from the template itself (and remove this code too)

	travisEnv='\n  - VERSION='"$version ARCH=i386$travisEnv"
	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
