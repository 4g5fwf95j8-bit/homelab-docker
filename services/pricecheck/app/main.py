import asyncio
import logging

from fastapi import FastAPI, HTTPException, Query

from .barcode_id import BarcodeNotFoundError, identify_barcode
from .models import LookupResponse, StorePrice
from .pricebuddy_client import get_price_via_pricebuddy
from .store_search import STORE_ADAPTERS

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("pricecheck")

app = FastAPI(title="pricecheck", version="0.1.0")


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/lookup", response_model=LookupResponse)
async def lookup(barcode: str = Query(..., description="Scanned UPC/EAN barcode")):
    try:
        product = await identify_barcode(barcode)
    except BarcodeNotFoundError:
        raise HTTPException(status_code=404, detail=f"No product found for barcode {barcode}")

    query = product.search_query
    logger.info("barcode %s -> %s", barcode, query)

    # Search all 4 stores in parallel for a candidate product URL.
    store_names = list(STORE_ADAPTERS.keys())
    search_results = await asyncio.gather(
        *(STORE_ADAPTERS[name].find_product_url(query) for name in store_names),
        return_exceptions=True,
    )

    urls: dict[str, str] = {}
    for name, result in zip(store_names, search_results):
        if isinstance(result, Exception):
            logger.warning("%s search failed: %s", name, result)
        elif result:
            urls[name] = result
        else:
            logger.info("%s: no match for '%s'", name, query)

    if not urls:
        raise HTTPException(status_code=404, detail=f"'{query}' not found at any configured store")

    # Get a live price for each found URL via PriceBuddy, in parallel.
    price_results = await asyncio.gather(
        *(get_price_via_pricebuddy(url) for url in urls.values()),
        return_exceptions=True,
    )

    prices: list[StorePrice] = []
    for name, result in zip(urls.keys(), price_results):
        if isinstance(result, Exception):
            logger.warning("%s price fetch failed: %s", name, result)
            continue
        if result:
            prices.append(
                StorePrice(
                    store=name,
                    price=float(result["price"]),
                    title=result.get("title") or query,
                    url=urls[name],
                )
            )

    if not prices:
        raise HTTPException(
            status_code=404,
            detail=f"Found '{query}' at {len(urls)} store(s) but couldn't get a price from any of them",
        )

    prices.sort(key=lambda p: p.price)

    return LookupResponse(
        barcode=barcode,
        product_name=query,
        cheapest=prices[0],
        top_matches=prices[:3],
    )
