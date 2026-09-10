# syntax=docker/dockerfile:1
FROM docker.elastic.co/logstash/logstash:9.4.3@sha256:03d605e3938504512a584b0d1209cf5768fdbaacb43b910a09c640bf7565fb12

# Plugins the vendored configfiles need. Matches sof-elk/ansible/roles/logstash/
# defaults/main.yaml minus logstash-input-google_pubsub, which only the inactive
# sample in sof-elk/configfiles-templates/ uses.
#   logstash-input-relp        0004-input-syslog.conf
#   logstash-filter-rest       1952-preprocess-kubernetes.conf, 6801-azure.conf
#   logstash-filter-json_encode  6901-aws.conf
#   logstash-filter-tld        installed by upstream, unused at this commit
RUN logstash-plugin install \
        logstash-input-relp \
        logstash-filter-tld \
        logstash-filter-rest \
        logstash-filter-json_encode

COPY pipeline-overrides/ /usr/share/logstash/pipeline-overrides/
COPY entrypoint.sh /usr/local/bin/sof-elk-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/sof-elk-entrypoint.sh"]
