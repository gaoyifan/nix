# warp-oss binary used by OpenWarp's SSH extension as the remote-server proxy.
#
# OpenWarp normally auto-installs this binary by curl'ing a script from
# `server_root_url`, but the OpenWarp build pins that URL to the unreachable
# sentinel http://192.0.2.0:9 to disable cloud calls — so the installer
# always 60s-timeouts. OpenWarp's installer-skip check is just:
#     test -x ~/.warp-dev/remote-server/warp-oss
# which we satisfy by symlinking this derivation's binary into place via
# Home Manager (see ../home-manager/default.nix).
#
# We intentionally do NOT build from source via rustPlatform.buildRustPackage:
# the OpenWarp workspace is the full Warp terminal app (massive Rust workspace
# with ~20 git-pinned crates and heavy GUI deps such as wgpu/winit/cocoa/
# x11/wayland/vulkan), and `warp-oss` is the same monolithic binary whether
# it's launched as a GUI or with the `remote-server-proxy` subcommand. Building
# it from source under Nix would mean a multi-GB / multi-hour closure with
# many manual outputHashes — way out of proportion for a binary that only
# needs to exist on disk so SSH callers can `exec warp-oss remote-server-proxy
# --identity-key ...`. We instead repackage the official OpenWarp release
# artifacts (`.deb` on Linux, `.dmg` on Darwin) which are themselves built
# from the zerx-lab/warp v${version} tag.
#
# Platform support is gated to the platforms upstream actually publishes
# pre-built `warp-oss` binaries for. aarch64-linux is intentionally skipped:
# zerx-lab/warp doesn't ship an aarch64-linux artifact at v2026.05.08.preview,
# and rebuilding the full GUI workspace just to land warp-oss on an ARM Linux
# box is not worth the closure cost. See `meta.platforms` below.
{pkgs}: let
  inherit (pkgs) lib stdenv fetchurl;

  version = "2026.05.08.preview";

  sources = {
    x86_64-linux = {
      url = "https://github.com/zerx-lab/warp/releases/download/v${version}/warp-terminal-oss_${version}_amd64.deb";
      hash = "sha256-7FSiKewjhS2e41WNzJF8DHA0C6U4Kc+9nWMSyYmn4P0=";
    };
    aarch64-darwin = {
      url = "https://github.com/zerx-lab/warp/releases/download/v${version}/OpenWarp-arm64.dmg";
      hash = "sha256-B4HaMNOmVyVWkLbHMP7Mi82wDNt/jcY6xR6Ccep61Zo=";
    };
  };

  inherit (stdenv.hostPlatform) system;
  isSupported = sources ? ${system};
in
  stdenv.mkDerivation {
    pname = "openwarp-ssh-extension";
    inherit version;

    # Defer the unsupported-platform error to derivation realisation so flake
    # evaluation (e.g. `nix flake check --all-systems`) still succeeds; only
    # an actual `nix build` on aarch64-linux trips it.
    src =
      if isSupported
      then fetchurl sources.${system}
      else throw "openwarp-ssh-extension: no upstream warp-oss artifact for ${system}; zerx-lab/warp v${version} only publishes x86_64-linux (.deb) and aarch64-darwin (.dmg).";

    sourceRoot = ".";

    nativeBuildInputs =
      lib.optionals stdenv.hostPlatform.isLinux [
        pkgs.dpkg
        pkgs.autoPatchelfHook
      ]
      ++ lib.optionals stdenv.hostPlatform.isDarwin [
        # APFS-formatted .dmg — undmg only handles HFS+, so use 7zz.
        pkgs._7zz
      ];

    # Only declare libs the binary actually links against directly (NEEDED).
    # Heavier GUI libs (X11/Wayland/Vulkan/freetype/fontconfig) are dlopen'd
    # lazily by the GUI code path and are not reached when warp-oss runs as
    # `remote-server-proxy`, so we don't pull them into the closure.
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      stdenv.cc.cc.lib
      pkgs.zlib
      pkgs.alsa-lib
      pkgs.dbus.lib
      pkgs.xz
    ];

    dontPatch = true;
    dontConfigure = true;
    dontBuild = true;

    unpackPhase =
      if stdenv.hostPlatform.isLinux
      then ''
        runHook preUnpack
        dpkg -x "$src" .
        runHook postUnpack
      ''
      else ''
        runHook preUnpack
        7zz x -bso0 -bsp0 -y "$src" >/dev/null
        runHook postUnpack
      '';

    installPhase =
      if stdenv.hostPlatform.isLinux
      then ''
        runHook preInstall
        install -Dm755 opt/warpdotdev/warp-terminal-oss/warp-oss "$out/bin/warp-oss"
        runHook postInstall
      ''
      else ''
        runHook preInstall
        binary=$(find . -path '*/OpenWarp.app/Contents/MacOS/warp-oss' -type f -print -quit)
        if [ -z "$binary" ]; then
          echo "openwarp-ssh-extension: could not locate warp-oss inside the DMG" >&2
          exit 1
        fi
        install -Dm755 "$binary" "$out/bin/warp-oss"
        runHook postInstall
      '';

    meta = with lib; {
      description = "OpenWarp warp-oss CLI used by the SSH extension's remote-server proxy";
      longDescription = ''
        Repackaged warp-oss binary from the official OpenWarp release at
        zerx-lab/warp v${version}. Used by Home Manager to satisfy
        OpenWarp's `test -x ~/.warp-dev/remote-server/warp-oss` check so
        the SSH extension skips its broken auto-installer.
      '';
      homepage = "https://github.com/zerx-lab/warp";
      changelog = "https://github.com/zerx-lab/warp/releases/tag/v${version}";
      license = with licenses; [agpl3Only mit];
      mainProgram = "warp-oss";
      # aarch64-linux intentionally excluded: upstream does not publish an
      # aarch64-linux artifact at v${version}, and building from source is
      # not worth the closure cost for a remote-server proxy binary.
      platforms = ["x86_64-linux" "aarch64-darwin"];
      sourceProvenance = [sourceTypes.binaryNativeCode];
    };
  }
