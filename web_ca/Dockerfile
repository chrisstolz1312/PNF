FROM debian:13

ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        systemd \
        systemd-sysv \
        nginx \
        bash \
        easy-rsa \
        openssl \
        openvpn \
        fcgiwrap \
        spawn-fcgi \
        util-linux \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Systemd services that are not useful inside this container.
RUN systemctl mask \
        dev-hugepages.mount \
        sys-fs-fuse-connections.mount \
        systemd-remount-fs.service \
        systemd-udev-trigger.service \
        systemd-udevd.service \
        getty.target

RUN mkdir -p \
    /run/nginx \
    /var/www/html \
    /var/www/cgi-bin \
    /scripts \
    /ca/config

# Web application and CA scripts.
COPY www/ /var/www/html/
COPY cgi/ /var/www/cgi-bin/
COPY scripts/ /scripts/

# Debian Nginx site configuration.
COPY nginx.conf /etc/nginx/sites-available/default

# PNF systemd units.
COPY systemd/pnf-fcgiwrap.service /etc/systemd/system/
COPY systemd/pnf-crl.service /etc/systemd/system/
COPY systemd/pnf-crl.timer /etc/systemd/system/

RUN chmod +x /var/www/cgi-bin/* /scripts/* && \
    systemctl enable nginx.service && \
    systemctl enable pnf-fcgiwrap.service && \
    systemctl enable pnf-crl.timer

VOLUME ["/ca"]

EXPOSE 80

STOPSIGNAL SIGRTMIN+3

CMD ["/sbin/init"]
