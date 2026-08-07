from __future__ import annotations

import asyncio
import importlib.util
import json
import stat
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, Mock, patch


def _load_plugin():
    gateway = types.ModuleType("gateway")
    gateway.__path__ = []
    gateway_status = types.ModuleType("gateway.status")
    gateway_status.get_running_pid = Mock(return_value=None)
    gateway_status.read_runtime_status = Mock(return_value={})
    gateway.status = gateway_status

    platforms = types.ModuleType("gateway.platforms")
    platforms.__path__ = []
    weixin = types.ModuleType("gateway.platforms.weixin")
    weixin.ILINK_BASE_URL = "https://ilink.example"
    weixin.EP_GET_BOT_QR = "get-qr"
    weixin.EP_GET_QR_STATUS = "get-status"
    weixin.QR_TIMEOUT_MS = 35_000
    weixin.check_weixin_requirements = Mock(return_value=True)
    weixin.save_weixin_account = Mock()
    weixin._make_ssl_connector = Mock(return_value=None)
    weixin._api_get = AsyncMock()
    weixin.aiohttp = types.SimpleNamespace(ClientSession=Mock())
    platforms.weixin = weixin
    gateway.platforms = platforms

    hermes_constants = types.ModuleType("hermes_constants")
    hermes_constants.get_hermes_home = Mock(return_value="/tmp/hermes")

    registry = types.ModuleType("tools.registry")

    def tool_result(data=None, **kwargs):
        return json.dumps(data if data is not None else kwargs, ensure_ascii=False)

    registry.tool_result = tool_result
    tools = types.ModuleType("tools")
    tools.__path__ = []
    tools.registry = registry

    utils = types.ModuleType("utils")

    def atomic_json_write(path, value, mode=None):
        path = Path(path)
        path.write_text(json.dumps(value), encoding="utf-8")
        if mode is not None:
            path.chmod(mode)

    utils.atomic_json_write = atomic_json_write

    def atomic_replace(temporary_path, path):
        Path(temporary_path).replace(path)
        return str(path)

    utils.atomic_replace = atomic_replace

    modules = {
        "gateway": gateway,
        "gateway.status": gateway_status,
        "gateway.platforms": platforms,
        "gateway.platforms.weixin": weixin,
        "hermes_constants": hermes_constants,
        "tools": tools,
        "tools.registry": registry,
        "utils": utils,
    }
    sys.modules.update(modules)

    path = Path(__file__).parents[1] / "__init__.py"
    spec = importlib.util.spec_from_file_location("weixin_channel_plugin", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


plugin = _load_plugin()


class FakeClientSession:
    async def __aenter__(self):
        return self

    async def __aexit__(self, _exc_type, _exc, _traceback):
        return False


class WeixinChannelPluginTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.home = Path(self.temporary_directory.name)
        self.addCleanup(self.temporary_directory.cleanup)
        environment = patch.dict(
            plugin.os.environ,
            {key: "" for key in plugin._ENV_KEYS},
        )
        environment.start()
        self.addCleanup(environment.stop)
        plugin.weixin.aiohttp.ClientSession.return_value = FakeClientSession()

    def test_write_env_replaces_duplicates_and_preserves_other_settings(self):
        env_path = self.home / ".env"
        env_path.write_text(
            "# existing settings\n"
            "OTHER=value\n"
            "export WEIXIN_TOKEN=old-token\n"
            "WEIXIN_TOKEN=older-token\n"
            "WEIXIN_DM_POLICY=allowlist\n",
            encoding="utf-8",
        )
        env_path.chmod(0o640)

        plugin._write_weixin_env(
            self.home,
            {
                "WEIXIN_ACCOUNT_ID": "bot-id",
                "WEIXIN_TOKEN": "new-token",
                "WEIXIN_BASE_URL": "https://base.example",
            },
        )

        content = env_path.read_text(encoding="utf-8")
        self.assertIn("# existing settings\n", content)
        self.assertIn("OTHER=value\n", content)
        self.assertIn("WEIXIN_DM_POLICY=allowlist\n", content)
        self.assertEqual(content.count("WEIXIN_TOKEN="), 1)
        self.assertIn('WEIXIN_TOKEN="new-token"\n', content)
        self.assertEqual(stat.S_IMODE(env_path.stat().st_mode), 0o640)

    def test_render_qr_writes_private_png(self):
        qrcode = types.ModuleType("qrcode")

        class QRCode:
            def __init__(self, **_kwargs):
                pass

            def add_data(self, _data):
                pass

            def make(self, *, fit):
                self.fit = fit

            def make_image(self, *, image_factory):
                self.image_factory = image_factory
                return types.SimpleNamespace(save=lambda output: output.write(b"\x89PNG\r\n\x1a\nimage"))

        qrcode.QRCode = QRCode
        image = types.ModuleType("qrcode.image")
        image.__path__ = []
        pure = types.ModuleType("qrcode.image.pure")
        pure.PyPNGImage = object

        with patch.dict(
            sys.modules,
            {
                "qrcode": qrcode,
                "qrcode.image": image,
                "qrcode.image.pure": pure,
            },
        ):
            image_path = plugin._render_qr(self.home, "weixin://scan-data")

        self.assertTrue(image_path.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"))
        self.assertEqual(stat.S_IMODE(image_path.stat().st_mode), 0o600)

    async def test_connect_creates_pending_state_and_media_tag(self):
        image_path = self.home / "images" / "weixin-channel" / "qr.png"
        image_path.parent.mkdir(parents=True)
        image_path.write_bytes(b"png")

        with (
            patch.object(plugin, "get_hermes_home", return_value=self.home),
            patch.object(
                plugin._WeixinLoginClient,
                "create_qr",
                AsyncMock(
                    return_value={
                        "qrcode": "qr-token",
                        "qrcode_img_content": "weixin://scan-data",
                    }
                ),
            ),
            patch.object(plugin, "_render_qr", return_value=image_path),
        ):
            result = json.loads(await plugin._handle_weixin_channel({"action": "connect"}))

        self.assertEqual(result["state"], "awaiting_scan")
        self.assertEqual(result["media_tag"], f"MEDIA:{image_path}")
        pending_path = self.home / "weixin" / "onboarding.json"
        pending = json.loads(pending_path.read_text(encoding="utf-8"))
        self.assertEqual(pending["qrcode"], "qr-token")
        self.assertNotIn("scan_data", pending)
        self.assertEqual(stat.S_IMODE(pending_path.stat().st_mode), 0o600)

    async def test_connect_preserves_existing_connection_but_reconnect_starts(self):
        (self.home / ".env").write_text(
            'WEIXIN_ACCOUNT_ID="current-account"\nWEIXIN_TOKEN="current-token"\n',
            encoding="utf-8",
        )
        pending_image = self.home / "pending.png"
        pending_image.write_bytes(b"png")
        plugin._save_pending(
            self.home,
            plugin._PendingLogin(
                action="reconnect",
                qrcode="pending-qr",
                base_url="https://ilink.example",
                image_path=str(pending_image),
                created_at=plugin.time.time(),
                expires_at=plugin.time.time() + 60,
                refresh_count=0,
            ),
        )

        with (
            patch.object(plugin, "get_hermes_home", return_value=self.home),
            patch.object(
                plugin,
                "_create_login",
                AsyncMock(return_value='{"state": "awaiting_scan"}'),
            ) as create_login,
        ):
            connected = json.loads(await plugin._handle_weixin_channel({"action": "connect"}))
            reconnect = json.loads(await plugin._handle_weixin_channel({"action": "reconnect"}))

        self.assertEqual(connected["state"], "already_connected")
        self.assertEqual(reconnect["state"], "awaiting_scan")
        create_login.assert_awaited_once_with(self.home, "reconnect")
        self.assertIn(
            'WEIXIN_TOKEN="current-token"',
            (self.home / ".env").read_text(encoding="utf-8"),
        )

    async def test_connect_reuses_pending_login(self):
        image_path = self.home / "pending.png"
        image_path.write_bytes(b"png")
        plugin._save_pending(
            self.home,
            plugin._PendingLogin(
                action="connect",
                qrcode="pending-qr",
                base_url="https://ilink.example",
                image_path=str(image_path),
                created_at=plugin.time.time(),
                expires_at=plugin.time.time() + 60,
                refresh_count=0,
            ),
        )

        with (
            patch.object(plugin, "get_hermes_home", return_value=self.home),
            patch.object(plugin, "_create_login", AsyncMock()) as create_login,
        ):
            result = json.loads(await plugin._handle_weixin_channel({"action": "connect"}))

        self.assertEqual(result["state"], "awaiting_scan")
        self.assertEqual(result["media_tag"], f"MEDIA:{image_path}")
        create_login.assert_not_awaited()

    async def test_concurrent_login_is_rejected(self):
        started = asyncio.Event()
        release = asyncio.Event()

        async def create_login(_home, _action):
            started.set()
            await release.wait()
            return '{"state": "awaiting_scan"}'

        with (
            patch.object(plugin, "get_hermes_home", return_value=self.home),
            patch.object(plugin, "_create_login", side_effect=create_login),
        ):
            first = asyncio.create_task(plugin._handle_weixin_channel({"action": "reconnect"}))
            await started.wait()
            second = json.loads(await plugin._handle_weixin_channel({"action": "reconnect"}))
            release.set()
            await first

        self.assertEqual(second["state"], "operation_in_progress")

    async def test_complete_login_writes_credentials_without_returning_token(self):
        (self.home / ".env").write_text(
            "OTHER=value\nWEIXIN_DM_POLICY=allowlist\n",
            encoding="utf-8",
        )
        pending_path = self.home / "weixin" / "onboarding.json"
        pending_path.parent.mkdir(parents=True)
        pending_path.write_text("{}", encoding="utf-8")
        response = {
            "ilink_bot_id": "new-account",
            "bot_token": "secret-token",
            "baseurl": "https://base.example",
            "ilink_user_id": "user-id",
        }

        with (
            patch.object(plugin.weixin, "save_weixin_account") as save_account,
            patch.object(plugin, "_restart_gateway", AsyncMock(return_value=True)),
        ):
            result_text = await plugin._complete_login(self.home, response)

        result = json.loads(result_text)
        self.assertEqual(result["state"], "connected")
        self.assertNotIn("secret-token", result_text)
        save_account.assert_called_once_with(
            str(self.home),
            account_id="new-account",
            token="secret-token",
            base_url="https://base.example",
            user_id="user-id",
        )
        env_content = (self.home / ".env").read_text(encoding="utf-8")
        self.assertIn("OTHER=value\n", env_content)
        self.assertIn("WEIXIN_DM_POLICY=allowlist\n", env_content)
        self.assertIn('WEIXIN_TOKEN="secret-token"\n', env_content)
        self.assertIn('WEIXIN_HOME_CHANNEL="user-id"\n', env_content)
        self.assertFalse(pending_path.exists())

    async def test_complete_login_clears_stale_home_channel(self):
        (self.home / ".env").write_text(
            'WEIXIN_HOME_CHANNEL="old-user"\n',
            encoding="utf-8",
        )
        response = {
            "ilink_bot_id": "new-account",
            "bot_token": "secret-token",
            "baseurl": "https://base.example",
        }

        with (
            patch.object(plugin.weixin, "save_weixin_account"),
            patch.object(plugin, "_restart_gateway", AsyncMock(return_value=True)),
        ):
            await plugin._complete_login(self.home, response)

        env_content = (self.home / ".env").read_text(encoding="utf-8")
        self.assertNotIn("old-user", env_content)
        self.assertIn('WEIXIN_HOME_CHANNEL=""\n', env_content)

    async def test_status_follows_scan_to_confirmation(self):
        state = plugin._PendingLogin(
            action="connect",
            qrcode="qr-token",
            base_url="https://ilink.example",
            image_path=str(self.home / "qr.png"),
            created_at=plugin.time.time(),
            expires_at=plugin.time.time() + 60,
            refresh_count=0,
        )

        with (
            patch.object(
                plugin.weixin,
                "_api_get",
                AsyncMock(
                    side_effect=[
                        {"status": "wait"},
                        {"status": "scaned"},
                        {"status": "confirmed"},
                    ]
                ),
            ),
            patch.object(plugin.asyncio, "sleep", AsyncMock()),
            patch.object(
                plugin,
                "_complete_login",
                AsyncMock(return_value='{"state": "connected"}'),
            ) as complete_login,
        ):
            result = json.loads(await plugin._check_status(self.home, state))

        self.assertEqual(result["state"], "connected")
        complete_login.assert_awaited_once()

    async def test_expired_status_refreshes_qr_without_changing_deadline(self):
        expires_at = plugin.time.time() + 60
        state = plugin._PendingLogin(
            action="reconnect",
            qrcode="old-qr",
            base_url="https://ilink.example",
            image_path=str(self.home / "old.png"),
            created_at=plugin.time.time(),
            expires_at=expires_at,
            refresh_count=1,
        )

        with (
            patch.object(
                plugin.weixin,
                "_api_get",
                AsyncMock(return_value={"status": "expired"}),
            ),
            patch.object(
                plugin,
                "_create_login",
                AsyncMock(return_value='{"state": "awaiting_scan"}'),
            ) as create_login,
        ):
            result = json.loads(await plugin._check_status(self.home, state))

        self.assertEqual(result["state"], "awaiting_scan")
        create_login.assert_awaited_once_with(
            self.home,
            "reconnect",
            refresh_count=2,
            expires_at=expires_at,
        )

    async def test_status_rejects_confirmation_after_deadline(self):
        clock = types.SimpleNamespace(now=0.0)
        state = plugin._PendingLogin(
            action="connect",
            qrcode="qr-token",
            base_url="https://ilink.example",
            image_path=str(self.home / "qr.png"),
            created_at=0.0,
            expires_at=1.0,
            refresh_count=0,
        )
        plugin._save_pending(self.home, state)

        async def confirm_after_deadline(*_args, **_kwargs):
            clock.now = 2.0
            return {"status": "confirmed"}

        with (
            patch.object(plugin.time, "time", side_effect=lambda: clock.now),
            patch.object(plugin.weixin, "_api_get", side_effect=confirm_after_deadline),
            patch.object(plugin, "_complete_login", AsyncMock()) as complete_login,
        ):
            result = json.loads(await plugin._check_status(self.home, state))

        self.assertEqual(result["state"], "expired")
        complete_login.assert_not_awaited()
        self.assertFalse((self.home / "weixin" / "onboarding.json").exists())

    async def test_qr_refresh_rejects_response_after_deadline(self):
        plugin._save_pending(
            self.home,
            plugin._PendingLogin(
                action="connect",
                qrcode="old-qr",
                base_url="https://ilink.example",
                image_path=str(self.home / "old.png"),
                created_at=0.0,
                expires_at=1.0,
                refresh_count=0,
            ),
        )
        clock = types.SimpleNamespace(now=0.0)

        async def fetch_after_deadline():
            clock.now = 2.0
            return {
                "qrcode": "new-qr",
                "qrcode_img_content": "weixin://new-qr",
            }

        with (
            patch.object(plugin.time, "time", side_effect=lambda: clock.now),
            patch.object(
                plugin._WeixinLoginClient,
                "create_qr",
                AsyncMock(side_effect=fetch_after_deadline),
            ),
            patch.object(plugin, "_render_qr") as render_qr,
        ):
            result = json.loads(
                await plugin._create_login(
                    self.home,
                    "connect",
                    refresh_count=1,
                    expires_at=1.0,
                )
            )

        self.assertEqual(result["state"], "expired")
        render_qr.assert_not_called()
        self.assertFalse((self.home / "weixin" / "onboarding.json").exists())

    async def test_status_stops_after_third_qr_refresh(self):
        state = plugin._PendingLogin(
            action="connect",
            qrcode="qr-token",
            base_url="https://ilink.example",
            image_path=str(self.home / "qr.png"),
            created_at=plugin.time.time(),
            expires_at=plugin.time.time() + 60,
            refresh_count=3,
        )
        plugin._save_pending(self.home, state)

        with (
            patch.object(
                plugin.weixin,
                "_api_get",
                AsyncMock(return_value={"status": "expired"}),
            ),
            patch.object(plugin, "_create_login", AsyncMock()) as create_login,
        ):
            result = json.loads(await plugin._check_status(self.home, state))

        self.assertEqual(result["state"], "expired")
        create_login.assert_not_awaited()
        self.assertFalse((self.home / "weixin" / "onboarding.json").exists())

    async def test_restart_signals_verified_pid_and_waits_for_connected_new_pid(self):
        get_running_pid = Mock(side_effect=[101, 202, 202])
        read_runtime_status = Mock(
            side_effect=[
                {"pid": 101, "platforms": {"weixin": {"state": "connected"}}},
                {"pid": 202, "platforms": {"weixin": {"state": "connected"}}},
            ]
        )

        with (
            patch.object(plugin.gateway_status, "get_running_pid", get_running_pid),
            patch.object(
                plugin.gateway_status,
                "read_runtime_status",
                read_runtime_status,
            ),
            patch.object(plugin.os, "kill") as kill,
            patch.object(plugin.asyncio, "sleep", AsyncMock()),
        ):
            connected = await plugin._restart_gateway()

        self.assertTrue(connected)
        kill.assert_called_once_with(101, plugin.signal.SIGUSR1)
        get_running_pid.assert_any_call(cleanup_stale=False)
        self.assertEqual(read_runtime_status.call_count, 2)

    def test_register_exposes_async_tool_in_desktop_toolset(self):
        context = Mock()
        plugin.register(context)
        context.register_tool.assert_called_once()
        registered = context.register_tool.call_args.kwargs
        self.assertEqual(registered["name"], "weixin_channel")
        self.assertEqual(registered["toolset"], "weixin-channel")
        self.assertTrue(registered["is_async"])


if __name__ == "__main__":
    unittest.main()
