{pkgs}:
pkgs.buildNpmPackage {
  pname = "node-docx";
  version = "9.7.1";

  src = ./node-docx;
  npmDepsHash = "sha256-7NufgetI3qoU2OJldv8wJnBv6rJ7PJkTQPFXXSlqkDQ=";
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    cp -r node_modules $out/lib/
    runHook postInstall
  '';

  meta = {
    description = "Node.js document modules for Hermes office skills";
    homepage = "https://docx.js.org";
    license = pkgs.lib.licenses.mit;
  };
}
