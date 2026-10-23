FROM alpine:latest


RUN apk add --no-cache \
    nginx \
    bash \
    easy-rsa \
    openssl \
    openvpn \
    fcgiwrap \
    spawn-fcgi \
    util-linux


RUN mkdir -p \
    /run/nginx \
    /var/www/html \
    /var/www/cgi-bin \
    /scripts \
    /ca/config


COPY www/ /var/www/html/
COPY nginx.conf /etc/nginx/http.d/default.conf
COPY cgi/ /var/www/cgi-bin/
COPY scripts/ /scripts/

RUN chmod +x \
    /var/www/cgi-bin/* \
    /scripts/* || true


VOLUME ["/ca"]


EXPOSE 80


CMD sh -c "\
    spawn-fcgi -s /run/fcgiwrap.sock -M 766 /usr/bin/fcgiwrap ; \
    nginx -g 'daemon off;'"
