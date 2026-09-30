# Isaimini Language Guard Specification

## 1. Objective

Prevent `IsaiminiScraper` from processing non-Indian / English titles to eliminate false-positive title token collisions (e.g. English movies accidentally matching unrelated Tamil movies with overlapping words) and avoid redundant HTTP network requests.

---

## 2. Shared Data Contract (`backend/scrappers/base.py`)

Ensure `MediaItem` contains language and regional metadata populated by `ScraperManager`:

```python
@dataclass(slots=True)
class MediaItem:
    title: str
    year: int
    media_type: str = "movie"  # "movie" or "tv"
    tmdb_id: int | None = None
    imdb_id: str | None = None
    season: int | None = None
    episode: int | None = None
    original_language: str | None = None
    origin_countries: list[str] = field(default_factory=list)
```

---

## 3. Provider Guard Logic (`backend/scrappers/providers/isaimini/scraper.py`)

Define supported Indian language codes in `backend/scrappers/providers/isaimini/constants.py`:

```python
INDIAN_LANGUAGES = {"ta", "te", "hi", "ml", "kn"}
```

At the top of `IsaiminiScraper.scrape()`, apply the eligibility check before initiating domain resolution or catalog lookups:

```python
class IsaiminiScraper(BaseScraper):
    name = "Isaimini"

    async def scrape(
        self,
        media: MediaItem,
        on_progress: Callable[[str, str], None] | None = None
    ) -> list[StreamSource]:
        results: list[StreamSource] = []

        # 1. Isaimini only supports movies
        if media.media_type != "movie":
            return results

        # 2. Language & Origin Guard
        is_indian_origin = (
            (media.original_language in INDIAN_LANGUAGES) or
            ("IN" in media.origin_countries)
        )

        # If language is known and non-Indian, skip immediately
        if media.original_language and not is_indian_origin:
            logger.debug(
                f"[{self.name}] Skipping non-Indian title '{media.title}' "
                f"(lang={media.original_language}, origin={media.origin_countries})"
            )
            return results

        # ... proceed with existing Isaimini scraping workflow ...
```

---

## 4. Expected Behavior & Test Matrix

| Title | Year | Language | `origin_countries` | Expected Isaimini Action |
|---|---|---|---|---|
| *Leo* | 2023 | `ta` | `["IN"]` | **Scrape** (Tamil native) |
| *RRR* | 2022 | `te` | `["IN"]` | **Scrape** (Regional/Dubbed candidate) |
| *Jawan* | 2023 | `hi` | `["IN"]` | **Scrape** (Hindi/Dubbed candidate) |
| *The Matrix* | 1999 | `en` | `["US"]` | **Fast Exit (`[]`)** |
| *Inception* | 2010 | `en` | `["US", "GB"]` | **Fast Exit (`[]`)** |
| *Spirited Away* | 2001 | `ja` | `["JP"]` | **Fast Exit (`[]`)** |

---

## 5. Verification Commandline Tests

```bash
# 1. Verify English movie returns 0 sources immediately without making requests:
python -c "
import asyncio
from backend.scrappers.base import MediaItem
from backend.scrappers.providers.isaimini import IsaiminiScraper

async def test():
    item = MediaItem(title='The Matrix', year=1999, original_language='en', origin_countries=['US'])
    scraper = IsaiminiScraper()
    sources = await scraper.scrape(item)
    print('English sources:', sources)
    assert len(sources) == 0

asyncio.run(test())
"

# 2. Verify Tamil movie proceeds to scrape:
python -c "
import asyncio
from backend.scrappers.base import MediaItem
from backend.scrappers.providers.isaimini import IsaiminiScraper

async def test():
    item = MediaItem(title='Leo', year=2023, original_language='ta', origin_countries=['IN'])
    scraper = IsaiminiScraper()
    sources = await scraper.scrape(item)
    print('Tamil sources count:', len(sources))

asyncio.run(test())
"
```
