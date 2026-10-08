{
  pkgs,
  rakazoSource,
}: let
  skillSource = pkgs.fetchFromGitHub {
    owner = "waditu-tushare";
    repo = "skills";
    rev = "5e12b31d09123e262c5fb38564e80c26d05cb830";
    hash = "sha256-n5/rYduDSk2gaSL8EGppyPDD8ijOkwNcAPCXw59dK9o=";
  };
  skill = pkgs.writeText "tushare-SKILL.md" (pkgs.lib.replaceStrings
    ["# tushare-data\n" "`references/数据接口.md`"]
    ["# tushare-data\n\n${builtins.readFile ./tushare-environment.md}\n" "`/opt/rakazo/skills/tushare-data/references/数据接口.md`"]
    (builtins.readFile "${skillSource}/tushare-data/SKILL.md"));
  buildContext = pkgs.runCommand "rakazo-computer-context" {} ''
    mkdir -p $out/tushare-data
    cp -r ${skillSource}/tushare-data/. $out/tushare-data/
    cp --remove-destination ${skill} $out/tushare-data/SKILL.md
    cat > $out/Dockerfile <<'EOF'
    FROM ghcr.io/elie222/rakazo/computer:sha-${rakazoSource.rev}
    USER root
    RUN uv pip install --system --break-system-packages --no-cache tushare==1.4.29
    COPY tushare-data /opt/rakazo/skills/tushare-data
    USER 1000:1000
    EOF
  '';
in {
  inherit buildContext;
  imageRef = "localhost/rakazo-computer:${builtins.baseNameOf buildContext}";
}
