FROM scratch

ADD image/openwrt-x86-64-generic-rootfs.tar.gz /

COPY files/ /

COPY 98-root-password /etc/uci-defaults/98-root-password
COPY 99-docker-network /etc/uci-defaults/99-docker-network
COPY 100-openvpn-bind /etc/uci-defaults/100-openvpn-bind

RUN chmod +x \
    /etc/uci-defaults/98-root-password \
    /etc/uci-defaults/99-docker-network \
    /etc/uci-defaults/100-openvpn-bind

CMD ["/sbin/init"]
