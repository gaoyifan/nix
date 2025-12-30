# Custom packages
{ pkgs }:
let
  packages = {
    lazyssh = import ./lazyssh.nix { inherit pkgs; };
    # Add more packages here
  };
in
packages
// {
  # Meta package that builds all custom packages
  default = pkgs.symlinkJoin {
    name = "all-custom-packages";
    paths = builtins.attrValues packages;
  };
}
