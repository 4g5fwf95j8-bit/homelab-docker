# clue-detective

A Clue (Cluedo) deduction helper. React + Vite + Tailwind, built into static
files and served by nginx. No backend — game state lives in each browser's
localStorage, so it won't sync between your phone and a laptop, but it
persists across visits on the same device.

## Run it

```
docker compose up -d --build
```

This publishes the app on `127.0.0.1:8095` (host-only), matching how Caddy
reaches your other services.

## Wire it into Caddy

Add a site block to your Caddyfile:

```
clue.gsofianos.duckdns.org {
    reverse_proxy 127.0.0.1:8095
}
```

Then reload/restart Caddy the same way you do for other services. DuckDNS
wildcard-resolves subdomains of gsofianos.duckdns.org already, so no extra
DNS setup is needed — same as jellyfin.* and the others.

## Update after changing the code

```
docker compose up -d --build
```

Rebuilds the Vite bundle and restarts the container with the new version.

## iPhone

Once `https://clue.gsofianos.duckdns.org` loads over HTTPS (Caddy handles
the cert automatically), open it in Safari and use Share → Add to Home
Screen. Because it's a real hosted page this time (not a Claude artifact or
a temporary Netlify Drop link), it'll behave like a normal bookmarked app —
stable URL, no expiry.
