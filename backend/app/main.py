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


# One router per area; add each new one here as it lands.
from .routers import auth, listings, me, photos, requests, scan, spots  # noqa: E402

ROUTERS: list = [auth.router, me.router, photos.router, spots.router, listings.router,
           scan.router, requests.router]
for router in ROUTERS:
    app.include_router(router)
