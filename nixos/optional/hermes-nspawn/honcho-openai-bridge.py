import json
import os
from collections.abc import AsyncIterator
from typing import Any

import litellm
from fastapi import Body, FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from litellm import stream_chunk_builder
from litellm.exceptions import OpenAIError


app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
new_api_base_url = os.environ["NEWAPI_BASE_URL"]


def dump_model(value: Any) -> dict[str, Any]:
    return value.model_dump(exclude_none=True, warnings=False)


def normalize_tool_finish_reason(response: dict[str, Any]) -> None:
    for choice in response.get("choices", []):
        message = choice.get("message", {})
        if message.get("tool_calls") and choice.get("finish_reason") == "stop":
            choice["finish_reason"] = "tool_calls"


def openai_error(exc: OpenAIError) -> JSONResponse:
    status_code = getattr(exc, "status_code", 500)
    error = {
        "message": getattr(exc, "message", str(exc)),
        "type": exc.__class__.__name__,
        "param": getattr(exc, "param", None),
        "code": getattr(exc, "code", None),
    }
    return JSONResponse(status_code=status_code, content={"error": error})


def bearer_token(request: Request) -> str | None:
    scheme, separator, token = request.headers.get("authorization", "").partition(" ")
    if separator and scheme.lower() == "bearer" and token:
        return token
    return None


async def completion_stream(
    first_chunk: Any,
    chunks: AsyncIterator[Any],
) -> AsyncIterator[str]:
    tool_call_choices: set[int] = set()

    def encode(chunk: Any) -> str:
        response = dump_model(chunk)
        for choice in response.get("choices", []):
            index = choice.get("index", 0)
            if choice.get("delta", {}).get("tool_calls"):
                tool_call_choices.add(index)
            if index in tool_call_choices and choice.get("finish_reason") == "stop":
                choice["finish_reason"] = "tool_calls"
        return f"data: {json.dumps(response, ensure_ascii=False, separators=(',', ':'))}\n\n"

    yield encode(first_chunk)
    async for chunk in chunks:
        yield encode(chunk)
    yield "data: [DONE]\n\n"


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/chat/completions", response_model=None)
async def chat_completions(
    request: Request,
    payload: dict[str, Any] = Body(...),
) -> JSONResponse | StreamingResponse:
    api_key = bearer_token(request)
    if api_key is None:
        return JSONResponse(
            status_code=401,
            headers={"WWW-Authenticate": "Bearer"},
            content={
                "error": {
                    "message": "Missing bearer token",
                    "type": "authentication_error",
                    "param": None,
                    "code": None,
                }
            },
        )

    request_payload = dict(payload)
    model = request_payload.pop("model")
    messages = request_payload.pop("messages")
    client_stream = bool(request_payload.pop("stream", False))

    try:
        chunks = await litellm.acompletion(
            model=f"openai/responses/{model}",
            messages=messages,
            api_base=new_api_base_url,
            api_key=api_key,
            stream=True,
            num_retries=0,
            **request_payload,
        )

        if client_stream:
            iterator = chunks.__aiter__()
            first_chunk = await anext(iterator)
            return StreamingResponse(
                completion_stream(first_chunk, iterator),
                media_type="text/event-stream",
            )

        collected = [chunk async for chunk in chunks]
        response = stream_chunk_builder(collected, messages=messages)
        if response is None:
            return JSONResponse(
                status_code=502,
                content={
                    "error": {
                        "message": "NewAPI returned no completion chunks",
                        "type": "upstream_error",
                        "param": None,
                        "code": None,
                    }
                },
            )
        result = dump_model(response)
        normalize_tool_finish_reason(result)
        return JSONResponse(content=result)
    except OpenAIError as exc:
        return openai_error(exc)
