#!/usr/bin/env python3
"""
cstheme.py - Claude Sounds Theme Package Tool

File format:
  [8  bytes] Magic: b"CSTHEME\x01"
  [64 bytes] SHA256 hex digest of ZIP content
  [N  bytes] ZIP archive (manifest.json + *.mp3, ZIP_STORED)
"""

import sys, os, io, zipfile, hashlib, json, shutil

MAGIC        = b"CSTHEME\x01"
HEADER_SIZE  = 72   # 8 magic + 64 sha256
REQUIRED     = ["stop", "notification", "error", "permission"]


# ── Format helpers ─────────────────────────────────────────────────────────────

def _build(zip_data: bytes) -> bytes:
    """Prepend magic + checksum to ZIP bytes."""
    checksum = hashlib.sha256(zip_data).hexdigest().encode()   # 64 bytes
    return MAGIC + checksum + zip_data


def _parse(path: str) -> tuple[dict, bytes]:
    """
    Read and validate a .cstheme file.
    Returns (manifest_dict, zip_bytes) or exits with error.
    """
    with open(path, "rb") as f:
        raw = f.read()

    if len(raw) < HEADER_SIZE or raw[:8] != MAGIC:
        _die(f"Not a valid .cstheme file: {path}")

    stored   = raw[8:72]
    zip_data = raw[72:]
    actual   = hashlib.sha256(zip_data).hexdigest().encode()

    if actual != stored:
        _die(f"Checksum mismatch — file may be corrupted: {path}")

    try:
        with zipfile.ZipFile(io.BytesIO(zip_data)) as zf:
            with zf.open("manifest.json") as mf:
                manifest = json.load(mf)
    except Exception as e:
        _die(f"Cannot read manifest: {e}")

    return manifest, zip_data


def _die(msg: str):
    print(f"Error: {msg}", file=sys.stderr)
    sys.exit(1)


# ── Commands ───────────────────────────────────────────────────────────────────

def cmd_pack(source_dir: str, output_path: str):
    """Pack a theme directory into a .cstheme file."""
    manifest_path = os.path.join(source_dir, "manifest.json")
    if not os.path.exists(manifest_path):
        _die(f"manifest.json not found in {source_dir}")

    with open(manifest_path) as f:
        manifest = json.load(f)

    missing = [s for s in REQUIRED if not os.path.exists(os.path.join(source_dir, f"{s}.mp3"))]
    if missing:
        _die(f"Missing audio files: {', '.join(m + '.mp3' for m in missing)}")

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as zf:
        zf.write(manifest_path, "manifest.json")
        for sound in REQUIRED:
            mp3 = os.path.join(source_dir, f"{sound}.mp3")
            zf.write(mp3, f"{sound}.mp3")

    data = _build(buf.getvalue())
    with open(output_path, "wb") as f:
        f.write(data)

    name = manifest.get("name", os.path.basename(source_dir))
    size = os.path.getsize(output_path)
    print(f"Packed theme '{name}' → {output_path}  ({size:,} bytes)")


def cmd_validate(path: str):
    """Validate a .cstheme file and print its manifest."""
    manifest, _ = _parse(path)
    print(json.dumps(manifest, indent=2, ensure_ascii=False))
    print("✓ Valid .cstheme file")


def cmd_install(src_path: str, themes_dir: str):
    """Validate and copy a .cstheme into the themes directory."""
    manifest, _ = _parse(src_path)
    name = manifest.get("name") or _die("manifest.json missing 'name' field")
    os.makedirs(themes_dir, exist_ok=True)
    dest = os.path.join(themes_dir, f"{name}.cstheme")
    shutil.copy2(src_path, dest)
    print(f"Installed theme '{name}'")
    print(f"  → {dest}")


def cmd_extract(cstheme_path: str, cache_dir: str):
    """Extract audio files from .cstheme into cache directory."""
    _, zip_data = _parse(cstheme_path)
    os.makedirs(cache_dir, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(zip_data)) as zf:
        for name in zf.namelist():
            if name.endswith(".mp3"):
                data = zf.read(name)
                with open(os.path.join(cache_dir, os.path.basename(name)), "wb") as f:
                    f.write(data)


def cmd_list(themes_dir: str):
    """List all installed themes as JSON lines."""
    if not os.path.exists(themes_dir):
        return
    for fname in sorted(os.listdir(themes_dir)):
        if not fname.endswith(".cstheme"):
            continue
        path = os.path.join(themes_dir, fname)
        try:
            manifest, _ = _parse(path)
            size = os.path.getsize(path)
            manifest["_size"] = size
            manifest["_file"] = fname
            print(json.dumps(manifest, ensure_ascii=False))
        except SystemExit:
            print(json.dumps({"name": fname[:-8], "_error": "invalid or corrupted"}))


def cmd_remove(name: str, themes_dir: str, cache_dir: str):
    """Remove a theme and its cache."""
    removed = False
    pkg = os.path.join(themes_dir, f"{name}.cstheme")
    if os.path.exists(pkg):
        os.remove(pkg)
        print(f"Removed: {pkg}")
        removed = True
    cache = os.path.join(cache_dir, name)
    if os.path.isdir(cache):
        shutil.rmtree(cache)
        print(f"Removed cache: {cache}")
        removed = True
    if not removed:
        _die(f"Theme '{name}' not found")


# ── Entry point ────────────────────────────────────────────────────────────────

def cmd_download(url: str, output_path: str, show_progress: bool = True):
    """Download a file from URL using urllib (no extra dependencies)."""
    import urllib.request
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            total = int(resp.headers.get("Content-Length", 0))
            downloaded = 0
            chunk = 8192
            with open(output_path, "wb") as f:
                while True:
                    data = resp.read(chunk)
                    if not data:
                        break
                    f.write(data)
                    downloaded += len(data)
                    if show_progress and total:
                        pct = downloaded * 100 // total
                        print(f"\r  Downloading... {pct}%", end="", flush=True)
            if show_progress and total:
                print()
    except Exception as e:
        _die(f"Download failed: {e}")


def cmd_fetch_index(index_url: str) -> list:
    """Fetch and parse index.json from store URL. Returns themes list."""
    import urllib.request
    url = index_url.rstrip("/") + "/index.json"
    try:
        with urllib.request.urlopen(url, timeout=15) as resp:
            data = json.load(resp)
        return data.get("themes", [])
    except Exception as e:
        _die(f"Cannot fetch store index: {e}")


USAGE = """Usage: cstheme.py <command> [args]

Commands:
  pack      <source-dir> <output.cstheme>        Pack theme directory
  validate  <file.cstheme>                       Validate and show manifest
  install   <file.cstheme> <themes-dir>          Install theme
  extract   <file.cstheme> <cache-dir>           Extract audio to cache
  list      <themes-dir>                         List installed themes (JSON lines)
  remove    <name> <themes-dir> <cache-dir>      Remove theme and cache
  download  <url> <output-path>                  Download file from URL
  fetch-index <index-url>                        Fetch store index (JSON lines)
"""

if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        print(USAGE); sys.exit(1)

    cmd = args[0]
    if   cmd == "pack"         and len(args) == 3: cmd_pack(args[1], args[2])
    elif cmd == "validate"     and len(args) == 2: cmd_validate(args[1])
    elif cmd == "install"      and len(args) == 3: cmd_install(args[1], args[2])
    elif cmd == "extract"      and len(args) == 3: cmd_extract(args[1], args[2])
    elif cmd == "list"         and len(args) == 2: cmd_list(args[1])
    elif cmd == "remove"       and len(args) == 4: cmd_remove(args[1], args[2], args[3])
    elif cmd == "download"     and len(args) == 3: cmd_download(args[1], args[2])
    elif cmd == "fetch-index"  and len(args) == 2:
        themes = cmd_fetch_index(args[1])
        for t in themes:
            print(json.dumps(t, ensure_ascii=False))
    else:
        print(USAGE); sys.exit(1)
