### Networking — non-RFC1918 pod CIDR

Your pods run on a non-RFC1918 CIDR. Mimir's memberlist autodetects a "private"
IP and fails to start otherwise. The generated `values-cluster.yaml` pins
`metricstore.config.memberlist.bind_addr`/`advertise_addr` to `127.0.0.1`
(correct for the single-replica monolithic Mimir this chart ships).

After install, if Mimir still misbehaves, also raise its log level off `warn` so
you get diagnostic output.
