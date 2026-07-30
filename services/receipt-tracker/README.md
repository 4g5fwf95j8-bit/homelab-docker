# Receipt Tracker

Photograph a grocery receipt on your phone → OCR (Tesseract) → structured
JSON (small local LLM via Ollama) → confirm on your phone → logged to
Postgres → charted in Grafana.

Runs entirely on server2-ai, next to your existing Ollama container.

## What's here

- `Dockerfile` / `requirements.txt` / `app/main.py` — the FastAPI service
- `app/schema.sql` — Postgres schema (auto-applied on first DB start)
- `docker-compose.yml` — `receipt-api` + `receipt-db`, included from
  `homelab-ai/docker-compose.yml`

The Grafana service lives alongside it at `services/grafana/`, pre-wired
to this DB as a datasource.

## 1. Add these to your root `.env`

```
PORT_RECEIPT_API=8001
RECEIPT_DB_NAME=receipts
RECEIPT_DB_USERNAME=receipts_user
RECEIPT_DB_PASSWORD=<choose a strong password>
RECEIPT_OLLAMA_MODEL=llama3.2:3b

PORT_GRAFANA=3001
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<choose a strong password>
```

Pick ports that don't collide with anything already in use on server2-ai.

## 2. Pull the parsing model

```bash
docker exec ollama ollama pull llama3.2:3b
```

`phi3:mini` is a fine alternative if you want to compare quality/speed —
just update `RECEIPT_OLLAMA_MODEL` to match.

## 3. Bring it up

```bash
cd /opt/docker/homelab-docker/homelab-ai
docker compose up -d --build
```

`--build` is needed the first time (and after any code changes) since
`receipt-api` builds from a local Dockerfile rather than pulling an image.

Check it's healthy:

```bash
curl http://localhost:${PORT_RECEIPT_API}/health
```

## 4. Confirm the Caddy entries

Two entries were added to `services/public/staticconfig/caddy/Caddyfile`
pointing at `100.71.98.85` (same Tailscale IP already used for the `ai.`
subdomain) — double check that's still server2-ai's current Tailscale IP,
and that the ports match what you set in `.env`. Restart Caddy on
server1-media after editing.

## 5. Test the API directly

```bash
# Extract (doesn't save anything yet)
curl -X POST http://receipts.gsofianos.duckdns.org/api/receipts/extract \
  -F "file=@/path/to/receipt.jpg"

# Save a (possibly hand-edited) result
curl -X POST http://receipts.gsofianos.duckdns.org/api/receipts \
  -H "Content-Type: application/json" \
  -d '{"store":"No Frills","purchased_at":"2026-07-30","total":42.17,"items":[{"name":"2% Milk","price":4.99,"quantity":1}]}'
```

## 6. Build the Shortcut

Create a new Shortcut with these actions, in order:

1. **Take Photo** (or **Select Photos** if you'd rather snap it in the
   Camera app first and pick it from your library)
2. **Get Contents of URL**
   - URL: `https://receipts.gsofianos.duckdns.org/api/receipts/extract`
   - Method: `POST`
   - Request Body: `Form`, add a field named `file` set to the photo from
     step 1
3. **Get Dictionary from Input** → run on the result of step 2, then
   **Get Value for "parsed"** → gives you the structured fields
4. **Show Result** (or a **Quick Look**) displaying store / total / items,
   so you can catch a bad OCR read before it's saved
5. Wrap the "looks good" path with **Get Value for "store"**,
   `"purchased_at"`, `"total"`, `"tax"`, `"subtotal"`, `"items"` and feed
   them into a **Text** action building the JSON body for the save call
   — or simpler: pass the whole `"parsed"` dictionary straight through as
   the body, since it's already shaped to match what `/api/receipts`
   expects
6. **Get Contents of URL**
   - URL: `https://receipts.gsofianos.duckdns.org/api/receipts`
   - Method: `POST`
   - Request Body: `JSON` → the dictionary from step 5
7. **Show Notification**: "Receipt saved" (or show the error if the
   request fails)

If you want an edit step before saving (e.g. fixing a misread price),
insert an **Ask Each Time** / text-edit action between steps 4 and 5 so
you can tweak the dictionary before it's committed — worth having,
since OCR on a crumpled receipt won't always be perfect.

## 7. Grafana

Once `grafana` is up, log in at `grafana.gsofianos.duckdns.org` (or
`http://<tailscale-ip>:${PORT_GRAFANA}` locally) with the admin
credentials from `.env`. The `ReceiptTracker` Postgres datasource is
already provisioned — from there, build panels like:

- Total spend by week/month (`SUM(total)` grouped by `purchased_at`)
- Spend by store
- Top items by total spend (join `receipts` + `receipt_items`)
