from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Callable, Any

@dataclass(slots=True)
class MediaItem:
    title: str
    year: int
    media_type: str = "movie"
    tmdb_id: int | None = None
    imdb_id: str | None = None
    season: int | None = None
    episode: int | None = None
    original_language: str | None = None
    origin_countries: list[str] = field(default_factory=list)
    runtime_minutes: int | None = None

@dataclass(slots=True)
class StreamSource:
    url: str
    provider: str
    quality: str
    headers: dict[str, str] = field(default_factory=dict)
    expires_at: int | None = None
    ttl: int | None = None
    priority: int = 100
    size_mb: float | None = None
    formatted_size: str | None = None
    bitrate_kbps: int | None = None
    bitrate_str: str | None = None
    languages: list[str] = field(default_factory=list)
    source: str | None = None
    host: str | None = None
    filename: str | None = None

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
