# Dockerized SOF-ELK

SOF-ELK as a compose stack instead of the upstream VM appliance. Same parsers,
same dashboards, same index layout, without downloading a 20 GB appliance image.

- Elastic stack 9.4.3, every image pinned by tag and digest.
- SOF-ELK content vendored from upstream `public/v20260706`, unmodified.
- Logstash pipeline, Elasticsearch templates and Kibana saved objects all load
  on `docker compose up`.

## Quick start

```sh
sudo sysctl -w vm.max_map_count=262144       # Elasticsearch 9.x requires this
mkdir -p elasticsearch-data filebeat-data resources/GeoIP
chmod 777 elasticsearch-data filebeat-data resources/GeoIP
docker compose build
docker compose up -d
```

First start takes a few minutes. Elasticsearch has to bootstrap, Kibana has to
build its browser bundles, and Logstash compiles 83 pipeline files. The
`dashboard-loader` container waits for Kibana, loads everything and exits 0.

Then browse to:

- `kibana.localhost` for Kibana
- `droppy.localhost` for the upload UI, which writes into `server-files/`

Set `BASE_URL` to use a real domain, and `TRAEFIK_CONFIG=traefik.toml` for the
TLS entrypoint.

## Getting data in

Drop files into `server-files/<type>/`, either through droppy or straight on
disk. Filebeat watches those directories, tags each file with its type, and
ships to Logstash. The directories match the ingest directories the VM creates
in `/logstash`: `syslog`, `httpd`, `zeek`, `nfarch`, `aws`, `azure`, `gcp`,
`gws`, `kape`, `plaso`, `microsoft365`, `kubernetes`, `hayabusa`, `appleul`,
`passivedns`, `volatility/*`.

Live syslog goes to Logstash on 5514/udp, 5514/tcp or relp on 5516. Those ports
are internal to the compose network. Publish them by adding a host mapping to
the `logstash` service, for example `"5514:5514/udp"`.

`server-files/httpd/test.log` is a synthetic Apache log used for smoke testing.
Filebeat's `filestream` input fingerprints the first 1024 bytes of a file to
identify it, so **files under 1024 bytes are never ingested**. A one-line test
file will sit there and do nothing.

Indices are named `<type>-YYYY.MM`: `httpdlog-2026.09`, `netflow-2026.09`,
`zeek-2026.09`. Anything with no recognized type lands in `logstash-YYYY.MM`.

## What is vendored, and how to update it

`sof-elk/` is a verbatim copy of
[philhagen/sof-elk](https://github.com/philhagen/sof-elk) at branch
`public/v20260706`, commit `321142e`. `sof-elk/UPSTREAM` records the exact
commit. Nothing in that directory is edited, so a future update is a clean
replacement rather than a merge:

```sh
git clone --depth 1 --branch public/vYYYYMMDD https://github.com/philhagen/sof-elk.git /tmp/sof-elk-upstream
rm -rf sof-elk && mkdir sof-elk && (cd /tmp/sof-elk-upstream && tar --exclude=.git -cf - .) | tar -xf - -C sof-elk
# then edit sof-elk/UPSTREAM with the new branch and commit
```

Upstream releases are branches named `public/vYYYYMMDD`, not GitHub releases.

## How the Docker glue maps to the VM

The VM installs SOF-ELK with the ansible playbook in `sof-elk/ansible/`. That
playbook is the reference for everything under `docker/`.

| VM step | Here |
|---|---|
| symlink `configfiles/*` into `/etc/logstash/conf.d` | `docker/logstash/entrypoint.sh` symlinks them into `/usr/share/logstash/pipeline` |
| `logstash-plugin install` at build time | `docker/logstash/Dockerfile` |
| `-Xss4m` in `/etc/logstash/jvm.options` | `LS_JAVA_OPTS` on the logstash service |
| `post_merge.sh` creates `/logstash/*` ingest dirs | committed directories under `server-files/` |
| `load_all_dashboards.sh` run by the finalize role | the `dashboard-loader` service |
| `geoip_bootstrap.sh` downloads MaxMind databases | see GeoIP below |

Two Logstash config files are overridden rather than edited in place, in
`docker/logstash/pipeline-overrides/`. The entrypoint links overrides in last,
under the vendored file's name, so a same-named override wins:

- `9900-output-elasticsearch-consolidated.conf` adds a `hosts` line. The VM runs
  Elasticsearch on localhost. Here it is a separate container.
- `0006-input-logspout.conf` and `1005-preprocess-logspout.conf` are additions,
  not overrides. They exist only for the optional logspout service.

`-Xss4m` is not tuning. The vendored pipeline is 83 files deep and compiling it
overflows the default 1 MB JVM thread stack, which Logstash reports as "Stack
overflow error while compiling Pipeline" and then exits.

## GeoIP

`8051-postprocess-ip_addresses.conf` hardcodes `/usr/local/share/GeoIP/
GeoLite2-City.mmdb` and `GeoLite2-ASN.mmdb`, and the `geoip` filter refuses to
start when either is missing. The VM downloads them with a free MaxMind account.

There is no account here, so `docker/logstash/entrypoint.sh` seeds
`resources/GeoIP/` from the copies bundled inside the Logstash image, once, if
the files are absent. Those copies are older than MaxMind's current data. To use
current data, run `geoipupdate` yourself and drop the `.mmdb` files into
`resources/GeoIP/`. The entrypoint leaves existing files alone.

The VM also installs a weekly cron job to refresh them. This stack has no cron.

## Container logs (logspout)

`logspout` ships this stack's own container logs to Logstash. It is off by
default, because container logs are not forensic source data and they crowd out
real evidence in the SOF-ELK data views. Turn it on with:

```sh
docker compose --profile logspout up -d
```

Its events go to `dockerlogs-YYYY.MM`, never to `logstash-*`. Expect Elasticsearch
mapping rejections in that index: it has no template, and JSON log lines from
different containers disagree about field types.

`bekt/logspout-logstash` is unmaintained (last published 2019, `latest` only). It
is pinned by digest so builds stay reproducible. Before relying on it, consider
[`gliderlabs/logspout`](https://github.com/gliderlabs/logspout) with a Logstash
adapter, or Filebeat's Docker input.

## Stack versions

| Component | Version | Image |
|---|---|---|
| Elasticsearch | 9.4.3 | `docker.elastic.co/elasticsearch/elasticsearch` |
| Kibana | 9.4.3 | `docker.elastic.co/kibana/kibana` |
| Logstash | 9.4.3 | `docker.elastic.co/logstash/logstash`, plus plugins |
| Filebeat | 9.4.3 | `docker.elastic.co/beats/filebeat` |
| Traefik | 3.7.7 | `traefik` |
| droppy | 12.2.0 | `silverwind/droppy` |
| logspout | pinned digest | `bekt/logspout-logstash` |

9.4.3 matches upstream's `elastic_stack_version` at the vendored commit. Keep
them in step: SOF-ELK pins its own stack version and the parsers assume it.

To bump a version, pull the new tag, re-resolve the digest with
`docker buildx imagetools inspect <ref> --format '{{.Manifest.Digest}}'`, then
update the `image:` line and its `# pinned` comment.

## Security

Elasticsearch security is on by default from 8.x. This stack turns it off
(`xpack.security.enabled: false`) to keep the original no-auth posture. Every
service talks plain HTTP to `elasticsearch:9200` with no credentials.

**Do not put this on an untrusted network as-is.** To productionize: enable
security, generate credentials, and add username, password and TLS to the
Kibana, Logstash and Filebeat connections.

## What is not here

- No cron. The VM refreshes GeoIP databases and checks for updates on a
  schedule. Run those by hand or add a scheduler.
- No elastalert, domain_stats or freq services. The vendored `lib/systemd/`
  units and `lib/elastalert_rules/` are carried along unused.
- `logstash-input-google_pubsub` is not installed. The only config that uses it
  is an inactive sample in `sof-elk/configfiles-templates/`.
- The SOF-ELK logo is not swapped into Kibana. `post_merge.sh` does that by
  symlinking into the Kibana install, which does not survive a container.

## Verified

Checked on a single host, Docker 29.6.1, against the vendored commit:

- Elasticsearch reaches green, 43 shards, 0 unassigned.
- Logstash compiles all 83 pipeline files and reports `Pipelines running
  {count: 1}` with zero `[ERROR]` lines.
- Kibana `/api/status` returns 200 at level `available`.
- The loader installs 9 component templates, 18 index templates and 109 saved
  objects (11 dashboards, 57 lens, 8 maps, 7 searches, 6 visualizations, 20 data
  views). Re-running it is a no-op that still exits 0.
- A 41-line Apache log dropped in `server-files/httpd/` produces 41 documents in
  `httpdlog-2026.09`, tagged `parse_done`, with `source.ip` mapped as `ip` and
  GeoIP and ASN fields populated.
- A syslog line sent to 5514/udp is parsed into `log.syslog.*` and indexed in
  `logstash-2026.09`.
