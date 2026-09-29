"""Export the Hackintosh Photos library; only the ZFS receiver retains deleted photos."""

import fcntl
import importlib
import json
import os
from dataclasses import replace
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import time


def summarize(report):
    # A zero exit status from osxphotos does not imply that all files were exported.
    if not isinstance(report, list) or not report:
        raise ValueError("Photos export report is empty or invalid")
    missing = sum(bool(row["missing"]) for row in report)
    errors = sum(
        bool(row["error"] or row["sidecar_user_error"] or row["exiftool_error"] or row["user_error"]) for row in report
    )
    return missing, errors


def stage_missing(self, options):
    # OSXPhotos 0.77.1's PhotoKit LivePhoto exporter documents that requesting
    # originals can yield the edited movie. Photos' original AppleScript export
    # preserves it; PhotoKit is needed for edited movies and missing burst members.
    if self.photo.live_photo and not options.edited:
        return self._stage_photo_for_export_with_applescript(options=options)
    return self._stage_photo_for_export_with_photokit(options=options)


def configure_osxphotos():
    import osxphotos
    from osxphotos.photoexporter import PhotoExporter
    from osxphotos.photokit import LivePhotoAsset, PhotoLibrary

    if osxphotos.__version__ != "0.77.1":
        raise RuntimeError("Revalidate the original Live Photo workaround before upgrading OSXPhotos")

    class ArchivePhotoExporter(PhotoExporter):
        _stage_missing_photos_for_export_helper = stage_missing

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
    volume = Path("/Volumes/Photos")
    library = volume / "Photos Library.photoslibrary"
    destination = volume / "icloud-export"
    info = plistlib.loads(subprocess.check_output(["/usr/sbin/diskutil", "info", "-plist", str(volume)]))
    if info.get("VolumeUUID") != "560D9DAE-6BB6-4291-9B17-848609B942C8" or info.get("MountPoint") != str(volume):
        raise RuntimeError("The expected Photos APFS volume is not mounted")
    if not (library / "database/Photos.sqlite").is_file():
        raise RuntimeError("The Photos library is missing")

    destination.mkdir(exist_ok=True)
    # Also protect against a disconnected SSH command still finishing an export.
    with (destination / ".backup.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # Open the actual library before AppleScript requests arrive at startup.
        subprocess.run(["/usr/bin/open", "-a", "Photos", str(library)], check=True)
        report_path = destination / ".export-report.json"
        status_path = destination / ".backup-status.json"
        report_path.unlink(missing_ok=True)
        status_path.unlink(missing_ok=True)
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
        disk = shutil.disk_usage(volume)
        status = {
            "completed_at": int(time.time()),
            "missing": missing,
            "errors": errors,
            "apfs_used_ratio": disk.used / disk.total,
            "complete": missing == 0 and errors == 0,
        }
        status_path.write_text(json.dumps(status) + "\n")
        print(json.dumps(status), flush=True)
        return 0 if status["complete"] else 1


def run_in_terminal():
    # PhotoKit denies SSH's execution context. Terminal is the authorized GUI
    # application, and this SSH launcher waits for its actual exit status.
    with tempfile.TemporaryDirectory(prefix="icloud-photos-") as temporary:
        log_path = Path(temporary) / "export.log"
        exit_path = Path(temporary) / "exit-status"
        exit_temporary = Path(temporary) / "exit-status.tmp"
        command = (
            f"{shlex.join([sys.executable, str(Path(__file__).resolve()), '--worker'])} "
            f"> {shlex.quote(str(log_path))} 2>&1; "
            f"printf '%s\\n' \"$?\" > {shlex.quote(str(exit_temporary))}; "
            f"/bin/mv {shlex.quote(str(exit_temporary))} {shlex.quote(str(exit_path))}"
        )
        window = subprocess.check_output(
            ["/usr/bin/osascript", "-", command],
            input="""on run argv
tell application "Terminal"
    do script (item 1 of argv)
    return id of front window
end tell
end run
""",
            text=True,
        ).strip()
        window_id = int(window)
        offset = 0
        print("Exporting in the authorized Terminal session", flush=True)
        while True:
            if log_path.exists():
                with log_path.open(errors="replace") as log:
                    log.seek(offset)
                    print(log.read(), end="", flush=True)
                    offset = log.tell()
            if exit_path.exists():
                result = int(exit_path.read_text())
                subprocess.run(
                    ["/usr/bin/osascript", "-e", f'tell application "Terminal" to close window id {window_id}'],
                    check=False,
                    capture_output=True,
                )
                return result
            time.sleep(1)


if __name__ == "__main__":
    sys.exit(export() if sys.argv[1:] == ["--worker"] else run_in_terminal())
