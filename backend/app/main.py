"""Loop API.

Run locally:  uvicorn app.main:app --reload --port 8000   (from backend/)
On the server: uvicorn app.main:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import logging
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .config import settings
from .errors import install_error_handlers
from .schemas import Health

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

app = FastAPI(title="Loop API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

install_error_handlers(app)

# Photos live on the server's disk and are served at /media/<file>.
media_dir = Path(settings.media_dir).expanduser()
media_dir.mkdir(parents=True, exist_ok=True)
app.mount("/media", StaticFiles(directory=media_dir), name="media")


@app.get("/health")
def health() -> Health:
    return Health(status="ok")


# Routers are added here as they land (S-8 onward), e.g.:
# from .routers import auth, me, photos, scan, listings, requests, messages, social, stats
# app.include_router(auth.router)
ROUTERS: list = []
for router in ROUTERS:
    app.include_router(router)
