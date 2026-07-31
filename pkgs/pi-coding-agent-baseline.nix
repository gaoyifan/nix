{pkgs}: let
  inherit (pkgs) lib;

  version = "0.83.0";
  bunBaseline =
    pkgs.runCommand "bun-baseline-compiler-1.3.14" {
      src = pkgs.fetchurl {
        url = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.14/bun-linux-x64-baseline.zip";
        hash = "sha256-oGOQiuCLeFLKEJObvcbO7T3avOj7lALc6D1l1zs25sc=";
      };
      nativeBuildInputs = [pkgs.python3Minimal pkgs.unzip];
      dontPatchELF = true;
      dontStrip = true;
    } ''
      install -dm755 "$out/bin"
      unzip -j "$src" 'bun-linux-x64-baseline/bun' -d "$out/bin"

      # Preserve Bun's program-header layout because --compile copies it.
      python3 - "$out/bin/bun" "${pkgs.stdenv.cc.bintools.dynamicLinker}" <<'PY'
      import struct
      import sys

      binary, interpreter = sys.argv[1:]
      with open(binary, "r+b") as elf:
          header = elf.read(64)
          phoff = struct.unpack_from("<Q", header, 32)[0]
          phentsize, phnum = struct.unpack_from("<HH", header, 54)
          for offset in range(phoff, phoff + phentsize * phnum, phentsize):
              elf.seek(offset)
              phdr = bytearray(elf.read(phentsize))
              if struct.unpack_from("<I", phdr)[0] == 3:
                  elf.seek(0, 2)
                  interp = interpreter.encode() + b"\0"
                  struct.pack_into("<Q", phdr, 8, elf.tell())
                  struct.pack_into("<Q", phdr, 32, len(interp))
                  struct.pack_into("<Q", phdr, 40, len(interp))
                  elf.write(interp)
                  elf.seek(offset)
                  elf.write(phdr)
                  break
      PY
      chmod 755 "$out/bin/bun"
    '';
in
  pkgs.buildNpmPackage {
    pname = "pi-coding-agent-baseline";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-${version}-source.tar.gz";
      hash = "sha256-8iW4fsO0gl3VuU6SKoYpVYrdyjGhtNLCBq5Zio4mksA=";
    };
    sourceRoot = "pi-${version}";
    npmDepsHash = "sha256-AbSfP1Ion8bN309NUBQb1QSn2cIIUjNONmZgls9vnYE=";
    npmBuildScript = "build:offline";
    npmRebuildFlags = ["--ignore-scripts"];
    nodejs = pkgs.nodejs_22;

    postPatch = ''
      substituteInPlace scripts/build-binaries.sh \
        --replace-fail '--target=bun-$platform' '--target=bun-$platform-baseline'
    '';

    nativeBuildInputs = [bunBaseline pkgs.autoPatchelfHook pkgs.makeWrapper];
    buildInputs = [pkgs.stdenv.cc.cc.lib];
    dontAutoPatchelf = true;
    dontPatchELF = true;
    dontStrip = true;

    installPhase = ''
      bash ./scripts/build-binaries.sh \
        --skip-install \
        --skip-deps \
        --skip-build \
        --platform linux-x64 \
        --out "$PWD/binaries"

      patchelf \
        --set-interpreter "${pkgs.stdenv.cc.bintools.dynamicLinker}" \
        binaries/linux-x64/pi

      install -dm755 "$out/bin" "$out/lib/pi-coding-agent"
      cp -R binaries/linux-x64/. "$out/lib/pi-coding-agent/"
      chmod -x "$out/lib/pi-coding-agent/examples/extensions/doom-overlay/doom/build.sh"
      makeWrapper \
        "$out/lib/pi-coding-agent/pi" \
        "$out/bin/pi" \
        --prefix PATH : ${lib.makeBinPath [pkgs.fd pkgs.ripgrep]} \
        --run 'if [ -S "$HOME/.ssh/agent.sock" ]; then export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"; fi'
    '';

    postFixup = ''
      autoPatchelf -- "$out/lib/pi-coding-agent/node_modules"
    '';

    meta = {
      mainProgram = "pi";
      platforms = ["x86_64-linux"];
    };
  }
