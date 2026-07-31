"""
Thin client for PriceBuddy's REST API.

Uses POST /api/meta-extraction -- a synchronous, non-persisting endpoint
that scrapes a single URL and returns {title, price, image} immediately.
This is what makes on-demand "scan a barcode right now" lookups possible;
PriceBuddy's normal product-tracking flow is schedule/cron-based, which
would be too slow for standing in a grocery aisle.

Requires the target store's domain to already have a Store configured in
PriceBuddy (Settings -> Stores) with working scrape selectors, OR you can
pass a one-off `store` override -- see the README for both options.
"""

import os
from typing import Optional

import httpx

PRICEBUDDY_BASE_URL = os.environ.get("PRICEBUDDY_BASE_URL", "http://pricebuddy").rstrip("/")
PRICEBUDDY_API_TOKEN = os.environ.get("PRICEBUDDY_API_TOKEN", "")


async def get_price_via_pricebuddy(url: str) -> Optional[dict]:
    endpoint = f"{PRICEBUDDY_BASE_URL}/api/meta-extraction"
    headers = {
        "Authorization": f"Bearer {PRICEBUDDY_API_TOKEN}",
        "Accept": "application/json",
    }
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(endpoint, json={"url": url}, headers=headers)
    except httpx.HTTPError:
        return None

    if resp.status_code != 200:
        return None

    data = resp.json().get("data", {})
    if data.get("price") is None:
        return None
    return data
