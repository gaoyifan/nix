{
  pkgs,
  inputs,
  package ? inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.minimal,
}: let
  inherit (pkgs) lib;
  upstream = inputs.hermes-agent;
  system = pkgs.stdenv.hostPlatform.system;
  target = "${
    if pkgs.stdenv.hostPlatform.isDarwin
    then "darwin"
    else "linux"
  }-${
    if pkgs.stdenv.hostPlatform.isAarch64
    then "arm64"
    else "x64"
  }";
  tools = {
    node = package.hermesNpmLib.nodejs;
    npm = package.hermesNpmLib.nodejs;
    ripgrep = upstream.packages.${system}.pm-ripgrep;
    ffmpeg = upstream.packages.${system}.pm-ffmpeg;
  };
  entries = pkgs.writeText "hermes-pm-tool-entries.json" (builtins.toJSON (lib.mapAttrs (name: _: name) tools));
in
  package.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        mkdir -p "$out/tools"
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: tool: ''
            mkdir -p "$out/tools/${name}"
            cp -rs ${tool}/. "$out/tools/${name}/"
          '')
          tools)}
        PYTHONPATH=${upstream} ${package.hermesVenv}/bin/python3 - "$out" <<'PY'
        import json, pathlib, sys
        from scripts.bundles.payload import record_tools

        record_tools(pathlib.Path(sys.argv[1]), pathlib.Path("${upstream}/pm/lock.json"),
                     "${target}", json.loads(pathlib.Path("${entries}").read_text()))
        PY
        for command in "$out"/bin/*; do
          wrapProgram "$command" --set HERMES_RUNTIME_DIR "$out/tools"
        done
      '';
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      export HERMES_HOME="$TMPDIR/hermes-home"
      mkdir -p "$HERMES_HOME/tools/old-node/bin" "$TMPDIR/ambient/bin"
      printf '#!${pkgs.runtimeShell}\necho v26.7.0\n' > "$HERMES_HOME/tools/old-node/bin/node"
      chmod +x "$HERMES_HOME/tools/old-node/bin/node"
      cat > "$HERMES_HOME/tools/facts.json" <<'JSON'
      {"schema":1,"packages":{"node":{"version":"26.7.0","entry":"old-node","target":"${target}"}}}
      JSON
      for tool in node npm; do
        printf '#!${pkgs.runtimeShell}\necho ambient-tool\n' > "$TMPDIR/ambient/bin/$tool"
        chmod +x "$TMPDIR/ambient/bin/$tool"
      done
      PATH="$TMPDIR/ambient/bin:$PATH" ${package.hermesVenv}/bin/python3 - "$out" "${upstream}" <<'PY'
      import json, os, pathlib, shutil, subprocess, sys

      package, source = map(pathlib.Path, sys.argv[1:])
      user_facts = pathlib.Path(os.environ["HERMES_HOME"]) / "tools/facts.json"
      before = user_facts.read_bytes()
      tool_env = json.loads(subprocess.check_output(
          [str(package / "bin/hermes"), "pm", "env", "node", "npm"], text=True))
      env = {**os.environ, **tool_env}
      lock = json.loads((source / "pm/lock.json").read_text())["packages"]
      for name in ("node", "npm"):
          executable = shutil.which(name, path=env["PATH"])
          assert executable and str(package / "tools") in executable, executable
          version = subprocess.check_output([executable, "--version"], env=env, text=True).strip().removeprefix("v")
          assert version == lock[name]["version"], (name, version)
      subprocess.run([str(package / "bin/hermes"), "pm", "doctor"], check=True)
      assert user_facts.read_bytes() == before, "package startup changed user tool records"
      PY
      runHook postInstallCheck
    '';
  })
