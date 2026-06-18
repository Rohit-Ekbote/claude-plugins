## Mimir crashloops: `no private IP address found`

**Symptom:** `metricstore`/mimir pod crashloops; logs (once `log_level` is above
`warn`) show `no private IP address found` and `memberlist-kv invalid service
state: Stopping`.

**Cause:** the pod CIDR is non-RFC1918 (e.g. 21.121.x). Mimir's memberlist
private-IP autodetection only accepts RFC1918 ranges.

**Fix:** set `metricstore.config.memberlist.bind_addr: ["127.0.0.1"]` and
`advertise_addr: "127.0.0.1"`. Safe for single-replica monolithic Mimir. The
wizard's `values-cluster.yaml` already contains this when you answered
"non-RFC1918". Also bump Mimir `log_level` off `warn` or you get zero logs.

_Source: INSTALL-FRICTIONS.md §23 / 2026-06-15 entry._
