from typing import List, Optional

from pydantic import BaseModel


class ProductInfo(BaseModel):
    """Result of identifying a barcode via Open Food Facts / UPCitemdb."""

    barcode: str
    search_query: str
    brand: Optional[str] = None
    raw_name: Optional[str] = None


class StorePrice(BaseModel):
    store: str
    price: float
    title: str
    url: str


class LookupResponse(BaseModel):
    barcode: str
    product_name: str
    cheapest: StorePrice
    top_matches: List[StorePrice]
