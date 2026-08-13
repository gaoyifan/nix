# Builds a Btrfs root image populated with the closure of storePaths, sized to
# fit its contents. Vendored from nixpkgs nixos/lib/make-btrfs-fs.nix so the
# store can be compressed while the image is created.
{
  pkgs,
  lib,
  storePaths,
  compressImage ? false,
  zstd,
  populateImageCommands ? "",
  volumeLabel,
  uuid ? "44444444-4444-4444-8888-888888888888",
  btrfs-progs,
  libfaketime,
  util-linux,
}: let
  sdClosureInfo = pkgs.buildPackages.closureInfo {rootPaths = storePaths;};
in
  pkgs.stdenv.mkDerivation {
    name = "btrfs-fs.img${lib.optionalString compressImage ".zst"}";

    nativeBuildInputs =
      [
        btrfs-progs
        libfaketime
        util-linux
      ]
      ++ lib.optional compressImage zstd;

    # fakeroot does not affect the ownership recorded by mkfs.btrfs -r, so
    # create the image in a user namespace where the build user maps to root.
    buildCommand = ''
      ${
        if compressImage
        then "img=temp.img"
        else "img=$out"
      }

      set -x
      (
          mkdir -p ./files
          ${populateImageCommands}
      )

      mkdir -p ./rootImage/nix/store

      xargs -I % cp -a --reflink=auto % -t ./rootImage/nix/store/ < ${sdClosureInfo}/store-paths
      (
        GLOBIGNORE=".:.."
        shopt -u dotglob

        for f in ./files/*; do
            cp -a --reflink=auto -t ./rootImage/ "$f"
        done
      )

      cp ${sdClosureInfo}/registration ./rootImage/nix-path-registration

      touch $img
      unshare -r bash -c '
        chown -R 0:0 ./rootImage
        faketime -f "1970-01-01 00:00:01" mkfs.btrfs \
          -L "$1" \
          -U "$2" \
          -r ./rootImage \
          --shrink \
          --compress zstd:6 \
          "$3"
      ' -- ${volumeLabel} ${uuid} "$img"

      if ! btrfs check $img; then
        echo "--- 'btrfs check' failed for BTRFS image ---"
        return 1
      fi

      if [ ${toString compressImage} ]; then
        echo "Compressing image"
        zstd -v --no-progress ./$img -o $out
      fi
    '';
  }
