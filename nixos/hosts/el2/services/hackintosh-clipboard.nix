{pkgs, ...}: {
  systemd.services.hackintosh-clipboard-bridge = {
    description = "Bidirectional text clipboard for the Hackintosh VNC console";
    wantedBy = ["el2-services.target"];
    requires = ["hackintosh-vnc.service"];
    after = ["hackintosh-vnc.service"];
    partOf = ["hackintosh-vnc.service"];
    path = [pkgs.diffutils pkgs.openssh pkgs.xclip];
    enableStrictShellChecks = true;
    script = builtins.readFile ./hackintosh-clipboard-bridge.sh;
    environment = {
      DISPLAY = ":91";
      XAUTHORITY = "/run/hackintosh-vnc/Xauthority";
    };
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
      RuntimeDirectory = "hackintosh-clipboard-bridge";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
    };
  };
}
