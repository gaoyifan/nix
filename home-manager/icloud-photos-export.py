"""Export the Hackintosh Photos library; only the ZFS receiver retains deleted photos."""

import fcntl
import importlib
import json
import os
from dataclasses import replace
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time

VOLUME = Path("/Volumes/Photos")
STATUS_PATH = VOLUME / "icloud-export/.backup-status.json"


def summarize(report):
    # A zero exit status from osxphotos does not imply that all files were exported.
    if not isinstance(report, list) or not report:
        raise ValueError("Photos export report is empty or invalid")
    missing = sum(bool(row["missing"]) for row in report)
    errors = sum(
        bool(row["error"] or row["sidecar_user_error"] or row["exiftool_error"] or row["user_error"]) for row in report
    )
    return missing, errors


def configure_osxphotos():
    import osxphotos
    from osxphotos.photoexporter import PhotoExporter
    from osxphotos.photokit import LivePhotoAsset, PhotoLibrary

    if osxphotos.__version__ != "0.77.1":
        raise RuntimeError("Revalidate the original Live Photo workaround before upgrading OSXPhotos")

    class ArchivePhotoExporter(PhotoExporter):
        def _stage_missing_photos_for_export_helper(self, options):
            # OSXPhotos 0.77.1's PhotoKit LivePhoto exporter documents that requesting
            # originals can yield the edited movie. Photos' original AppleScript export
            # preserves it; PhotoKit is needed for edited movies and missing burst members.
            if self.photo.live_photo and not options.edited:
                return self._stage_photo_for_export_with_applescript(options=options)
            return self._stage_photo_for_export_with_photokit(options=options)

        def _export(self, dest, filename, options):
            if options.edited and self.photo.live_photo:
                # Photos can turn Live off in an edit while retaining the original
                # pair. Its current PhotoKit type, unlike the database's original
                # Live flag, tells us whether an edited companion movie exists.
                current = PhotoLibrary().fetch_uuid(self.photo.uuid)
                if not isinstance(current, LivePhotoAsset):
                    options = replace(options, live_photo=False)
            return super()._export(dest, filename, options)

    export_module = importlib.import_module("osxphotos.cli.export")
    export_module.PhotoExporter = ArchivePhotoExporter
    return export_module.export_cli


def export():
    export_photos = configure_osxphotos()

    os.umask(0o077)
    library = VOLUME / "Photos Library.photoslibrary"
    destination = STATUS_PATH.parent
    info = plistlib.loads(subprocess.check_output(["/usr/sbin/diskutil", "info", "-plist", str(VOLUME)]))
    if info.get("VolumeUUID") != "560D9DAE-6BB6-4291-9B17-848609B942C8" or info.get("MountPoint") != str(VOLUME):
        raise RuntimeError("The expected Photos APFS volume is not mounted")
    if not (library / "database/Photos.sqlite").is_file():
        raise RuntimeError("The Photos library is missing")

    destination.mkdir(exist_ok=True)
    # Also protect against a disconnected SSH command still finishing an export.
    with (destination / ".backup.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # Open the actual library before PhotoKit requests arrive at startup.
        subprocess.run(["/usr/bin/open", "-a", "Photos", str(library)], check=True)
        report_path = destination / ".export-report.json"
        report_path.unlink(missing_ok=True)
        STATUS_PATH.unlink(missing_ok=True)
        template = destination / ".photo-json.mako"
        template.write_text("${photo.json(shallow=False, indent=4)}\n")
        result = export_photos(
            dest=str(destination),
            db=str(library),
            update=True,
            update_errors=True,
            download_missing=True,
            use_photokit=True,
            cleanup=True,
            not_shared=True,
            not_hidden=True,
            directory="{created.year}/{created.mm}",
            filename_template="{original_name}_{uuid}",
            sidecar=("xmp",),
            sidecar_template=((str(template), "{filepath}.osxphotos.json", ("write_skipped",)),),
            report=str(report_path),
            no_progress=True,
        )
        if result:
            return result
        missing, errors = summarize(json.loads(report_path.read_text()))
        disk = shutil.disk_usage(VOLUME)
        status = {
            "completed_at": int(time.time()),
            "missing": missing,
            "errors": errors,
            "apfs_used_ratio": disk.used / disk.total,
            "complete": missing == 0 and errors == 0,
        }
        STATUS_PATH.write_text(json.dumps(status) + "\n")
        print(json.dumps(status), flush=True)
        return 0 if status["complete"] else 1


def trigger(label):
    target = f"gui/{os.getuid()}/{label}"
    started_at = int(time.time())
    subprocess.run(["/bin/launchctl", "kickstart", target], check=True)
    while True:
        try:
            status = json.loads(STATUS_PATH.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            status = None
        if isinstance(status, dict) and status.get("completed_at", 0) >= started_at:
            return 0 if status.get("complete") else 1
        if time.time() - started_at > 10:
            state = subprocess.check_output(["/bin/launchctl", "print", target], text=True)
            if "state = running" not in state:
                raise RuntimeError("Photos exporter agent exited without producing a current status")
        time.sleep(1)


if __name__ == "__main__":
    if sys.argv[1:] == ["--worker"]:
        sys.exit(export())
    if len(sys.argv) == 3 and sys.argv[1] == "--trigger":
        sys.exit(trigger(sys.argv[2]))
    sys.exit("Expected --worker or --trigger <launchd label>")
