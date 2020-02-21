FROM adoptopenjdk:8-jre-hotspot-bionic

# explicitly set user/group IDs
RUN set -eux; \
	groupadd -r cassandra --gid=999; \
	useradd -r -g cassandra --uid=999 cassandra

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
# solves warning: "jemalloc shared library could not be preloaded to speed up memory allocations"
		libjemalloc1 \
# "free" is used by cassandra-env.sh
		procps \
# "cqlsh" needs a python interpreter
		python \
# "ip" is not required by Cassandra itself, but is commonly used in scripting Cassandra's configuration (since it is so fixated on explicit IP addresses)
		iproute2 \
# Cassandra will automatically use numactl if available
#   https://github.com/apache/cassandra/blob/18bcda2d4c2eba7370a0b21f33eed37cb730bbb3/bin/cassandra#L90-L100
#   https://github.com/apache/cassandra/commit/604c0e87dc67fa65f6904ef9a98a029c9f2f865a
		numactl \
	; \
	rm -rf /var/lib/apt/lists/*

# grab gosu for easy step-down from root
ENV GOSU_VERSION 1.11
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends ca-certificates dirmngr gnupg wget; \
	rm -rf /var/lib/apt/lists/*; \
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	chmod +x /usr/local/bin/gosu; \
	gosu --version; \
	gosu nobody true

ENV CASSANDRA_HOME /opt/cassandra
ENV CASSANDRA_CONF /etc/cassandra
ENV PATH $CASSANDRA_HOME/bin:$PATH

# https://cwiki.apache.org/confluence/display/CASSANDRA2/DebianPackaging#DebianPackaging-AddingRepositoryKeys
ENV GPG_KEYS \
# gpg: key 0353B12C: public key "T Jake Luciani <jake@apache.org>" imported
	514A2AD631A57A16DD0047EC749D6EEC0353B12C \
# gpg: key FE4B2BDA: public key "Michael Shuler <michael@pbandjelly.org>" imported
	A26E528B271F19B9E5D8E19EA278B781FE4B2BDA \
# gpg: key E91335D77E3E87CB: public key "Michael Semb Wever <mick@thelastpickle.com>" imported
	A4C465FEA0C552561A392A61E91335D77E3E87CB

ENV CASSANDRA_VERSION 3.11.6
ENV CASSANDRA_SHA512 0e778f8fb4a050fde3ec174a9ca365e49ef437cd9e61280b6b4dcba950418a3d04a104bb41aed1add858e2acc2513cf7df4065ca5ca751dd1daf60e70adc4042

RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends ca-certificates dirmngr gnupg wget; \
	rm -rf /var/lib/apt/lists/*; \
	\
	ddist() { \
		local f="$1"; shift; \
		local distFile="$1"; shift; \
		local success=; \
		local distUrl=; \
		for distUrl in \
# https://issues.apache.org/jira/browse/INFRA-8753?focusedCommentId=14735394#comment-14735394
			'https://www.apache.org/dyn/closer.cgi?action=download&filename=' \
# if the version is outdated (or we're grabbing the .asc file), we might have to pull from the dist/archive :/
			https://www-us.apache.org/dist/ \
			https://www.apache.org/dist/ \
			https://archive.apache.org/dist/ \
		; do \
			if wget --progress=dot:giga -O "$f" "$distUrl$distFile" && [ -s "$f" ]; then \
				success=1; \
				break; \
			fi; \
		done; \
		[ -n "$success" ]; \
	}; \
	\
	ddist 'cassandra-bin.tgz' "cassandra/$CASSANDRA_VERSION/apache-cassandra-$CASSANDRA_VERSION-bin.tar.gz"; \
	echo "$CASSANDRA_SHA512 *cassandra-bin.tgz" | sha512sum --check --strict -; \
	\
	ddist 'cassandra-bin.tgz.asc' "cassandra/$CASSANDRA_VERSION/apache-cassandra-$CASSANDRA_VERSION-bin.tar.gz.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	for key in $GPG_KEYS; do \
		gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
	done; \
	gpg --batch --verify cassandra-bin.tgz.asc cassandra-bin.tgz; \
	rm -rf "$GNUPGHOME"; \
	\
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	\
	mkdir -p "$CASSANDRA_HOME"; \
	tar --extract --file cassandra-bin.tgz --directory "$CASSANDRA_HOME" --strip-components 1; \
	rm cassandra-bin.tgz*; \
	\
	[ ! -e "$CASSANDRA_CONF" ]; \
	mv "$CASSANDRA_HOME/conf" "$CASSANDRA_CONF"; \
	ln -sT "$CASSANDRA_CONF" "$CASSANDRA_HOME/conf"; \
	\
	dpkgArch="$(dpkg --print-architecture)"; \
	case "$dpkgArch" in \
		ppc64el) \
# https://issues.apache.org/jira/browse/CASSANDRA-13345
# "The stack size specified is too small, Specify at least 328k"
			if grep -q -- '^-Xss' "$CASSANDRA_CONF/jvm.options"; then \
# 3.11+ (jvm.options)
				grep -- '^-Xss256k$' "$CASSANDRA_CONF/jvm.options"; \
				sed -ri 's/^-Xss256k$/-Xss512k/' "$CASSANDRA_CONF/jvm.options"; \
				grep -- '^-Xss512k$' "$CASSANDRA_CONF/jvm.options"; \
			elif grep -q -- '-Xss256k' "$CASSANDRA_CONF/cassandra-env.sh"; then \
# 3.0 (cassandra-env.sh)
				sed -ri 's/-Xss256k/-Xss512k/g' "$CASSANDRA_CONF/cassandra-env.sh"; \
				grep -- '-Xss512k' "$CASSANDRA_CONF/cassandra-env.sh"; \
			fi; \
			;; \
	esac; \
	\
	mkdir -p "$CASSANDRA_CONF" /var/lib/cassandra /var/log/cassandra; \
	chown -R cassandra:cassandra "$CASSANDRA_CONF" /var/lib/cassandra /var/log/cassandra; \
	chmod 777 "$CASSANDRA_CONF" /var/lib/cassandra /var/log/cassandra; \
	ln -sT /var/lib/cassandra "$CASSANDRA_HOME/data"; \
	ln -sT /var/log/cassandra "$CASSANDRA_HOME/logs"; \
	\
# smoke test
	cassandra -v

VOLUME /var/lib/cassandra

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /docker-entrypoint.sh # backwards compat
ENTRYPOINT ["docker-entrypoint.sh"]

# 7000: intra-node communication
# 7001: TLS intra-node communication
# 7199: JMX
# 9042: CQL
# 9160: thrift service
EXPOSE 7000 7001 7199 9042 9160
CMD ["cassandra", "-f"]
