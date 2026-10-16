"""Guard the documentation PR preflight and main-only deployment boundary."""

from pathlib import Path
import re
import unittest


WORKFLOW_PATH = Path(__file__).resolve().parents[1] / "workflows" / "Deploy Zensical.yml"


class DocumentationDeployWorkflowTests(unittest.TestCase):
    """Keep pull-request builds separate from publishing."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW_PATH.read_text(encoding="utf-8")

    def test_pull_requests_run_the_build_without_publishing(self) -> None:
        events = re.search(
            r"^on:\n(.*?)(?=^permissions:)",
            self.workflow,
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(events)
        self.assertRegex(events.group(1), r"(?m)^  pull_request:\n    branches:\n      - main$")
        self.assertRegex(events.group(1), r"(?m)^  push:\n    branches:\n      - main$")
        self.assertRegex(events.group(1), r"(?m)^  workflow_dispatch:$")

        build = re.search(
            r"^  build:\n(.*?)(?=^  deploy:)",
            self.workflow,
            re.MULTILINE | re.DOTALL,
        )
        deploy = re.search(
            r"^  deploy:\n(.*?)(?=^  verify:)",
            self.workflow,
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(build)
        self.assertIsNotNone(deploy)
        self.assertIn(
            "if: github.event_name == 'pull_request' || github.ref == 'refs/heads/main'",
            build.group(1),
        )
        self.assertRegex(build.group(1), r"(?m)^    permissions:\n      contents: read$")
        self.assertIn("build_documentation_manifest.py create", build.group(1))
        self.assertIn("📦 Retain Checked Site and Manifest", build.group(1))
        self.assertIn(
            "if: github.ref == 'refs/heads/main' && "
            "(github.event_name == 'push' || github.event_name == 'workflow_dispatch')",
            deploy.group(1),
        )
        self.assertRegex(deploy.group(1), r"(?m)^    permissions:\n      contents: write$")
        self.assertRegex(self.workflow, r"(?m)^  verify:\n    needs: deploy$")

    def test_pull_request_preflights_cannot_cancel_main_deployments(self) -> None:
        self.assertIn(
            "group: ${{ github.event_name == 'pull_request' && "
            "format('documentation-gh-pages-pr-{0}', github.event.pull_request.number) "
            "|| 'documentation-gh-pages' }}",
            self.workflow,
        )
        self.assertIn(
            "cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main()
