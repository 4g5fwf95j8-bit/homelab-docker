"""
Per-store "find the product page URL for this search query" adapters.

Design note: these adapters ONLY find a candidate product URL. They do not
try to scrape the price themselves -- that's PriceBuddy's job (see
pricebuddy_client.py), since it already has a proper scraping engine,
CSS/JSONPath selector support, and AI self-healing for when a store changes
its markup. Keeping "find the URL" and "extract the price" as separate
steps means each one stays simple.

Confidence notes (verified against live search results on 2026-07-28):
  - No Frills / Loblaws (same PC Express backend, Loblaw Companies):
    HIGH confidence. Search results are server-rendered; product URLs
    consistently look like /en/<slug>/p/<digits>_<unit>.
  - Walmart Canada: MEDIUM confidence. Confirmed product URL pattern
    (/en/ip/<slug>/<id>) and search URL pattern, but not tested end-to-end
    against a live response body -- most likely first thing to need a
    tweak if it doesn't match right away.
  - Costco.ca: LOWEST confidence. Confirmed product URL pattern
    (<slug>.product.<id>.html) but Costco.ca has real anti-bot protection,
    so this may need a different fetch strategy (e.g. routing through
    PriceBuddy's SeleniumBase scraper service instead of a plain GET) or
    may simply fail for warehouse-only items that aren't sold online at
    all -- that's a real gap, not a bug.
"""

import re
from abc import ABC, abstractmethod
from typing import Optional
from urllib.parse import quote_plus, urljoin

import httpx

# A real browser UA + Accept-Language helps avoid basic bot-blocking on
# sites that don't otherwise require JS execution to render search results.
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    ),
    "Accept-Language": "en-CA,en;q=0.9",
}


class StoreAdapter(ABC):
    name: str
    base_url: str

    @abstractmethod
    def search_url(self, query: str) -> str:
        ...

    @abstractmethod
    def product_link_pattern(self) -> "re.Pattern[str]":
        ...

    async def find_product_url(self, query: str) -> Optional[str]:
        url = self.search_url(query)
        async with httpx.AsyncClient(headers=HEADERS, follow_redirects=True, timeout=15) as client:
            resp = await client.get(url)
            if resp.status_code != 200:
                return None
            html = resp.text

        match = self.product_link_pattern().search(html)
        if not match:
            return None
        href = match.group(1).replace("&amp;", "&")
        return urljoin(self.base_url, href)


class NoFrillsAdapter(StoreAdapter):
    name = "No Frills"
    base_url = "https://www.nofrills.ca"

    def search_url(self, query: str) -> str:
        return f"https://www.nofrills.ca/en/search?search-bar={quote_plus(query)}"

    def product_link_pattern(self):
        return re.compile(r'href="([^"]*?/p/\d+_[A-Za-z]+[^"]*)"')


class LoblawsAdapter(StoreAdapter):
    name = "Loblaws"
    base_url = "https://www.loblaws.ca"

    def search_url(self, query: str) -> str:
        return f"https://www.loblaws.ca/en/search?search-bar={quote_plus(query)}"

    def product_link_pattern(self):
        return re.compile(r'href="([^"]*?/p/\d+_[A-Za-z]+[^"]*)"')


class WalmartAdapter(StoreAdapter):
    name = "Walmart"
    base_url = "https://www.walmart.ca"

    def search_url(self, query: str) -> str:
        return f"https://www.walmart.ca/en/search?q={quote_plus(query)}"

    def product_link_pattern(self):
        return re.compile(r'href="([^"]*?/en/ip/[^"]+)"')


class CostcoAdapter(StoreAdapter):
    name = "Costco"
    base_url = "https://www.costco.ca"

    def search_url(self, query: str) -> str:
        return f"https://www.costco.ca/CatalogSearch?keyword={quote_plus(query)}"

    def product_link_pattern(self):
        return re.compile(r'href="([^"]*?\.product\.\d+\.html)"')


# Order here is also the tie-break order when two stores return the same
# price (see main.py) -- cheapest, most-reliable-first.
STORE_ADAPTERS = {
    "No Frills": NoFrillsAdapter(),
    "Loblaws": LoblawsAdapter(),
    "Walmart": WalmartAdapter(),
    "Costco": CostcoAdapter(),
}
