# syntax=docker/dockerfile:1
FROM debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

# bash, curl and jq are what sof-elk/supporting-scripts/load_all_dashboards.sh
# needs. It also calls `mktemp --suffix`, which busybox does not implement, so
# this is a Debian base rather than Alpine.
RUN apt-get update \
    && apt-get install -y --no-install-recommends bash ca-certificates curl jq \
    && rm -rf /var/lib/apt/lists/*

COPY load.sh /usr/local/bin/load.sh

ENTRYPOINT ["/usr/local/bin/load.sh"]
