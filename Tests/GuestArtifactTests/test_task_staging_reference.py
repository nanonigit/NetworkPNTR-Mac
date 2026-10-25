from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
import task_staging_reference as reference


class TaskStagingReferenceTests(unittest.TestCase):
    def item(self, name='fixture.bin', size=70001):
        return {'name': name, 'path': 'uploads/' + name, 'size': size,
                'abs': '/state/data/drafts/' + reference.DRAFT + '/uploads/' + name}

    def test_fixed_metadata_and_byte_spelling_are_required(self):
        self.assertEqual(reference.validate_attachment(self.item(), 'fixture.bin', 70001), self.item())
        for item in [self.item('other.bin'), self.item(size=1), {**self.item(), 'abs': '/Users/private/file'},
                     {**self.item(), 'path': '../fixture.bin'}, {**self.item(), 'size': True}, {}]:
            with self.assertRaises(RuntimeError):
                reference.validate_attachment(item, 'fixture.bin', 70001)
        name = reference.INPUT_NAMES[3]
        self.assertIn('e\u0301', name)
        with self.assertRaises(RuntimeError):
            reference.validate_attachment(self.item('日本-é.txt', 1280), name, 1280)

    def test_fixture_content_inventory_matches_native(self):
        self.assertEqual([len(data) for data in reference.CONTENTS], [70001, 0, 28, 1280])
        self.assertEqual(reference.FIRST_NAMES[:3], ['fixture.bin', 'empty.txt', 'fixture-1.bin'])
        self.assertEqual(reference.REPEAT_NAMES[:3], ['fixture-2.bin', 'empty-1.txt', 'fixture-3.bin'])
        self.assertEqual(reference.CONTENTS[0][:256], bytes(range(256)))
        self.assertEqual(reference.CONTENTS[3][:251], bytes(range(251)))


if __name__ == '__main__':
    unittest.main()
