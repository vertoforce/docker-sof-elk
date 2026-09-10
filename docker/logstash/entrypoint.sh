#!/bin/bash
# Assemble the Logstash pipeline directory from the vendored SOF-ELK snapshot,
# then hand off to the stock Logstash entrypoint.
#
# The SOF-ELK VM does this with symlinks from /usr/local/sof-elk/configfiles into
# /etc/logstash/conf.d (see sof-elk/supporting-scripts/post_merge.sh). Same idea
# here, with one extra layer: anything in pipeline-overrides/ replaces the
# same-named vendored file, which is how the Elasticsearch host gets set without
# editing the snapshot.

set -euo pipefail

SOFELK_ROOT=${SOFELK_ROOT:-/usr/local/sof-elk}
PIPELINE_DIR=${PIPELINE_DIR:-/usr/share/logstash/pipeline}
OVERRIDE_DIR=${OVERRIDE_DIR:-/usr/share/logstash/pipeline-overrides}
GEOIP_DIR=${GEOIP_DIR:-/usr/local/share/GeoIP}

mkdir -p "${PIPELINE_DIR}"
find "${PIPELINE_DIR}" -mindepth 1 -delete

for conf in "${SOFELK_ROOT}"/configfiles/*.conf; do
    [ -e "${conf}" ] || continue
    ln -sf "${conf}" "${PIPELINE_DIR}/$( basename "${conf}" )"
done

for conf in "${OVERRIDE_DIR}"/*.conf; do
    [ -e "${conf}" ] || continue
    ln -sf "${conf}" "${PIPELINE_DIR}/$( basename "${conf}" )"
done

echo "sof-elk: ${PIPELINE_DIR} holds $( ls -1 "${PIPELINE_DIR}" | wc -l ) pipeline files"

# 8051-postprocess-ip_addresses.conf hardcodes two MaxMind databases and the
# geoip filter refuses to start if either is missing. The VM downloads them with
# a MaxMind account (sof-elk/supporting-scripts/geoip_bootstrap.sh). No account
# here, so seed the mount from the copies bundled in the Logstash image. They are
# older than MaxMind's current data. Drop fresh .mmdb files into resources/GeoIP
# to override.
seed_geoip() {
    local bundled
    bundled=$( find /usr/share/logstash/vendor/bundle -name 'GeoLite2-City.mmdb' -print -quit 2>/dev/null || true )
    [ -n "${bundled}" ] || { echo "sof-elk: no bundled GeoIP databases found" >&2; return; }
    bundled=$( dirname "${bundled}" )

    mkdir -p "${GEOIP_DIR}" 2>/dev/null || true
    for db in GeoLite2-City.mmdb GeoLite2-ASN.mmdb; do
        if [ ! -s "${GEOIP_DIR}/${db}" ] && [ -s "${bundled}/${db}" ]; then
            if cp "${bundled}/${db}" "${GEOIP_DIR}/${db}" 2>/dev/null; then
                echo "sof-elk: seeded ${GEOIP_DIR}/${db} from the Logstash image"
            else
                echo "sof-elk: cannot write ${GEOIP_DIR}/${db} - the geoip filter will fail to start." >&2
                echo "sof-elk: run 'mkdir -p resources/GeoIP && chmod 777 resources/GeoIP' on the host." >&2
            fi
        fi
    done
}
seed_geoip

exec /usr/local/bin/docker-entrypoint "$@"
