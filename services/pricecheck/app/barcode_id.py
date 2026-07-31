"""
Barcode -> product identification.

Re-implements the Open Food Facts + UPCitemdb pipeline George already had
working on the home server. If his existing pricecheck code differs from
this, swap this module out -- the rest of the service only depends on the
`identify_barcode()` function returning a ProductInfo.
"""

from typing import Optional

import httpx

from .models import ProductInfo

OPEN_FOOD_FACTS_URL = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
UPCITEMDB_URL = "https://api.upcitemdb.com/prod/trial/lookup"


class BarcodeNotFoundError(Exception):
    """Raised when no product could be identified for a barcode."""


async def _try_open_food_facts(client: httpx.AsyncClient, barcode: str) -> Optional[ProductInfo]:
    resp = await client.get(OPEN_FOOD_FACTS_URL.format(barcode=barcode))
    if resp.status_code != 200:
        return None
    data = resp.json()
    if data.get("status") != 1:
        return None
    product = data.get("product", {})
    name = product.get("product_name") or product.get("product_name_en")
    if not name:
        return None
    brand = None
    if product.get("brands"):
        brand = product["brands"].split(",")[0].strip()
    query = f"{brand} {name}".strip() if brand else name
    return ProductInfo(barcode=barcode, search_query=query, brand=brand, raw_name=name)


async def _try_upcitemdb(client: httpx.AsyncClient, barcode: str) -> Optional[ProductInfo]:
    resp = await client.get(UPCITEMDB_URL, params={"upc": barcode})
    if resp.status_code != 200:
        return None
    data = resp.json()
    items = data.get("items") or []
    if not items:
        return None
    item = items[0]
    name = item.get("title")
    if not name:
        return None
    brand = item.get("brand")
    query = f"{brand} {name}".strip() if brand else name
    return ProductInfo(barcode=barcode, search_query=query, brand=brand, raw_name=name)


async def identify_barcode(barcode: str) -> ProductInfo:
    """Try Open Food Facts first (better for groceries), then UPCitemdb."""
    async with httpx.AsyncClient(timeout=10) as client:
        for source in (_try_open_food_facts, _try_upcitemdb):
            try:
                result = await source(client, barcode)
            except httpx.HTTPError:
                continue
            if result:
                return result
    raise BarcodeNotFoundError(f"No product identified for barcode {barcode}")
