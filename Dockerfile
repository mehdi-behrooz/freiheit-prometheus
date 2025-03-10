# syntax=docker/dockerfile:1

FROM prom/prometheus:v3.2.1 AS prometheus
FROM alpine:3

RUN apk update \
    && apk add --no-cache moreutils apache2-utils curl jq gomplate

COPY --from=prometheus /bin/prometheus /bin/prometheus
COPY --from=prometheus /bin/promtool /bin/promtool
COPY --from=prometheus /npm_licenses.tar.bz2 /npm_licenses.tar.bz2
COPY --chmod=755 entrypoint.sh /usr/bin/entrypoint.sh
COPY config/*.tmpl /etc/prometheus/

ENV SCRAPE_INTERVAL=15s
ENV SERVER_NAME=localhost
ENV ALERT_DISK_USAGE=80
ENV ALERT_WAIT_TIME=1h

WORKDIR /prometheus/

EXPOSE 9090
VOLUME ["/prometheus"]
ENTRYPOINT ["/usr/bin/entrypoint.sh"]
CMD ["/bin/prometheus", \
    "--storage.tsdb.path=/prometheus", \
    "--config.file=/etc/prometheus/prometheus.yml", \
    "--web.config.file=/etc/prometheus/prometheus-web.yml"]

HEALTHCHECK --interval=5m \
     --start-period=5m \
     --start-interval=10s \
     CMD pgrep prometheus && nc -z localhost 9090 || exit 1
