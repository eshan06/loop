"""Pydantic request and response models. They must match docs/API.md."""

from pydantic import BaseModel


class Health(BaseModel):
    status: str
