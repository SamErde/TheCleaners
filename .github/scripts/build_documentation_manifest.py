#!/usr/bin/env python3
"""Create and verify a byte-level manifest for a built documentation site."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any


SCHEMA_VERSION = 1
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")


class ManifestError(ValueError):
    """Raised when site content or a manifest violates the delivery contract."""


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def _validate_relative_path(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts or "\\" in value:
        raise ManifestError(f"Unsafe manifest path: {value!r}")
    return path


def _validate_site_directories(current_path: Path, directory_names: list[str]) -> None:
    for directory_name in directory_names:
        directory_path = current_path / directory_name
        if directory_path.is_symlink():
            raise ManifestError(f"Site contains a symbolic-link directory: {directory_path}")


def _site_file_record(root: Path, file_path: Path) -> dict[str, Any]:
    if file_path.is_symlink():
        raise ManifestError(f"Site contains a symbolic-link file: {file_path}")
    if not file_path.is_file():
        raise ManifestError(f"Site contains a non-regular file: {file_path}")

    content = file_path.read_bytes()
    relative_path = file_path.relative_to(root).as_posix()
    _validate_relative_path(relative_path)
    return {
        "path": relative_path,
        "size": len(content),
        "sha256": sha256_bytes(content),
    }


def _raise_walk_error(error: OSError) -> None:
    raise ManifestError(f"Cannot traverse site directory: {error}") from error


def collect_site_files(site_dir: Path) -> list[dict[str, Any]]:
    if site_dir.is_symlink():
        raise ManifestError(f"Site path is a symbolic link: {site_dir}")
    root = site_dir.resolve(strict=True)
    if not root.is_dir():
        raise ManifestError(f"Site path is not a directory: {root}")

    records: list[dict[str, Any]] = []
    for current, directory_names, file_names in os.walk(
        root,
        followlinks=False,
        onerror=_raise_walk_error,
    ):
        directory_names.sort()
        file_names.sort()
        current_path = Path(current)
        _validate_site_directories(current_path, directory_names)

        for file_name in file_names:
            records.append(_site_file_record(root, current_path / file_name))

    records.sort(key=lambda item: item["path"])
    if not records:
        raise ManifestError("The built site contains no files.")
    return records


def calculate_tree_sha256(records: list[dict[str, Any]]) -> str:
    digest = hashlib.sha256()
    for record in records:
        digest.update(record["path"].encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(record["size"]).encode("ascii"))
        digest.update(b"\0")
        digest.update(record["sha256"].encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def create_manifest(
    site_dir: Path,
    source_repository: str,
    source_commit: str,
    source_ref: str,
    workflow_run_id: str,
    workflow_run_attempt: str,
) -> dict[str, Any]:
    if not COMMIT_PATTERN.fullmatch(source_commit):
        raise ManifestError("Source commit must be a lowercase, full-length Git SHA.")
    if not source_repository.strip():
        raise ManifestError("Source repository must not be empty.")

    records = collect_site_files(site_dir)
    record_paths = {record["path"] for record in records}
    missing_required = sorted({"index.html", "sitemap.xml"} - record_paths)
    if missing_required:
        raise ManifestError(
            "Built site is missing required files: " + ", ".join(missing_required)
        )

    return {
        "schema_version": SCHEMA_VERSION,
        "source": {
            "repository": source_repository,
            "commit": source_commit,
            "ref": source_ref,
            "workflow_run_id": workflow_run_id,
            "workflow_run_attempt": workflow_run_attempt,
        },
        "content": {
            "file_count": len(records),
            "total_bytes": sum(record["size"] for record in records),
            "tree_sha256": calculate_tree_sha256(records),
        },
        "files": records,
    }


def write_manifest(manifest: dict[str, Any], output_path: Path, site_dir: Path) -> None:
    site_root = site_dir.resolve(strict=True)
    output = output_path.resolve()
    if output == site_root or site_root in output.parents:
        raise ManifestError("Manifest output must be outside the site directory.")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def _validate_file_size(path: str, size: Any) -> int:
    if isinstance(size, bool) or not isinstance(size, int) or size < 0:
        raise ManifestError(f"Manifest size is invalid for {path}.")
    return size


def _validate_file_digest(path: str, digest: Any) -> str:
    if not isinstance(digest, str) or not SHA256_PATTERN.fullmatch(digest):
        raise ManifestError(f"Manifest SHA-256 is invalid for {path}.")
    return digest


def _normalize_file_record(record: Any, paths: set[str]) -> dict[str, Any]:
    if not isinstance(record, dict):
        raise ManifestError("Manifest file record has the wrong type.")
    path = record.get("path")
    if not isinstance(path, str):
        raise ManifestError("Manifest file path has the wrong type.")
    _validate_relative_path(path)
    if path in paths:
        raise ManifestError(f"Manifest contains a duplicate path: {path}")
    paths.add(path)
    return {
        "path": path,
        "size": _validate_file_size(path, record.get("size")),
        "sha256": _validate_file_digest(path, record.get("sha256")),
    }


def _validate_file_records(records: list[Any]) -> tuple[list[dict[str, Any]], set[str]]:
    paths: set[str] = set()
    normalized_records = [_normalize_file_record(record, paths) for record in records]
    return normalized_records, paths


def _validate_manifest_aggregates(
    content: dict[str, Any],
    records: list[dict[str, Any]],
    paths: set[str],
) -> None:
    if records != sorted(records, key=lambda item: item["path"]):
        raise ManifestError("Manifest file records are not sorted by path.")
    if content.get("file_count") != len(records):
        raise ManifestError("Manifest file count does not match its records.")
    if content.get("total_bytes") != sum(record["size"] for record in records):
        raise ManifestError("Manifest byte count does not match its records.")
    if content.get("tree_sha256") != calculate_tree_sha256(records):
        raise ManifestError("Manifest tree SHA-256 does not match its records.")
    if not {"index.html", "sitemap.xml"}.issubset(paths):
        raise ManifestError("Manifest is missing index.html or sitemap.xml.")


def load_manifest(manifest_path: Path) -> dict[str, Any]:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"Cannot read manifest {manifest_path}: {error}") from error

    if not isinstance(manifest, dict):
        raise ManifestError("Manifest root must be a JSON object.")
    if manifest.get("schema_version") != SCHEMA_VERSION:
        raise ManifestError(
            f"Unsupported manifest schema: {manifest.get('schema_version')!r}"
        )
    source = manifest.get("source")
    content = manifest.get("content")
    records = manifest.get("files")
    if (
        not isinstance(source, dict)
        or not isinstance(content, dict)
        or not isinstance(records, list)
    ):
        raise ManifestError("Manifest source, content, or files field has the wrong type.")
    if not COMMIT_PATTERN.fullmatch(str(source.get("commit", ""))):
        raise ManifestError("Manifest source commit is not a full lowercase Git SHA.")

    normalized_records, paths = _validate_file_records(records)
    _validate_manifest_aggregates(content, normalized_records, paths)
    return manifest


def _difference_text(label: str, paths: list[str]) -> str:
    if not paths:
        return ""
    return f"{label}=" + ",".join(paths[:10])


def _site_difference_details(
    expected: dict[str, dict[str, Any]],
    actual: dict[str, dict[str, Any]],
) -> str:
    missing = sorted(set(expected) - set(actual))
    unexpected = sorted(set(actual) - set(expected))
    changed = sorted(
        path for path in set(expected) & set(actual) if expected[path] != actual[path]
    )
    differences = (
        _difference_text("missing", missing),
        _difference_text("unexpected", unexpected),
        _difference_text("changed", changed),
    )
    return "; ".join(filter(None, differences))


def verify_site_directory(site_dir: Path, manifest: dict[str, Any]) -> None:
    actual_records = collect_site_files(site_dir)
    expected_records = manifest["files"]
    if actual_records == expected_records:
        return

    expected = {record["path"]: record for record in expected_records}
    actual = {record["path"]: record for record in actual_records}
    raise ManifestError(
        "Site does not match manifest: " + _site_difference_details(expected, actual)
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    create_parser = subparsers.add_parser("create", help="Create a site manifest.")
    create_parser.add_argument("--site-dir", type=Path, required=True)
    create_parser.add_argument("--output", type=Path, required=True)
    create_parser.add_argument("--source-repository", required=True)
    create_parser.add_argument("--source-commit", required=True)
    create_parser.add_argument("--source-ref", default="")
    create_parser.add_argument("--workflow-run-id", default="")
    create_parser.add_argument("--workflow-run-attempt", default="")

    verify_parser = subparsers.add_parser("verify", help="Verify a site against a manifest.")
    verify_parser.add_argument("--site-dir", type=Path, required=True)
    verify_parser.add_argument("--manifest", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.command == "create":
            manifest = create_manifest(
                arguments.site_dir,
                arguments.source_repository,
                arguments.source_commit,
                arguments.source_ref,
                arguments.workflow_run_id,
                arguments.workflow_run_attempt,
            )
            write_manifest(manifest, arguments.output, arguments.site_dir)
            print(
                f"Recorded {manifest['content']['file_count']} files, "
                f"{manifest['content']['total_bytes']} bytes, tree SHA-256 "
                f"{manifest['content']['tree_sha256']}."
            )
        else:
            manifest = load_manifest(arguments.manifest)
            verify_site_directory(arguments.site_dir, manifest)
            print(
                f"Verified {manifest['content']['file_count']} files against tree SHA-256 "
                f"{manifest['content']['tree_sha256']}."
            )
    except (ManifestError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
