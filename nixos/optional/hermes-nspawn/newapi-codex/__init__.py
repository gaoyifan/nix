"""OpenAI image generation backend routed through New API.

Adaptation of the bundled ``openai-codex`` image-gen plugin: same gpt-image-2
tiers and the same Codex Responses ``image_generation`` tool call, but sent to
New API (Bearer token from ``NEWAPI_API_KEY``) instead of chatgpt.com with a
ChatGPT OAuth token. The Codex channel inside New API
replays the request to the real Codex backend, so behavior matches the bundled
plugin while credentials stay centralized on the gateway.

Image editing is not inferred from the prompt: source images must be serialized
as Responses ``input_image`` content parts. Keep that path aligned with the
bundled ``openai-codex`` plugin when Hermes changes its image-input handling.

Configuration:
    NEWAPI_BASE_URL  e.g. http://somo-minisforum.ts.gaof.net:3000/v1
    NEWAPI_API_KEY   per-VM New API token
"""

from __future__ import annotations

import base64
import json
import logging
import os
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

# The chat model only hosts the image_generation tool call; the image work is
# done by API_MODEL. Must be a model enabled on the New API token/channel.
_CHAT_MODEL = "gpt-5.6-sol"
_INSTRUCTIONS = (
    "You are an assistant that must fulfill image generation and image editing "
    "requests by using the image_generation tool when provided."
)
# These limits and accepted formats mirror Hermes' bundled openai-codex
# provider and the gpt-image-2 Responses input contract.
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


def _to_input_image_part(value: str) -> Dict[str, str]:
    candidate = (value or "").strip()
    if not candidate:
        raise ValueError("Blank image input")
    lowered = candidate.lower()
    if lowered.startswith("http://") or lowered.startswith("https://"):
        image_url = candidate
    elif lowered.startswith("data:"):
        image_url = _data_url_to_input_image_url(candidate)
    else:
        image_url = _local_image_to_data_url(candidate)
    return {"type": "input_image", "image_url": image_url}


def _normalize_input_images(
    image_url: Optional[str],
    reference_image_urls: Optional[List[str]],
) -> List[Dict[str, str]]:
    """Convert Hermes' primary/reference inputs into ordered Responses parts."""
    values: List[str] = []
    if isinstance(image_url, str) and image_url.strip():
        values.append(image_url.strip())
    values.extend(normalize_reference_images(reference_image_urls) or [])
    values = values[:_MAX_REFERENCE_IMAGES]
    return [_to_input_image_part(value) for value in values]


def _build_payload(
    prompt: str,
    size: str,
    quality: str,
    input_images: Optional[List[Dict[str, str]]] = None,
) -> Dict[str, Any]:
    content: List[Dict[str, Any]] = [{"type": "input_text", "text": prompt}]
    if input_images:
        # The image_generation tool alone does not carry source pixels. They
        # must accompany the edit instruction in the same user message.
        content.extend(input_images)
    return {
        "model": _CHAT_MODEL,
        "store": False,
        "stream": True,
        "instructions": _INSTRUCTIONS,
        "input": [
            {
                "type": "message",
                "role": "user",
                "content": content,
            }
        ],
        "tools": [
            {
                "type": "image_generation",
                "model": API_MODEL,
                "size": size,
                "quality": quality,
                "output_format": "png",
                "background": "opaque",
                "partial_images": 1,
            }
        ],
        "tool_choice": {
            "type": "allowed_tools",
            "mode": "required",
            "tools": [{"type": "image_generation"}],
        },
    }


def _extract_image_b64(value: Any) -> Optional[str]:
    found: Optional[str] = None
    if isinstance(value, dict):
        if value.get("type") == "image_generation_call":
            result = value.get("result")
            if isinstance(result, str) and result:
                found = result
        partial = value.get("partial_image_b64")
        if isinstance(partial, str) and partial:
            found = partial
        for child in value.values():
            nested = _extract_image_b64(child)
            if nested:
                found = nested
    elif isinstance(value, list):
        for child in value:
            nested = _extract_image_b64(child)
            if nested:
                found = nested
    return found


def _iter_sse_json(response: Any):
    data_lines: List[str] = []
    for line in response.iter_lines():
        if isinstance(line, bytes):
            line = line.decode("utf-8", errors="replace")
        line = str(line)
        if line == "":
            raw = "\n".join(data_lines).strip()
            data_lines = []
            if raw and raw != "[DONE]":
                try:
                    yield json.loads(raw)
                except ValueError:
                    pass
            continue
        if line.startswith("data:"):
            data_lines.append(line[len("data:") :].lstrip())


def _collect_image_b64(base_url: str, api_key: str, payload: Dict[str, Any]) -> Optional[str]:
    import httpx

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
    }
    timeout = httpx.Timeout(300.0, connect=30.0, read=300.0, write=30.0, pool=30.0)
    url = base_url.rstrip("/") + "/responses"

    image_b64: Optional[str] = None
    with httpx.Client(timeout=timeout, headers=headers) as http:
        with http.stream("POST", url, json=payload) as response:
            try:
                response.raise_for_status()
            except httpx.HTTPStatusError as exc:
                exc.response.read()
                raise RuntimeError(
                    f"New API returned HTTP {exc.response.status_code}: {exc.response.text[:500]}"
                ) from exc
            for event in _iter_sse_json(response):
                found = _extract_image_b64(event)
                if found:
                    image_b64 = found
    return image_b64


class NewApiCodexImageGenProvider(ImageGenProvider):
    """gpt-image-2 via the Codex Responses tool, proxied by New API."""

    @property
    def name(self) -> str:
        return "newapi-codex"

    @property
    def display_name(self) -> str:
        return "OpenAI gpt-image-2 (New API gateway)"

    def is_available(self) -> bool:
        if not (_get_setting("NEWAPI_API_KEY") and _get_setting("NEWAPI_BASE_URL")):
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
            "name": "OpenAI gpt-image-2 (New API gateway)",
            "tag": "gpt-image-2 via New API — supports text and image inputs",
            "env_vars": [
                {"key": "NEWAPI_BASE_URL", "prompt": "New API base URL (…/v1)"},
                {"key": "NEWAPI_API_KEY", "prompt": "New API token"},
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

        base_url = _get_setting("NEWAPI_BASE_URL")
        api_key = _get_setting("NEWAPI_API_KEY")
        if not (base_url and api_key):
            return error_response(
                error="NEWAPI_BASE_URL / NEWAPI_API_KEY not configured",
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

        payload = _build_payload(
            prompt,
            size,
            meta["quality"],
            input_images=input_images or None,
        )

        try:
            b64 = _collect_image_b64(base_url, api_key, payload)
        except Exception as exc:
            logger.debug("New API image generation failed", exc_info=True)
            return error_response(
                error=f"Image generation via New API failed: {exc}",
                error_type="api_error",
                provider=self.name,
                model=tier_id,
                prompt=prompt,
                aspect_ratio=aspect,
            )

        if not b64:
            return error_response(
                error="Response contained no image_generation_call result",
                error_type="empty_response",
                provider=self.name,
                model=tier_id,
                prompt=prompt,
                aspect_ratio=aspect,
            )

        try:
            saved_path = save_b64_image(b64, prefix=f"newapi_codex_{tier_id}")
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
            },
        )


def register(ctx) -> None:
    ctx.register_image_gen_provider(NewApiCodexImageGenProvider())
