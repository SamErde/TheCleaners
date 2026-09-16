"""Regression checks for rejecting stale, incomplete or altered build evidence."""

import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location("compare_archives", Path(__file__).with_name("Compare-Archives.py"))
COMPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPARE)


class ArchiveEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.versions = ["7.4.20", "7.5.11", "7.6.6"]
        for version in self.versions:
            self.write_lane(version)

    def write_lane(self, version, content=b"fixture"):
        directory = self.root / f"zip-archive-pwsh-{version}"
        directory.mkdir(exist_ok=True)
        stream = io.BytesIO()
        entry = zipfile.ZipInfo("\u00e9.txt", (1980, 1, 1, 0, 0, 0))
        entry.create_system = 0
        with zipfile.ZipFile(stream, "w") as archive:
            archive.writestr(entry, content)
            entry.external_attr = 0
        data = stream.getvalue()
        digest = hashlib.sha256(data).hexdigest()
        name = "TheCleaners_0.0.15.zip"
        (directory / name).write_bytes(data)
        (directory / (name + ".repeat.zip")).write_bytes(data)
        (directory / (name + ".sha256")).write_text(f"{digest} *{name}")
        manifest = {"ModuleName": "TheCleaners", "ModuleVersion": "0.0.15", "Commit": "a" * 40,
                    "Runtime": {"PowerShellVersion": version, "PSEdition": "Core"},
                    "Archive": name, "ArchiveSHA256": digest,
                    "Files": [{"Path": entry.filename, "Length": len(content),
                               "SHA256": hashlib.sha256(content).hexdigest()}]}
        (directory / "package.manifest.json").write_text(json.dumps(manifest))

    def verify(self):
        return COMPARE.verify(self.root, "a" * 40, self.versions)

    def alter_manifest(self, change):
        path = self.root / "zip-archive-pwsh-7.4.20/package.manifest.json"
        manifest = json.loads(path.read_text())
        change(manifest)
        path.write_text(json.dumps(manifest))

    def test_matching_archives(self):
        self.assertEqual(len(self.verify()), 3)

    def test_wrong_commit(self):
        self.alter_manifest(lambda m: m.update(Commit="b" * 40))
        with self.assertRaisesRegex(ValueError, "Wrong commit"):
            self.verify()

    def test_wrong_producer(self):
        self.alter_manifest(lambda m: m["Runtime"].update(PowerShellVersion="7.5.9"))
        with self.assertRaisesRegex(ValueError, "Wrong producer"):
            self.verify()

    def test_missing_lane(self):
        self.versions.append("7.0.0")
        with self.assertRaisesRegex(ValueError, "Expected one manifest"):
            self.verify()

    def test_wrong_content(self):
        self.alter_manifest(lambda m: m["Files"][0].update(SHA256="0" * 64))
        with self.assertRaisesRegex(ValueError, "Entry content mismatch"):
            self.verify()

    def test_duplicate_paths(self):
        self.alter_manifest(lambda m: m["Files"].append(m["Files"][0]))
        with self.assertRaisesRegex(ValueError, "Duplicate manifest paths"):
            self.verify()

    def test_changed_sidecar(self):
        path = self.root / "zip-archive-pwsh-7.4.20/TheCleaners_0.0.15.zip.sha256"
        path.write_text("incorrect")
        with self.assertRaisesRegex(ValueError, "Sidecar mismatch"):
            self.verify()

    def test_changed_repeat(self):
        path = self.root / "zip-archive-pwsh-7.4.20/TheCleaners_0.0.15.zip.repeat.zip"
        path.write_bytes(b"different")
        with self.assertRaisesRegex(ValueError, "Repeated archive differs"):
            self.verify()

    def test_valid_but_different_runtime_output(self):
        self.write_lane("7.5.11", content=b"different valid content")
        with self.assertRaisesRegex(ValueError, "Cross-runtime archive differs"):
            self.verify()


if __name__ == "__main__":
    unittest.main()
