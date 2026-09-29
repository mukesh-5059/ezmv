import re
from urllib.parse import urlparse
from bs4 import BeautifulSoup
from .constants import BLACKLIST_TOKENS
from .storage import save_catalog_entries

def clean_title_tokens(title: str) -> set[str]:
    title = title.lower()
    tokens = re.findall(r'[a-z0-9]+', title)
    return set(tokens)

def extract_and_save_all_movies_from_soup(soup: BeautifulSoup, year: int, page_num: int = 1) -> list[dict]:
    entries = []
    for a in soup.find_all("a"):
        href = a.get("href")
        text = a.get_text().strip()
        if not href or not text:
            continue

        parsed = urlparse(href)
        if parsed.query:
            continue

        path = parsed.path.strip('/')
        if path.startswith("tamil-movies/") or path.endswith("-movies"):
            continue

        if not (path.endswith("-movie") or path.endswith("-web-series")):
            continue

        clean_path = f"/{path}/"
        entries.append({
            "path": clean_path,
            "title": text,
            "year": year,
            "page": page_num
        })

    if entries:
        save_catalog_entries(entries)
    return entries

def find_candidates_in_entries(entries: list[dict], target_tokens: set[str], base_url: str) -> list[dict]:
    candidates = []
    alpha_target = {t for t in target_tokens if not t.isdigit()}
    for e in entries:
        text = e["title"]
        path = e["path"]
        page_num = e.get("page", 1)

        combined_tokens = clean_title_tokens(f"{text} {path}")
        if any(black in combined_tokens for black in BLACKLIST_TOKENS):
            continue

        link_tokens = clean_title_tokens(text)
        if alpha_target and not (alpha_target & link_tokens):
            continue

        overlap = target_tokens & link_tokens
        score = len(overlap)
        if score > 0:
            is_strict = target_tokens.issubset(link_tokens)
            extra_tokens = len(link_tokens - target_tokens)
            full_url = f"{base_url.rstrip('/')}{path}"
            candidates.append({
                "url": full_url,
                "page": page_num,
                "is_strict": is_strict,
                "extra_tokens": extra_tokens,
                "overlap": score,
                "text": text
            })
    return candidates

def find_candidates_in_soup(soup: BeautifulSoup, target_tokens: set[str], base_url: str, year: int, page_num: int = 1) -> list[dict]:
    entries = extract_and_save_all_movies_from_soup(soup, year=year, page_num=page_num)
    return find_candidates_in_entries(entries, target_tokens, base_url)
