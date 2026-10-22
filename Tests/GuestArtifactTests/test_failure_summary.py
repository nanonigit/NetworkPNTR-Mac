from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'guest'))
import summarize_failure


class FailureSummaryTests(unittest.TestCase):
    def test_only_fixed_categories_can_leave_private_log(self):
        secret = 'sensitive-fixture-value'
        raw = 'open stores: password authentication failed ' + secret + '\nSIGSEGV panic: ' + secret
        found = summarize_failure.categories(raw)
        self.assertEqual(found, ['go_panic', 'signal_fault', 'database_open', 'database_auth'])
        self.assertNotIn(secret, str(found))
        self.assertEqual(summarize_failure.categories(secret), [])
