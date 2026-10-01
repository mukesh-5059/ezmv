import asyncio
from curl_cffi.requests import AsyncSession
from curl_cffi import CurlOpt

_session: AsyncSession | None = None

def get_session() -> AsyncSession:
    global _session
    try:
        current_loop = asyncio.get_running_loop()
    except RuntimeError:
        current_loop = None

    if _session is None or _session.loop is None or _session.loop.is_closed() or (current_loop and _session.loop != current_loop):
        curl_opts = {
            CurlOpt.DOH_URL: b"https://1.1.1.1/dns-query",
            CurlOpt.IPRESOLVE: 1,
        }
        _session = AsyncSession(curl_options=curl_opts, loop=current_loop)
    return _session

async def init_session():
    global _session
    current_loop = asyncio.get_running_loop()
    if _session is None or _session.loop != current_loop:
        curl_opts = {
            CurlOpt.DOH_URL: b"https://1.1.1.1/dns-query",
            CurlOpt.IPRESOLVE: 1,
        }
        _session = AsyncSession(curl_options=curl_opts, loop=current_loop)

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
