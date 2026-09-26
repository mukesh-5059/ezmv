from curl_cffi.requests import AsyncSession
from curl_cffi import CurlOpt

_session: AsyncSession | None = None

def get_session() -> AsyncSession:
    """
    Get the global shared persistent AsyncSession.
    If not initialized, performs fallback on-demand creation.
    """
    global _session
    if _session is None:
        curl_opts = {CurlOpt.DOH_URL: b"https://1.1.1.1/dns-query"}
        _session = AsyncSession(curl_options=curl_opts)
    return _session

async def init_session():
    """
    Initialize the persistent session. Called during application startup.
    """
    global _session
    if _session is None:
        curl_opts = {CurlOpt.DOH_URL: b"https://1.1.1.1/dns-query"}
        _session = AsyncSession(curl_options=curl_opts)

async def close_session():
    """
    Close the persistent session. Called during application shutdown.
    """
    global _session
    if _session is not None:
        try:
            import asyncio
            res = _session.close()
            if asyncio.iscoroutine(res):
                await res
        except Exception:
            pass
        _session = None
