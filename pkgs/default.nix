{
  inputs,
  pkgs,
}:
{
  lazyssh = import ./lazyssh.nix {inherit pkgs;};
  dcv = import ./dcv.nix {inherit pkgs;};
  restic = import ./restic.nix {inherit pkgs;};
  mcat = import ./mcat.nix {inherit pkgs;};
  agy = import ./antigravity-cli.nix {inherit pkgs;};
  copilot-cli = import ./copilot-cli.nix {inherit pkgs;};
  codex = import ./codex.nix {inherit pkgs;};
  cursor-cli = import ./cursor-cli.nix {inherit pkgs;};
  pi-coding-agent = import ./pi-coding-agent.nix {inherit pkgs;};
  pi-coding-agent-baseline = import ./pi-coding-agent-baseline.nix {inherit pkgs;};
  playwright-cli = import ./playwright-cli.nix {inherit pkgs;};
  tssh = import ./tssh.nix {inherit pkgs;};
  htop = import ./htop.nix {inherit pkgs;};
  tailscale = import ./tailscale.nix {inherit pkgs;};
  telegram-bot-api = import ./telegram-bot-api.nix {inherit pkgs;};
  whisper-large-v3-turbo = import ./whisper-large-v3-turbo.nix {inherit pkgs;};
  lark-cli = import ./lark-cli.nix {inherit inputs pkgs;};
  node-docx = import ./node-docx.nix {inherit pkgs;};
}
// pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
  jip = import ./jip.nix {inherit pkgs;};
  nylon = import ./nylon.nix {inherit pkgs;};
}
// pkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "aarch64-linux") {
  nanopi-r4s-uboot = import ./nanopi-r4s-uboot.nix {inherit pkgs;};
}
