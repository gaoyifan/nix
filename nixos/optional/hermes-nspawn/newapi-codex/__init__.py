"""Native Codex image generation and editing through codex-api.

Adapted from Hermes' official openai-codex plugin. Image requests go directly
through images/generations or images/edits without a chat model or SSE stream.
The legacy newapi-codex provider ID preserves existing user plugin selections.

Configuration:
    CODEX_API_BASE_URL  codex-api URL ending in /v1
    NEWAPI_API_KEY      existing per-user key, shared with codex-api
"""

from __future__ import annotations

import base64
import logging
import os
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from agent.image_gen_provider import (
    DEFAULT_ASPECT_RATIO,
    ImageGenProvider,
    error_response,
    normalize_reference_images,
    resolve_aspect_ratio,
    save_b64_image,
    success_response,
)

logger = logging.getLogger(__name__)

API_MODEL = "gpt-image-2"

_MODELS: Dict[str, Dict[str, Any]] = {
    "gpt-image-2-low": {
        "display": "GPT Image 2 (Low)",
        "speed": "~15s",
        "strengths": "Fast iteration, lowest cost",
        "quality": "low",
    },
    "gpt-image-2-medium": {
        "display": "GPT Image 2 (Medium)",
        "speed": "~40s",
        "strengths": "Balanced — default",
        "quality": "medium",
    },
    "gpt-image-2-high": {
        "display": "GPT Image 2 (High)",
        "speed": "~2min",
        "strengths": "Highest fidelity, strongest prompt adherence",
        "quality": "high",
    },
}

DEFAULT_MODEL = "gpt-image-2-medium"

_SIZES = {"landscape": "1536x1024", "square": "1024x1024", "portrait": "1024x1536"}

# Match the native image input limits in the official openai-codex plugin.
_MAX_REFERENCE_IMAGES = 16
_MAX_INPUT_IMAGE_BYTES = 25 * 1024 * 1024
_ACCEPTED_INPUT_MIME = frozenset({"image/png", "image/jpeg", "image/gif", "image/webp"})


def _get_setting(name: str) -> Optional[str]:
    value = os.environ.get(name, "").strip()
    return value or None


def _resolve_model() -> Tuple[str, Dict[str, Any]]:
    env_override = os.environ.get("OPENAI_IMAGE_MODEL")
    if env_override and env_override in _MODELS:
        return env_override, _MODELS[env_override]
    try:
        from hermes_cli.config import load_config

        cfg = load_config()
        section = cfg.get("image_gen") if isinstance(cfg, dict) else {}
        if isinstance(section, dict):
            sub = section.get("newapi-codex")
            if isinstance(sub, dict) and sub.get("model") in _MODELS:
                return sub["model"], _MODELS[sub["model"]]
            if section.get("model") in _MODELS:
                return section["model"], _MODELS[section["model"]]
    except Exception as exc:
        logger.debug("Could not load image_gen config: %s", exc)
    return DEFAULT_MODEL, _MODELS[DEFAULT_MODEL]


def _sniff_image_mime(raw: bytes) -> Optional[str]:
    from agent.image_routing import _sniff_mime_from_bytes

    mime = _sniff_mime_from_bytes(raw)
    return mime if mime in _ACCEPTED_INPUT_MIME else None


def _data_url_to_input_image_url(value: str) -> str:
    if "," not in value:
        raise ValueError("Image data URL is missing a comma separator")
    header, data = value.split(",", 1)
    header_lc = header.lower()
    if not header_lc.startswith("data:image/") or ";base64" not in header_lc:
        raise ValueError("Only base64 data:image URLs are supported as Codex image inputs")
    raw = base64.b64decode(data, validate=True)
    if len(raw) > _MAX_INPUT_IMAGE_BYTES:
        raise ValueError("Image data URL exceeds 25MB cap")
    mime = _sniff_image_mime(raw)
    if mime is None:
        raise ValueError("Image data URL does not contain supported image bytes")
    encoded = base64.b64encode(raw).decode("ascii")
    return f"data:{mime};base64,{encoded}"


def _local_image_to_data_url(value: str) -> str:
    from agent.file_safety import get_read_block_error

    blocked = get_read_block_error(value)
    if blocked:
        raise ValueError(blocked)

    path = Path(os.path.expanduser(value)).resolve()
    if not path.is_file():
        raise ValueError(f"Image input path does not exist or is not a file: {value}")
    size = path.stat().st_size
    if size <= 0:
        raise ValueError(f"Image input path is empty: {value}")
    if size > _MAX_INPUT_IMAGE_BYTES:
        raise ValueError(f"Image input path exceeds 25MB cap: {value}")
    raw = path.read_bytes()
    mime = _sniff_image_mime(raw)
    if mime is None:
        raise ValueError(f"Image input path is not a supported image: {value}")
    encoded = base64.b64encode(raw).decode("ascii")
    return f"data:{mime};base64,{encoded}"


def _remote_image_to_data_url(value: str) -> str:
    from tools.url_safety import create_ssrf_safe_client, is_safe_url

    if not is_safe_url(value):
        raise ValueError(f"Image URL failed the SSRF safety check: {value}")
    with create_ssrf_safe_client(timeout=60.0, follow_redirects=True) as client:
        response = client.get(value)
    response.raise_for_status()
    raw = response.content
    if len(raw) > _MAX_INPUT_IMAGE_BYTES:
        raise ValueError(f"Image URL exceeds 25MB cap: {value}")
    mime = _sniff_image_mime(raw)
    if mime is None:
        raise ValueError(f"Image URL did not return a supported image: {value}")
    return f"data:{mime};base64,{base64.b64encode(raw).decode('ascii')}"


def _to_input_image(value: str) -> Dict[str, str]:
    candidate = (value or "").strip()
    if not candidate:
        raise ValueError("Blank image input")
    lowered = candidate.lower()
    if lowered.startswith("http://") or lowered.startswith("https://"):
        image_url = _remote_image_to_data_url(candidate)
    elif lowered.startswith("data:"):
        image_url = _data_url_to_input_image_url(candidate)
    else:
        image_url = _local_image_to_data_url(candidate)
    return {"image_url": image_url}


def _normalize_input_images(
    image_url: Optional[str],
    reference_image_urls: Optional[List[str]],
) -> List[Dict[str, str]]:
    """Convert Hermes' primary/reference inputs into native Images API inputs."""
    values: List[str] = []
    if isinstance(image_url, str) and image_url.strip():
        values.append(image_url.strip())
    values.extend(normalize_reference_images(reference_image_urls) or [])
    values = values[:_MAX_REFERENCE_IMAGES]
    return [_to_input_image(value) for value in values]


def _build_image_request(
    prompt: str,
    size: str,
    quality: str,
    input_images: Optional[List[Dict[str, str]]] = None,
) -> Tuple[str, Dict[str, Any]]:
    body: Dict[str, Any] = {
        "model": API_MODEL,
        "prompt": prompt,
        "n": 1,
        "size": size,
        "quality": quality,
        "background": "opaque",
    }
    if input_images:
        body["images"] = input_images
        return "images/edits", body
    return "images/generations", body


def _post_image_request(base_url: str, api_key: str, path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    import httpx

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "x-codex-image-turn-id": str(uuid.uuid4()),
    }
    timeout = httpx.Timeout(300.0, connect=30.0, read=300.0, write=60.0, pool=30.0)
    with httpx.Client(timeout=timeout, headers=headers) as http:
        response = http.post(base_url.rstrip("/") + "/" + path, json=payload)
    if response.status_code >= 400:
        raise RuntimeError(f"Codex images API returned HTTP {response.status_code}: {response.text[:500]}")
    return response.json()


class NewApiCodexImageGenProvider(ImageGenProvider):
    """gpt-image-2 via the native Codex Images API."""

    @property
    def name(self) -> str:
        return "newapi-codex"

    @property
    def display_name(self) -> str:
        return "OpenAI gpt-image-2 (codex-api)"

    def is_available(self) -> bool:
        if not (_get_setting("NEWAPI_API_KEY") and _get_setting("CODEX_API_BASE_URL")):
            return False
        try:
            import httpx  # noqa: F401
        except ImportError:
            return False
        return True

    def list_models(self) -> List[Dict[str, Any]]:
        return [
            {
                "id": mid,
                "display": m["display"],
                "speed": m["speed"],
                "strengths": m["strengths"],
                "price": "varies",
            }
            for mid, m in _MODELS.items()
        ]

    def default_model(self) -> Optional[str]:
        return DEFAULT_MODEL

    def get_setup_schema(self) -> Dict[str, Any]:
        return {
            "name": "OpenAI gpt-image-2 (codex-api)",
            "tag": "gpt-image-2 via codex-api — supports text and image inputs",
            "env_vars": [
                {"key": "CODEX_API_BASE_URL", "prompt": "codex-api base URL (…/v1)"},
                {"key": "NEWAPI_API_KEY", "prompt": "codex-api token"},
            ],
        }

    def capabilities(self) -> Dict[str, Any]:
        # Hermes builds the image_generate tool schema from this value. If
        # "image" is absent, the model is told that image_url is unsupported.
        return {
            "modalities": ["text", "image"],
            "max_reference_images": _MAX_REFERENCE_IMAGES,
        }

    def generate(
        self,
        prompt: str,
        aspect_ratio: str = DEFAULT_ASPECT_RATIO,
        *,
        image_url: Optional[str] = None,
        reference_image_urls: Optional[List[str]] = None,
        **kwargs: Any,
    ) -> Dict[str, Any]:
        prompt = (prompt or "").strip()
        aspect = resolve_aspect_ratio(aspect_ratio)
        if not prompt:
            return error_response(
                error="Prompt is required and must be a non-empty string",
                error_type="invalid_argument",
                provider=self.name,
                aspect_ratio=aspect,
            )

        base_url = _get_setting("CODEX_API_BASE_URL")
        api_key = _get_setting("NEWAPI_API_KEY")
        if not (base_url and api_key):
            return error_response(
                error="CODEX_API_BASE_URL / NEWAPI_API_KEY not configured",
                error_type="auth_required",
                provider=self.name,
                aspect_ratio=aspect,
            )

        tier_id, meta = _resolve_model()
        size = _SIZES.get(aspect, _SIZES["square"])

        try:
            input_images = _normalize_input_images(image_url, reference_image_urls)
        except Exception as exc:
            return error_response(
                error=f"Invalid image input for Codex image editing: {exc}",
                error_type="invalid_image_input",
                provider=self.name,
                model=tier_id,
                prompt=prompt,
                aspect_ratio=aspect,
            )

        path, payload = _build_image_request(
            prompt,
            size,
            meta["quality"],
            input_images=input_images or None,
        )

        try:
            result = _post_image_request(base_url, api_key, path, payload)
            data = result.get("data")
            b64 = data[0].get("b64_json") if isinstance(data, list) and data and isinstance(data[0], dict) else None
        except Exception as exc:
            logger.debug("Codex image generation failed", exc_info=True)
            return error_response(
                error=f"Image generation via codex-api failed: {exc}",
                error_type="api_error",
                provider=self.name,
                model=tier_id,
                prompt=prompt,
                aspect_ratio=aspect,
            )

        if not isinstance(b64, str) or not b64:
            return error_response(
                error="Codex images API response contained no image data",
                error_type="empty_response",
                provider=self.name,
                model=tier_id,
                prompt=prompt,
                aspect_ratio=aspect,
            )

        try:
            saved_path = save_b64_image(b64, prefix=f"codex_api_{tier_id}")
        except Exception as exc:
            return error_response(
                error=f"Could not save image to cache: {exc}",
                error_type="io_error",
                provider=self.name,
                model=tier_id,
                prompt=prompt,
                aspect_ratio=aspect,
            )

        return success_response(
            image=str(saved_path),
            model=tier_id,
            prompt=prompt,
            aspect_ratio=aspect,
            provider=self.name,
            modality="image" if input_images else "text",
            extra={
                "size": size,
                "quality": meta["quality"],
                "input_image_count": len(input_images),
                "reported_size": result.get("size"),
                "reported_quality": result.get("quality"),
            },
        )


def register(ctx) -> None:
    ctx.register_image_gen_provider(NewApiCodexImageGenProvider())
