import os
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    ApiKey: str
    ReadAccessToken: str
    
    # We can default to Cloudflare's public DNS over HTTPS resolver
    DOH_URL: str = "https://1.1.1.1/dns-query"
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

settings = Settings()
