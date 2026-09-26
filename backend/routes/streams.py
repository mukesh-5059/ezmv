from fastapi import APIRouter, Query, HTTPException, Request, Header
from fastapi.responses import StreamingResponse
from backend.services.tmdb import tmdb_client
from backend.services.scrapers.manager import scraper_manager
from urllib.parse import quote
import asyncio
import logging
import httpx

logger = logging.getLogger(__name__)
router = APIRouter()

async def _resolve_cdn_redirect(url: str) -> str:
    """
    Resolves 302 redirects from .php / download.php / uptomkv to direct CDN media URLs.
    """
    if "download.php" not in url and ".php" not in url and "uptomkv" not in url:
        return url

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://cdn.uptomkv.ch/"
    }
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(url, headers=headers, follow_redirects=False)
            if resp.status_code in (301, 302, 303, 307, 308):
                loc = resp.headers.get("Location") or resp.headers.get("location")
                if loc:
                    resolved = quote(str(loc), safe=":/%?&=#+,-")
                    return resolved
    except Exception as e:
        logger.warning(f"Failed to resolve 302 redirect for {url}: {e}")
    return url


@router.get("/")
async def get_streaming_links(
    request: Request,
    tmdb_id: int = Query(..., description="TMDb ID of the movie or TV show"),
    media_type: str = Query("movie", enum=["movie", "tv"], description="Media type: movie or tv"),
    season: int | None = Query(None, description="Season number (required for TV shows)"),
    episode: int | None = Query(None, description="Episode number (required for TV shows)"),
    bypass_cache: bool = Query(False, description="Bypass manager cache and force re-scrape")
):
    """
    Search and return streaming links for a given movie or TV show.
    """
    # 1. Fetch metadata & IMDb ID from TMDB
    if media_type == "movie":
        details = await tmdb_client.get_movie_details(tmdb_id)
        if not details:
            raise HTTPException(status_code=404, detail="Movie not found on TMDB.")
        
        title = details.get("title")
        release_date = details.get("release_date", "")
        year = int(release_date.split("-")[0]) if release_date else 0
        imdb_id = details.get("imdb_id")
        
    else:
        # TV Show
        if season is None or episode is None:
            raise HTTPException(status_code=400, detail="Season and Episode are required for TV shows.")
            
        details = await tmdb_client.get_tv_details(tmdb_id)
        if not details:
            raise HTTPException(status_code=404, detail="TV Show not found on TMDB.")
            
        title = details.get("name")
        first_air_date = details.get("first_air_date", "")
        year = int(first_air_date.split("-")[0]) if first_air_date else 0
        
        # Get external ids for TV show
        external_ids = details.get("external_ids", {})
        imdb_id = external_ids.get("imdb_id")

    try:
        links = await scraper_manager.get_streams(
            title=title,
            year=year,
            media_type=media_type,
            tmdb_id=tmdb_id,
            imdb_id=imdb_id,
            season=season,
            episode=episode,
            bypass_cache=bypass_cache
        )
    except Exception as e:
        logger.error(f"Error executing scrapers: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal scraper failure occurred.")

    cache_key = f"{tmdb_id}_{season}_{episode}"
    remaining_ttl = scraper_manager._stream_cache.get_remaining_ttl(cache_key)

    # 3. Resolve direct CDN links if .php / download.php redirects exist
    base_url = str(request.base_url).rstrip("/")

    async def process_stream(stream: dict):
        raw_url = stream.get("url", "")
        if "download.php" in raw_url or ".php" in raw_url:
            resolved_url = await _resolve_cdn_redirect(raw_url)
            if resolved_url != raw_url:
                stream["url"] = resolved_url
                stream["type"] = "direct"
                log_msg = f"🎬 [CDN STREAM RESOLVED] ({stream.get('quality', 'HD')}) -> {resolved_url}"
                logger.info(log_msg)
                print(log_msg, flush=True)
            else:
                stream["url"] = f"{base_url}/api/v1/streams/proxy/stream.mp4?url={quote(raw_url, safe='')}"
                stream["type"] = "direct"
        elif "uptomkv" in raw_url and "/api/v1/streams/proxy" not in raw_url:
            stream["url"] = f"{base_url}/api/v1/streams/proxy/stream.mp4?url={quote(raw_url, safe='')}"
            stream["type"] = "direct"

    if links:
        await asyncio.gather(*(process_stream(s) for s in links))

    return {
        "title": title,
        "year": year,
        "media_type": media_type,
        "tmdb_id": tmdb_id,
        "imdb_id": imdb_id,
        "season": season,
        "episode": episode,
        "cache_expires_in": remaining_ttl,
        "streams": links
    }


@router.get("/proxy")
@router.get("/proxy/{filename}")
async def proxy_stream(url: str, request: Request, filename: str | None = None):
    """
    Proxy video streams from external hosts (e.g. download.php or uptomkv)
    to bypass IP-locking, CORS, and Content-Disposition download constraints.
    """
    if not url:
        raise HTTPException(status_code=400, detail="Missing url parameter.")

    # Unwrap any nested proxy URLs to prevent proxy loops
    from urllib.parse import unquote
    while "/api/v1/streams/proxy" in url:
        if "?url=" in url:
            url = url.split("?url=", 1)[1]
            url = unquote(url)
        else:
            break

    range_header = request.headers.get("range") or request.headers.get("Range")
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://cdn.uptomkv.ch/"
    }
    if range_header:
        headers["Range"] = range_header

    # Pre-resolve 302 redirect (e.g. download.php -> mv1.uptomkv.ch) to preserve Range header across domains
    target_url = url
    if "download.php" in target_url:
        try:
            async with httpx.AsyncClient(timeout=6.0) as res_client:
                resp = await res_client.get(
                    target_url,
                    headers={"User-Agent": headers["User-Agent"], "Referer": "https://cdn.uptomkv.ch/"},
                    follow_redirects=False
                )
                if resp.status_code in (301, 302, 303, 307, 308):
                    loc = resp.headers.get("Location") or resp.headers.get("location")
                    if loc:
                        from urllib.parse import quote
                        target_url = quote(str(loc), safe=":/%?&=#+,-")
        except Exception as e:
            logger.warning(f"Error pre-resolving 302 redirect for {target_url}: {e}")

    try:
        client = httpx.AsyncClient(follow_redirects=True, timeout=20.0)
        req = client.build_request("GET", target_url, headers=headers)
        res = await client.send(req, stream=True)

        response_headers = {
            "Accept-Ranges": res.headers.get("Accept-Ranges", "bytes"),
            "Content-Type": res.headers.get("Content-Type") or "video/mp4",
            "Content-Disposition": "inline",
        }
        if "Content-Length" in res.headers:
            response_headers["Content-Length"] = res.headers["Content-Length"]
        if "Content-Range" in res.headers:
            response_headers["Content-Range"] = res.headers["Content-Range"]

        async def stream_generator():
            try:
                async for chunk in res.aiter_bytes(chunk_size=64 * 1024):
                    yield chunk
            finally:
                await res.aclose()
                await client.aclose()

        return StreamingResponse(
            stream_generator(),
            status_code=res.status_code if res.status_code in (200, 206) else 200,
            headers=response_headers
        )
    except Exception as e:
        logger.error(f"Error proxying stream URL {url}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Proxy error: {str(e)}")

