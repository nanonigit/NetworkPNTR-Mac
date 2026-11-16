import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
import skill_overrides


class SkillOverrideTests(unittest.TestCase):
    def test_build_requires_the_named_local_docker_builder(self):
        local = 'Name: desktop-linux\nDriver: docker\nEndpoint: desktop-linux\n'
        with patch('skill_overrides.docker', side_effect=['unix:///tmp/docker.sock', local]), patch.object(Path, 'is_socket', return_value=True):
            skill_overrides.require_local_builder()
        with patch('skill_overrides.docker', return_value='tcp://remote:2375'):
            with self.assertRaises(ValueError):
                skill_overrides.require_local_builder()
        with patch('skill_overrides.docker', side_effect=['unix:///tmp/docker.sock', 'Name: desktop-linux\nDriver: remote\nEndpoint: remote\n']), patch.object(Path, 'is_socket', return_value=True):
            with self.assertRaises(ValueError):
                skill_overrides.require_local_builder()

    def test_copy_preserves_authorized_session_policy_exactly(self):
        with tempfile.TemporaryDirectory() as temp:
            skills = Path(temp)
            skill_overrides.apply_to_context(skills)
            data = (skills / skill_overrides.RELATIVE).read_bytes()
            self.assertEqual(data, skill_overrides.SKILL.read_bytes())
            text = data.decode()
            self.assertIn('可以使用用户已经登录的真实会话', text)
            self.assertIn('替换前取得许可', text)
            self.assertIn('具体操作、测试对象及预期影响的明确许可', text)
            self.assertIn('自动工具输出也属于记录', text)
            self.assertIn('保存位置或接收方并取得许可', text)
            self.assertIn('扩展目标和原因并取得许可', text)
            self.assertIn('浏览器配置及登录会话', text)
            self.assertNotIn('stub/mock 仅用于无会话', text)
            self.assertNotIn('尝试真实登录表单提交', text)

    def test_manifest_rejects_missing_and_stale_skill_declarations(self):
        with tempfile.TemporaryDirectory() as temp:
            manifest = Path(temp) / 'manifest.json'
            for data in ({}, {'skillOverrides': {'api-recon': {'sha256': 'stale'}}}):
                manifest.write_text(json.dumps(data))
                with self.assertRaises(ValueError):
                    skill_overrides.verify_manifest(manifest)
            manifest.write_text(json.dumps({'skillOverrides': skill_overrides.declaration()}))
            self.assertEqual(skill_overrides.verify_manifest(manifest)['skillOverrides'], skill_overrides.declaration())

    def test_copy_cannot_follow_an_external_skill_directory(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'skills').mkdir()
            (root / 'external').mkdir()
            (root / 'skills/api-recon').symlink_to(root / 'external', target_is_directory=True)
            with self.assertRaises(ValueError):
                skill_overrides.apply_to_context(root / 'skills')
