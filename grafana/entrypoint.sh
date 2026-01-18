#!/bin/sh
set -e

# Replace PROMETHEUS_URL in datasource config if env var is set
if [ -n "$PROMETHEUS_URL" ]; then
    sed -i "s|PROMETHEUS_URL_PLACEHOLDER|$PROMETHEUS_URL|g" /etc/grafana/provisioning/datasources/prometheus.yml
fi

# Run Grafana
exec /run.sh "$@"

