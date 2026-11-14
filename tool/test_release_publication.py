"""Release publication failures and workflow dependency contracts; no network."""

import json
from pathlib import Path
import re
import subprocess
import unittest
from unittest.mock import patch

import release_publication as release


class ReleasePublicationTests(unittest.TestCase):
    repo = "owner/repo"
    tag = "v1.2.3"

    def complete(self, **extra):
        return {"tag_name": self.tag, "draft": True, "prerelease": False,
                "assets": [{"name": name, "size": 100}
                           for name in release.REQUIRED_ASSETS]} | extra

    @patch.object(release.subprocess, "run")
    @patch.object(release, "release_info", return_value=None)
    def test_new_release_is_always_a_draft(self, info, run):
        release.prepare(self.repo, self.tag, "Title", "notes.md")
        command = run.call_args.args[0]
        self.assertIn("--draft", command)
        self.assertIn("--verify-tag", command)
        self.assertNotIn("delete", command)

    @patch.object(release.subprocess, "run")
    @patch.object(release, "release_info")
    def test_prepare_retains_existing_draft_and_published_assets(self, info, run):
        for draft in [True, False]:
            info.return_value = self.complete(draft=draft)
            release.prepare(self.repo, self.tag, "Title", "notes.md")
        run.assert_not_called()

    @patch.object(release.subprocess, "run")
    @patch.object(release, "release_info")
    def test_source_archives_alone_cannot_publish(self, info, run):
        # GitHub's automatic source ZIP/TAR links aren't uploaded binary assets.
        info.return_value = self.complete(assets=[])
        with self.assertRaisesRegex(RuntimeError, "missing or empty"):
            release.publish(self.repo, self.tag)
        run.assert_not_called()

    @patch.object(release.subprocess, "run")
    @patch.object(release, "release_info")
    def test_each_platform_binary_is_mandatory_and_nonempty(self, info, run):
        for name in release.REQUIRED_ASSETS:
            for size in [None, 0, -1, True, "100"]:
                data = self.complete()
                for asset in data["assets"]:
                    if asset["name"] == name:
                        asset["size"] = size
                info.return_value = data
                with self.subTest(name=name, size=size), self.assertRaises(RuntimeError):
                    release.publish(self.repo, self.tag)
        run.assert_not_called()

    @patch.object(release.subprocess, "run")
    @patch.object(release, "release_info")
    def test_complete_stable_draft_is_published_as_latest(self, info, run):
        info.return_value = self.complete()
        release.publish(self.repo, self.tag)
        self.assertIn("--draft=false", run.call_args.args[0])
        self.assertIn("--latest", run.call_args.args[0])

    @patch.object(release.subprocess, "run")
    @patch.object(release, "release_info")
    def test_prerelease_does_not_become_latest(self, info, run):
        info.return_value = self.complete(prerelease=True)
        release.publish(self.repo, self.tag)
        self.assertNotIn("--latest", run.call_args.args[0])

    @patch.object(release.subprocess, "run")
    @patch.object(release, "release_info")
    def test_complete_published_release_is_not_mutated(self, info, run):
        info.return_value = self.complete(draft=False)
        release.publish(self.repo, self.tag)
        run.assert_not_called()

    @patch.object(release.subprocess, "run")
    @patch.object(release, "release_info", return_value=None)
    def test_missing_draft_cannot_publish(self, info, run):
        with self.assertRaisesRegex(RuntimeError, "draft is missing"):
            release.publish(self.repo, self.tag)
        run.assert_not_called()

    @patch.object(release.subprocess, "run")
    def test_api_permission_or_network_error_is_not_a_missing_release(self, run):
        run.return_value = subprocess.CompletedProcess([], 1, "", "gh: forbidden (HTTP 403)")
        with self.assertRaises(RuntimeError):
            release.prepare(self.repo, self.tag, "Title", "notes.md")
        self.assertEqual(run.call_count, 1)

    @patch.object(release.subprocess, "run")
    def test_only_explicit_404_means_release_is_missing(self, run):
        run.return_value = subprocess.CompletedProcess([], 1, "", "gh: not found (HTTP 404)")
        self.assertIsNone(release.release_info(self.repo, self.tag))

    @patch.object(release.subprocess, "run")
    def test_wrong_tag_metadata_is_rejected(self, run):
        run.return_value = subprocess.CompletedProcess([], 0, json.dumps({"tag_name": "other"}), "")
        with self.assertRaisesRegex(RuntimeError, "requested tag"):
            release.release_info(self.repo, self.tag)

    def test_workflow_waits_for_every_platform_and_cli_before_publication(self):
        root = Path(__file__).resolve().parents[1]
        workflow = (root / ".github/workflows/release.yml").read_text().split("\njobs:\n", 1)[1]
        jobs = dict(re.findall(r"(?ms)^  ([\w-]+):\n(.*?)(?=^  [\w-]+:|\Z)", workflow))
        final = jobs["publish-release"]
        needs = set(re.search(r"needs: \[([^]]+)\]", final).group(1).replace(" ", "").split(","))
        self.assertEqual(needs, {name for name in jobs if name.startswith("build-")} | {"create-release"})
        self.assertNotIn("if: always()", final)
        self.assertIn('release_publication.py publish "$RELEASE_TAG"', final)
        self.assertIn("release_publication.py prepare", jobs["create-release"])
        self.assertNotIn("gh release delete", jobs["create-release"])


if __name__ == "__main__":
    unittest.main()
