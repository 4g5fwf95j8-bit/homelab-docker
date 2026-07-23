FROM caddy:latest

RUN xcaddy build \
    --with github.com/caddy-dns/duckdns