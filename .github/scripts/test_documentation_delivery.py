import importlib.util
import json
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock
from urllib.parse import urlparse


SCRIPT_DIRECTORY = Path(__file__).resolve().parent


def load_script(module_name: str, filename: str):
    spec = importlib.util.spec_from_file_location(module_name, SCRIPT_DIRECTORY / filename)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


manifest_tool = load_script(
    "build_documentation_manifest", "build_documentation_manifest.py"
)
deployment_tool = load_script(
    "verify_documentation_deployment", "verify_documentation_deployment.py"
)


COMMIT = "a" * 40
BASE_PATH = "/TheCleaners/"


def write_site(root: Path, include_navigation: bool = True) -> None:
    routes = [
        "Get-TheCleaners/",
        "support-matrix/",
        "command-contracts/",
        "migration-to-1.0/",
        "release-plan-1.0/",
    ]
    links = "".join(f'<a href="{route}">{route}</a>' for route in routes)
    if not include_navigation:
        links = ""
    (root / "index.html").write_text(
        '<html><head><link rel="canonical" '
        'href="https://day3bits.com/TheCleaners/"></head>'
        f"<body>{links}</body></html>",
        encoding="utf-8",
    )
    (root / "sitemap.xml").write_bytes(b"<urlset></urlset>\n")
    (root / ".nojekyll").write_bytes(b"")
    (root / "assets").mkdir()
    (root / "assets" / "binary.dat").write_bytes(b"\x00\xff\x10exact-bytes")
    for route in routes:
        route_directory = root / route
        route_directory.mkdir()
        (route_directory / "index.html").write_text(route, encoding="utf-8")


def build_manifest(site: Path) -> dict:
    return manifest_tool.create_manifest(
        site,
        "SamErde/TheCleaners",
        COMMIT,
        "refs/heads/main",
        "1234",
        "1",
    )


class SiteServer:
    def __init__(
        self,
        files: dict[str, bytes],
        stale_once: set[str] | None = None,
        stale_on_requests: dict[str, set[int]] | None = None,
        redirects: dict[str, str] | None = None,
    ):
        self.files = files
        self.stale_once = set(stale_once or set())
        self.stale_on_requests = stale_on_requests or {}
        self.redirects = redirects or {}
        self.request_counts: dict[str, int] = {}

        owner = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                path = urlparse(self.path).path
                owner.request_counts[path] = owner.request_counts.get(path, 0) + 1
                if path in owner.redirects:
                    self.send_response(302)
                    self.send_header("Location", owner.redirects[path])
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                if (
                    path in owner.stale_once and owner.request_counts[path] == 1
                ) or owner.request_counts[path] in owner.stale_on_requests.get(path, set()):
                    content = b"stale"
                else:
                    content = owner.files.get(path)
                if content is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)

            def log_message(self, format, *args):
                return

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return f"http://127.0.0.1:{self.server.server_port}{BASE_PATH}"

    def __exit__(self, exc_type, exc_value, traceback):
        self.server.shutdown()
        self.thread.join(timeout=5)
        self.server.server_close()


def public_files(site: Path, manifest: dict) -> dict[str, bytes]:
    files = {}
    for record in manifest["files"]:
        relative_path = record["path"]
        public_path = deployment_tool._public_path(relative_path)
        files[BASE_PATH + public_path] = (site / relative_path).read_bytes()
    return files


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

            binary_record = next(
                record for record in loaded["files"] if record["path"] == "assets/binary.dat"
            )
            self.assertEqual(binary_record["size"], 14)
            self.assertEqual(
                binary_record["sha256"],
                manifest_tool.sha256_bytes(b"\x00\xff\x10exact-bytes"),
            )
            marker = next(record for record in loaded["files"] if record["path"] == ".nojekyll")
            self.assertEqual(marker["size"], 0)
            self.assertEqual(marker["sha256"], manifest_tool.sha256_bytes(b""))

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


class DocumentationDeploymentTests(unittest.TestCase):
    required_routes = [
        "Get-TheCleaners/",
        "support-matrix/",
        "command-contracts/",
        "migration-to-1.0/",
        "release-plan-1.0/",
    ]

    def test_non_http_schemes_are_rejected_before_transport(self):
        manifest = {"source": {"commit": COMMIT}, "files": []}
        for base_url in ("file://localhost/", "ftp://localhost/"):
            with self.subTest(base_url=base_url):
                with mock.patch.object(deployment_tool, "_read_http_response") as transport:
                    with self.assertRaisesRegex(
                        deployment_tool.DeploymentVerificationError,
                        "URL must use HTTPS",
                    ):
                        deployment_tool.verify_deployment(
                            manifest,
                            base_url,
                            self.required_routes,
                            attempts=1,
                            initial_delay=0,
                            backoff=1,
                            maximum_delay=0,
                            timeout=2,
                            workers=1,
                        )
                    transport.assert_not_called()

    def test_exact_deployment_and_navigation_pass(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            site = Path(temporary_directory) / "site"
            site.mkdir()
            write_site(site)
            manifest = build_manifest(site)

            with SiteServer(public_files(site, manifest)) as base_url:
                attempts, content = deployment_tool.verify_deployment(
                    manifest,
                    base_url,
                    self.required_routes,
                    attempts=1,
                    initial_delay=0,
                    backoff=1,
                    maximum_delay=0,
                    timeout=2,
                    workers=4,
                )

            self.assertEqual(attempts, 1)
            self.assertEqual(set(content), {record["path"] for record in manifest["files"]})

    def test_stale_file_is_retried_then_passes(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            site = Path(temporary_directory) / "site"
            site.mkdir()
            write_site(site)
            manifest = build_manifest(site)
            stale_path = BASE_PATH + "support-matrix/"
            server = SiteServer(public_files(site, manifest), {stale_path})

            with server as base_url:
                attempts, _ = deployment_tool.verify_deployment(
                    manifest,
                    base_url,
                    self.required_routes,
                    attempts=2,
                    initial_delay=0,
                    backoff=1,
                    maximum_delay=0,
                    timeout=2,
                    workers=1,
                )

            self.assertEqual(attempts, 2)
            self.assertEqual(server.request_counts[stale_path], 2)
            self.assertTrue(all(count == 2 for count in server.request_counts.values()))

    def test_redirect_is_rejected_without_following_location(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            site = Path(temporary_directory) / "site"
            site.mkdir()
            write_site(site)
            manifest = build_manifest(site)
            redirect_target = BASE_PATH + "redirect-target/"
            server = SiteServer(
                public_files(site, manifest),
                redirects={BASE_PATH: redirect_target},
            )

            with server as base_url:
                with self.assertRaisesRegex(
                    deployment_tool.DeploymentVerificationError,
                    "index.html: HTTP 302",
                ):
                    deployment_tool.verify_deployment(
                        manifest,
                        base_url,
                        self.required_routes,
                        attempts=1,
                        initial_delay=0,
                        backoff=1,
                        maximum_delay=0,
                        timeout=2,
                        workers=2,
                    )

            self.assertEqual(server.request_counts.get(redirect_target, 0), 0)

    def test_alternating_generations_never_form_a_complete_passing_attempt(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            site = Path(temporary_directory) / "site"
            site.mkdir()
            write_site(site)
            manifest = build_manifest(site)
            # A matches only on attempt one; B matches only on attempt two.
            # Accumulating successes across attempts would incorrectly pass.
            server = SiteServer(
                public_files(site, manifest),
                stale_on_requests={
                    BASE_PATH: {2},
                    BASE_PATH + "support-matrix/": {1},
                },
            )
            with server as base_url:
                with self.assertRaisesRegex(
                    deployment_tool.DeploymentVerificationError,
                    "after 2 attempts; 1 file.*index.html",
                ):
                    deployment_tool.verify_deployment(
                        manifest,
                        base_url,
                        self.required_routes,
                        attempts=2,
                        initial_delay=0,
                        backoff=1,
                        maximum_delay=0,
                        timeout=2,
                        workers=1,
                    )

    def test_wrong_bytes_fail_closed_after_bounded_attempts(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            site = Path(temporary_directory) / "site"
            site.mkdir()
            write_site(site)
            manifest = build_manifest(site)
            files = public_files(site, manifest)
            files[BASE_PATH + "assets/binary.dat"] = b"wrong"

            with SiteServer(files) as base_url:
                with self.assertRaisesRegex(
                    deployment_tool.DeploymentVerificationError,
                    "after 2 attempts; 1 file.*assets/binary.dat",
                ):
                    deployment_tool.verify_deployment(
                        manifest,
                        base_url,
                        self.required_routes,
                        attempts=2,
                        initial_delay=0,
                        backoff=1,
                        maximum_delay=0,
                        timeout=2,
                        workers=2,
                    )

    def test_missing_representative_navigation_fails(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            site = Path(temporary_directory) / "site"
            site.mkdir()
            write_site(site, include_navigation=False)
            manifest = build_manifest(site)

            with SiteServer(public_files(site, manifest)) as base_url:
                with self.assertRaisesRegex(
                    deployment_tool.DeploymentVerificationError,
                    "not linked from index.html",
                ):
                    deployment_tool.verify_deployment(
                        manifest,
                        base_url,
                        self.required_routes,
                        attempts=1,
                        initial_delay=0,
                        backoff=1,
                        maximum_delay=0,
                        timeout=2,
                        workers=2,
                    )


if __name__ == "__main__":
    unittest.main()
