#!/bin/sh

DOCKER_SOCKET=/var/run/docker.sock
DOCKER_ENDPOINT=http://localhost/v1.46/containers/json
CONFIGS="
/etc/prometheus/prometheus-web.yml
/etc/prometheus/prometheus.yml
/etc/prometheus/alerting-rules.yml
"

indent() { sed 's/^/    /'; }

json=$(mktemp)
echo "{}" >$json

if [ -z "$WEB_USERNAME" ]; then
    echo "Missing environment variable: WEB_USERNAME" >&2
    exit 1
fi

if [ -z "$WEB_PASSWORD" ]; then
    echo "Missing environment variable: WEB_PASSWORD" >&2
    exit 1
fi

username=$WEB_USERNAME
password=$(/usr/bin/htpasswd -nbBC 10 '' "$WEB_PASSWORD" | tr -d ':\n')

jq '. + {user: {username: $u, password: $p}}' \
    --arg u "$username" \
    --arg p "$password" \
    $json | sponge $json

containers="$(curl -sS --unix-socket $DOCKER_SOCKET $DOCKER_ENDPOINT)"

if [ -z "$containers" ]; then
    echo "Cannot connect to $DOCKER_SOCKET" >&2
    exit 1
fi

targets=$(
    echo $containers |
    jq '[.[] | select(.Labels["prometheus.mode"]) |
        {mode: .Labels["prometheus.mode"],
        name: .Labels["com.docker.compose.service"],
        host: (.Labels["prometheus.host"] // .Labels["com.docker.compose.service"]),
        port: (.Labels["prometheus.port"] // .Ports[0].PrivatePort)}]'
)

jq '. + {targets: $t}' \
    --argjson t "$targets" \
    $json | sponge $json

blackbox_targets=$(
    echo "$BLACKBOX_TARGETS" \
        | tr -d '"' \
        | tr ',;\n' ' ' \
        | awk '{$1=$1}1' \
        | jq -R '[splits("\\s+")]'
)

jq '. + {blackbox_targets: $t}' \
    --argjson t "$blackbox_targets" \
    $json | sponge $json

echo "*** derived values ***"
cat $json | jq | indent

for config in $CONFIGS; do
    gomplate -c data=file://$json?type=application/json \
        -f $config.tmpl \
        -o $config
    echo "*** generated config: $config ***"
    cat $config | indent
done

exec "$@"
