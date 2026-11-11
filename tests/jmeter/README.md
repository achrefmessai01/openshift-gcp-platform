# JMeter — performance acceptance (RL-001)

`subscriber-api-smoke.jmx` drives N virtual users for D seconds through the health, listing
and create/delete endpoints. Every sampler asserts its HTTP status, so a failing assertion is
an error in the results.

Run headless (CLI mode) and build the HTML dashboard:

```bash
jmeter -n -t tests/jmeter/subscriber-api-smoke.jmx \
  -Jprotocol=https -Jhost=subscriber-api-staging.apps.ocp.example.com -Jport=443 \
  -Jthreads=20 -Jrampup=10 -Jduration=120 -JapiKey="$API_KEY" \
  -l reports/staging/jmeter.jtl -e -o reports/staging/jmeter-html
```

Then apply the acceptance thresholds (error rate and p95 latency per endpoint):

```bash
python tools/jmeter_gate.py reports/staging/jmeter.jtl --max-error-rate 1 --max-p95-ms 500
```

| Property   | Default   | Meaning                                  |
|------------|-----------|------------------------------------------|
| `protocol` | `http`    | `http` or `https`                        |
| `host`     | localhost | Target host (Route hostname on OpenShift)|
| `port`     | 8080      | 443 behind the Route                     |
| `threads`  | 20        | Concurrent virtual users                 |
| `rampup`   | 10        | Seconds to reach `threads`               |
| `duration` | 60        | Test duration in seconds                 |
| `apiKey`   | empty     | `X-API-Key` for the create/delete calls  |
