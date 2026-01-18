FROM grafana/grafana:11.4.0

# Switch to root for file operations
USER root

# Create provisioning directories
RUN mkdir -p /etc/grafana/provisioning/datasources \
    && mkdir -p /etc/grafana/provisioning/dashboards \
    && mkdir -p /var/lib/grafana/dashboards

# Copy provisioning files
COPY provisioning/datasources/prometheus.yml /etc/grafana/provisioning/datasources/
COPY provisioning/dashboards/dashboards.yml /etc/grafana/provisioning/dashboards/
COPY dashboards/*.json /var/lib/grafana/dashboards/

# Copy entrypoint for dynamic config
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Fix permissions
RUN chown -R grafana:root /etc/grafana/provisioning \
    && chown -R grafana:root /var/lib/grafana/dashboards

# Switch back to grafana user
USER grafana

EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]

