"""One place that turns every error into the shape in docs/API.md:

    {"error": {"code": "not_found", "message": "..."}}

Routers raise `ApiError(status, code, message)`. Plain `HTTPException`s,
FastAPI's validation errors, and unhandled exceptions are converted too.
"""

from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

log = logging.getLogger("loop.errors")

# Default code and user-facing message for each status.
_DEFAULTS: dict[int, tuple[str, str]] = {
    400: ("bad_request", "Something about that request wasn't right."),
    401: ("unauthorized", "Please sign in again."),
    403: ("forbidden", "You can't do that."),
    404: ("not_found", "We couldn't find that."),
    405: ("bad_request", "That action isn't supported here."),
    409: ("conflict", "That conflicts with something that already happened."),
    413: ("photo_too_large", "That photo is too large."),
    422: ("bad_request", "Something about that request wasn't right."),
    500: ("server_error", "Something went wrong on our end. Please try again."),
    502: ("ai_unavailable", "The AI is unavailable right now."),
}


class ApiError(Exception):
    """Raise from any route: `raise ApiError(404, "not_found", "No such listing.")`."""

    def __init__(self, status: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def error_response(status: int, code: str | None = None, message: str | None = None,
                   headers: dict[str, str] | None = None) -> JSONResponse:
    default_code, default_message = _DEFAULTS.get(
        status, ("server_error", _DEFAULTS[500][1]) if status >= 500 else ("bad_request", _DEFAULTS[400][1])
    )
    return JSONResponse(
        status_code=status,
        content={"error": {"code": code or default_code, "message": message or default_message}},
        headers=headers,
    )


async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
    return error_response(exc.status, exc.code, exc.message)


async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    code = message = None
    detail = exc.detail
    if isinstance(detail, dict):
        code, message = detail.get("code"), detail.get("message")
    elif isinstance(detail, str) and exc.status_code not in (404, 405) and detail.strip():
        # Starlette's stock details ("Not Found") are replaced by friendlier defaults.
        message = detail
    return error_response(exc.status_code, code, message, getattr(exc, "headers", None))


def _field_name(loc: tuple) -> str:
    parts = [str(p) for p in loc if p not in ("body", "query", "path", "header", "form")]
    return ".".join(parts) or "request"


async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
    errors = exc.errors()
    if errors:
        first = errors[0]
        message = f"{_field_name(tuple(first.get('loc', ())))}: {first.get('msg', 'invalid value')}"
    else:
        message = None
    return error_response(400, "bad_request", message)


async def _unhandled(request: Request, exc: Exception) -> JSONResponse:
    log.exception("Unhandled error on %s %s", request.method, request.url.path, exc_info=exc)
    return error_response(500)


def install_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(ApiError, _api_error)
    app.add_exception_handler(StarletteHTTPException, _http_error)
    app.add_exception_handler(RequestValidationError, _validation_error)
    app.add_exception_handler(Exception, _unhandled)
