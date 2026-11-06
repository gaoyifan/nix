{
  pkgs,
  rakazoSource,
  anthropicSkills,
}: let
  inherit (pkgs) lib;
  pythonRequirements = lib.concatStringsSep " " (map
    (package: "${package.pname}==${package.version}")
    (with pkgs.python3Packages; [
      defusedxml
      lxml
      pdf2image
      pdfplumber
      pillow
      pypdf
      python-pptx
      pyyaml
      pytesseract
      reportlab
    ]));
  # yt-dlp's EJS solver requires Node 22 or newer; Bookworm provides Node 18.
  nodejsBinary = pkgs.fetchurl {
    url = "https://nodejs.org/dist/v${pkgs.nodejs_22.version}/node-v${pkgs.nodejs_22.version}-linux-x64.tar.xz";
    hash = "sha256-30UK+JJhEV75+eODDD7rLMkhO2PHILGvYjy13L4uAt4=";
  };
  transcriptionScripts = ../../../../optional/hermes-nspawn/skills/audio-transcription/scripts;
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
    mkdir -p $out/skills $out/codex $out/bin $out/node $out/nodejs
    cp -r ${./skills}/{audio-transcription,video-processing,codex} $out/skills/
    for name in docx xlsx pdf pptx; do
      cp -r ${anthropicSkills}/skills/$name $out/skills/
      chmod u+w $out/skills/$name/SKILL.md
      cat ${./skills/environment.md} >> $out/skills/$name/SKILL.md
    done
    cp -r ${skillSource}/tushare-data $out/skills/
    chmod -R u+w $out/skills
    cp --remove-destination ${skill} $out/skills/tushare-data/SKILL.md
    install -m 0755 ${transcriptionScripts}/transcribe_audio.py $out/bin/transcribe-audio
    install -m 0755 ${transcriptionScripts}/estimate_transcription_time.py $out/bin/estimate-transcription-time
    substituteInPlace $out/bin/{transcribe-audio,estimate-transcription-time} \
      --replace-fail '#!/usr/bin/env python3' '#!/usr/bin/python3'
    tar -xzf ${pkgs.codex.src} -C $out/codex
    tar -xJf ${nodejsBinary} -C $out/nodejs --strip-components=1
    cp -r ${pkgs.node-docx}/lib/node_modules $out/node/
    cat > $out/Dockerfile <<'EOF'
    FROM ghcr.io/elie222/rakazo/computer:sha-${rakazoSource.rev}
    USER root
    RUN unset LD_PRELOAD; apt-get update && apt-get install -y --no-install-recommends \
        libreoffice-writer libreoffice-calc libreoffice-impress \
        tesseract-ocr tesseract-ocr-eng tesseract-ocr-chi-sim qpdf ffmpeg bubblewrap \
        fonts-crosextra-carlito fonts-crosextra-caladea \
      && rm -rf /var/lib/apt/lists/*
    RUN unset LD_PRELOAD; uv pip install --system --break-system-packages --no-cache \
        tushare==1.4.29 'markitdown[docx,pdf,pptx,xlsx]==${pkgs.python3Packages.markitdown.version}' \
        'yt-dlp[default,curl-cffi]==${pkgs.yt-dlp.version}' ${pythonRequirements}
    COPY node /opt/rakazo/node
    COPY codex /opt/codex
    RUN ln -s /opt/codex/bin/codex /usr/local/bin/codex \
      && ln -s /opt/codex/bin/codex-code-mode-host /usr/local/bin/codex-code-mode-host
    COPY skills /opt/rakazo/skills
    COPY bin /usr/local/bin
    COPY nodejs /opt/nodejs
    RUN ln -sf /opt/nodejs/bin/node /usr/local/bin/node \
      && ln -sf /opt/nodejs/bin/npm /usr/local/bin/npm \
      && ln -sf /opt/nodejs/bin/npx /usr/local/bin/npx
    ENV NODE_PATH=/opt/rakazo/node/node_modules
    USER 1000:1000
    EOF
  '';
in {
  inherit buildContext;
  imageRef = "localhost/rakazo-computer:${builtins.baseNameOf buildContext}";
}
