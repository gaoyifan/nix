{pkgs}:
pkgs.cloud-hypervisor.overrideAttrs (finalAttrs: previousAttrs: {
  version = "53.0";

  src = pkgs.fetchFromGitHub {
    owner = "cloud-hypervisor";
    repo = "cloud-hypervisor";
    rev = "v${finalAttrs.version}";
    hash = "sha256-fPTGf8bAITDA8QwllWbbGXA7tJ6p/SxRDfcBQVRvCTI=";
  };

  cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
    inherit (finalAttrs) src;
    hash = "sha256-+RbW/9ap/69MyODUk/bHBlH6ZuqYYIyKaarYSMQ2G7w=";
  };

  buildInputs =
    previousAttrs.buildInputs
    ++ [
      pkgs.openssl
      pkgs.zstd
    ];

  env =
    previousAttrs.env
    // {
      ZSTD_SYS_USE_PKG_CONFIG = true;
    };

  # Upstream tests need KVM/TUN access, which the Nix build sandbox does not
  # provide, and their skip list is version-specific. This override only
  # backports the released VSOCK half-close fix.
  doCheck = false;
})
