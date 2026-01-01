# Overlays for custom packages and modifications
{ ... }:
{
  # Brings custom packages from the 'pkgs' directory
  # Makes them accessible via 'pkgs.lazyssh', etc.
  additions = final: _prev: import ../pkgs final;

  # Modifications to existing packages
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    # example = prev.example.overrideAttrs (oldAttrs: { ... });
  };
}
