import os
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = DATA_DIR / "catalog.db"

class Settings(BaseSettings):
    ApiKey: str
    ReadAccessToken: str
    
    # We can default to Cloudflare's public DNS over HTTPS resolver
    DOH_URL: str = "https://1.1.1.1/dns-query"

    MEDIAFLOW_PORT: int = 8888
    MEDIAFLOW_API_PASSWORD: str = "mediaflow_secret"
    MEDIAFLOW_PUBLIC_HOST: str | None = None

    PENGUPLAY_MANIFEST_URL: str = "https://pengu.uk/%7B%22auth_token%22%3A%22p30MBIC3MSN4Dbh5ZGDeVyGUzMoFFJUBEL4FNv36DWY%22%7D/manifest.json"
    HDHUB_MANIFEST_URL: str = "https://hdhub.thevolecitor.qzz.io/eyJ0b3Jib3giOiJ1bnNldCIsInF1YWxpdGllcyI6IjIxNjBwLDEwODBwLDcyMHAsNDgwcCIsInNvcnQiOiJkZXNjIiwiY29udGVudCI6ImFzaWFuIiwiY2F0YWxvZ3MiOiIifQ/manifest.json"
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

settings = Settings()
