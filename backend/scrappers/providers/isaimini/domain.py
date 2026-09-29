import asyncio
import logging
from urllib.parse import urlparse
from .constants import DEFAULT_HEADERS
from .storage import get_cached_domain, save_cached_domain

logger = logging.getLogger(__name__)

def extract_base_domain(url: str) -> str:
    parsed = urlparse(url)
    return f"{parsed.scheme}://{parsed.netloc}/"

async def resolve_moviesda_domain(session) -> str | None:
    cached_domain = get_cached_domain()
    if not cached_domain:
        logger.warning("[Isaimini] No active domain configured in isaimini.json. Scraper aborted.")
        return None

    for attempt in range(1, 3):
        try:
            resp = await session.get(
                cached_domain,
                headers=DEFAULT_HEADERS,
                allow_redirects=True,
                timeout=8.0
            )
            if resp.status_code == 200:
                final_domain = extract_base_domain(str(resp.url))
                if final_domain != cached_domain:
                    logger.info(f"[Isaimini:Domain] Active mirror redirected: {cached_domain} -> {final_domain}")
                    save_cached_domain(final_domain)
                else:
                    logger.info(f"[Isaimini:Domain] Active mirror: {final_domain}")
                return final_domain
        except Exception as e:
            logger.warning(f"[Isaimini] Attempt {attempt} failed on '{cached_domain}': {e}")
            if attempt < 2:
                await asyncio.sleep(1.5)

    logger.warning(f"[Isaimini] Cached domain '{cached_domain}' is unreachable after retries.")
    return None
