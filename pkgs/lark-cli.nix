{
  inputs,
  pkgs,
}:
pkgs.buildGoModule rec {
  pname = "lark-cli";
  version = "1.0.69";

  src = inputs.lark-cli-src;
  vendorHash = "sha256-jAnqQb0+/GbsW8FcKNBYxN8VPPTs3c9JPfmHe90UqOQ=";
  subPackages = ["."];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/larksuite/cli/internal/build.Version=${version}"
    "-X github.com/larksuite/cli/internal/build.Date=1970-01-01"
  ];

  env.CGO_ENABLED = 0;
  postInstall = ''
    mv $out/bin/cli $out/bin/lark-cli
  '';

  meta = {
    description = "Official CLI for the Lark and Feishu Open Platform";
    homepage = "https://github.com/larksuite/cli";
    license = pkgs.lib.licenses.mit;
    mainProgram = "lark-cli";
  };
}
