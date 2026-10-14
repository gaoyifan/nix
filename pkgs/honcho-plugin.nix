{pkgs}: let
  src = pkgs.fetchFromGitHub {
    owner = "plastic-labs";
    repo = "honcho";
    rev = "e2d2aba182862deeb846e5cd4a30a41bce0ed82a";
    hash = "sha256-EZWqItroZopzw1c0nSyujPWpsN5OAUG3TpQmTdYAAsY=";
  };
in
  pkgs.runCommand "honcho" {} ''
    mkdir -p $out
    cp -r ${src}/hermes-plugin-honcho/. $out/
    # Nix supplies the Python dependencies; PM must not require its own venv.
    chmod u+w $out/plugin.yaml
    printf '\npython_runtime: external\n' >> $out/plugin.yaml
  ''
