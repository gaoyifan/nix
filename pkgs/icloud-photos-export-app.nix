{pkgs}: let
  bundleName = "ICloudPhotosExporter.app";
  bundleIdentifier = "com.gaoyifan.icloud-photos-export";
  executableName = "icloud-photos-export";
  info = builtins.toFile "icloud-photos-export-Info.plist" (pkgs.lib.generators.toPlist {escape = true;} {
    CFBundleExecutable = executableName;
    CFBundleIdentifier = bundleIdentifier;
    CFBundleName = "iCloud Photos Exporter";
    CFBundlePackageType = "APPL";
    CFBundleVersion = "1";
    LSUIElement = true;
    NSPhotoLibraryUsageDescription = "Read your Photos library to back it up to the configured archive.";
    NSAppleEventsUsageDescription = "Ask Photos to export original Live Photo videos for the archive.";
  });
in
  pkgs.runCommand "icloud-photos-export-app" {
    # Fixup may change the Mach-O executable after signing.
    dontFixup = true;
    passthru = {inherit bundleName bundleIdentifier executableName;};
    meta.platforms = ["x86_64-darwin"];
  } ''
    app="$out/Applications/${bundleName}"
    install -Dm755 ${pkgs.python313.interpreter} "$app/Contents/MacOS/${executableName}"
    install -Dm644 ${info} "$app/Contents/Info.plist"
    /usr/bin/codesign --force --sign - "$app"
    /usr/bin/codesign --verify --strict "$app"
  ''
