{pkgs}:
assert pkgs.stdenv.isLinux;
assert pkgs.mutagen.version == "0.18.1";
  pkgs.mutagen.overrideAttrs (old: {
    pname = "mutagen-fanotify-agent";
    agents = null;

    # The upstream Linux recursive watcher is gated behind both of these
    # SSPL build tags. The regular Mutagen package deliberately omits them.
    tags = [
      "mutagenagent"
      "mutagensspl"
      "mutagenfanotify"
    ];
    subPackages = ["cmd/mutagen-agent"];
    env =
      old.env
      // {
        CGO_ENABLED = 0;
      };
    nativeBuildInputs = [pkgs.go];

    # The regular package generates shell completions with the CLI, which this
    # agent-only derivation does not build.
    postInstall = "";

    meta =
      old.meta
      // {
        license = pkgs.lib.licenses.sspl;
        mainProgram = "mutagen-agent";
        sourceProvenance = [pkgs.lib.sourceTypes.fromSource];
      };
  })
