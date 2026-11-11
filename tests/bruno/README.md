# Bruno collection — subscriber-api

Manual and scripted API checks used during integration and support (the Git-friendly
alternative to a Postman workspace). Open the folder in the Bruno desktop app or run it
headless:

```bash
cd tests/bruno
npx --yes @usebruno/cli run --env local                    # local container
npx --yes @usebruno/cli run --env dev --env-var apiKey=... # OpenShift dev Route
```

Requests are ordered by `seq` so the collection is a full lifecycle: health → create →
read → duplicate → suspend → delete → gone, plus a validation check.
