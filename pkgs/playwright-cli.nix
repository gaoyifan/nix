{pkgs}: let
  inherit (pkgs) lib stdenv;

  chromium = pkgs.playwright-driver.components.chromium;
  browserExecutable =
    {
      x86_64-linux = "${chromium}/chrome-linux64/chrome";
      aarch64-linux = "${chromium}/chrome-linux/chrome";
      aarch64-darwin = "${chromium}/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";
    }
    .${
      stdenv.hostPlatform.system
    };
in
  pkgs.buildNpmPackage rec {
    pname = "playwright-cli";
    version = "0.1.17";

    src = pkgs.fetchFromGitHub {
      owner = "microsoft";
      repo = "playwright-cli";
      tag = "v${version}";
      hash = "sha256-tc/2Qck3mm6BqWTu2lvvfsM0/BHO/Z0ZvCdFZ7QQqKI=";
    };

    npmDepsHash = "sha256-u44jWprmr3RdzB3aDL3K0ShT5lLxr175z3C8pN43YFA=";

    nativeBuildInputs = [pkgs.makeWrapper];

    dontNpmBuild = true;

    postInstall = ''
      wrapProgram "$out/bin/playwright-cli" \
        --set-default PLAYWRIGHT_MCP_EXECUTABLE_PATH "${browserExecutable}"
    '';

    meta = {
      description = "Playwright CLI for browser automation with coding agents";
      homepage = "https://github.com/microsoft/playwright-cli";
      changelog = "https://github.com/microsoft/playwright-cli/releases/tag/v${version}";
      license = lib.licenses.asl20;
      mainProgram = "playwright-cli";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  }
