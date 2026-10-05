{
  inputs,
  pkgs,
}: let
  upstream = pkgs.lib.importTOML "${inputs.osxphotos-src}/pyproject.toml";
  workspace = inputs.uv2nix.lib.workspace.loadWorkspace {workspaceRoot = inputs.osxphotos-src;};
  pythonSet =
    (pkgs.callPackage inputs.pyproject-nix.build.packages {
      python = pkgs.python313;
    }).overrideScope (pkgs.lib.composeManyExtensions [
      (workspace.mkPyprojectOverlay {sourcePreference = "wheel";})
      (final: prev: {
        # uv.lock omits the dynamically computed project version.
        osxphotos = prev.osxphotos.overrideAttrs {
          version = upstream.tool.bumpversion.current_version;
          patches = [./osxphotos-performance.patch];
          # Keep upstream's multi-gigabyte test libraries out of the build source.
          src = pkgs.lib.cleanSourceWith {
            src = inputs.osxphotos-src;
            filter = path: _: path != "${inputs.osxphotos-src}/tests";
          };
        };
        # The locked bitmath release has no wheel or declared build backend.
        bitmath = prev.bitmath.overrideAttrs (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem {setuptools = [];};
        });
      })
    ]);
in
  (pythonSet.mkVirtualEnv "osxphotos-${pythonSet.osxphotos.version}" workspace.deps.default).overrideAttrs {
    # Darwin wrapper UUIDs otherwise depend on Nix's temporary output path.
    env.NIX_LDFLAGS = "-no_uuid";
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      export XDG_CONFIG_HOME="$TMPDIR/osxphotos-config"
      export XDG_DATA_HOME="$TMPDIR/osxphotos-data"
      "$out/bin/python" -m pip check
      "$out/bin/python" -c 'import osxphotos, objc, Photos, Foundation, photoscript, cgmetadata, makelive, osxmetadata; assert osxphotos.__version__ == "${pythonSet.osxphotos.version}"'
      "$out/bin/osxphotos" --version
      runHook postInstallCheck
    '';
    meta = {
      description = "Pinned Apple Photos export runtime for the Intel Hackintosh";
      homepage = "https://github.com/RhetTbull/osxphotos";
      license = pkgs.lib.licenses.mit;
      sourceProvenance = with pkgs.lib.sourceTypes; [fromSource binaryNativeCode];
      platforms = ["x86_64-darwin"];
      mainProgram = "osxphotos";
    };
  }
