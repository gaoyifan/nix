{
  bootstrapImage,
  lib,
  pkgs,
  ...
}: let
  image = "${bootstrapImage}/sd-image/nanopi-r5c-bootstrap.img.zst";
  imageMetadata =
    pkgs.runCommand "nanopi-r5c-bootstrap-image-metadata" {
      nativeBuildInputs = [pkgs.coreutils pkgs.zstd];
    } ''
      mkdir -p "$out"
      zstd -dc ${image} > image.img
      stat -c %s image.img > "$out/size"
      sha256sum image.img | cut -d' ' -f1 > "$out/sha256"
    '';
  flashEmmc = pkgs.writeShellApplication {
    name = "flash-nanopi-r5c-emmc";
    runtimeInputs = with pkgs; [coreutils gnugrep util-linux zstd];
    text = builtins.readFile ./flash-emmc.sh;
  };
in {
  imports = [../nanopi-r5c-bootstrap];

  networking.hostName = lib.mkForce "nanopi-r5c-emmc-flasher";
  sdImage = {
    firmwarePartitionID = "0x5c5c5c5c";
    rootPartitionUUID = "55555555-5555-4555-8555-555555555555";
    rootVolumeLabel = "R5C_FLASH";
  };

  systemd.services.flash-nanopi-r5c-emmc = {
    description = "Write NanoPi R5C bootstrap image to eMMC";
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
    script = ''
      ${flashEmmc}/bin/flash-nanopi-r5c-emmc \
        ${image} \
        "$(cat ${imageMetadata}/size)" \
        "$(cat ${imageMetadata}/sha256)"
    '';
  };
}
