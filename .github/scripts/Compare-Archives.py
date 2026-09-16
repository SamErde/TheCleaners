"""Verify downloaded lane archives, repeated ZIPs, sidecars and commit identity."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_manifest(directory, commit, version):
    manifests = list(directory.glob("*.manifest.json"))
    require(len(manifests) == 1, f"Expected one manifest for {version}")
    manifest = json.loads(manifests[0].read_text(encoding="utf-8-sig"))
    require(manifest["Commit"] == commit, f"Wrong commit for {version}")
    require(manifest["Runtime"] == {"PowerShellVersion": version, "PSEdition": "Core"},
            f"Wrong producer for {version}")
    require(manifest["ModuleName"] == "TheCleaners", "Wrong module name")
    require(manifest["Archive"] == f'TheCleaners_{manifest["ModuleVersion"]}.zip',
            "Unexpected archive name")
    require(Path(manifest["Archive"]).name == manifest["Archive"], "Unsafe archive name")
    return manifest


def verify_bytes(path, manifest):
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    require(digest == manifest["ArchiveSHA256"], "Manifest digest mismatch")
    require(Path(str(path) + ".sha256").read_text().strip() == f"{digest} *{path.name}",
            "Sidecar mismatch")
    require(Path(str(path) + ".repeat.zip").read_bytes() == data, "Repeated archive differs")
    return data, digest


def verify_entry(archive, entry, item):
    require(entry.date_time == (1980, 1, 1, 0, 0, 0), "Noncanonical timestamp")
    require(entry.compress_type == zipfile.ZIP_STORED, "Runtime-dependent compression is forbidden")
    require((entry.external_attr, entry.internal_attr, entry.extra, entry.comment) == (0, 0, b"", b""),
            "Noncanonical entry metadata")
    require((entry.flag_bits, entry.create_system) == (0x800, 0),
            "Expected UTF-8 names and a Windows producer")
    require(entry.file_size == item["Length"], "Entry length mismatch")
    require(hashlib.sha256(archive.read(entry)).hexdigest() == item["SHA256"], "Entry content mismatch")


def verify_contents(path, manifest):
    expected = {item["Path"]: item for item in manifest["Files"]}
    require(bool(expected), "Empty manifest")
    require(len(expected) == len(manifest["Files"]), "Duplicate manifest paths")
    with zipfile.ZipFile(path) as archive:
        # .NET ordinal ordering compares UTF-16 code units, including supplementary characters.
        names = sorted(expected, key=lambda name: name.encode("utf-16-be"))
        require(archive.namelist() == names, "Entry set/order mismatch")
        for entry in archive.infolist():
            verify_entry(archive, entry, expected[entry.filename])
    return len(expected)


def verify(root, commit, versions):
    records = []
    reference = None
    for version in versions:
        directory = root / f"zip-archive-pwsh-{version}"
        manifest = read_manifest(directory, commit, version)
        path = directory / manifest["Archive"]
        data, digest = verify_bytes(path, manifest)
        count = verify_contents(path, manifest)
        if reference is None:
            reference = data
        require(reference == data, f"Cross-runtime archive differs for {version}")
        records.append({"Version": version, "Commit": commit, "Archive": path.name,
                        "Length": len(data), "SHA256": digest, "Files": count,
                        "RepeatMatched": True})
    return records


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--versions", nargs="+", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.root, args.commit, args.versions)
    report = json.dumps(result, indent=2) + "\n"
    args.output.write_text(report, encoding="utf-8")
    print(report)
