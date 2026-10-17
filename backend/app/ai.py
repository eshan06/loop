"""OCI Generative AI: chat helpers and the scan pipeline (docs/ARCHITECTURE.md).

    vision_chat(images_b64, prompt) -> str     cohere.command-a-vision (Cohere V2 chat)
    text_chat(prompt) -> str                   cohere.command-a-03-2025
    scan_draft(jpegs, labels) -> (draft, source)

`scan_draft` never raises. It tries the vision model on the photos, falls back to
the text model with the on-device `labels`, and gives up after SCAN_TIMEOUT
seconds with an all-null draft and source "none".

Config comes from `settings` (backend/.env), never os.environ directly: systemd
doesn't load .env. Importing this module has no side effects; the client is
built on first use.

Quick check on the server (from backend/):
    .venv/bin/python -m app.ai text "t-shirt, red, cotton"
    .venv/bin/python -m app.ai vision photo1.jpg [photo2.jpg ...]
"""

from __future__ import annotations

import base64
import io
import json
import logging
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeout
from functools import lru_cache
from typing import Any

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
from PIL import Image
from pydantic import BaseModel, field_validator, model_validator

from .config import settings

log = logging.getLogger("loop.ai")

CATEGORIES = ("tops", "bottoms", "outerwear", "dresses", "shoes", "accessories", "bags")
CONDITIONS = ("new", "like_new", "good", "worn")
# Same limits as POST /listings in docs/API.md, so a draft always posts as is.
MAX_LEN = {"title": 120, "size": 20, "color": 60, "brand": 80, "description": 2000}
MAX_TAGS, MAX_TAG_LEN = 10, 30
AI_SIDE = 1024  # photos sent to the model are downscaled to this (faster, same answers)
MAX_LABELS_CHARS = 600

EMPTY_DRAFT: dict[str, Any] = {
    "title": None, "category": None, "size": None, "color": None,
    "brand": None, "condition": None, "description": None, "tags": [],
}


# --------------------------------------------------------------------------- client


@lru_cache(maxsize=1)
def _config() -> dict:
    cfg = oci.config.from_file(
        file_location=settings.oci_config_file,
        profile_name=settings.oci_config_profile,
    )
    cfg["region"] = settings.oci_region or cfg.get("region") or "us-chicago-1"
    return cfg


def _compartment_id() -> str:
    return settings.oci_compartment_id or _config()["tenancy"]


@lru_cache(maxsize=1)
def _client() -> GenerativeAiInferenceClient:
    cfg = _config()
    return GenerativeAiInferenceClient(
        config=cfg,
        service_endpoint=f"https://inference.generativeai.{cfg['region']}.oci.oraclecloud.com",
        retry_strategy=oci.retry.NoneRetryStrategy(),
        timeout=(5, settings.scan_timeout),
    )


def _chat(model_id: str, content: list, max_tokens: int = 700) -> str:
    details = ChatDetails(
        compartment_id=_compartment_id(),
        serving_mode=OnDemandServingMode(model_id=model_id),
        chat_request=CohereChatRequestV2(
            messages=[CohereUserMessageV2(content=content)],
            max_tokens=max_tokens,
            temperature=0.2,
        ),
    )
    message = _client().chat(details).data.chat_response.message
    return "".join(p.text for p in (message.content or []) if getattr(p, "text", None))


def _data_url(image_b64: str) -> str:
    return image_b64 if image_b64.startswith("data:") else f"data:image/jpeg;base64,{image_b64}"


def vision_chat(images_b64: list[str], prompt: str) -> str:
    """A prompt plus one or more base64 JPEGs to the vision model; returns its text."""
    content = [CohereTextContentV2(text=prompt)]
    content += [CohereImageContentV2(image_url=CohereImageUrlV2(url=_data_url(b))) for b in images_b64]
    return _chat(settings.genai_vision_model, content)


def text_chat(prompt: str, max_tokens: int = 700) -> str:
    """A text-only prompt to the text model; returns its text."""
    return _chat(settings.genai_text_model, [CohereTextContentV2(text=prompt)], max_tokens)


# --------------------------------------------------------------------------- parsing

_FENCE = re.compile(r"```[a-zA-Z]*\s*|\s*```")


def extract_json(reply: str) -> dict:
    """The first JSON object in a model reply (code fences and chatter ignored)."""
    text = _FENCE.sub("", reply or "").strip()
    start = text.find("{")
    if start < 0:
        raise ValueError("no JSON object in reply")
    obj, _ = json.JSONDecoder().raw_decode(text[start:])
    if not isinstance(obj, dict):
        raise ValueError("reply JSON is not an object")
    return obj


_NULLISH = {"", "null", "none", "n/a", "na", "unknown", "unsure", "not visible", "-", "?"}

_CATEGORY_ALIASES = {
    "top": "tops", "shirt": "tops", "shirts": "tops", "t-shirt": "tops", "tshirt": "tops",
    "sweater": "tops", "sweaters": "tops", "hoodie": "tops", "blouse": "tops",
    "bottom": "bottoms", "pants": "bottoms", "jeans": "bottoms", "shorts": "bottoms",
    "skirt": "bottoms", "skirts": "bottoms", "trousers": "bottoms",
    "jacket": "outerwear", "jackets": "outerwear", "coat": "outerwear", "coats": "outerwear",
    "dress": "dresses", "shoe": "shoes", "sneakers": "shoes", "boots": "shoes",
    "accessory": "accessories", "hat": "accessories", "hats": "accessories",
    "bag": "bags", "backpack": "bags", "handbag": "bags", "purse": "bags",
}
_CONDITION_ALIASES = {
    "brand_new": "new", "new_with_tags": "new", "nwt": "new",
    "likenew": "like_new", "excellent": "like_new", "very_good": "like_new",
    "used": "good", "gently_used": "good", "fair": "worn", "well_worn": "worn", "poor": "worn",
}


# Size vocabulary (IOS-2, docs/API.md "Sizes"): the app's size picker and the feed's
# exact-match size filter use these values, so drafts are mapped into them.
LETTER_SIZES = ("XS", "S", "M", "L", "XL", "XXL")
ONE_SIZE = "One size"
_LETTER_ALIASES = {
    "xs": "XS", "x-small": "XS", "xsmall": "XS", "extra small": "XS", "extra-small": "XS",
    "s": "S", "sm": "S", "small": "S",
    "m": "M", "med": "M", "medium": "M",
    "l": "L", "lg": "L", "large": "L",
    "xl": "XL", "x-large": "XL", "xlarge": "XL", "extra large": "XL", "extra-large": "XL",
    "xxl": "XXL", "2xl": "XXL", "xx-large": "XXL", "xxlarge": "XXL", "2x": "XXL",
    "extra extra large": "XXL",
}
_ONE_SIZE_ALIASES = {
    "one size", "onesize", "one-size", "os", "o/s", "osfa", "osfm", "one size fits all",
    "one size fits most", "free size", "universal", "adjustable",
}
_SIZE_PREFIX = re.compile(r"^(?:size|sz|us|usa|men'?s|women'?s|mens|womens|unisex|m|w)\b[\s:.]*")
_WAIST = (
    re.compile(r"^w\s*(\d{2})(?:\s*[x/ ]?\s*l\s*\d{2})?$"),     # W32, W32 L30, W32xL30
    re.compile(r"^(\d{2})\s*w(?:\s*[x/ ]?\s*\d{2}\s*l)?$"),      # 32W, 32W 30L
    re.compile(r"^(\d{2})\s*[x/]\s*\d{2}$"),                     # 32x30, 32/30
)
_SHOE = re.compile(r"^(\d{1,2})(?:\.(\d))?(\s*1/2|½)?$")


def normalize_size(size: str | None, category: str | None) -> str | None:
    """Map a model's size into the IOS-2 vocabulary where it clearly fits.

    "Large" -> "L", "W32 L30" -> "32", "US 9 1/2" -> "9.5" (shoes), "one-size" ->
    "One size". Anything else is kept as is (the app shows it as "Other"). A bag or
    accessory with no size gets "One size".
    """
    if size is None:
        return ONE_SIZE if category in ("accessories", "bags") else None
    key = " ".join(size.lower().replace("_", " ").split()).strip(" .,;")
    if key in _ONE_SIZE_ALIASES:
        return ONE_SIZE
    if key in _LETTER_ALIASES:
        return _LETTER_ALIASES[key]
    bare = _SIZE_PREFIX.sub("", key, count=1).strip() if len(key) > 1 else key
    if bare in _LETTER_ALIASES and bare != key:
        return _LETTER_ALIASES[bare]
    # "M (8-10)": a letter size followed by a conversion in brackets.
    for text in (key, bare):
        head = re.match(r"^([a-z0-9\-]+(?: [a-z]+)?)\s*\(", text)
        if head and head.group(1) in _LETTER_ALIASES and category != "shoes":
            return _LETTER_ALIASES[head.group(1)]
    for pattern in _WAIST:
        m = pattern.match(key) or pattern.match(bare)
        if m and 24 <= int(m.group(1)) <= 40:
            return m.group(1)
    if category == "shoes":
        m = _SHOE.match(bare)
        if m:
            value = int(m.group(1)) + (int(m.group(2) or 0) / 10) + (0.5 if m.group(3) else 0)
            value = round(value * 2) / 2
            if 5 <= value <= 14:
                return f"{value:g}"
    elif category == "bottoms" and re.fullmatch(r"\d{2}", bare) and 24 <= int(bare) <= 40:
        return bare
    return size


def _clean_str(value: Any, cap: int) -> str | None:
    if value is None or isinstance(value, (dict, list, bool)):
        return None
    text = " ".join(str(value).split())
    if text.lower() in _NULLISH:
        return None
    return text[:cap].rstrip() or None


def _enum(value: Any, allowed: tuple[str, ...], aliases: dict[str, str]) -> str | None:
    if not isinstance(value, str):
        return None
    key = re.sub(r"[\s\-]+", "_", value.strip().lower())
    key = aliases.get(key, aliases.get(key.replace("_", "-"), key))
    return key if key in allowed else None


class ScanDraft(BaseModel):
    """Lenient validation of a model reply into the docs/API.md ScanDraft shape."""

    title: str | None = None
    category: str | None = None
    size: str | None = None
    color: str | None = None
    brand: str | None = None
    condition: str | None = None
    description: str | None = None
    tags: list[str] = []

    @field_validator("title", "size", "color", "brand", "description", mode="before")
    @classmethod
    def _text(cls, value: Any, info) -> str | None:
        return _clean_str(value, MAX_LEN[info.field_name])

    @field_validator("category", mode="before")
    @classmethod
    def _category(cls, value: Any) -> str | None:
        return _enum(value, CATEGORIES, _CATEGORY_ALIASES)

    @field_validator("condition", mode="before")
    @classmethod
    def _condition(cls, value: Any) -> str | None:
        return _enum(value, CONDITIONS, _CONDITION_ALIASES)

    @field_validator("tags", mode="before")
    @classmethod
    def _tags(cls, value: Any) -> list[str]:
        if isinstance(value, str):
            value = value.split(",")
        if not isinstance(value, (list, tuple)):
            return []
        tags: list[str] = []
        for item in value:
            tag = _clean_str(item, MAX_TAG_LEN) if isinstance(item, (str, int, float)) else None
            tag = tag.lower().strip("#").strip() if tag else None
            if tag and tag not in tags:
                tags.append(tag)
        return tags[:MAX_TAGS]

    @model_validator(mode="after")
    def _size_vocabulary(self) -> ScanDraft:
        self.size = normalize_size(self.size, self.category)
        return self


def parse_draft(reply: str) -> dict[str, Any]:
    """Model reply -> validated draft dict. Raises ValueError if unusable."""
    draft = ScanDraft.model_validate(extract_json(reply)).model_dump()
    if not draft["title"] and not draft["category"]:
        raise ValueError("draft has neither title nor category")
    return draft


# --------------------------------------------------------------------------- scan

_SCHEMA_HINT = (
    "Reply with ONLY one JSON object, no markdown and no other text, with exactly these keys:\n"
    '{"title": string, "category": string, "size": string, "color": string, '
    '"brand": string, "condition": string, "description": string, "tags": [string]}\n'
    "Rules:\n"
    "- title: short and catchy for a student marketplace, at most 60 characters, "
    "e.g. \"Vintage Levi's denim trucker jacket\". Include the brand if you know it.\n"
    f"- category: exactly one of {', '.join(CATEGORIES)} "
    "(t-shirts, shirts, sweaters and hoodies are tops; jackets and coats are outerwear).\n"
    f"- condition: exactly one of {', '.join(CONDITIONS)} (judge visible wear; "
    "use good if it looks fine but used).\n"
    "- size: only from a visible size label, else null. Never guess a size. Write it in this "
    "vocabulary: tops, outerwear and dresses XS, S, M, L, XL or XXL; bottoms the waist number "
    "24 to 40 (32 for 32x30 or W32 L30) or a letter size; shoes the US size 5 to 14 in halves "
    "(9, 9.5); accessories and bags \"One size\".\n"
    "- color: the main color in plain words, like \"Light wash blue\".\n"
    "- brand: only if a logo or label shows it, else null.\n"
    "- description: one or two friendly sentences about style, material and fit.\n"
    "- tags: 3 to 6 short lowercase tags (style, material, type, color).\n"
    "Use null for anything you can't tell. Don't invent details."
)


def _vision_prompt(kinds: list[str]) -> str:
    order = ", ".join(kinds) if kinds else "front"
    return (
        "You write listings for Loop, an app where college students swap and give away "
        f"clothes. The attached photos show ONE clothing item ({order}, in that order; "
        "a label photo shows its tag). Describe the item.\n" + _SCHEMA_HINT
    )


def _labels_prompt(labels: str) -> str:
    return (
        "You write listings for Loop, an app where college students swap and give away "
        "clothes. A phone's on-device image classifier looked at ONE clothing item and "
        "produced these labels and text read off its tag (they may be noisy):\n"
        f"{labels}\n"
        "Describe the item from these labels only.\n" + _SCHEMA_HINT
    )


def _downscaled_b64(jpeg: bytes) -> str:
    with Image.open(io.BytesIO(jpeg)) as img:
        img = img.convert("RGB")
        img.thumbnail((AI_SIDE, AI_SIDE), Image.Resampling.LANCZOS)
        out = io.BytesIO()
        img.save(out, "JPEG", quality=80)
    return base64.b64encode(out.getvalue()).decode()


def clean_labels(labels: str | None) -> str:
    """Comma-separated labels from the app -> a short, deduped, comma-separated string."""
    seen: list[str] = []
    for part in (labels or "").split(","):
        word = " ".join(part.split())
        if word and word.lower() not in (s.lower() for s in seen):
            seen.append(word)
    return ", ".join(seen)[:MAX_LABELS_CHARS]


def _describe(exc: BaseException) -> str:
    if isinstance(exc, oci.exceptions.ServiceError):
        return f"ServiceError {exc.status} {exc.code}: {str(exc.message)[:200]}"
    return f"{type(exc).__name__}: {str(exc)[:200]}"


def _pipeline(jpegs: list[bytes], kinds: list[str], labels: str,
              give_up_at: float) -> tuple[dict[str, Any], str]:
    if jpegs:
        start = time.monotonic()
        try:
            images = [_downscaled_b64(j) for j in jpegs]
            draft = parse_draft(vision_chat(images, _vision_prompt(kinds)))
            log.info("scan: vision ok in %.1fs (%d photos)", time.monotonic() - start, len(jpegs))
            return draft, "vision"
        except Exception as exc:  # noqa: BLE001 - any failure means "try the fallback"
            log.warning("scan: vision failed after %.1fs: %s", time.monotonic() - start, _describe(exc))
    if labels and time.monotonic() < give_up_at:
        start = time.monotonic()
        try:
            draft = parse_draft(text_chat(_labels_prompt(labels)))
            log.info("scan: labels ok in %.1fs", time.monotonic() - start)
            return draft, "labels"
        except Exception as exc:  # noqa: BLE001
            log.warning("scan: labels failed after %.1fs: %s", time.monotonic() - start, _describe(exc))
    return dict(EMPTY_DRAFT, tags=[]), "none"


# A few threads so a stuck AI call can be abandoned at the deadline without blocking
# the request; the client's own read timeout ends the stuck call soon after.
_pool = ThreadPoolExecutor(max_workers=8, thread_name_prefix="ai")


def scan_draft(jpegs: list[bytes], labels: str | None = None,
               kinds: list[str] | None = None) -> tuple[dict[str, Any], str]:
    """(draft, source) for saved JPEG photos. Never raises; source is vision|labels|none."""
    deadline = settings.scan_timeout
    future = _pool.submit(_pipeline, jpegs, kinds or [], clean_labels(labels),
                          time.monotonic() + deadline)
    try:
        return future.result(timeout=deadline)
    except FutureTimeout:
        log.warning("scan: gave up after %.0fs deadline", deadline)
    except Exception as exc:  # noqa: BLE001 - _pipeline shouldn't raise, but never fail a scan
        log.warning("scan: pipeline error: %s", _describe(exc))
    return dict(EMPTY_DRAFT, tags=[]), "none"


# --------------------------------------------------------------------------- CLI


def _main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else "text"
    start = time.monotonic()
    if mode == "vision":
        jpegs = [open(p, "rb").read() for p in argv[2:]]
        draft, source = scan_draft(jpegs, kinds=["front", "back", "label"][: len(jpegs)])
    else:
        draft, source = scan_draft([], labels=argv[2] if len(argv) > 2 else "t-shirt, red, cotton")
    print(f"{source} in {time.monotonic() - start:.1f}s")
    print(json.dumps(draft, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
