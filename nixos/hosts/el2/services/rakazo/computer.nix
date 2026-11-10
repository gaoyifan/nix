{
  pkgs,
  rakazoSource,
  anthropicSkills,
}: let
  inherit (pkgs) lib;
  x11vncClosure = pkgs.closureInfo {rootPaths = [pkgs.x11vnc-utf8];};
  novnc = pkgs.applyPatches {
    name = "rakazo-novnc-1.3.0";
    src = pkgs.fetchFromGitHub {
      owner = "novnc";
      repo = "noVNC";
      rev = "v1.3.0";
      hash = "sha256-Z+bks7kcwj+Z3uf/t0u25DnGOM60QhSH6uuoIi59jqU=";
    };
    patches = [./novnc-provide.patch];
  };
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
  officeKitPptx = pkgs.fetchFromGitHub {
    owner = "office-kit";
    repo = "pptx";
    rev = "18b7e75cfa7fd1c6e9891ce1285a76c7889b644b";
    hash = "sha256-Bs8z6rJsVTSVj4QmQCbXWgO+tJ6lavmZH1LDrcGlbKQ=";
  };
  officeKitDocx = pkgs.fetchFromGitHub {
    owner = "office-kit";
    repo = "docx";
    rev = "a5fe1b8b58923619bd6ff040b10de0e887e68c5f";
    hash = "sha256-O+3duse6tK0KD0L6Ihm8jOR8S0oeE/sfMzuIRWNbrgw=";
  };
  officeKitXlsx = pkgs.fetchFromGitHub {
    owner = "office-kit";
    repo = "xlsx";
    rev = "528525d3682d338319489835838db7380257949f";
    hash = "sha256-MMICyKe1DtakgoYwDYxYTNC5gGnPBxOfwEK/4ULHA1Q=";
  };
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
    cp -r ${officeKitPptx}/skill $out/skills/office-kit-pptx
    cp -r ${./skills}/{audio-transcription,video-processing,codex,office-kit-docx,office-kit-xlsx} $out/skills/
    for name in docx xlsx pdf pptx; do
      cp -r ${anthropicSkills}/skills/$name $out/skills/
    done
    cp -r ${skillSource}/tushare-data $out/skills/
    chmod -R u+w $out/skills
    ${pkgs.patch}/bin/patch --directory=$out/skills/office-kit-pptx --strip=1 < ${./skills/office-kit-pptx.patch}
    mkdir -p $out/skills/office-kit-docx/references $out/skills/office-kit-xlsx/references
    cp ${officeKitDocx}/docs/examples.md $out/skills/office-kit-docx/references/examples.md
    cp ${officeKitXlsx}/site/src/routes/docs/cheatsheet/+page.svx $out/skills/office-kit-xlsx/references/cheatsheet.md
    cp -r ${officeKitXlsx}/site/src/lib/examples/recipes $out/skills/office-kit-xlsx/references/
    for name in docx xlsx pptx; do
      sed -i "s/^description:.*/description: Legacy $name utilities for extraction, conversion, validation and specialised operations. For document creation and ordinary revisions, use office-kit-$name./" \
        $out/skills/$name/SKILL.md
      sed -i "0,/^# /s/^# /## Office Kit authoring default\\n\\nFor creation and ordinary revisions, read and use the \`office-kit-$name\` Skill as the default authoring workflow. For an Office Kit project, revise its source or use its read\/edit\/write API. The instructions below provide extraction, conversion, validation and specialised utilities.\\n\\n# /" \
        $out/skills/$name/SKILL.md
    done
    for name in office-kit-docx office-kit-pptx office-kit-xlsx docx xlsx pdf pptx; do
      sed -i '1a metadata:\n  managed-by: rakazo-computer' $out/skills/$name/SKILL.md
      cat ${./skills/environment.md} >> $out/skills/$name/SKILL.md
    done
    cp --remove-destination ${skill} $out/skills/tushare-data/SKILL.md
    install -m 0755 ${transcriptionScripts}/transcribe_audio.py $out/bin/transcribe-audio
    install -m 0755 ${transcriptionScripts}/estimate_transcription_time.py $out/bin/estimate-transcription-time
    substituteInPlace $out/bin/{transcribe-audio,estimate-transcription-time} \
      --replace-fail '#!/usr/bin/env python3' '#!/usr/bin/python3'
    substituteInPlace $out/bin/transcribe-audio \
      --replace-fail 'http://100.65.3.254:8080' 'http://100.64.2.254:8178'
    tar -xzf ${pkgs.codex.src} -C $out/codex
    tar -xJf ${nodejsBinary} -C $out/nodejs --strip-components=1
    cp -r ${pkgs.node-docx}/lib/node_modules $out/node/
    mkdir -p $out/office-kit
    cp ${./office-kit}/{package.json,package-lock.json} $out/office-kit/
    ${pkgs.gnutar}/bin/tar -cf $out/x11vnc.tar -T ${x11vncClosure}/store-paths
    cp ${novnc}/core/rfb.js $out/rfb.js
    cat > $out/Dockerfile <<'EOF'
    FROM ghcr.io/elie222/rakazo/computer:sha-${rakazoSource.rev}
    USER root
    ADD x11vnc.tar /
    RUN ln -sf ${pkgs.x11vnc-utf8}/bin/x11vnc /usr/bin/x11vnc
    COPY rfb.js /usr/share/novnc/core/rfb.js
    ENV X11VNC_AVOID_WINDOWS=never
    RUN unset LD_PRELOAD; apt-get update && apt-get install -y --no-install-recommends \
        libreoffice-writer libreoffice-calc libreoffice-impress \
        tesseract-ocr tesseract-ocr-eng tesseract-ocr-chi-sim qpdf ffmpeg bubblewrap \
        fonts-crosextra-carlito fonts-crosextra-caladea \
        fonts-noto-cjk \
      && rm -rf /var/lib/apt/lists/*
    RUN unset LD_PRELOAD; uv pip install --system --break-system-packages --no-cache \
        tushare==1.4.29 'markitdown[docx,pdf,pptx,xlsx]==${pkgs.python3Packages.markitdown.version}' \
        'yt-dlp[default,curl-cffi]==${pkgs.yt-dlp.version}' ${pythonRequirements}
    COPY node /opt/rakazo/node
    COPY nodejs /opt/nodejs
    RUN ln -sf /opt/nodejs/bin/node /usr/local/bin/node \
      && ln -sf /opt/nodejs/bin/npm /usr/local/bin/npm \
      && ln -sf /opt/nodejs/bin/npx /usr/local/bin/npx
    COPY office-kit /opt/rakazo/office-kit
    RUN unset LD_PRELOAD; cd /opt/rakazo/office-kit \
      && npm ci --cache /tmp/office-kit-npm --ignore-scripts --no-audit --no-fund --registry=https://registry.npmjs.org \
      && sed -i 's|Changes are persisted in TSX\.|Canvas edits are saved in .office-kit/*.editor.zip, not TSX. Before source revisions, run npm run build once to capture the current saved presentation as the baseline. Preserve saved edits on untouched slides.|g' node_modules/@office-kit/pptx-dev/dist/*.mjs \
      && rm -rf /tmp/office-kit-npm \
      && ln -s /opt/rakazo/office-kit/node_modules /node_modules \
      && ln -s /opt/rakazo/office-kit/node_modules/@office-kit/pptx-dev/dist/cli.mjs /usr/local/bin/office-pptx
    COPY codex /opt/codex
    RUN ln -s /opt/codex/bin/codex /usr/local/bin/codex \
      && ln -s /opt/codex/bin/codex-code-mode-host /usr/local/bin/codex-code-mode-host
    COPY skills /opt/rakazo/skills
    COPY bin /usr/local/bin
    ENV NODE_PATH=/opt/rakazo/node/node_modules
    USER 1000:1000
    EOF
  '';
in {
  inherit buildContext;
  imageRef = "localhost/rakazo-computer:${builtins.baseNameOf buildContext}";
}
