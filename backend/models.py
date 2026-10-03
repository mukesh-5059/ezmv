from pydantic import BaseModel, ConfigDict, Field

class MovieSummary(BaseModel):
    model_config = ConfigDict(extra="ignore")

    tmdb_id: int
    title: str = ""
    original_title: str = ""
    overview: str = ""
    release_date: str = ""
    poster_path: str = ""
    backdrop_path: str = ""
    vote_average: float = 0.0
    original_language: str = "ta"
    media_type: str = "movie"
    genre_ids: list[int] = Field(default_factory=list)

    @classmethod
    def from_catalog(cls, row: dict, default_genre: int | None = None) -> "MovieSummary":
        year = row.get("year")
        release_date = f"{year}-01-01" if year else ""
        genre_ids = [default_genre] if default_genre else []
        return cls(
            tmdb_id=row.get("tmdb_id") or (abs(hash(row.get("imdb_id", "0"))) % 100000000),
            title=row.get("title", ""),
            original_title=row.get("title", ""),
            overview=row.get("overview") or "",
            release_date=release_date,
            poster_path=row.get("poster_path") or "",
            backdrop_path=row.get("backdrop_path") or "",
            vote_average=float(row.get("rating") or 0.0),
            original_language="ta",
            media_type="movie",
            genre_ids=genre_ids,
        )

    @classmethod
    def from_tmdb(cls, item: dict, media_type: str = "movie") -> "MovieSummary":
        return cls(
            tmdb_id=item.get("id") or 0,
            title=item.get("title") if media_type == "movie" else (item.get("name") or ""),
            original_title=item.get("original_title") if media_type == "movie" else (item.get("original_name") or ""),
            overview=item.get("overview") or "",
            release_date=item.get("release_date") if media_type == "movie" else (item.get("first_air_date") or ""),
            poster_path=item.get("poster_path") or "",
            backdrop_path=item.get("backdrop_path") or "",
            vote_average=float(item.get("vote_average") or 0.0),
            original_language=item.get("original_language") or "",
            media_type=media_type,
            genre_ids=item.get("genre_ids") or [],
        )


class CastMember(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    name: str = ""
    character: str = ""
    profile_path: str | None = None
    order: int = 0


class TvEpisode(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    episode_number: int
    season_number: int = 1
    name: str = ""
    overview: str = ""
    still_path: str | None = None
    air_date: str | None = None
    vote_average: float = 0.0
    runtime: int | None = None


class TvSeason(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    season_number: int
    name: str = ""
    overview: str = ""
    poster_path: str | None = None
    episode_count: int = 0
    air_date: str | None = None
    episodes: list[TvEpisode] = Field(default_factory=list)


class MovieDetails(BaseModel):
    model_config = ConfigDict(extra="allow")

    tmdb_id: int
    title: str = ""
    imdb_id: str | None = None
    overview: str = ""
    release_date: str = ""
    poster_path: str = ""
    backdrop_path: str = ""
    vote_average: float = 0.0
    vote_count: int = 0
    genres: list[dict] = Field(default_factory=list)
    runtime: int | None = None
    tagline: str | None = None
    media_type: str = "movie"
    number_of_seasons: int = 0
    number_of_episodes: int = 0
    seasons: list[TvSeason] = Field(default_factory=list)
    external_ids: dict = Field(default_factory=dict)
    cast: list[CastMember] = Field(default_factory=list)

    @classmethod
    def from_tmdb(cls, details: dict, media_type: str = "movie") -> "MovieDetails":
        data = dict(details)
        external_ids = data.get("external_ids", {})
        imdb_id = data.get("imdb_id") or external_ids.get("imdb_id")
        data["tmdb_id"] = data.get("id") or 0
        data["imdb_id"] = imdb_id
        is_tv = media_type == "tv" or "first_air_date" in data or "number_of_seasons" in data
        data["media_type"] = "tv" if is_tv else "movie"
        data["title"] = (data.get("name") or data.get("title") or "") if is_tv else (data.get("title") or "")
        data["release_date"] = (data.get("first_air_date") or data.get("release_date") or "") if is_tv else (data.get("release_date") or "")
        data["external_ids"] = external_ids

        raw_seasons = data.get("seasons", [])
        data["seasons"] = [
            TvSeason(
                id=s.get("id", 0),
                season_number=s.get("season_number", 0),
                name=s.get("name", ""),
                overview=s.get("overview", ""),
                poster_path=s.get("poster_path"),
                episode_count=s.get("episode_count", 0),
                air_date=s.get("air_date"),
            )
            for s in raw_seasons
            if isinstance(s, dict)
        ]
        data["number_of_seasons"] = data.get("number_of_seasons") or len(data["seasons"])
        data["number_of_episodes"] = data.get("number_of_episodes") or 0

        credits_data = data.get("credits", {})
        raw_cast = credits_data.get("cast", []) if isinstance(credits_data, dict) else []
        data["cast"] = [
            CastMember(
                id=c.get("id", 0),
                name=c.get("name", ""),
                character=c.get("character", ""),
                profile_path=c.get("profile_path"),
                order=c.get("order", 0)
            )
            for c in raw_cast
            if isinstance(c, dict)
        ]
        return cls(**data)


class StreamSource(BaseModel):
    model_config = ConfigDict(extra="allow")

    quality: str = "HD"
    url: str
    type: str = "direct"
    provider: str = ""
    size_mb: float | None = None


class StreamResponse(BaseModel):
    model_config = ConfigDict(extra="allow")

    title: str = ""
    year: int = 0
    media_type: str = "movie"
    tmdb_id: int
    imdb_id: str | None = None
    season: int | None = None
    episode: int | None = None
    cache_expires_in: int = 0
    streams: list[StreamSource] = Field(default_factory=list)


class SubtitleTrack(BaseModel):
    model_config = ConfigDict(extra="allow")

    id: str = ""
    language: str = "English"
    code: str = "en"
    url: str
    format: str = "vtt"
    release: str | None = None


class SubtitleResponse(BaseModel):
    model_config = ConfigDict(extra="allow")

    tmdb_id: int
    imdb_id: str | None = None
    media_type: str = "movie"
    season: int | None = None
    episode: int | None = None
    subtitles: list[SubtitleTrack] = Field(default_factory=list)


class DashboardLane(BaseModel):
    model_config = ConfigDict(extra="allow")

    id: str
    title: str
    items: list[MovieSummary] = Field(default_factory=list)
    has_more: bool = False
    next_page: int | None = None


class DashboardResponse(BaseModel):
    model_config = ConfigDict(extra="allow")

    language: str
    lanes: list[DashboardLane] = Field(default_factory=list)


class LaneMoviesResponse(BaseModel):
    model_config = ConfigDict(extra="allow")

    id: str
    page: int
    has_more: bool = False
    next_page: int | None = None
    items: list[MovieSummary] = Field(default_factory=list)


class FilterOption(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int | str | None = None
    label: str
    year_min: int | None = None
    year_max: int | None = None


class FiltersResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    languages: list[FilterOption]
    genres: list[FilterOption]
    years: list[FilterOption]
    sort_options: list[FilterOption]


class TraktListSummary(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int | str
    name: str
    description: str = ""
    item_count: int = 0
    likes: int = 0
    user_name: str = ""
    slug: str = ""


class ActorSummary(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    name: str
    profile_path: str | None = None
    character: str | None = None
    known_for_department: str | None = None


class PersonDetailsResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    name: str
    biography: str = ""
    profile_path: str | None = None
    known_for_department: str | None = None
    birthday: str | None = None
    place_of_birth: str | None = None
    popular: list[MovieSummary] = Field(default_factory=list)
    recent: list[MovieSummary] = Field(default_factory=list)



