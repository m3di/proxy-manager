FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openvpn easy-rsa iptables iproute2 curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /dev/net && \
    mknod /dev/net/tun c 10 200 || true && \
    chmod 600 /dev/net/tun

COPY entrypoint.sh /entrypoint.sh
COPY generate-client.sh /usr/local/bin/generate-client
RUN chmod +x /entrypoint.sh /usr/local/bin/generate-client

EXPOSE 1194/tcp

VOLUME ["/etc/openvpn"]

ENTRYPOINT ["/entrypoint.sh"]
