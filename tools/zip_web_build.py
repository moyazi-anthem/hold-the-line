"""Zip the web export so it can be uploaded to itch.io.

Run it after exporting (see "Export for itch.io" in the README):

    python tools/zip_web_build.py

It reads build/web/ and writes build/hold-the-line-web.zip. itch.io needs
index.html at the top level of the zip, not inside a folder, so the files are
added with paths relative to build/web/.
"""
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "build" / "web"
TARGET = ROOT / "build" / "hold-the-line-web.zip"


def main() -> int:
    if not (SOURCE / "index.html").is_file():
        print(f"No {SOURCE / 'index.html'}: export the game first (see README).", file=sys.stderr)
        return 1

    with zipfile.ZipFile(TARGET, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(SOURCE.rglob("*")):
            # skip the .import files Godot may leave next to exported images
            if path.is_file() and path.suffix != ".import":
                archive.write(path, path.relative_to(SOURCE).as_posix())

    with zipfile.ZipFile(TARGET) as archive:
        names = archive.namelist()
        if "index.html" not in names:
            print("index.html is not at the top of the zip", file=sys.stderr)
            return 1
        print(f"{TARGET.relative_to(ROOT)}: {len(names)} files, {TARGET.stat().st_size / 1048576:.1f} MB")
        for name in names:
            print(f"  {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
