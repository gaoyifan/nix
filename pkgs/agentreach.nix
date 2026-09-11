{pkgs}:
pkgs.buildGoModule rec {
  pname = "agentreach";
  version = "0.6.0";

  src = pkgs.fetchFromGitHub {
    owner = "bojieli";
    repo = "agentreach";
    tag = "v${version}";
    hash = "sha256-SgR7gXaD/lxaUCXVvozPckrZImpbdAigcSxDgEn+zSc=";
  };

  vendorHash = null;
  subPackages = ["cmd/reach"];

  postPatch = ''
    substituteInPlace cmd/reach/shimpassthrough_test.go \
      --replace-fail '#!/usr/bin/env bash' '#!${pkgs.coreutils}/bin/env bash'
  '';

  env.CGO_ENABLED = 0;
  ldflags = [
    "-s"
    "-w"
    "-X main.buildVersion=${version}"
    "-X main.buildCommit=3433f13"
    "-X main.buildDate=2026-09-04"
  ];

  postBuild = ''
    for platform in linux-amd64 linux-arm64 darwin-amd64 darwin-arm64; do
      (
        export GOOS="''${platform%-*}" GOARCH="''${platform#*-}"
        go build \
          -ldflags "-s -w -X main.version=${version}" \
          -o "$NIX_BUILD_TOP/reach-helper-$platform" \
          ./cmd/reach-helper
      )
    done
  '';

  postInstall = ''
    install -Dm755 "$NIX_BUILD_TOP"/reach-helper-* -t "$out/bin"
  '';

  meta = {
    description = "Run local coding agents against remote hosts over SSH";
    homepage = "https://github.com/bojieli/agentreach";
    changelog = "https://github.com/bojieli/agentreach/blob/v${version}/CHANGELOG.md";
    license = pkgs.lib.licenses.mit;
    mainProgram = "reach";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
