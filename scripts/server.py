#!/usr/bin/env python3
"""
Claude Sounds Plugin - Web UI Server
Usage: python3 server.py [port] [plugin_root]
"""

import sys
import os
import json
import shutil
import subprocess
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from pathlib import Path
import importlib.util

# ── Paths ──────────────────────────────────────────────────────────────────────

SCRIPT_DIR   = Path(__file__).parent.resolve()
PLUGIN_ROOT  = Path(os.environ.get("CLAUDE_PLUGIN_ROOT", SCRIPT_DIR.parent))
USER_DIR     = Path.home() / ".claude" / "claude-sounds-xapipro"
CONFIG_FILE  = USER_DIR / "config.json"
THEMES_DIR   = USER_DIR / "themes"
CACHE_DIR    = USER_DIR / "cache"
CSTHEME_PY   = SCRIPT_DIR / "cstheme.py"
UI_DIR       = SCRIPT_DIR / "ui"
VALID_HOOKS     = ["stop", "notification", "error", "permission", "permission_request"]
PLUGIN_VERSION  = "1.1.0"

# ── Load cstheme module ────────────────────────────────────────────────────────

spec = importlib.util.spec_from_file_location("cstheme", CSTHEME_PY)
cstheme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cstheme)

# ── Config helpers ─────────────────────────────────────────────────────────────

DEFAULT_CONFIG = {
    "theme": "default",
    "enabled": True,
    "store_url": "https://raw.githubusercontent.com/0xbaiqi/claude-sounds-themes/main",
    "hooks": {"stop": True, "notification": True, "error": True, "permission": False, "permission_request": True}
}

def _init_config():
    if not CONFIG_FILE.exists():
        USER_DIR.mkdir(parents=True, exist_ok=True)
        THEMES_DIR.mkdir(exist_ok=True)
        CONFIG_FILE.write_text(json.dumps(DEFAULT_CONFIG, indent=2) + "\n")

def _read_config():
    _init_config()
    with open(CONFIG_FILE) as f:
        return json.load(f)

def _write_config(cfg):
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")

def _read_project_config(project_path):
    p = Path(project_path) / ".claude" / "sounds.json"
    if p.exists():
        with open(p) as f:
            return json.load(f)
    return {}

def _write_project_config(project_path, data):
    d = Path(project_path) / ".claude"
    d.mkdir(parents=True, exist_ok=True)
    p = d / "sounds.json"
    with open(p, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    # Register project path in global config
    cfg = _read_config()
    projects = cfg.get("projects", [])
    if project_path not in projects:
        projects.append(project_path)
        cfg["projects"] = projects
        _write_config(cfg)

# ── Theme helpers ──────────────────────────────────────────────────────────────

def _theme_info(path):
    try:
        manifest, _ = cstheme._parse(str(path))
        return {
            "name": manifest.get("name", "?"),
            "display_name": manifest.get("display_name", manifest.get("name", "?")),
            "version": manifest.get("version", ""),
            "description": manifest.get("description", ""),
            "author": manifest.get("author", ""),
            "size": os.path.getsize(path),
            "file": Path(path).name,
        }
    except Exception:
        return None

def _list_themes():
    themes = []
    cfg = _read_config()
    current = cfg.get("theme", "default")
    # Built-in
    for f in (PLUGIN_ROOT / "themes").glob("*.cstheme"):
        info = _theme_info(f)
        if info:
            info["builtin"] = True
            info["active"] = (info["name"] == current)
            themes.append(info)
    # User installed
    THEMES_DIR.mkdir(exist_ok=True)
    for f in THEMES_DIR.glob("*.cstheme"):
        info = _theme_info(f)
        if info:
            info["builtin"] = False
            info["active"] = (info["name"] == current)
            themes.append(info)
    return themes

# ── HTTP Handler ───────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass  # suppress access logs

    def _send(self, code, data=None, content_type="application/json"):
        body = json.dumps(data or {}).encode() if content_type == "application/json" else data
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _ok(self, data=None):
        self._send(200, {"ok": True, **(data or {})})

    def _err(self, msg, code=400):
        self._send(code, {"ok": False, "error": msg})

    def _body(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length)) if length else {}

    def _serve_file(self, path):
        ext_map = {
            ".html": "text/html; charset=utf-8",
            ".js":   "application/javascript; charset=utf-8",
            ".css":  "text/css; charset=utf-8",
            ".png":  "image/png",
            ".ico":  "image/x-icon",
        }
        if not path.exists():
            self._err("Not found", 404); return
        ct = ext_map.get(path.suffix, "application/octet-stream")
        data = path.read_bytes()
        self._send(200, data, ct)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path   = parsed.path
        qs     = parse_qs(parsed.query)

        # ── Static files
        if path == "/" or path == "/index.html":
            self._serve_file(UI_DIR / "index.html"); return
        if path.startswith("/") and not path.startswith("/api/"):
            self._serve_file(UI_DIR / path.lstrip("/")); return

        # ── API
        if path == "/api/status":
            cfg = _read_config()
            self._ok({
                "enabled":   cfg.get("enabled", True),
                "theme":     cfg.get("theme", "default"),
                "store_url": cfg.get("store_url", DEFAULT_CONFIG["store_url"]),
                "hooks":     cfg.get("hooks", DEFAULT_CONFIG["hooks"]),
                "version":   PLUGIN_VERSION,
            }); return

        if path == "/api/themes":
            self._ok({"themes": _list_themes()}); return

        if path == "/api/store":
            store_url = _read_config().get("store_url", DEFAULT_CONFIG["store_url"])
            try:
                # fetch-index prints one JSON per line to stdout
                result = subprocess.run(
                    [sys.executable, str(CSTHEME_PY), "fetch-index", store_url],
                    capture_output=True, text=True, timeout=15
                )
                themes = [json.loads(l) for l in result.stdout.strip().splitlines() if l.strip()]
                installed_names = {t["name"] for t in _list_themes()}
                for t in themes:
                    t["installed"] = t["name"] in installed_names
                self._ok({"themes": themes})
            except Exception as e:
                self._err(str(e))
            return

        if path == "/api/cwd":
            self._ok({"cwd": os.getcwd()}); return

        if path == "/api/projects":
            cfg = _read_config()
            cwd = str(Path(os.getcwd()))
            known = cfg.get("projects", [])
            # Always include cwd
            if cwd not in known:
                known = [cwd] + known
            projects = []
            for proj_path in known:
                p = Path(proj_path)
                p_cfg = p / ".claude" / "sounds.json"
                entry = {
                    "path": proj_path,
                    "name": p.name,
                    "is_cwd": proj_path == cwd,
                    "theme": "",
                    "hooks": {},
                    "no_config": not p_cfg.exists(),
                }
                if p_cfg.exists():
                    try:
                        with open(p_cfg) as f:
                            proj_cfg = json.load(f)
                        entry["theme"] = proj_cfg.get("theme", "")
                        entry["hooks"] = proj_cfg.get("hooks", {})
                    except Exception:
                        pass
                projects.append(entry)
            self._ok({"projects": projects}); return

        if path == "/api/project":
            project = qs.get("path", [os.getcwd()])[0]
            data = _read_project_config(project)
            p = Path(project) / ".claude" / "sounds.json"
            self._ok({"config": data, "exists": p.exists(), "path": str(p), "project": project}); return

        self._err("Not found", 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path   = parsed.path
        body   = self._body()

        # ── Enable / disable plugin
        if path == "/api/enable":
            cfg = _read_config()
            cfg["enabled"] = body.get("enabled", True)
            _write_config(cfg)
            self._ok(); return

        # ── Set global theme
        if path == "/api/theme":
            name = body.get("name", "")
            if not name:
                self._err("name required"); return
            cfg = _read_config()
            cfg["theme"] = name
            _write_config(cfg)
            self._ok(); return

        # ── Hook toggle
        if path == "/api/hook":
            hook  = body.get("hook", "")
            value = body.get("enabled", True)
            if hook not in VALID_HOOKS:
                self._err(f"Unknown hook: {hook}"); return
            cfg = _read_config()
            cfg.setdefault("hooks", {})[hook] = value
            _write_config(cfg)
            self._ok(); return

        # ── Install from store
        if path == "/api/store/install":
            name = body.get("name", "")
            if not name:
                self._err("name required"); return
            store_url = _read_config().get("store_url", DEFAULT_CONFIG["store_url"])
            try:
                # find file path in index
                result = subprocess.run(
                    [sys.executable, str(CSTHEME_PY), "fetch-index", store_url],
                    capture_output=True, text=True, timeout=15
                )
                file_path = ""
                for line in result.stdout.strip().splitlines():
                    t = json.loads(line)
                    if t.get("name") == name:
                        file_path = t.get("file", "")
                        break
                if not file_path:
                    self._err(f"Theme '{name}' not found in store"); return
                url = f"{store_url}/{file_path}"
                import tempfile
                with tempfile.NamedTemporaryFile(suffix=".cstheme", delete=False) as tmp:
                    tmp_path = tmp.name
                subprocess.run(
                    [sys.executable, str(CSTHEME_PY), "download", url, tmp_path],
                    check=True, timeout=30
                )
                subprocess.run(
                    [sys.executable, str(CSTHEME_PY), "validate", tmp_path],
                    check=True
                )
                THEMES_DIR.mkdir(exist_ok=True)
                subprocess.run(
                    [sys.executable, str(CSTHEME_PY), "install", tmp_path, str(THEMES_DIR)],
                    check=True
                )
                os.unlink(tmp_path)
                self._ok({"message": f"Installed: {name}"}); return
            except subprocess.CalledProcessError as e:
                self._err(str(e))
            except Exception as e:
                self._err(str(e))
            return

        # ── Install local .cstheme (multipart upload)
        if path == "/api/theme/upload":
            import tempfile
            ct = self.headers.get("Content-Type", "")
            if "multipart/form-data" not in ct:
                self._err("Expected multipart/form-data"); return
            try:
                length = int(self.headers.get("Content-Length", 0))
                raw = self.rfile.read(length)
                # Extract boundary
                boundary = ct.split("boundary=")[-1].strip().encode()
                parts = raw.split(b"--" + boundary)
                for part in parts:
                    if b"filename=" not in part:
                        continue
                    # Split headers from body
                    header_end = part.find(b"\r\n\r\n")
                    if header_end == -1:
                        continue
                    file_data = part[header_end + 4:]
                    if file_data.endswith(b"\r\n"):
                        file_data = file_data[:-2]
                    with tempfile.NamedTemporaryFile(suffix=".cstheme", delete=False) as tmp:
                        tmp.write(file_data)
                        tmp_path = tmp.name
                    subprocess.run(
                        [sys.executable, str(CSTHEME_PY), "validate", tmp_path],
                        check=True
                    )
                    THEMES_DIR.mkdir(exist_ok=True)
                    subprocess.run(
                        [sys.executable, str(CSTHEME_PY), "install", tmp_path, str(THEMES_DIR)],
                        check=True
                    )
                    os.unlink(tmp_path)
                    self._ok({"message": "Installed"}); return
                self._err("No file found in upload")
            except subprocess.CalledProcessError:
                self._err("Invalid .cstheme file")
            except Exception as e:
                self._err(str(e))
            return

        # ── Project config
        if path == "/api/project/theme":
            project = body.get("path", os.getcwd())
            name    = body.get("name", "")
            data = _read_project_config(project)
            if name:
                data["theme"] = name
            else:
                data.pop("theme", None)
            _write_project_config(project, data)
            self._ok(); return

        if path == "/api/project/hook":
            project = body.get("path", os.getcwd())
            hook    = body.get("hook", "")
            value   = body.get("enabled", True)
            if hook not in VALID_HOOKS:
                self._err(f"Unknown hook: {hook}"); return
            data = _read_project_config(project)
            data.setdefault("hooks", {})[hook] = value
            _write_project_config(project, data)
            self._ok(); return

        if path == "/api/project/hook/clear":
            project = body.get("path", os.getcwd())
            hook    = body.get("hook", "")
            if hook not in VALID_HOOKS:
                self._err(f"Unknown hook: {hook}"); return
            data = _read_project_config(project)
            data.get("hooks", {}).pop(hook, None)
            if not data.get("hooks"):
                data.pop("hooks", None)
            _write_project_config(project, data)
            self._ok(); return

        if path == "/api/project/clear":
            project = body.get("path", os.getcwd())
            p = Path(project) / ".claude" / "sounds.json"
            if p.exists():
                p.unlink()
            self._ok(); return

        # ── Preview theme sound
        if path == "/api/theme/preview":
            name  = body.get("name", "")
            sound = body.get("sound", "notification")
            if not name:
                self._err("name required"); return
            # Resolve .cstheme file
            theme_file = THEMES_DIR / f"{name}.cstheme"
            if not theme_file.exists():
                theme_file = PLUGIN_ROOT / "themes" / f"{name}.cstheme"
            if not theme_file.exists():
                self._err(f"Theme '{name}' not found"); return
            # Extract to cache if needed
            cache_dir    = CACHE_DIR / name
            cache_marker = cache_dir / ".cached"
            need_refresh = (not cache_marker.exists() or
                            theme_file.stat().st_mtime > cache_marker.stat().st_mtime)
            if need_refresh:
                cache_dir.mkdir(parents=True, exist_ok=True)
                subprocess.run(
                    [sys.executable, str(CSTHEME_PY), "extract", str(theme_file), str(cache_dir)],
                    check=True
                )
                cache_marker.touch()
            sound_file = cache_dir / f"{sound}.mp3"
            if not sound_file.exists():
                self._err(f"{sound}.mp3 not found in theme"); return
            # Play asynchronously
            import platform
            system = platform.system()
            try:
                if system == "Darwin":
                    subprocess.Popen(["afplay", str(sound_file)],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                elif system == "Windows":
                    subprocess.Popen(
                        ["powershell", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
                         "-Command",
                         f"Add-Type -AssemblyName PresentationCore; "
                         f"$m=[System.Windows.Media.MediaPlayer]::new(); "
                         f"$m.Open([Uri]::new('file:///{str(sound_file)}')); "
                         f"$m.Play(); Start-Sleep 5"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                else:
                    if shutil.which("paplay"):
                        subprocess.Popen(["paplay", str(sound_file)],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    elif shutil.which("aplay"):
                        subprocess.Popen(["aplay", str(sound_file)],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception as e:
                self._err(str(e)); return
            self._ok(); return

        # ── Cache clear
        if path == "/api/cache/clear":
            name = body.get("name", "")
            if name:
                shutil.rmtree(CACHE_DIR / name, ignore_errors=True)
            else:
                shutil.rmtree(CACHE_DIR, ignore_errors=True)
            self._ok(); return

        if path == "/api/shutdown":
            self._ok({"message": "Shutting down..."})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return

        self._err("Not found", 404)

    def do_DELETE(self):
        parsed = urlparse(self.path)
        path   = parsed.path

        if path.startswith("/api/theme/"):
            name = path.split("/api/theme/")[-1]
            if not name:
                self._err("name required"); return
            try:
                subprocess.run(
                    [sys.executable, str(CSTHEME_PY), "remove", name,
                     str(THEMES_DIR), str(CACHE_DIR)],
                    check=True
                )
                self._ok()
            except subprocess.CalledProcessError as e:
                self._err(str(e))
            return

        self._err("Not found", 404)


# ── Open browser ───────────────────────────────────────────────────────────────

def _open_browser(url):
    time.sleep(0.5)
    import platform
    system = platform.system()
    try:
        if system == "Darwin":
            subprocess.Popen(["open", url])
        elif system == "Windows":
            subprocess.Popen(["cmd", "/c", "start", url], shell=True)
        else:
            subprocess.Popen(["xdg-open", url])
    except Exception:
        pass


# ── Main ───────────────────────────────────────────────────────────────────────

def _is_our_server(port):
    """Check if our server is already running on this port."""
    try:
        import urllib.request
        with urllib.request.urlopen(f"http://localhost:{port}/api/status", timeout=2) as r:
            data = json.loads(r.read())
            return data.get("ok") is True
    except Exception:
        return False

def _find_free_port(start, attempts=10):
    """Find a free port starting from `start`."""
    import socket
    for port in range(start, start + attempts):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    return None

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 52437
    if len(sys.argv) > 2:
        PLUGIN_ROOT = Path(sys.argv[2])

    _init_config()

    # If our server is already running on the requested port, just open browser
    if _is_our_server(port):
        url = f"http://localhost:{port}"
        print(f"Claude Sounds UI already running → {url}")
        _open_browser(url)
        sys.exit(0)

    # Find a free port
    free_port = _find_free_port(port)
    if free_port is None:
        print(f"Error: No free port found in range {port}-{port+9}", file=sys.stderr)
        sys.exit(1)

    if free_port != port:
        print(f"Port {port} is in use, using {free_port} instead.")

    server = HTTPServer(("127.0.0.1", free_port), Handler)
    url = f"http://localhost:{free_port}"
    print(f"Claude Sounds UI → {url}")
    print("Press Ctrl+C to stop.")

    threading.Thread(target=_open_browser, args=(url,), daemon=True).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
