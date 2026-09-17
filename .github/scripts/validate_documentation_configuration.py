"""Validate the active Zensical documentation configuration."""

from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath

try:
    import tomllib
except ModuleNotFoundError:  # Python 3.10 is supported by Zensical.
    import tomli as tomllib


class ConfigurationError(ValueError):
    """Report an invalid documentation configuration."""


EXPECTED_SITE_URL = "https://day3bits.com/TheCleaners/"
EXPECTED_REQUIREMENT = "zensical==0.0.62"
REQUIRED_NAVIGATION = {
    "index.md",
    "command-contracts.md",
    "support-matrix.md",
    "Get-TheCleaners.md",
    "release-plan-1.0.md",
    "lab-acceptance.md",
    "deployment-validation.md",
}


def _collect_navigation_paths(navigation: object) -> list[str]:
    """Flatten a validated navigation array into relative source paths."""
    if not isinstance(navigation, list):
        raise ConfigurationError("project.nav must be an array")

    paths: list[str] = []
    for item in navigation:
        if not isinstance(item, dict) or len(item) != 1:
            raise ConfigurationError("each navigation entry must have one label")
        value = next(iter(item.values()))
        if isinstance(value, str):
            paths.append(value)
        elif isinstance(value, list):
            paths.extend(_collect_navigation_paths(value))
        else:
            raise ConfigurationError("navigation targets must be paths or arrays")
    return paths


def _validate_navigation_paths(paths: list[str]) -> None:
    """Require safe, unique navigation paths and mandatory pages."""
    if len(paths) != len(set(paths)):
        raise ConfigurationError("project.nav contains duplicate paths")

    for path in paths:
        parsed_path = PurePosixPath(path)
        unsafe_path = (
            parsed_path.is_absolute()
            or ".." in parsed_path.parts
            or parsed_path.suffix != ".md"
        )
        if unsafe_path:
            raise ConfigurationError(f"project.nav contains an unsafe path: {path}")

    missing_required = sorted(REQUIRED_NAVIGATION - set(paths))
    if missing_required:
        raise ConfigurationError(
            f"project.nav is missing required pages: {', '.join(missing_required)}"
        )


def _validate_navigation(project: dict[str, object], repository_root: Path) -> None:
    """Require navigation entries that resolve beneath the docs tree."""
    paths = _collect_navigation_paths(project.get("nav"))
    _validate_navigation_paths(paths)

    docs_dir = project.get("docs_dir")
    if not isinstance(docs_dir, str) or not docs_dir:
        raise ConfigurationError("project.docs_dir must be a non-empty path")
    missing_files = [path for path in paths if not (repository_root / docs_dir / path).is_file()]
    if missing_files:
        raise ConfigurationError(
            f"project.nav references missing files: {', '.join(sorted(missing_files))}"
        )


def _validate_theme_and_links(project: dict[str, object]) -> None:
    """Require the selected appearance and strict link checks."""
    theme = project.get("theme")
    if not isinstance(theme, dict) or theme.get("variant") != "classic":
        raise ConfigurationError("project.theme.variant must be 'classic'")
    validation = project.get("validation")
    if not isinstance(validation, dict):
        raise ConfigurationError("project.validation must be a table")
    for option in ("invalid_links", "invalid_link_anchors"):
        if validation.get(option) is not True:
            raise ConfigurationError(f"project.validation.{option} must be true")


def _validate_project(project: object, repository_root: Path) -> None:
    """Validate the project, theme, link, and navigation contracts."""
    if not isinstance(project, dict):
        raise ConfigurationError("project must be a table")
    expected_values = {
        "site_url": EXPECTED_SITE_URL,
        "site_dir": "site",
        "docs_dir": "docs",
        "strict": True,
    }
    for name, expected in expected_values.items():
        if project.get(name) != expected:
            raise ConfigurationError(f"project.{name} must be {expected!r}")

    _validate_theme_and_links(project)
    _validate_navigation(project, repository_root)


def validate_configuration(repository_root: Path) -> None:
    """Validate the config, dependency pin, and every navigation target."""
    config_path = repository_root / "zensical.toml"
    try:
        with config_path.open("rb") as config_file:
            config = tomllib.load(config_file)
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise ConfigurationError(f"cannot load {config_path}: {error}") from error
    _validate_project(config.get("project"), repository_root)

    requirements_path = repository_root / "docs" / "requirements.txt"
    try:
        requirements = [
            line.split("#", 1)[0].strip().lower()
            for line in requirements_path.read_text(encoding="utf-8").splitlines()
            if line.split("#", 1)[0].strip()
        ]
    except OSError as error:
        raise ConfigurationError(f"cannot load {requirements_path}: {error}") from error
    if requirements != [EXPECTED_REQUIREMENT]:
        raise ConfigurationError(
            f"documentation requirements must contain only {EXPECTED_REQUIREMENT}"
        )


def main() -> int:
    """Run configuration validation from the command line."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--repository-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
    )
    args = parser.parse_args()
    try:
        validate_configuration(args.repository_root.resolve())
    except ConfigurationError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
