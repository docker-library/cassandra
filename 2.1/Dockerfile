# vim:set ft=dockerfile:
FROM cassandra:2.1

RUN apt-get update \
	&& apt-get install -y curl dnsutils \
	&& rm -rf /var/lib/apt/lists/*

COPY *.sh /
RUN cat replace_node_patch.sh >> $CASSANDRA_CONFIG/cassandra-env.sh \
    && rm replace_node_patch.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

RUN mkdir -p /root/.cassandra /home/cassandra \
  && echo "[connection]\nclient_timeout=40" > /root/.cassandra/cqlshrc

VOLUME /var/lib/cassandra

ENV CASSANDRA_SEEDS=auto \
    CASSANDRA_BROADCAST_ADDRESS=auto \
    CASSANDRA_LISTEN_ADDRESS=auto

# 7000: intra-node communication
# 7001: TLS intra-node communication
# 7199: JMX
# 9042: CQL
# 9160: thrift service
EXPOSE 7000 7001 7199 9042 9160
CMD ["cassandra", "-f"]
