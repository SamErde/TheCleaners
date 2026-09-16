"""Verify downloaded lane archives, repeated ZIPs, sidecars and commit identity."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def verify(root, commit, versions):
    records = []
    reference = None
    for version in versions:
        directory = root / f"zip-archive-pwsh-{version}"
        manifests = list(directory.glob("*.manifest.json"))
        if len(manifests) != 1:
            raise ValueError(f"Expected one manifest for {version}")
        manifest = json.loads(manifests[0].read_text(encoding="utf-8-sig"))
        if manifest["Commit"] != commit:
            raise ValueError(f"Wrong commit for {version}")
        if manifest["Runtime"] != {"PowerShellVersion": version, "PSEdition": "Core"}:
            raise ValueError(f"Wrong producer for {version}")
        name = manifest["Archive"]
        if name != f'TheCleaners_{manifest["ModuleVersion"]}.zip':
            raise ValueError(f"Unexpected archive name: {name}")
        path = directory / name
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if digest != manifest["ArchiveSHA256"]:
            raise ValueError(f"Manifest digest mismatch for {version}")
        if Path(str(path) + ".sha256").read_text().strip() != f"{digest} *{name}":
            raise ValueError(f"Sidecar mismatch for {version}")
        if Path(str(path) + ".repeat.zip").read_bytes() != data:
            raise ValueError(f"Repeated archive differs for {version}")
        expected = {item["Path"]: item for item in manifest["Files"]}
        if not expected or len(expected) != len(manifest["Files"]):
            raise ValueError("Empty or duplicate manifest paths")
        with zipfile.ZipFile(path) as archive:
            entries = archive.infolist()
            if archive.namelist() != sorted(expected):
                raise ValueError(f"Entry set/order mismatch for {version}")
            for entry in entries:
                item = expected[entry.filename]
                if entry.date_time != (1980, 1, 1, 0, 0, 0):
                    raise ValueError("Noncanonical timestamp")
                if entry.compress_type != zipfile.ZIP_STORED:
                    raise ValueError("Runtime-dependent compression is forbidden")
                if entry.external_attr or entry.internal_attr or entry.extra or entry.comment:
                    raise ValueError("Noncanonical entry metadata")
                if entry.flag_bits != 0x800 or entry.create_system != 0:
                    raise ValueError("Expected UTF-8 names and a Windows producer")
                if entry.file_size != item["Length"]:
                    raise ValueError("Entry length mismatch")
                if hashlib.sha256(archive.read(entry)).hexdigest() != item["SHA256"]:
                    raise ValueError("Entry content mismatch")
        if reference is None:
            reference = data
        elif reference != data:
            raise ValueError(f"Cross-runtime archive differs for {version}")
        records.append({"Version": version, "Commit": commit, "Archive": name,
                        "Length": len(data), "SHA256": digest, "Files": len(expected),
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
