# Dockerized Sof-ELK

## Purpose

I decided to make Sof-ELK in a dockerized deployment stack to make it:

* Easier to deploy
* Scalable
* Easy to add additional services such as file managers to uploads logs to
* Easier to manage persistent data

## Stack versions

All internet-pulled images are pinned by tag **and** digest (see `docker-compose.yaml`):

| Component | Version | Image |
|-----------|---------|-------|
| Elasticsearch | 9.4.3 | `docker.elastic.co/elasticsearch/elasticsearch` |
| Kibana | 9.4.3 | `docker.elastic.co/kibana/kibana` |
| Logstash | 9.4.3 | `docker.elastic.co/logstash/logstash` |
| Filebeat | 9.4.3 | `docker.elastic.co/beats/filebeat` |
| Traefik | 3.7.7 | `traefik` |
| droppy | 12.2.0 | `silverwind/droppy` |
| logspout | pinned digest | `bekt/logspout-logstash` (see caveat below) |

To bump a version: pull the new tag, re-resolve the digest with
`docker buildx imagetools inspect <ref> --format '{{.Manifest.Digest}}'`, then
update the `image:` line and its `# pinned` comment.

### Security note

Elasticsearch has security **on by default** since 8.x. This lab intentionally
disables it (`xpack.security.enabled: false` in
`elk_config/elasticsearch/elasticsearch.yml`) to keep the original no-auth
posture — every service here talks plain HTTP to `elasticsearch:9200` with no
credentials. **Do not expose this to an untrusted network as-is.** To
productionize, enable security, generate credentials, and add
username/password + TLS to the Kibana, Logstash, and logspout Elasticsearch
connections.

### logspout caveat

`bekt/logspout-logstash` is unmaintained (last published 2019, no semver tags —
only `latest`/`master`). It is pinned by digest so builds stay reproducible, but
before relying on it consider a maintained alternative such as
[`gliderlabs/logspout`](https://github.com/gliderlabs/logspout) built with a
Logstash/GELF adapter, or shipping container logs via Filebeat's Docker input.

# Usage

## Prerequisites

Elasticsearch 9.x requires the host kernel setting `vm.max_map_count >= 262144`:

```sh
sudo sysctl -w vm.max_map_count=262144   # add to /etc/sysctl.conf to persist
```

The compose `networks.master` uses the `overlay` driver (Swarm). To run with a
plain `docker compose up` on a single host, either `docker swarm init` first, or
change the network `driver` to `bridge`.

## Run the stack

```sh
# Set up directories
mkdir elasticsearch-data filebeat-data
chmod 777 elasticsearch-data filebeat-data
# Bring up the stack
docker compose up
```

**Note** that the stack will take a few minutes to come online depending on your hardware.  A few microservices will fail to start and restart until elasticsearch and logstash finish initializing.

## URLs

Then to access kibana and droppy, access the following URLS.  They are load balanced and sent to the appropriate microservice through docker and traefik.

`BASE_URL` by default is localhost.

* droppy.BASE_URL - Access online file browser
* kibana.BASE_URL - Access kibana

## Data streams

If you want to add data streams into logstash, you simply need to open the ports to the logstash microservice.
In `docker-compose.yaml` add ports to the `ports` section for the streams you want to allow in.
All the streams that are available are defined in the `sof-elk/configfiles/*-input-*` files.

## Method

The following describes how the dockerized sof elk was built.  It does not have every feature in sof-elk (like the included dashboards)...yet!

I basically went to each of these files in the VM

```sh
/etc/logstash/logstash.yml
/etc/filebeat/filebeat.yml
```

And I replicated their equivalents (with correct hostnames and such) in the respective `elk_config/` configs.

The following steps were taken to set up sof-elk from the sof-elk config repo

* Copied `sof-elk/lib` to `sof-elk/lib`
* Copied `sof-elk/conffiles` to `sof-elk/conffiles`
* Copied `sof-elk/grok-patterns` to `sof-elk/grok-patterns`
* Copied `sof-elk/supporting-scripts` to `sof-elk/supporting-scrips`
* Copied `lsplugins` from `sof-elk/supporting-scripts/ls_plugin_update.sh` to the plugin install command in the docker-compose.yaml for logstash
* Added `logspout.conf` to `sof-elk/conffiles` for logspout
* Changed all `sof-elk/conffiles/*output*` to contain this output line (for correct elasticsearch host)

```conf
hosts => "elasticsearch:9200"
```

* See docker-compose.yaml for mounting of each folder inside each container and environmental variables

## Future Work

* Add cron jobs to docker just like VM for updating things like geoip etc. `sof-elk/supporting-scripts/*.cron`
* Add ELK dashboards from sof-elk
* Add geoip support
