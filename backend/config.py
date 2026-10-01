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
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

settings = Settings()
