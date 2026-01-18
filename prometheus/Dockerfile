FROM prom/prometheus:v2.54.1

# Copy Prometheus configuration templates
COPY prometheus.yml /etc/prometheus/prometheus.yml.tpl
COPY prometheus-aws.yml /etc/prometheus/prometheus-aws.yml.tpl

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh

# Prometheus image runs as nobody, but we need to set executable
USER root
RUN chmod +x /entrypoint.sh
USER nobody

# Expose Prometheus port
EXPOSE 9090

# Use custom entrypoint
ENTRYPOINT ["/entrypoint.sh"]

