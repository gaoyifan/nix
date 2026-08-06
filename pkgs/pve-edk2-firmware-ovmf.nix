{pkgs}:
pkgs.runCommand "pve-edk2-firmware-ovmf-4.2025.05-2" {
  nativeBuildInputs = [pkgs.dpkg];
} ''
  dpkg-deb -x ${pkgs.fetchurl {
    url = "http://download.proxmox.com/debian/pve/dists/trixie/pve-no-subscription/binary-amd64/pve-edk2-firmware-ovmf_4.2025.05-2_all.deb";
    hash = "sha256-zPDyj++vPwQobKeRYRA24f0gLHPlS8AjtjDiOYL39no=";
  }} $out
''
