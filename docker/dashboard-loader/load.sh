#!/bin/bash
# One-shot: load the vendored SOF-ELK Elasticsearch templates, data views and
# Kibana saved objects, then exit.
#
# The work is done by sof-elk/supporting-scripts/load_all_dashboards.sh, which is
# written for the VM where Elasticsearch, Kibana and the repo all share a host.
# This wrapper supplies the two things that assumption provides: host overrides
# via /etc/sysconfig/sof-elk, and a Kibana package.json to read the version from.

set -euo pipefail

ES_HOST=${ES_HOST:-elasticsearch}
ES_PORT=${ES_PORT:-9200}
KIBANA_HOST=${KIBANA_HOST:-kibana}
KIBANA_PORT=${KIBANA_PORT:-5601}
MAX_WAIT=${MAX_WAIT:-600}

kibana_status_url="http://${KIBANA_HOST}:${KIBANA_PORT}/api/status"

echo "waiting for Kibana at ${kibana_status_url} (up to ${MAX_WAIT}s)"
waited=0
until curl -sf "${kibana_status_url}" | jq -e '.status.overall.level == "available"' > /dev/null 2>&1; do
    sleep 5
    waited=$(( waited + 5 ))
    if [ "${waited}" -ge "${MAX_WAIT}" ]; then
        echo "ERROR: Kibana was not available after ${MAX_WAIT}s" >&2
        exit 1
    fi
done
echo "Kibana available after ${waited}s"

# load_all_dashboards.sh reads the Kibana version out of the local install. There
# is no local install here, so build the file it looks for from the API.
mkdir -p /usr/share/kibana
curl -sf "${kibana_status_url}" \
    | jq '{version: .version.number, build: {number: .version.build_number}}' \
    > /usr/share/kibana/package.json

mkdir -p /etc/sysconfig
cat > /etc/sysconfig/sof-elk <<SYSCONFIG
es_host=${ES_HOST}
es_port=${ES_PORT}
kibana_host=${KIBANA_HOST}
kibana_port=${KIBANA_PORT}
SYSCONFIG

# Kibana creates this index with one replica, which a single-node cluster can
# never allocate, so the cluster sits at yellow forever. sof-elk/ansible/roles/
# sof-elk_finalize/tasks/main.yml deletes it for the same reason.
for index in .entity_analytics.watchlists.default; do
    code=$( curl -s -o /dev/null -w '%{http_code}' -X DELETE "http://${ES_HOST}:${ES_PORT}/${index}" )
    echo "delete ${index}: HTTP ${code}"
done

exec /usr/local/sof-elk/supporting-scripts/load_all_dashboards.sh
