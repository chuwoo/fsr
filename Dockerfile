FROM python:2.7-alpine
LABEL maintainer="chuwoo <chuwooem@gmail.com>"
USER root
RUN set -ex \
        && apk add --no-cache tar libsodium-dev openssl \
        && apk add supervisor \
        && wget -O /tmp/shadowsocksr-3.2.2.tar.gz https://github.com/shadowsocksrr/shadowsocksr/archive/3.2.2.tar.gz \
        && tar zxf /tmp/shadowsocksr-3.2.2.tar.gz -C /tmp \
        && mkdir /var/fsr \
        && mv /tmp/shadowsocksr-3.2.2/shadowsocks /var/fsr/ \
        && rm -fr /tmp/shadowsocksr-3.2.2 \
        && rm -f /tmp/shadowsocksr-3.2.2.tar.gz \
        && wget -O /tmp/frp-0.48.0.tar.gz https://github.com/fatedier/frp/releases/download/v0.48.0/frp_0.48.0_linux_amd64.tar.gz \
    && tar zxf /tmp/frp-0.48.0.tar.gz -C /tmp \
    && mv /tmp/frp_0.48.0_linux_amd64/frpc /var/fsr/ \
    && rm -fr /tmp/frp_0.48.0_linux_amd64 \
    && rm -f /tmp/frp-0.48.0.tar.gz \
    && wget -O /var/fsr/config.json https://raw.githubusercontent.com/chuwoo/fsr/main/config.json \
    && wget -O /var/fsr/frpc.ini https://raw.githubusercontent.com/chuwoo/fsr/main/frpc.ini \
    && wget -O /etc/supervisord.conf https://raw.githubusercontent.com/chuwoo/fsr/main/supervisord.conf
#COPY ./config.json /var/fsr/config.json
#COPY ./frpc.ini /var/fsr/frpc.ini
#ADD supervisord.conf /etc
#COPY ./entrypoint.sh /var/fsr/entrypoint.sh
#RUN chmod +x /var/fsr/entrypoint.sh
WORKDIR /var/fsr
#EXPOSE 5555
EXPOSE 7000
#RUN echo user=root >>  /etc/supervisord.conf
CMD ["/usr/bin/supervisord","-n", "-c", "/etc/supervisord.conf"]
