from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Callable, Any

@dataclass(slots=True)
class MediaItem:
    title: str
    year: int
    media_type: str = "movie"  # "movie" or "tv"
    tmdb_id: int | None = None
    imdb_id: str | None = None
    season: int | None = None
    episode: int | None = None

@dataclass(slots=True)
class StreamSource:
    url: str
    provider: str
    quality: str
    headers: dict[str, str] = field(default_factory=dict)

class BaseScraper(ABC):
    name: str = "BaseScraper"

    @abstractmethod
    async def scrape(
        self,
        media: MediaItem,
        on_progress: Callable[[str, str], None] | None = None
    ) -> list[StreamSource]:
        """
        Scrapes stream sources for a given MediaItem.
        Optionally reports progress milestones via on_progress(step, message).
        """
        pass
