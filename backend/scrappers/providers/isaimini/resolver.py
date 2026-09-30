import asyncio
import base64
import logging
import time
from dataclasses import replace
from urllib.parse import urlparse, parse_qs, urlsplit, urlunsplit, quote, unquote, urljoin
from curl_cffi.requests import AsyncSession
from curl_cffi import CurlOpt, CurlHttpVersion
from backend.scrappers.base import StreamSource

logger = logging.getLogger(__name__)

SHARED_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)

def extract_url_expiry(url: str) -> tuple[int | None, int | None]:
    if not url:
        return None, None
    now = int(time.time())
    try:
        parsed = urlparse(url)
        qs = parse_qs(parsed.query)
        if "e" in qs:
            exp = int(qs["e"][0])
            ttl = max(30, exp - now - 30) if exp > now else 30
            return exp, ttl
        if "etag" in qs:
            exp = int(qs["etag"][0])
            ttl = max(30, exp - now - 30) if exp > now else 30
            return exp, ttl
        if "dl" in qs:
            dl_raw = qs["dl"][0]
            padded = dl_raw + "=" * (-len(dl_raw) % 4)
            decoded = base64.urlsafe_b64decode(padded).decode("utf-8", errors="ignore")
            params = parse_qs(decoded)
            if "exp" in params:
                exp = int(params["exp"][0])
                ttl = max(30, exp - now - 30) if exp > now else 30
                return exp, ttl
    except Exception:
        pass
    return None, None

def attach_stream_metadata(stream: StreamSource) -> StreamSource:
    exp, ttl = extract_url_expiry(stream.url)
    priority = 10 if any(k in stream.provider for k in ["Original", "PreDVD"]) else 20
    return replace(
        stream,
        expires_at=exp,
        ttl=ttl if ttl is not None else 3600,
        priority=priority
    )

def sanitize_redirect_url(base_url: str, location: str) -> str:
    full_url = urljoin(base_url, location.strip())
    parts = urlsplit(full_url)
    clean_path = quote(unquote(parts.path), safe="/:@!$&'()*+,;=-._~")
    return urlunsplit((parts.scheme, parts.netloc, clean_path, parts.query, parts.fragment))

async def probe_and_resolve(stream: StreamSource) -> StreamSource:
    try:
        if not stream.url or ".php" not in stream.url.lower():
            return attach_stream_metadata(stream)

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
                return attach_stream_metadata(stream)

            location = resp.headers.get("location")
            if not location:
                return attach_stream_metadata(stream)

            if "htag=" in location.lower() or "fastly." in stream.url.lower():
                logger.debug(f"[Isaimini:Resolver] Preserving session-bound Fastly URL: {stream.url}")
                return attach_stream_metadata(stream)

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
                return attach_stream_metadata(replace(stream, url=resolved_url, headers=updated_headers))

        return attach_stream_metadata(stream)
    except Exception as e:
        logger.debug(f"[Isaimini:Resolver] Probe failed for {stream.url}: {e}")
        return attach_stream_metadata(stream)

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
