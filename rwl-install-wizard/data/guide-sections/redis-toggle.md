### Redis deploy toggle

The bundled Redis subchart (Bitnami standalone) is controlled by `redis.deploy`.
The chart default is `redis.deploy: true` — Redis deploys automatically on a
standard `helm install`.

The generated overlay sets this explicitly to make the intent visible in your
values file and to protect against an accidental override in another overlay file.

If you are connecting to an **external** Redis instead, set `redis.deploy: false`
and supply `redis.external.host` / `redis.external.port` — see the `subcharts`
axis (BYO external option) for that path.

_Source: charts/runwhen-platform/values.yaml `redis.deploy: true` (line 1025)._
