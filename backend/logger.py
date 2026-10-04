import logging
import sys
import time

# ANSI Color Codes
RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[90m"

GREEN = "\033[92m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
RED = "\033[91m"
MAGENTA = "\033[95m"
BLUE = "\033[94m"


class EzMVFormatter(logging.Formatter):
    """Custom formatter: HH:MM:SS [TAG] Message with zero extra metadata bloat."""
    def format(self, record: logging.LogRecord) -> str:
        ts = time.strftime("%H:%M:%S", time.localtime(record.created))
        time_str = f"{DIM}{ts}{RESET}"
        msg = record.getMessage()
        return f"{time_str} {msg}"


def setup_logging():
    root = logging.getLogger()
    for h in list(root.handlers):
        root.removeHandler(h)

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(EzMVFormatter())
    root.addHandler(handler)
    root.setLevel(logging.INFO)

    # Silence uvicorn and third-party verbose loggers
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.error").setLevel(logging.INFO)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)


# Helper Formatters
def cache_hit_tag(key: str, remaining_ttl: int) -> str:
    return f"{GREEN}{BOLD}[CACHE] [HIT]{RESET}  '{key}' {DIM}(TTL: {remaining_ttl}s){RESET}"


def cache_miss_tag(key: str) -> str:
    return f"{YELLOW}{BOLD}[CACHE] [MISS]{RESET} '{key}'"


def cache_set_tag(key: str, ttl: int) -> str:
    return f"{MAGENTA}{BOLD}[CACHE] [SET]{RESET}  '{key}' {DIM}(TTL: {ttl}s){RESET}"


def cache_stream_hit_tag(tmdb_id: int, s: int, e: int, count: int) -> str:
    return f"{GREEN}{BOLD}[CACHE] [HIT]{RESET}  Streams tmdb={tmdb_id} s={s} e={e} {DIM}({count} streams){RESET}"


def cache_stream_miss_tag(tmdb_id: int, s: int, e: int) -> str:
    return f"{YELLOW}{BOLD}[CACHE] [MISS]{RESET} Streams tmdb={tmdb_id} s={s} e={e}"


def cache_stream_set_tag(tmdb_id: int, s: int, e: int, count: int) -> str:
    return f"{MAGENTA}{BOLD}[CACHE] [SET]{RESET}  Streams tmdb={tmdb_id} s={s} e={e} {DIM}({count} saved){RESET}"


def scraper_start_tag(title: str, year: int, tmdb_id: int, scrapers: list) -> str:
    return f"{CYAN}{BOLD}[SCRAPER] [START]{RESET} '{title}' ({year}) | TMDb: {tmdb_id} | Running: {scrapers}"


def scraper_exec_tag(name: str, count: int, elapsed: float) -> str:
    if count > 0:
        return f"{BLUE}[SCRAPER] [{name}]{RESET} Returned {count} stream sources in {elapsed:.2f}s"
    return f"{DIM}[SCRAPER] [{name}] No sources found in {elapsed:.2f}s{RESET}"


def scraper_error_tag(name: str, err: str, elapsed: float) -> str:
    return f"{RED}{BOLD}[SCRAPER] [{name}] FAILED in {elapsed:.2f}s: {err}{RESET}"


def scraper_done_tag(title: str, total: int) -> str:
    return f"{GREEN}{BOLD}[SCRAPER] [DONE]{RESET} Returning {total} total streams for '{title}'"


def scraper_cache_tag(title: str, total: int) -> str:
    return f"{GREEN}{BOLD}[SCRAPER] [CACHE]{RESET} Serving {total} cached streams for '{title}'"


def http_log(method: str, path: str, status_code: int, duration_ms: float) -> str:
    if 200 <= status_code < 300:
        status_str = f"{GREEN}{status_code} OK{RESET}"
    elif 300 <= status_code < 400:
        status_str = f"{CYAN}{status_code}{RESET}"
    elif 400 <= status_code < 500:
        status_str = f"{YELLOW}{status_code}{RESET}"
    else:
        status_str = f"{RED}{status_code} Error{RESET}"

    time_color = GREEN if duration_ms < 20 else (YELLOW if duration_ms < 100 else RED)
    dur_str = f"{time_color}({duration_ms:.1f}ms){RESET}"
    return f"{CYAN}[HTTP]{RESET}    {method:<4} {path} -> {status_str} {dur_str}"
