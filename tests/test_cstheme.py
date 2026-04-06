"""
Tests for cstheme.py — Claude Sounds Theme Package Tool

Run:  python3 -m pytest tests/test_cstheme.py -v
"""

import hashlib
import io
import json
import os
import shutil
import sys
import tempfile
import zipfile

import pytest

# Add scripts/ to path so we can import cstheme
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
import cstheme


# ── Fixtures ──────────────────────────────────────────────────────────────────


@pytest.fixture
def tmp_dir():
    """Create a temp directory, clean up after test."""
    d = tempfile.mkdtemp(prefix="cstheme-test-")
    yield d
    shutil.rmtree(d, ignore_errors=True)


@pytest.fixture
def sample_theme_dir(tmp_dir):
    """Create a valid theme directory with manifest + 4 dummy mp3 files."""
    theme_dir = os.path.join(tmp_dir, "testtheme")
    os.makedirs(theme_dir)

    manifest = {
        "name": "testtheme",
        "display_name": "Test Theme",
        "version": "1.0.0",
        "description": "A test theme",
        "author": "tester",
    }
    with open(os.path.join(theme_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f)

    for sound in cstheme.REQUIRED:
        # Create small fake mp3 (just some bytes, not real audio)
        with open(os.path.join(theme_dir, f"{sound}.mp3"), "wb") as f:
            f.write(f"FAKE-MP3-{sound}".encode() * 100)

    return theme_dir


@pytest.fixture
def sample_cstheme(sample_theme_dir, tmp_dir):
    """Pack sample theme dir into a .cstheme file and return its path."""
    output = os.path.join(tmp_dir, "testtheme.cstheme")
    cstheme.cmd_pack(sample_theme_dir, output)
    return output


# ── Format helpers ────────────────────────────────────────────────────────────


class TestBuild:
    def test_prepends_magic(self):
        data = b"some-zip-data"
        result = cstheme._build(data)
        assert result[:8] == cstheme.MAGIC

    def test_includes_sha256_checksum(self):
        data = b"some-zip-data"
        result = cstheme._build(data)
        expected = hashlib.sha256(data).hexdigest().encode()
        assert result[8:72] == expected

    def test_appends_zip_data(self):
        data = b"some-zip-data"
        result = cstheme._build(data)
        assert result[72:] == data

    def test_total_header_size(self):
        data = b"x"
        result = cstheme._build(data)
        assert len(result) == cstheme.HEADER_SIZE + len(data)


class TestParse:
    def test_valid_file(self, sample_cstheme):
        manifest, zip_data = cstheme._parse(sample_cstheme)
        assert manifest["name"] == "testtheme"
        assert manifest["version"] == "1.0.0"
        assert len(zip_data) > 0

    def test_rejects_too_small_file(self, tmp_dir):
        path = os.path.join(tmp_dir, "small.cstheme")
        with open(path, "wb") as f:
            f.write(b"tiny")
        with pytest.raises(SystemExit):
            cstheme._parse(path)

    def test_rejects_wrong_magic(self, tmp_dir):
        path = os.path.join(tmp_dir, "bad.cstheme")
        with open(path, "wb") as f:
            f.write(b"NOTCSTHM" + b"\x00" * 64 + b"zipdata")
        with pytest.raises(SystemExit):
            cstheme._parse(path)

    def test_rejects_corrupted_checksum(self, sample_cstheme):
        with open(sample_cstheme, "rb") as f:
            raw = bytearray(f.read())
        # Corrupt one byte in the ZIP data
        raw[-1] ^= 0xFF
        with open(sample_cstheme, "wb") as f:
            f.write(raw)
        with pytest.raises(SystemExit):
            cstheme._parse(sample_cstheme)

    def test_rejects_tampered_checksum(self, sample_cstheme):
        with open(sample_cstheme, "rb") as f:
            raw = bytearray(f.read())
        # Tamper checksum (byte at index 10)
        raw[10] ^= 0xFF
        with open(sample_cstheme, "wb") as f:
            f.write(raw)
        with pytest.raises(SystemExit):
            cstheme._parse(sample_cstheme)

    def test_rejects_random_binary(self, tmp_dir):
        path = os.path.join(tmp_dir, "random.cstheme")
        with open(path, "wb") as f:
            f.write(os.urandom(500))
        with pytest.raises(SystemExit):
            cstheme._parse(path)


# ── cmd_pack ──────────────────────────────────────────────────────────────────


class TestPack:
    def test_creates_file(self, sample_theme_dir, tmp_dir):
        output = os.path.join(tmp_dir, "out.cstheme")
        cstheme.cmd_pack(sample_theme_dir, output)
        assert os.path.exists(output)

    def test_file_starts_with_magic(self, sample_cstheme):
        with open(sample_cstheme, "rb") as f:
            assert f.read(8) == cstheme.MAGIC

    def test_file_has_correct_checksum(self, sample_cstheme):
        with open(sample_cstheme, "rb") as f:
            raw = f.read()
        stored = raw[8:72]
        actual = hashlib.sha256(raw[72:]).hexdigest().encode()
        assert stored == actual

    def test_zip_contains_manifest(self, sample_cstheme):
        with open(sample_cstheme, "rb") as f:
            zip_data = f.read()[72:]
        with zipfile.ZipFile(io.BytesIO(zip_data)) as zf:
            assert "manifest.json" in zf.namelist()

    def test_zip_contains_all_mp3s(self, sample_cstheme):
        with open(sample_cstheme, "rb") as f:
            zip_data = f.read()[72:]
        with zipfile.ZipFile(io.BytesIO(zip_data)) as zf:
            names = zf.namelist()
            for sound in cstheme.REQUIRED:
                assert f"{sound}.mp3" in names

    def test_zip_no_extra_files(self, sample_cstheme):
        with open(sample_cstheme, "rb") as f:
            zip_data = f.read()[72:]
        with zipfile.ZipFile(io.BytesIO(zip_data)) as zf:
            # manifest + 4 mp3s = 5 files
            assert len(zf.namelist()) == 5

    def test_fails_without_manifest(self, tmp_dir):
        theme = os.path.join(tmp_dir, "nomanifest")
        os.makedirs(theme)
        for s in cstheme.REQUIRED:
            with open(os.path.join(theme, f"{s}.mp3"), "wb") as f:
                f.write(b"data")
        with pytest.raises(SystemExit):
            cstheme.cmd_pack(theme, os.path.join(tmp_dir, "out.cstheme"))

    def test_fails_with_missing_mp3(self, tmp_dir):
        theme = os.path.join(tmp_dir, "missingmp3")
        os.makedirs(theme)
        with open(os.path.join(theme, "manifest.json"), "w") as f:
            json.dump({"name": "test"}, f)
        # Only create 2 of 4 mp3s
        for s in cstheme.REQUIRED[:2]:
            with open(os.path.join(theme, f"{s}.mp3"), "wb") as f:
                f.write(b"data")
        with pytest.raises(SystemExit):
            cstheme.cmd_pack(theme, os.path.join(tmp_dir, "out.cstheme"))


# ── cmd_validate ──────────────────────────────────────────────────────────────


class TestValidate:
    def test_valid_file_passes(self, sample_cstheme, capsys):
        cstheme.cmd_validate(sample_cstheme)
        out = capsys.readouterr().out
        assert "Valid .cstheme file" in out
        assert "testtheme" in out

    def test_invalid_file_exits(self, tmp_dir):
        path = os.path.join(tmp_dir, "bad.cstheme")
        with open(path, "wb") as f:
            f.write(b"not a theme file")
        with pytest.raises(SystemExit):
            cstheme.cmd_validate(path)


# ── cmd_extract ───────────────────────────────────────────────────────────────


class TestExtract:
    def test_extracts_all_mp3s(self, sample_cstheme, tmp_dir):
        cache = os.path.join(tmp_dir, "cache")
        cstheme.cmd_extract(sample_cstheme, cache)
        for sound in cstheme.REQUIRED:
            assert os.path.exists(os.path.join(cache, f"{sound}.mp3"))

    def test_does_not_extract_manifest(self, sample_cstheme, tmp_dir):
        cache = os.path.join(tmp_dir, "cache")
        cstheme.cmd_extract(sample_cstheme, cache)
        assert not os.path.exists(os.path.join(cache, "manifest.json"))

    def test_creates_cache_dir(self, sample_cstheme, tmp_dir):
        cache = os.path.join(tmp_dir, "nonexistent", "deep", "cache")
        cstheme.cmd_extract(sample_cstheme, cache)
        assert os.path.isdir(cache)

    def test_extracted_content_matches_original(self, sample_theme_dir, sample_cstheme, tmp_dir):
        cache = os.path.join(tmp_dir, "cache")
        cstheme.cmd_extract(sample_cstheme, cache)
        for sound in cstheme.REQUIRED:
            orig = os.path.join(sample_theme_dir, f"{sound}.mp3")
            extr = os.path.join(cache, f"{sound}.mp3")
            with open(orig, "rb") as a, open(extr, "rb") as b:
                assert a.read() == b.read(), f"{sound}.mp3 content mismatch"


# ── cmd_install ───────────────────────────────────────────────────────────────


class TestInstall:
    def test_copies_to_themes_dir(self, sample_cstheme, tmp_dir):
        themes = os.path.join(tmp_dir, "themes")
        cstheme.cmd_install(sample_cstheme, themes)
        assert os.path.exists(os.path.join(themes, "testtheme.cstheme"))

    def test_creates_themes_dir(self, sample_cstheme, tmp_dir):
        themes = os.path.join(tmp_dir, "new", "themes")
        cstheme.cmd_install(sample_cstheme, themes)
        assert os.path.isdir(themes)

    def test_installed_file_identical(self, sample_cstheme, tmp_dir):
        themes = os.path.join(tmp_dir, "themes")
        cstheme.cmd_install(sample_cstheme, themes)
        with open(sample_cstheme, "rb") as a:
            orig = a.read()
        with open(os.path.join(themes, "testtheme.cstheme"), "rb") as b:
            copy = b.read()
        assert orig == copy

    def test_rejects_invalid_cstheme(self, tmp_dir):
        bad = os.path.join(tmp_dir, "bad.cstheme")
        with open(bad, "wb") as f:
            f.write(b"not valid")
        with pytest.raises(SystemExit):
            cstheme.cmd_install(bad, os.path.join(tmp_dir, "themes"))


# ── cmd_list ──────────────────────────────────────────────────────────────────


class TestList:
    def test_lists_installed_themes(self, sample_cstheme, tmp_dir, capsys):
        themes = os.path.join(tmp_dir, "themes")
        cstheme.cmd_install(sample_cstheme, themes)
        capsys.readouterr()  # clear prior output
        cstheme.cmd_list(themes)
        out = capsys.readouterr().out
        data = json.loads(out.strip())
        assert data["name"] == "testtheme"
        assert data["_file"] == "testtheme.cstheme"
        assert "_size" in data

    def test_empty_dir(self, tmp_dir, capsys):
        themes = os.path.join(tmp_dir, "empty")
        os.makedirs(themes)
        cstheme.cmd_list(themes)
        assert capsys.readouterr().out == ""

    def test_nonexistent_dir(self, tmp_dir, capsys):
        cstheme.cmd_list(os.path.join(tmp_dir, "nope"))
        assert capsys.readouterr().out == ""

    def test_skips_non_cstheme_files(self, tmp_dir, capsys):
        themes = os.path.join(tmp_dir, "themes")
        os.makedirs(themes)
        with open(os.path.join(themes, "readme.txt"), "w") as f:
            f.write("not a theme")
        cstheme.cmd_list(themes)
        assert capsys.readouterr().out == ""

    def test_handles_corrupted_file(self, tmp_dir, capsys):
        themes = os.path.join(tmp_dir, "themes")
        os.makedirs(themes)
        with open(os.path.join(themes, "broken.cstheme"), "wb") as f:
            f.write(b"garbage data")
        cstheme.cmd_list(themes)
        out = capsys.readouterr().out
        data = json.loads(out.strip())
        assert data["_error"] == "invalid or corrupted"

    def test_multiple_themes(self, sample_theme_dir, tmp_dir, capsys):
        themes = os.path.join(tmp_dir, "themes")
        os.makedirs(themes)
        # Create two themes
        for name in ["alpha", "beta"]:
            manifest_path = os.path.join(sample_theme_dir, "manifest.json")
            with open(manifest_path, "w") as f:
                json.dump({"name": name, "version": "1.0.0"}, f)
            out_path = os.path.join(tmp_dir, f"{name}.cstheme")
            cstheme.cmd_pack(sample_theme_dir, out_path)
            cstheme.cmd_install(out_path, themes)

        capsys.readouterr()  # clear prior output
        cstheme.cmd_list(themes)
        lines = [l for l in capsys.readouterr().out.strip().split("\n") if l]
        assert len(lines) == 2
        names = {json.loads(l)["name"] for l in lines}
        assert names == {"alpha", "beta"}


# ── cmd_remove ────────────────────────────────────────────────────────────────


class TestRemove:
    def test_removes_theme_file(self, sample_cstheme, tmp_dir):
        themes = os.path.join(tmp_dir, "themes")
        cache = os.path.join(tmp_dir, "cache")
        cstheme.cmd_install(sample_cstheme, themes)
        assert os.path.exists(os.path.join(themes, "testtheme.cstheme"))
        cstheme.cmd_remove("testtheme", themes, cache)
        assert not os.path.exists(os.path.join(themes, "testtheme.cstheme"))

    def test_removes_cache_dir(self, sample_cstheme, tmp_dir):
        themes = os.path.join(tmp_dir, "themes")
        cache = os.path.join(tmp_dir, "cache")
        cstheme.cmd_install(sample_cstheme, themes)
        cstheme.cmd_extract(sample_cstheme, os.path.join(cache, "testtheme"))
        assert os.path.isdir(os.path.join(cache, "testtheme"))
        cstheme.cmd_remove("testtheme", themes, cache)
        assert not os.path.isdir(os.path.join(cache, "testtheme"))

    def test_fails_for_nonexistent(self, tmp_dir):
        with pytest.raises(SystemExit):
            cstheme.cmd_remove("nope", tmp_dir, tmp_dir)


# ── Round-trip ────────────────────────────────────────────────────────────────


class TestRoundTrip:
    def test_pack_validate_extract_matches(self, sample_theme_dir, tmp_dir):
        """Full round-trip: pack → validate → extract → compare files."""
        packed = os.path.join(tmp_dir, "roundtrip.cstheme")
        cache = os.path.join(tmp_dir, "roundtrip-cache")

        # Pack
        cstheme.cmd_pack(sample_theme_dir, packed)

        # Validate
        manifest, _ = cstheme._parse(packed)
        assert manifest["name"] == "testtheme"

        # Extract
        cstheme.cmd_extract(packed, cache)

        # Compare all mp3s
        for sound in cstheme.REQUIRED:
            orig = os.path.join(sample_theme_dir, f"{sound}.mp3")
            extr = os.path.join(cache, f"{sound}.mp3")
            assert os.path.exists(extr)
            with open(orig, "rb") as a, open(extr, "rb") as b:
                assert a.read() == b.read()

    def test_pack_install_extract(self, sample_theme_dir, tmp_dir):
        """Pack → install → extract from installed copy."""
        packed = os.path.join(tmp_dir, "rt.cstheme")
        themes = os.path.join(tmp_dir, "themes")
        cache = os.path.join(tmp_dir, "cache")

        cstheme.cmd_pack(sample_theme_dir, packed)
        cstheme.cmd_install(packed, themes)

        installed = os.path.join(themes, "testtheme.cstheme")
        cstheme.cmd_extract(installed, cache)

        for sound in cstheme.REQUIRED:
            assert os.path.exists(os.path.join(cache, f"{sound}.mp3"))


# ── cmd_download (with mock server) ──────────────────────────────────────────


class TestDownload:
    def test_downloads_file(self, sample_cstheme, tmp_dir):
        """Test download using a local HTTP server."""
        import http.server
        import threading

        serve_dir = os.path.dirname(sample_cstheme)

        class Handler(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, directory=serve_dir, **kwargs)
            def log_message(self, *args):
                pass  # suppress output

        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        try:
            fname = os.path.basename(sample_cstheme)
            url = f"http://127.0.0.1:{port}/{fname}"
            dest = os.path.join(tmp_dir, "downloaded.cstheme")
            cstheme.cmd_download(url, dest, show_progress=False)

            with open(sample_cstheme, "rb") as a, open(dest, "rb") as b:
                assert a.read() == b.read()
        finally:
            server.shutdown()

    def test_download_bad_url(self, tmp_dir):
        dest = os.path.join(tmp_dir, "fail.cstheme")
        with pytest.raises(SystemExit):
            cstheme.cmd_download("http://127.0.0.1:1/nonexistent", dest, show_progress=False)


# ── cmd_fetch_index (with mock server) ────────────────────────────────────────


class TestFetchIndex:
    def test_fetches_and_parses(self, tmp_dir):
        import http.server
        import threading

        index = {
            "version": "1",
            "themes": [
                {"name": "foo", "version": "1.0.0", "file": "foo/foo.cstheme"}
            ],
        }
        with open(os.path.join(tmp_dir, "index.json"), "w") as f:
            json.dump(index, f)

        class Handler(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, directory=tmp_dir, **kwargs)
            def log_message(self, *args):
                pass

        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        try:
            result = cstheme.cmd_fetch_index(f"http://127.0.0.1:{port}")
            assert len(result) == 1
            assert result[0]["name"] == "foo"
        finally:
            server.shutdown()

    def test_bad_url_exits(self):
        with pytest.raises(SystemExit):
            cstheme.cmd_fetch_index("http://127.0.0.1:1")
