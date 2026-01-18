#!/bin/sh
set -e

# Select config template based on environment (default: dev)
CONFIG_TEMPLATE="/etc/prometheus/prometheus.yml.tpl"
if [ "$PROMETHEUS_ENV" = "aws" ]; then
    CONFIG_TEMPLATE="/etc/prometheus/prometheus-aws.yml.tpl"
fi

# Generate Prometheus config from template using sed
# Replace ${BACKEND_TARGET} with actual value
sed "s|\${BACKEND_TARGET}|${BACKEND_TARGET}|g" "$CONFIG_TEMPLATE" > /tmp/prometheus.yml

# Start Prometheus with generated config
exec /bin/prometheus \
  --config.file=/tmp/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.enable-lifecycle \
  --storage.tsdb.retention.time=7d \
  "$@"

