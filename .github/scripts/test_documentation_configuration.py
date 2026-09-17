"""Tests for the active Zensical documentation contract."""

from __future__ import annotations

from pathlib import Path
import shutil
import tempfile
import unittest

import validate_documentation_configuration as validator


SCRIPT_DIRECTORY = Path(__file__).resolve().parent
REPOSITORY_ROOT = SCRIPT_DIRECTORY.parents[1]


class DocumentationConfigurationTests(unittest.TestCase):
    """Exercise framework, navigation, dependency, and workflow guards."""

    def setUp(self) -> None:
        """Copy repository documentation into an isolated fixture."""
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.fixture_root = Path(self.temporary_directory.name)
        shutil.copytree(REPOSITORY_ROOT / "docs", self.fixture_root / "docs")
        shutil.copy2(REPOSITORY_ROOT / "zensical.toml", self.fixture_root / "zensical.toml")

    def test_repository_configuration_is_valid(self) -> None:
        """Accept the checked-in Zensical configuration and dependency pin."""
        validator.validate_configuration(REPOSITORY_ROOT)

    def test_malformed_navigation_is_rejected(self) -> None:
        """Reject a navigation item containing more than one label."""
        config_path = self.fixture_root / "zensical.toml"
        config_text = config_path.read_text(encoding="utf-8")
        config_path.write_text(
            config_text.replace(
                '{ "Home" = "index.md" }',
                '{ "Home" = "index.md", "Duplicate label" = "index.md" }',
                1,
            ),
            encoding="utf-8",
        )

        with self.assertRaisesRegex(validator.ConfigurationError, "one label"):
            validator.validate_configuration(self.fixture_root)

    def test_missing_navigation_target_is_rejected(self) -> None:
        """Reject navigation that names a missing documentation source."""
        (self.fixture_root / "docs" / "support-matrix.md").unlink()

        with self.assertRaisesRegex(validator.ConfigurationError, "missing files"):
            validator.validate_configuration(self.fixture_root)

    def test_navigation_cannot_escape_the_documentation_tree(self) -> None:
        """Reject a navigation path that traverses outside docs."""
        config_path = self.fixture_root / "zensical.toml"
        config_text = config_path.read_text(encoding="utf-8")
        config_path.write_text(
            config_text.replace('"index.md"', '"../README.md"', 1),
            encoding="utf-8",
        )

        with self.assertRaisesRegex(validator.ConfigurationError, "unsafe path"):
            validator.validate_configuration(self.fixture_root)

    def test_workflows_use_the_pinned_zensical_build_contract(self) -> None:
        """Require supported builds and the single-build deployment order."""
        deploy_workflow = (
            REPOSITORY_ROOT / ".github" / "workflows" / "Deploy Zensical.yml"
        ).read_text(encoding="utf-8")
        build_workflow = (
            REPOSITORY_ROOT / ".github" / "workflows" / "Build Module.yml"
        ).read_text(encoding="utf-8")
        read_the_docs = (REPOSITORY_ROOT / ".readthedocs.yaml").read_text(encoding="utf-8")

        self.assertEqual(deploy_workflow.count("zensical build --strict --clean"), 1)
        self.assertEqual(build_workflow.count("zensical build --strict --clean"), 1)
        self.assertEqual(read_the_docs.count("zensical build --strict --clean"), 1)
        self.assertNotIn("mkdocs", deploy_workflow.lower())
        self.assertNotIn("mkdocs", build_workflow.lower())
        self.assertNotIn("mkdocs", read_the_docs.lower())
        self.assertIn("zensical-site-${{ github.sha }}", deploy_workflow)
        self.assertLess(
            deploy_workflow.index("zensical build --strict --clean"),
            deploy_workflow.index("touch site/.nojekyll"),
        )
        self.assertLess(
            deploy_workflow.index("touch site/.nojekyll"),
            deploy_workflow.index("build_documentation_manifest.py create"),
        )


if __name__ == "__main__":
    unittest.main()
