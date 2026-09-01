{pkgs}:
pkgs.bitmagnet.overrideAttrs (_: {
  version = "0.10.0-unstable-2026-09-02";

  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "bitmagnet";
    rev = "54942d6ca42f2e8c2e3881440ec900d6739cecf4";
    hash = "sha256-zEgSgi9L6DUmPdbn/rYgOa//lbOnxqqPuyRD2Xkx1QE=";
  };

  vendorHash = "sha256-aWFh3vytRARFEnVxTtSkvBOXZP0ke9e602BVNQ6xoRY=";
})
