"""Settings read from the environment and backend/.env.

Real environment variables win over the file. On the server the systemd unit sets
none (SELinux blocks EnvironmentFile in the home dir), so backend/.env is the source.
Blank values in .env fall back to the defaults below.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        env_ignore_empty=True,
        extra="ignore",
    )

    db_host: str = "127.0.0.1"
    db_port: int = 3306
    db_user: str = ""
    db_password: str = ""
    db_name: str = "loop"

    oci_config_file: str = "~/.oci/config"
    oci_config_profile: str = "DEFAULT"
    oci_region: str = "us-chicago-1"
    oci_compartment_id: str | None = None
    genai_vision_model: str = "cohere.command-a-vision"
    genai_text_model: str = "cohere.command-a-03-2025"
    scan_timeout: float = 20.0  # seconds POST /scan gives the AI before returning source "none"

    media_dir: str = "/home/opc/loop-media"
    public_base_url: str = ""

    def media_url(self, relative_path: str) -> str:
        """Public URL for a file under MEDIA_DIR, e.g. media_url("71.jpg")."""
        base = self.public_base_url.rstrip("/")
        return f"{base}/media/{relative_path.lstrip('/')}"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
