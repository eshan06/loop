"""Minimal OCI Generative AI chat helpers (Cohere V2 chat format).

Proven in S-3 against `cohere.command-a-vision` and `cohere.command-a-03-2025`
in us-chicago-1. S-10 (`POST /scan`) and "Style it" reuse these.

Settings come from the environment (all optional):
    OCI_CONFIG_FILE      default ~/.oci/config
    OCI_CONFIG_PROFILE   default DEFAULT
    OCI_REGION           default us-chicago-1
    OCI_COMPARTMENT_ID   default the tenancy OCID from the OCI config
    GENAI_VISION_MODEL   default cohere.command-a-vision
    GENAI_TEXT_MODEL     default cohere.command-a-03-2025
    GENAI_TIMEOUT        read timeout in seconds, default 20

Importing this module has no side effects; the client is built on first use.

Run as a script for a smoke test:
    python -m app.genai_probe text
    python -m app.genai_probe vision path/to/photo.jpg
"""

from __future__ import annotations

import base64
import os
import sys
import time
from functools import lru_cache

import oci
from oci.generative_ai_inference import GenerativeAiInferenceClient
from oci.generative_ai_inference.models import (
    ChatDetails,
    CohereChatRequestV2,
    CohereImageContentV2,
    CohereImageUrlV2,
    CohereTextContentV2,
    CohereUserMessageV2,
    OnDemandServingMode,
)


def _env(name: str, default: str) -> str:
    return os.environ.get(name) or default


@lru_cache(maxsize=1)
def _config() -> dict:
    cfg = oci.config.from_file(
        file_location=_env("OCI_CONFIG_FILE", "~/.oci/config"),
        profile_name=_env("OCI_CONFIG_PROFILE", "DEFAULT"),
    )
    cfg["region"] = _env("OCI_REGION", cfg.get("region") or "us-chicago-1")
    return cfg


def _compartment_id() -> str:
    return os.environ.get("OCI_COMPARTMENT_ID") or _config()["tenancy"]


@lru_cache(maxsize=1)
def _client() -> GenerativeAiInferenceClient:
    cfg = _config()
    endpoint = f"https://inference.generativeai.{cfg['region']}.oci.oraclecloud.com"
    timeout = float(_env("GENAI_TIMEOUT", "20"))
    return GenerativeAiInferenceClient(
        config=cfg,
        service_endpoint=endpoint,
        retry_strategy=oci.retry.NoneRetryStrategy(),
        timeout=(10, timeout),
    )


def _chat(model_id: str, content: list, max_tokens: int = 600) -> str:
    request = CohereChatRequestV2(
        messages=[CohereUserMessageV2(content=content)],
        max_tokens=max_tokens,
        temperature=0.2,
    )
    details = ChatDetails(
        compartment_id=_compartment_id(),
        serving_mode=OnDemandServingMode(model_id=model_id),
        chat_request=request,
    )
    response = _client().chat(details)
    message = response.data.chat_response.message
    return "".join(
        part.text for part in (message.content or []) if getattr(part, "text", None)
    )


def _data_url(image_b64: str) -> str:
    if image_b64.startswith("data:"):
        return image_b64
    return f"data:image/jpeg;base64,{image_b64}"


def vision_chat(images_b64: list[str], prompt: str) -> str:
    """Send a prompt plus one or more base64 JPEGs to the vision model; return its text."""
    content = [CohereTextContentV2(text=prompt)]
    content += [
        CohereImageContentV2(image_url=CohereImageUrlV2(url=_data_url(img)))
        for img in images_b64
    ]
    return _chat(_env("GENAI_VISION_MODEL", "cohere.command-a-vision"), content)


def text_chat(prompt: str) -> str:
    """Send a text-only prompt to the text model; return its text."""
    content = [CohereTextContentV2(text=prompt)]
    return _chat(_env("GENAI_TEXT_MODEL", "cohere.command-a-03-2025"), content)


_DEMO_PROMPT = (
    "This is a photo of a clothing item for a campus swap listing. "
    'Reply with only a JSON object with keys "title", "category", "color".'
)


def _main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else "text"
    start = time.monotonic()
    if mode == "vision":
        with open(argv[2], "rb") as f:
            reply = vision_chat([base64.b64encode(f.read()).decode()], _DEMO_PROMPT)
    else:
        reply = text_chat(
            "Labels from a phone's image classifier: t-shirt, red, cotton. "
            + _DEMO_PROMPT.replace("This is a photo of", "They describe")
        )
    print(f"{mode}: {time.monotonic() - start:.1f}s")
    print(reply)
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
