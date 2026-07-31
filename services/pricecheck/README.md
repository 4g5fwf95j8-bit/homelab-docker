# Pricecheck

Scan a grocery barcode on your iPhone → get back the cheapest price across
Walmart, Loblaws, No Frills, and Costco (Richmond Hill).

Runs entirely on server1-media, right next to PriceBuddy — no cross-box
networking needed, unlike receipt-tracker's reference to Ollama on
server2-ai.

```
iPhone Shortcut (Scan Barcode)
        │  GET /lookup?barcode=060383668618
        ▼
pricecheck  ──1──▶  identify product (Open Food Facts, then UPCitemdb)
            ──2──▶  search each store's site for that product name,
                    grab the first matching product page URL
            ──3──▶  ask PriceBuddy for a live price at each URL
                    (POST /api/meta-extraction — synchronous, no
                    waiting on a cron)
            ──4──▶  sort, return cheapest + top 3
        ▼
iPhone Shortcut shows the result
```

pricecheck only finds *which page* to check at each store. PriceBuddy does
the actual price scraping — it already has a proper scraping engine, CSS/
JSONPath selectors, a headless-browser fallback for JS-heavy pages, and
AI self-healing when a store's markup changes. No point re-building that.

## What's here

- `Dockerfile` / `requirements.txt` / `app/main.py` — the FastAPI service
- `app/barcode_id.py` — barcode → product (Open Food Facts, then
  UPCitemdb fallback)
- `app/store_search.py` — per-store "find the product URL" adapters for
  the 4 target stores
- `app/pricebuddy_client.py` — calls PriceBuddy's on-demand price API
- `docker-compose.yml` — `pricecheck`, included from
  `homelab-media/docker-compose.yml` (added right after `pricebuddy`,
  since it depends on it)

Note on stack: this uses `httpx` async rather than `requests` (unlike
receipt-tracker) because step 2 fans out to all 4 stores in parallel, and
step 3 fans out to PriceBuddy for all of them in parallel too — worth the
one dependency swap for the latency win.

## 1. Add these to your root `.env`

```
PORT_PRICECHECK=8002
PRICEBUDDY_API_TOKEN=<generate in PriceBuddy: user menu (top right) -> API tokens -> create>
```

Pick a port that doesn't collide with anything already in use on
server1-media.

## 2. One-time: configure the 4 stores in PriceBuddy

In PriceBuddy: **Settings → Stores → Add Store**, one each for
`walmart.ca`, `nofrills.ca`, `loblaws.ca`, `costco.ca`. For each, add a
scrape strategy. A reasonable starting point (many product pages expose
this via Open Graph tags for link previews):

```json
{
  "title": { "type": "selector", "value": "meta[property=\"og:title\"]|content" },
  "price": { "type": "selector", "value": "meta[property=\"og:price:amount\"]|content" },
  "image": { "type": "selector", "value": "meta[property=\"og:image\"]|content" }
}
```

Test it against one real product URL from each store using the "test
URL" feature on the store edit page before relying on it. **If you have
an AI provider connected in PriceBuddy (Settings → AI providers), use
"Heal with AI" / bootstrap-from-URL instead of hand-writing selectors**
— it's built for exactly this and will likely do better than guessing,
especially for Costco, which tends to be the least standard of the four.

## 3. Bring it up

```bash
cd /opt/docker/homelab-docker/homelab-media
docker compose up -d --build
```

`--build` is needed the first time (and after any code changes) since
`pricecheck` builds from a local Dockerfile rather than pulling an image.

Check it's healthy:

```bash
curl http://localhost:${PORT_PRICECHECK}/health
```

## 4. Confirm the Caddy entry

Already added to `services/public/staticconfig/caddy/Caddyfile`:

```
pricecheck.gsofianos.duckdns.org {
    reverse_proxy pricecheck:8000
}
```

Since this is a same-box container reference (not a Tailscale IP like the
`receipts.`/`grafana.` entries), there's nothing to double-check here
beyond making sure Caddy picks up the change — restart it after pulling.

## 5. Test the API directly

```bash
curl "http://pricecheck.gsofianos.duckdns.org/lookup?barcode=060383668618"
```

Expect back JSON like:

```json
{
  "barcode": "060383668618",
  "product_name": "...",
  "cheapest": {"store": "No Frills", "price": 4.99, "title": "...", "url": "..."},
  "top_matches": [ ... up to 3 ... ]
}
```

## 6. Build the Shortcut

Shortcuts app → **+** → add these actions in order:

1. **Scan QR/Barcode** — built-in action, scans with the camera and
   outputs text.
2. **Get Contents of URL**
   - URL: `https://pricecheck.gsofianos.duckdns.org/lookup?barcode=` +
     (insert the Scan QR/Barcode result as a variable right after it)
   - Method: GET
3. **Get Dictionary from Input** — feeds in the previous result.
4. **Get Value for Key** `cheapest` from the dictionary, then again for
   `store` and `price` from that result.
5. **Show Result** (or **Show Alert**): `Cheapest: [price] at [store]`

Because this goes out through Caddy/DuckDNS (same as `receipts.` and
`pricebuddy.`), it works over plain cellular data — no need for Tailscale
to be connected on your phone.

Optional nice-to-have once the basic version works: an **If** action
checking for a `detail` key (the error case) to show a friendlier
"not found" alert; and a **Repeat with Each** over `top_matches` to show
all 3 prices instead of just the cheapest.

## Known gaps / where this will need a second pass

I built the store-search adapters without live access to your server or
to walmart.ca / costco.ca / nofrills.ca's actual HTML, so confidence
levels differ:

- **No Frills / Loblaws** — high confidence. Fetched their live search
  results directly; server-rendered, product URLs reliably match
  `/en/<slug>/p/<digits>_<unit>`.
- **Walmart** — medium confidence. Search URL and product URL pattern
  (`/en/ip/<slug>/<id>`) confirmed from search-engine-indexed pages, but
  not fetched live end-to-end. First place to check if it comes back
  empty.
- **Costco** — lowest confidence. Costco.ca has real anti-bot protection,
  so plain HTTP requests may get blocked — may need routing through
  PriceBuddy's SeleniumBase scraper service instead. Separately:
  **Costco's online catalog is only a subset of what's on the warehouse
  shelf.** Plenty of things you'd scan in-store just won't be found
  online — a real ceiling, not a bug to fix.
- Didn't wire in barcodelookup.com as a barcode-ID source — it requires
  a paid API key, and Open Food Facts + UPCitemdb already cover this
  end-to-end. Easy to add as a third fallback in `barcode_id.py` later.