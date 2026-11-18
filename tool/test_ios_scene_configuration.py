"""Guard against a launchable iOS app whose configured scene delegate is absent.

Xcode builds successfully when Info.plist references an unlinked Swift class;
the resulting application can stay alive with a black window.
"""

import copy
import json
from pathlib import Path
import plistlib
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


def runner_scene_is_compiled(project, info):
    objects = project['objects']
    runner = next(value for value in objects.values()
                  if value.get('isa') == 'PBXNativeTarget'
                  and value.get('name') == 'Runner')
    compiled = {
        objects[build_file]['fileRef']
        for phase_id in runner['buildPhases']
        if objects[phase_id]['isa'] == 'PBXSourcesBuildPhase'
        for build_file in objects[phase_id]['files']
    }
    configurations = info['UIApplicationSceneManifest']['UISceneConfigurations']
    for scene in configurations['UIWindowSceneSessionRoleApplication']:
        source = scene['UISceneDelegateClassName'].rsplit('.', 1)[-1] + '.swift'
        if not any(objects[file_id].get('path') == source for file_id in compiled):
            return False
    return True


class IOSSceneConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.project = json.loads(subprocess.check_output([
            'plutil', '-convert', 'json', '-o', '-',
            str(ROOT / 'ios/Runner.xcodeproj/project.pbxproj'),
        ]))
        cls.info = plistlib.loads((ROOT / 'ios/Runner/Info.plist').read_bytes())

    def test_configured_scene_is_in_runner_compile_sources(self):
        self.assertTrue(runner_scene_is_compiled(self.project, self.info))

    def test_file_reference_without_target_membership_is_rejected(self):
        project = copy.deepcopy(self.project)
        objects = project['objects']
        for value in objects.values():
            if value.get('isa') == 'PBXSourcesBuildPhase':
                value['files'] = [file_id for file_id in value['files']
                                  if objects[objects[file_id]['fileRef']].get('path')
                                  != 'SceneDelegate.swift']
        self.assertFalse(runner_scene_is_compiled(project, self.info))

    def test_programmatic_windows_do_not_create_storyboard_engines(self):
        self.assertNotIn('UIMainStoryboardFile', self.info)
        configurations = self.info['UIApplicationSceneManifest']['UISceneConfigurations']
        for scene in configurations['UIWindowSceneSessionRoleApplication']:
            self.assertNotIn('UISceneStoryboardFile', scene)


if __name__ == '__main__':
    unittest.main()
