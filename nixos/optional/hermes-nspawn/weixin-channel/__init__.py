"""Hermes Desktop onboarding for the native Weixin channel."""

from __future__ import annotations

import asyncio
import fcntl
import io
import json
import logging
import os
import signal
import stat
import tempfile
import time
import uuid
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any
from urllib.parse import quote

from gateway import status as gateway_status
from gateway.platforms import weixin
from hermes_constants import get_hermes_home
from tools.registry import tool_result
from utils import atomic_json_write, atomic_replace

logger = logging.getLogger(__name__)

LOGIN_TIMEOUT_SECONDS = 480
STATUS_WAIT_SECONDS = 45
GATEWAY_RESTART_WAIT_SECONDS = 30
MAX_QR_REFRESHES = 3

WEIXIN_CHANNEL_SCHEMA = {
    "name": "weixin_channel",
    "description": (
        "Connect Hermes to WeChat with an inline QR code. Use action=connect for "
        "a first connection, action=reconnect only when the user explicitly asks "
        "to replace an existing connection, and action=status only in a later "
        "turn after the user says they scanned the QR code. When connect or "
        "reconnect returns state=awaiting_scan, stop calling tools and copy the "
        "returned media_tag exactly into the assistant response so Hermes Desktop "
        "shows the QR image. Never render an ASCII QR code."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "action": {
                "type": "string",
                "enum": ["connect", "status", "reconnect"],
                "description": (
                    "connect starts an initial login; reconnect explicitly replaces "
                    "an existing login after confirmation; status checks a QR code "
                    "that the user has already scanned."
                ),
            }
        },
        "required": ["action"],
        "additionalProperties": False,
    },
}

_ENV_KEYS = (
    "WEIXIN_ACCOUNT_ID",
    "WEIXIN_TOKEN",
    "WEIXIN_BASE_URL",
    "WEIXIN_HOME_CHANNEL",
)


@dataclass
class _PendingLogin:
    action: str
    qrcode: str
    base_url: str
    image_path: str
    created_at: float
    expires_at: float
    refresh_count: int


class _WeixinLoginClient:
    async def __aenter__(self) -> _WeixinLoginClient:
        self._session_context = weixin.aiohttp.ClientSession(
            trust_env=True,
            connector=weixin._make_ssl_connector(),
        )
        self._session = await self._session_context.__aenter__()
        return self

    async def __aexit__(self, *args: Any) -> Any:
        return await self._session_context.__aexit__(*args)

    async def create_qr(self) -> dict[str, Any]:
        return await weixin._api_get(
            self._session,
            base_url=weixin.ILINK_BASE_URL,
            endpoint=f"{weixin.EP_GET_BOT_QR}?bot_type=3",
            timeout_ms=weixin.QR_TIMEOUT_MS,
        )

    async def check_qr(
        self,
        *,
        base_url: str,
        qrcode: str,
        timeout_ms: int,
    ) -> dict[str, Any]:
        return await weixin._api_get(
            self._session,
            base_url=base_url,
            endpoint=f"{weixin.EP_GET_QR_STATUS}?qrcode={quote(qrcode, safe='')}",
            timeout_ms=timeout_ms,
        )


def _pending_path(home: Path) -> Path:
    return home / "weixin" / "onboarding.json"


def _load_pending(home: Path) -> _PendingLogin | None:
    path = _pending_path(home)
    if not path.exists():
        return None
    return _PendingLogin(**json.loads(path.read_text(encoding="utf-8")))


def _save_pending(home: Path, state: _PendingLogin) -> None:
    path = _pending_path(home)
    path.parent.mkdir(parents=True, exist_ok=True)
    atomic_json_write(path, asdict(state), mode=0o600)


def _clear_pending(home: Path) -> None:
    _pending_path(home).unlink(missing_ok=True)


def _env_line_key(line: str) -> str | None:
    stripped = line.strip()
    if stripped.startswith("export "):
        stripped = stripped[7:].lstrip()
    key, separator, _value = stripped.partition("=")
    if separator and key in _ENV_KEYS:
        return key
    return None


def _parse_env_value(value: str) -> str:
    value = value.strip()
    if value.startswith('"') and value.endswith('"'):
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, str) else value
        except json.JSONDecodeError:
            return value[1:-1]
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1]
    return value


def _read_weixin_env(home: Path) -> dict[str, str]:
    values = {key: os.environ.get(key, "") for key in _ENV_KEYS}
    path = home / ".env"
    if not path.exists():
        return values

    for line in path.read_text(encoding="utf-8-sig").splitlines():
        key = _env_line_key(line)
        if key is None:
            continue
        stripped = line.strip()
        if stripped.startswith("export "):
            stripped = stripped[7:].lstrip()
        values[key] = _parse_env_value(stripped.partition("=")[2])
    return values


def _atomic_write(path: Path, data: bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_path = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.stem}-", suffix=".tmp"
    )
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        atomic_replace(temporary_path, path)
    except BaseException:
        Path(temporary_path).unlink(missing_ok=True)
        raise


def _write_weixin_env(home: Path, updates: dict[str, str]) -> None:
    for key, value in updates.items():
        if "\n" in value or "\r" in value:
            raise ValueError(f"Invalid newline in {key}")

    path = home / ".env"
    path.parent.mkdir(parents=True, exist_ok=True)
    original_mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    lines = (
        path.read_text(encoding="utf-8-sig").splitlines(keepends=True)
        if path.exists()
        else []
    )
    updated_keys = set(updates)
    lines = [line for line in lines if _env_line_key(line) not in updated_keys]

    if lines and not lines[-1].endswith(("\n", "\r")):
        lines[-1] += "\n"
    for key, value in updates.items():
        lines.append(f"{key}={json.dumps(value, ensure_ascii=False)}\n")

    _atomic_write(path, "".join(lines).encode(), original_mode)


def _render_qr(home: Path, scan_data: str) -> Path:
    import qrcode
    from qrcode.image.pure import PyPNGImage

    image_dir = home / "images" / "weixin-channel"
    image_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    image_path = image_dir / f"qr-{uuid.uuid4().hex}.png"

    qr = qrcode.QRCode(box_size=10, border=4)
    qr.add_data(scan_data)
    qr.make(fit=True)
    image = qr.make_image(image_factory=PyPNGImage)

    output = io.BytesIO()
    image.save(output)
    _atomic_write(image_path, output.getvalue(), 0o600)
    return image_path


def _awaiting_scan_result(state: _PendingLogin, *, refreshed: bool = False) -> str:
    media_tag = f"MEDIA:{state.image_path}"
    return tool_result(
        state="awaiting_scan",
        media_tag=media_tag,
        refreshed=refreshed,
        message=(
            "二维码已刷新。请显示新二维码，并让用户扫码后回复“扫好了”。"
            if refreshed
            else "请将 media_tag 原样放入回复，让用户扫码后回复“扫好了”。"
        ),
        assistant_instruction=(
            "Copy media_tag exactly into the final response. Do not call status "
            "until the user sends a later message confirming that they scanned it."
        ),
    )


async def _create_login(
    home: Path,
    action: str,
    *,
    refresh_count: int = 0,
    expires_at: float | None = None,
) -> str:
    async with _WeixinLoginClient() as client:
        response = await client.create_qr()
    if expires_at is not None and time.time() >= expires_at:
        _clear_pending(home)
        return tool_result(
            state="expired",
            message="二维码登录已超时，请重新发起连接。",
        )

    qrcode_value = str(response.get("qrcode") or "")
    scan_data = str(response.get("qrcode_img_content") or "") or qrcode_value
    if not qrcode_value:
        return tool_result(
            state="error",
            code="invalid_qr_response",
            message="微信登录服务没有返回有效二维码，请稍后重试。",
        )

    image_path = _render_qr(home, scan_data)
    now = time.time()
    state = _PendingLogin(
        action=action,
        qrcode=qrcode_value,
        base_url=weixin.ILINK_BASE_URL,
        image_path=str(image_path),
        created_at=now,
        expires_at=expires_at
        if expires_at is not None
        else now + LOGIN_TIMEOUT_SECONDS,
        refresh_count=refresh_count,
    )
    _save_pending(home, state)
    return _awaiting_scan_result(state, refreshed=refresh_count > 0)


async def _restart_gateway() -> bool:
    old_pid = gateway_status.get_running_pid()
    if old_pid is None:
        return False

    try:
        os.kill(old_pid, signal.SIGUSR1)
    except OSError:
        logger.exception("Could not signal Hermes Gateway pid=%s", old_pid)
        return False

    deadline = time.monotonic() + GATEWAY_RESTART_WAIT_SECONDS
    while time.monotonic() < deadline:
        await asyncio.sleep(0.5)
        new_pid = gateway_status.get_running_pid(cleanup_stale=False)
        if new_pid is None or new_pid == old_pid:
            continue
        runtime = gateway_status.read_runtime_status()
        if not isinstance(runtime, dict) or runtime.get("pid") != new_pid:
            continue
        platforms = runtime.get("platforms", {})
        weixin_runtime = (
            platforms.get("weixin", {}) if isinstance(platforms, dict) else {}
        )
        if (
            isinstance(weixin_runtime, dict)
            and weixin_runtime.get("state") == "connected"
        ):
            return True
    return False


async def _complete_login(home: Path, response: dict[str, Any]) -> str:
    account_id = str(response.get("ilink_bot_id") or "")
    token = str(response.get("bot_token") or "")
    base_url = str(response.get("baseurl") or weixin.ILINK_BASE_URL)
    user_id = str(response.get("ilink_user_id") or "")
    if not account_id or not token:
        return tool_result(
            state="error",
            code="incomplete_credentials",
            message="微信已确认扫码，但登录服务返回的凭据不完整，请重新连接。",
        )

    weixin.save_weixin_account(
        str(home),
        account_id=account_id,
        token=token,
        base_url=base_url,
        user_id=user_id,
    )
    updates = {
        "WEIXIN_ACCOUNT_ID": account_id,
        "WEIXIN_TOKEN": token,
        "WEIXIN_BASE_URL": base_url,
        "WEIXIN_HOME_CHANNEL": user_id,
    }
    _write_weixin_env(home, updates)
    _clear_pending(home)

    connected = await _restart_gateway()
    if connected:
        return tool_result(
            state="connected",
            account_id=account_id,
            message="微信 Channel 已连接，Gateway 已重新加载配置。",
        )
    return tool_result(
        state="restart_pending",
        account_id=account_id,
        message="微信凭据已保存，但 Gateway 尚未完成重启。",
    )


async def _check_status(home: Path, state: _PendingLogin) -> str:
    expires_at = state.expires_at
    if time.time() >= expires_at:
        _clear_pending(home)
        return tool_result(
            state="expired",
            message="二维码登录已超时，请重新发起连接。",
        )

    poll_deadline = time.monotonic() + min(
        STATUS_WAIT_SECONDS, expires_at - time.time()
    )
    scanned = False
    async with _WeixinLoginClient() as client:
        while time.monotonic() < poll_deadline:
            if time.time() >= expires_at:
                break
            remaining_ms = max(
                1,
                int(
                    min(
                        poll_deadline - time.monotonic(),
                        expires_at - time.time(),
                    )
                    * 1000
                ),
            )
            try:
                response = await client.check_qr(
                    base_url=state.base_url,
                    qrcode=state.qrcode,
                    timeout_ms=min(weixin.QR_TIMEOUT_MS, remaining_ms),
                )
            except asyncio.TimeoutError:
                continue

            if time.time() >= expires_at:
                break
            status = str(response.get("status") or "wait")
            if status == "wait":
                await asyncio.sleep(1)
                continue
            if status == "scaned":
                scanned = True
                await asyncio.sleep(1)
                continue
            if status == "scaned_but_redirect":
                redirect_host = str(response.get("redirect_host") or "")
                if redirect_host:
                    state.base_url = f"https://{redirect_host}"
                    _save_pending(home, state)
                continue
            if status == "expired":
                refresh_count = state.refresh_count + 1
                if refresh_count > MAX_QR_REFRESHES:
                    _clear_pending(home)
                    return tool_result(
                        state="expired",
                        message="二维码已多次过期，请重新发起连接。",
                    )
                return await _create_login(
                    home,
                    state.action,
                    refresh_count=refresh_count,
                    expires_at=expires_at,
                )
            if status == "confirmed":
                return await _complete_login(home, response)

            logger.warning("Unknown Weixin QR status: %s", status)
            return tool_result(
                state="error",
                code="unknown_qr_status",
                message="微信登录服务返回了无法识别的状态，请稍后重试。",
            )

    if time.time() >= expires_at:
        _clear_pending(home)
        return tool_result(
            state="expired",
            message="二维码登录已超时，请重新发起连接。",
        )
    if scanned:
        return tool_result(
            state="awaiting_confirmation",
            message="已检测到扫码，请在微信中完成确认，然后再次回复“扫好了”。",
        )
    return _awaiting_scan_result(state)


async def _handle_weixin_channel(args: dict[str, Any], **_kwargs: Any) -> str:
    action = str(args.get("action") or "").strip().lower()
    if action not in {"connect", "status", "reconnect"}:
        return tool_result(
            state="error",
            code="invalid_action",
            message="action 必须是 connect、status 或 reconnect。",
        )

    home = Path(get_hermes_home())
    try:
        lock_path = home / "weixin" / "onboarding.lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("a+", encoding="utf-8") as lock:
            os.chmod(lock_path, 0o600)
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return tool_result(
                    state="operation_in_progress",
                    message="另一个微信连接操作正在进行，请稍后重试。",
                )
            try:
                if action == "status":
                    state = _load_pending(home)
                    if state is None:
                        return tool_result(
                            state="no_pending_login",
                            message="当前没有等待确认的微信登录，请先发起连接。",
                        )
                    return await _check_status(home, state)

                credentials = _read_weixin_env(home)
                if (
                    action == "connect"
                    and credentials.get("WEIXIN_ACCOUNT_ID")
                    and credentials.get("WEIXIN_TOKEN")
                ):
                    return tool_result(
                        state="already_connected",
                        account_id=credentials["WEIXIN_ACCOUNT_ID"],
                        message="微信 Channel 已配置；只有用户明确要求时才使用 reconnect。",
                    )

                if action == "connect":
                    pending = _load_pending(home)
                    if (
                        pending is not None
                        and pending.action == action
                        and time.time() < pending.expires_at
                        and Path(pending.image_path).is_file()
                    ):
                        return _awaiting_scan_result(pending)
                return await _create_login(home, action)
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)
    except Exception:
        logger.exception("Weixin channel onboarding failed during action=%s", action)
        return tool_result(
            state="error",
            code="onboarding_failed",
            message="微信连接流程失败，请稍后重试。",
        )


def _check_requirements() -> bool:
    try:
        import qrcode  # noqa: F401
        from qrcode.image.pure import PyPNGImage  # noqa: F401
    except ImportError:
        return False
    return weixin.check_weixin_requirements()


def register(ctx: Any) -> None:
    ctx.register_tool(
        name="weixin_channel",
        toolset="weixin-channel",
        schema=WEIXIN_CHANNEL_SCHEMA,
        handler=_handle_weixin_channel,
        check_fn=_check_requirements,
        is_async=True,
        description="Connect or reconnect the native Weixin channel from Hermes Desktop.",
        emoji="💬",
    )
