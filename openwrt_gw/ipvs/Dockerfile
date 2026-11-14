FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
        ipvsadm \
        iproute2 \
        procps && \
    rm -rf /var/lib/apt/lists/*

COPY ipvs.sh /ipvs.sh
COPY watchdog.sh /watchdog.sh

RUN chmod +x /ipvs.sh /watchdog.sh

CMD ["/watchdog.sh"]
