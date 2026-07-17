"""OpenAI image generation backend routed through New API.

Adaptation of the bundled ``openai-codex`` image-gen plugin: same gpt-image-2
tiers and the same Codex Responses ``image_generation`` tool call, but sent to
New API (Bearer token from ``NEWAPI_API_KEY``) instead of chatgpt.com with a
ChatGPT OAuth token. The Codex channel inside New API
replays the request to the real Codex backend, so behavior matches the bundled
plugin while credentials stay centralized on the gateway.

Configuration:
    NEWAPI_BASE_URL  e.g. http://somo-minisforum.ts.gaof.net:3000/v1
    NEWAPI_API_KEY   per-VM New API token
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any, Dict, List, Optional, Tuple

from agent.image_gen_provider import (
    DEFAULT_ASPECT_RATIO,
    ImageGenProvider,
    error_response,
    resolve_aspect_ratio,
    save_b64_image,
    success_response,
)

logger = logging.getLogger(__name__)

API_MODEL = "gpt-image-2"

_MODELS: Dict[str, Dict[str, Any]] = {
    "gpt-image-2-low": {"display": "GPT Image 2 (Low)", "speed": "~15s", "strengths": "Fast iteration, lowest cost", "quality": "low"},
    "gpt-image-2-medium": {"display": "GPT Image 2 (Medium)", "speed": "~40s", "strengths": "Balanced — default", "quality": "medium"},
    "gpt-image-2-high": {"display": "GPT Image 2 (High)", "speed": "~2min", "strengths": "Highest fidelity, strongest prompt adherence", "quality": "high"},
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


def _build_payload(prompt: str, size: str, quality: str) -> Dict[str, Any]:
    return {
        "model": _CHAT_MODEL,
        "store": False,
        "stream": True,
        "instructions": _INSTRUCTIONS,
        "input": [{
            "type": "message",
            "role": "user",
            "content": [{"type": "input_text", "text": prompt}],
        }],
        "tools": [{
            "type": "image_generation",
            "model": API_MODEL,
            "size": size,
            "quality": quality,
            "output_format": "png",
            "background": "opaque",
            "partial_images": 1,
        }],
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
            data_lines.append(line[len("data:"):].lstrip())


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
            {"id": mid, "display": m["display"], "speed": m["speed"], "strengths": m["strengths"], "price": "varies"}
            for mid, m in _MODELS.items()
        ]

    def default_model(self) -> Optional[str]:
        return DEFAULT_MODEL

    def get_setup_schema(self) -> Dict[str, Any]:
        return {
            "name": "OpenAI gpt-image-2 (New API gateway)",
            "tag": "gpt-image-2 via New API — uses NEWAPI_BASE_URL / NEWAPI_API_KEY",
            "env_vars": [
                {"key": "NEWAPI_BASE_URL", "prompt": "New API base URL (…/v1)"},
                {"key": "NEWAPI_API_KEY", "prompt": "New API token"},
            ],
        }

    def capabilities(self) -> Dict[str, Any]:
        # Text-to-image only: reference-image passthrough is untested through
        # the gateway, so don't advertise it in the tool schema.
        return {"modalities": ["text"], "max_reference_images": 0}

    def generate(
        self,
        prompt: str,
        aspect_ratio: str = DEFAULT_ASPECT_RATIO,
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
        payload = _build_payload(prompt, size, meta["quality"])

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
            modality="text",
            extra={"size": size, "quality": meta["quality"]},
        )


def register(ctx) -> None:
    ctx.register_image_gen_provider(NewApiCodexImageGenProvider())
