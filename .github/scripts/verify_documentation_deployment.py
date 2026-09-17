#!/usr/bin/env python3
"""Verify deployed documentation bytes and representative navigation."""

from __future__ import annotations

import argparse
import html.parser
import http.client
import json
import sys
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path, PurePosixPath
from typing import Any

from build_documentation_manifest import ManifestError, load_manifest, sha256_bytes


class DeploymentVerificationError(RuntimeError):
    """Raised when deployed content does not match the retained build."""


LOCAL_HTTP_HOSTS = {"127.0.0.1", "localhost"}


class LinkCollector(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []
        self.canonicals: list[str] = []

    def handle_starttag(self, tag: str, attributes: list[tuple[str, str | None]]) -> None:
        values = dict(attributes)
        if tag == "a" and values.get("href"):
            self.links.append(str(values["href"]))
        if tag == "link" and values.get("href"):
            relationships = str(values.get("rel", "")).lower().split()
            if "canonical" in relationships:
                self.canonicals.append(str(values["href"]))


def _public_path(relative_path: str) -> str:
    if relative_path == "index.html":
        return ""
    if relative_path.endswith("/index.html"):
        return relative_path[: -len("index.html")]
    return relative_path


def _file_url(base_url: str, relative_path: str, source_commit: str, attempt: int) -> str:
    public_path = _public_path(relative_path)
    quoted_path = "/".join(
        urllib.parse.quote(part, safe="")
        for part in PurePosixPath(public_path).parts
    )
    if public_path.endswith("/") and quoted_path:
        quoted_path += "/"
    query = urllib.parse.urlencode(
        {"thecleaners_source": source_commit, "verification_attempt": attempt}
    )
    return urllib.parse.urljoin(base_url, quoted_path) + "?" + query


def _parse_http_url(url: str) -> urllib.parse.SplitResult:
    try:
        parsed = urllib.parse.urlsplit(url)
        hostname = parsed.hostname
        parsed.port
    except ValueError as error:
        raise DeploymentVerificationError(f"Invalid HTTP URL: {url!r}.") from error

    if parsed.scheme == "http":
        if hostname not in LOCAL_HTTP_HOSTS:
            raise DeploymentVerificationError(
                "URL must use HTTPS, except HTTP is allowed for localhost tests."
            )
    elif parsed.scheme != "https":
        raise DeploymentVerificationError(
            "URL must use HTTPS, except HTTP is allowed for localhost tests."
        )
    if not hostname:
        raise DeploymentVerificationError("HTTP URL must include a hostname.")
    if parsed.username is not None or parsed.password is not None:
        raise DeploymentVerificationError("HTTP URL must not include user information.")
    if parsed.fragment:
        raise DeploymentVerificationError("HTTP URL must not include a fragment.")
    return parsed


def _request_target(parsed: urllib.parse.SplitResult) -> str:
    return urllib.parse.urlunsplit(("", "", parsed.path or "/", parsed.query, ""))


def _read_http_response(
    request_url: str,
    maximum_body_bytes: int,
    timeout: float,
) -> tuple[int, bytes]:
    parsed = _parse_http_url(request_url)
    connection_type = (
        http.client.HTTPSConnection
        if parsed.scheme == "https"
        else http.client.HTTPConnection
    )
    connection = connection_type(parsed.hostname, parsed.port, timeout=timeout)
    try:
        connection.request(
            "GET",
            _request_target(parsed),
            headers={
                "Accept-Encoding": "identity",
                "Cache-Control": "no-cache",
                "User-Agent": "TheCleaners-documentation-verifier/1",
            },
        )
        response = connection.getresponse()
        try:
            return response.status, response.read(maximum_body_bytes + 1)
        finally:
            response.close()
    finally:
        connection.close()


def _fetch_file(
    base_url: str,
    record: dict[str, Any],
    source_commit: str,
    attempt: int,
    timeout: float,
) -> tuple[str, bytes | None, str | None]:
    relative_path = record["path"]
    request_url = _file_url(base_url, relative_path, source_commit, attempt)
    try:
        status, body = _read_http_response(
            request_url,
            record["size"],
            timeout,
        )
    except (OSError, http.client.HTTPException) as error:
        return relative_path, None, f"request failed: {error}"

    allowed_statuses = {200, 404} if relative_path == "404.html" else {200}
    if status not in allowed_statuses:
        return relative_path, body, f"HTTP {status}"

    if len(body) != record["size"]:
        return relative_path, body, f"size {len(body)} != {record['size']}"
    actual_digest = sha256_bytes(body)
    if actual_digest != record["sha256"]:
        return relative_path, body, f"SHA-256 {actual_digest} != {record['sha256']}"
    return relative_path, body, None


def _normalized_navigation_url(base_url: str, route: str) -> str:
    if not route or route.startswith("/") or ".." in PurePosixPath(route).parts:
        raise DeploymentVerificationError(f"Unsafe navigation route: {route!r}")
    return urllib.parse.urljoin(base_url, route)


def _route_manifest_path(route: str) -> str:
    if route.endswith("/"):
        return route + "index.html"
    return route


def verify_navigation(
    base_url: str,
    index_content: bytes,
    required_routes: list[str],
    manifest_paths: set[str],
) -> None:
    try:
        document = index_content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise DeploymentVerificationError("Deployed index.html is not UTF-8.") from error

    collector = LinkCollector()
    collector.feed(document)
    base_path = urllib.parse.urlparse(base_url).path
    base_parts = urllib.parse.urlparse(base_url)
    canonical_urls = {
        urllib.parse.urlunparse(
            urllib.parse.urlparse(urllib.parse.urljoin(base_url, href))._replace(
                params="", query="", fragment=""
            )
        )
        for href in collector.canonicals
    }
    expected_canonical = urllib.parse.urlunparse(
        base_parts._replace(params="", query="", fragment="")
    )
    local_test = base_parts.hostname in {"127.0.0.1", "localhost"}
    canonical_paths = {urllib.parse.urlparse(url).path for url in canonical_urls}
    if (local_test and base_path not in canonical_paths) or (
        not local_test and expected_canonical not in canonical_urls
    ):
        raise DeploymentVerificationError(
            f"index.html does not declare the canonical URL {expected_canonical!r}."
        )

    linked_paths = {
        urllib.parse.urlparse(urllib.parse.urljoin(base_url, href)).path
        for href in collector.links
    }
    missing_links: list[str] = []
    missing_files: list[str] = []
    for route in required_routes:
        expected_url = _normalized_navigation_url(base_url, route)
        expected_path = urllib.parse.urlparse(expected_url).path
        if expected_path not in linked_paths:
            missing_links.append(route)
        manifest_path = _route_manifest_path(route)
        if manifest_path not in manifest_paths:
            missing_files.append(manifest_path)

    problems = []
    if missing_links:
        problems.append("not linked from index.html: " + ", ".join(missing_links))
    if missing_files:
        problems.append("not present in manifest: " + ", ".join(missing_files))
    if problems:
        raise DeploymentVerificationError("; ".join(problems))


def verify_deployment(
    manifest: dict[str, Any],
    base_url: str,
    required_routes: list[str],
    attempts: int,
    initial_delay: float,
    backoff: float,
    maximum_delay: float,
    timeout: float,
    workers: int,
) -> tuple[int, dict[str, bytes]]:
    parsed_base = _parse_http_url(base_url)
    if parsed_base.query:
        raise DeploymentVerificationError("Base URL must not include a query string.")
    if not base_url.endswith("/"):
        raise DeploymentVerificationError("Base URL must end with '/'.")
    if attempts < 1 or workers < 1:
        raise DeploymentVerificationError("Attempts and workers must be positive.")

    source_commit = manifest["source"]["commit"]
    records = {record["path"]: record for record in manifest["files"]}
    verified_content: dict[str, bytes] = {}
    last_errors: dict[str, str] = {}

    for attempt in range(1, attempts + 1):
        last_errors = {}
        verified_content = {}
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = {
                executor.submit(
                    _fetch_file,
                    base_url,
                    record,
                    source_commit,
                    attempt,
                    timeout,
                ): path
                for path, record in records.items()
            }
            for future in as_completed(futures):
                path, body, error = future.result()
                if error is None and body is not None:
                    verified_content[path] = body
                else:
                    last_errors[path] = error or "empty response"

        if not last_errors:
            verify_navigation(
                base_url,
                verified_content["index.html"],
                required_routes,
                set(records),
            )
            return attempt, verified_content
        if attempt < attempts:
            delay = min(initial_delay * (backoff ** (attempt - 1)), maximum_delay)
            time.sleep(delay)

    samples = "; ".join(
        f"{path}: {last_errors[path]}" for path in sorted(last_errors)[:10]
    )
    raise DeploymentVerificationError(
        f"Deployment did not match after {attempts} attempts; "
        f"{len(last_errors)} file(s) still differ. {samples}"
    )


def write_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--required-navigation", action="append", default=[])
    parser.add_argument("--attempts", type=int, default=6)
    parser.add_argument("--initial-delay", type=float, default=5.0)
    parser.add_argument("--backoff", type=float, default=2.0)
    parser.add_argument("--maximum-delay", type=float, default=30.0)
    parser.add_argument("--timeout", type=float, default=15.0)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--deployment-commit", default="")
    parser.add_argument("--report", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    report: dict[str, Any] = {
        "schema_version": 1,
        "base_url": arguments.base_url,
        "deployment_commit": arguments.deployment_commit,
        "status": "failed",
    }
    try:
        manifest = load_manifest(arguments.manifest)
        report["source"] = manifest["source"]
        report["content"] = manifest["content"]
        used_attempts, _ = verify_deployment(
            manifest,
            arguments.base_url,
            arguments.required_navigation,
            arguments.attempts,
            arguments.initial_delay,
            arguments.backoff,
            arguments.maximum_delay,
            arguments.timeout,
            arguments.workers,
        )
        report["status"] = "passed"
        report["attempts_used"] = used_attempts
        report["verified_file_count"] = manifest["content"]["file_count"]
        report["required_navigation"] = arguments.required_navigation
        print(
            f"Verified {manifest['content']['file_count']} deployed files and "
            f"{len(arguments.required_navigation)} navigation routes in {used_attempts} attempt(s)."
        )
        return_code = 0
    except (DeploymentVerificationError, ManifestError, OSError) as error:
        report["error"] = str(error)
        print(f"error: {error}", file=sys.stderr)
        return_code = 1

    try:
        write_report(arguments.report, report)
    except OSError as error:
        print(f"error: cannot write verification report: {error}", file=sys.stderr)
        return 1
    return return_code


if __name__ == "__main__":
    raise SystemExit(main())
