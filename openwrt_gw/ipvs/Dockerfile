FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ipvsadm \
        iproute2 \
        procps && \
    rm -rf /var/lib/apt/lists/*

COPY ipvs.sh /ipvs.sh

RUN chmod +x /ipvs.sh

CMD ["/ipvs.sh"]
