import asyncio
import logging
from dataclasses import replace
from urllib.parse import urlsplit, urlunsplit, quote, unquote, urljoin
from curl_cffi.requests import AsyncSession
from curl_cffi import CurlOpt, CurlHttpVersion
from backend.scrappers.base import StreamSource

logger = logging.getLogger(__name__)

SHARED_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)

def sanitize_redirect_url(base_url: str, location: str) -> str:
    full_url = urljoin(base_url, location.strip())
    parts = urlsplit(full_url)
    clean_path = quote(unquote(parts.path), safe="/:@!$&'()*+,;=-._~")
    return urlunsplit((parts.scheme, parts.netloc, clean_path, parts.query, parts.fragment))

async def probe_and_resolve(stream: StreamSource) -> StreamSource:
    try:
        if not stream.url or ".php" not in stream.url.lower():
            return stream

        req_headers = dict(stream.headers) if stream.headers else {}
        req_ua = req_headers.get("User-Agent") or req_headers.get("user-agent") or SHARED_USER_AGENT
        req_headers["User-Agent"] = req_ua

        hit_headers = dict(req_headers)
        hit_headers["Range"] = "bytes=0-1023"

        curl_opts = {
            CurlOpt.DOH_URL: b"https://1.1.1.1/dns-query",
            CurlOpt.IPRESOLVE: 1,
        }

        async with AsyncSession(
            impersonate="chrome124",
            http_version=CurlHttpVersion.V1_1,
            curl_options=curl_opts,
        ) as session:
            resp = await session.get(stream.url, headers=hit_headers, allow_redirects=False, timeout=6)

            if resp.status_code not in (301, 302, 303, 307, 308):
                no_range_headers = {k: v for k, v in req_headers.items() if k.lower() != "range"}
                resp = await session.get(stream.url, headers=no_range_headers, allow_redirects=False, timeout=6)

            if resp.status_code not in (301, 302, 303, 307, 308):
                return stream

            location = resp.headers.get("location")
            if not location:
                return stream

            if "htag=" in location.lower() or "fastly." in stream.url.lower():
                logger.debug(f"[Isaimini:Resolver] Preserving session-bound Fastly URL: {stream.url}")
                return stream

            resolved_url = sanitize_redirect_url(stream.url, location)

        async with AsyncSession(
            http_version=CurlHttpVersion.V1_1,
            curl_options=curl_opts,
        ) as clean_client:
            probe_headers = {
                "User-Agent": req_ua,
                "Range": "bytes=0-1023",
            }
            probe = await clean_client.get(
                resolved_url,
                headers=probe_headers,
                allow_redirects=True,
                stream=True,
                timeout=6,
            )
            ct = probe.headers.get("content-type", "").lower()
            is_valid_media = (
                probe.status_code in (200, 206)
                and not ct.startswith("text/html")
            )
            if is_valid_media:
                async for _ in probe.aiter_content(512):
                    break

            if is_valid_media:
                logger.info(f"[Isaimini:Resolver] Resolved stream URL: {stream.url} -> {resolved_url}")
                updated_headers = dict(stream.headers)
                updated_headers["User-Agent"] = req_ua
                return replace(stream, url=resolved_url, headers=updated_headers)

        return stream
    except Exception as e:
        logger.debug(f"[Isaimini:Resolver] Probe failed for {stream.url}: {e}")
        return stream

async def probe_and_resolve_all(streams: list[StreamSource]) -> list[StreamSource]:
    if not streams:
        return []
    tasks = [probe_and_resolve(stream) for stream in streams]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    resolved: list[StreamSource] = []
    for stream, result in zip(streams, results):
        if isinstance(result, Exception):
            logger.debug(f"[Isaimini:Resolver] Probe task error: {result}")
            resolved.append(stream)
        else:
            resolved.append(result)
    return resolved
