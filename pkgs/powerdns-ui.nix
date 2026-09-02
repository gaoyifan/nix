{pkgs}:
pkgs.buildNpmPackage {
  pname = "powerdns-ui";
  version = "1.1.3";
  src = pkgs.fetchFromGitHub {
    owner = "gaoyifan";
    repo = "powerdns-ui";
    rev = "8cfe1f649e3f2671ab01ab1d7292eafe536d4ba3";
    hash = "sha256-v5jJVzTRJxA2BB5vCQlNffjRWIVpvKFdpEtsSH/RPPs=";
  };
  npmDepsHash = "sha256-cBcXgmGCn9DbIY25PXmE4BClxTS4E5kcbtdd02aCUtI=";
  installPhase = ''
    runHook preInstall
    cp -r dist $out
    runHook postInstall
  '';
}
