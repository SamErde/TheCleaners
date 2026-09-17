import json
import tempfile
import unittest
from pathlib import Path

import build_documentation_manifest as manifest_tool


COMMIT = "a" * 40


def write_site(root: Path) -> None:
    (root / "index.html").write_text("index", encoding="utf-8")
    (root / "sitemap.xml").write_bytes(b"<urlset></urlset>\n")
    (root / ".nojekyll").write_bytes(b"")
    (root / "assets").mkdir()
    (root / "assets" / "binary.dat").write_bytes(b"\x00\xff\x10exact-bytes")


def build_manifest(site: Path) -> dict:
    return manifest_tool.create_manifest(
        site,
        "SamErde/TheCleaners",
        COMMIT,
        "refs/heads/main",
        "1234",
        "1",
    )


class DocumentationManifestTests(unittest.TestCase):
    def test_manifest_records_exact_binary_content_and_verifies_download(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            site = root / "site"
            site.mkdir()
            write_site(site)

            manifest = build_manifest(site)
            output = root / "evidence" / "site-manifest.json"
            manifest_tool.write_manifest(manifest, output, site)
            loaded = manifest_tool.load_manifest(output)
            manifest_tool.verify_site_directory(site, loaded)

            records = {record["path"]: record for record in loaded["files"]}
            self.assertEqual(records["assets/binary.dat"]["size"], 14)
            self.assertEqual(
                records["assets/binary.dat"]["sha256"],
                manifest_tool.sha256_bytes(b"\x00\xff\x10exact-bytes"),
            )
            self.assertEqual(records[".nojekyll"]["size"], 0)
            self.assertEqual(
                records[".nojekyll"]["sha256"],
                manifest_tool.sha256_bytes(b""),
            )

    def test_local_verification_fails_for_changed_or_unexpected_files(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            site = Path(temporary_directory) / "site"
            site.mkdir()
            write_site(site)
            manifest = build_manifest(site)
            (site / "index.html").write_text("changed", encoding="utf-8")
            (site / "unexpected.txt").write_text("unexpected", encoding="utf-8")

            with self.assertRaisesRegex(
                manifest_tool.ManifestError, "unexpected=.*unexpected.txt; changed=index.html"
            ):
                manifest_tool.verify_site_directory(site, manifest)

    def test_manifest_rejects_symlinks_when_supported(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            site = Path(temporary_directory) / "site"
            site.mkdir()
            write_site(site)
            link = site / "linked-index.html"
            try:
                link.symlink_to(site / "index.html")
            except OSError:
                self.skipTest("The current host does not permit symbolic links.")

            with self.assertRaisesRegex(manifest_tool.ManifestError, "symbolic-link file"):
                manifest_tool.collect_site_files(site)

    def test_manifest_loader_rejects_duplicate_paths(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            site = root / "site"
            site.mkdir()
            write_site(site)
            manifest = build_manifest(site)
            manifest["files"].append(dict(manifest["files"][0]))
            manifest["content"]["file_count"] += 1
            manifest_path = root / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            with self.assertRaisesRegex(manifest_tool.ManifestError, "duplicate path"):
                manifest_tool.load_manifest(manifest_path)


if __name__ == "__main__":
    unittest.main()
