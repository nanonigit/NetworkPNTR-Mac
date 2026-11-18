import sys
from pathlib import Path
import unittest
from unittest.mock import patch
import subprocess
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
from probe_cloud_process_context import require_public_ipv4, classify_pair, resolve_public_ipv4


class CloudProcessContextTests(unittest.TestCase):
    def test_fixed_vendor_probe_rejects_nonpublic_or_malformed_addresses(self):
        for address in ['127.0.0.1', '10.0.0.1', '169.254.169.254', '198.18.0.1', '::1', '8.8.8.8;command', '']:
            with self.subTest(address=address), self.assertRaises(ValueError):
                require_public_ipv4(address)
        self.assertEqual(require_public_ipv4('162.159.140.245'), '162.159.140.245')

    def test_process_difference_is_observed_without_attributing_firewall_cause(self):
        self.assertEqual(classify_pair({'result':2,'httpStatus':0}, {'result':0,'httpStatus':401}), 'process-context-difference')
        self.assertEqual(classify_pair({'result':0,'httpStatus':401}, {'result':0,'httpStatus':401}), 'both-reached-upstream')
        self.assertEqual(classify_pair({'result':2,'httpStatus':0}, {'result':2,'httpStatus':0}), 'unresolved')
        self.assertEqual(classify_pair({'result':0,'httpStatus':403}, {'result':0,'httpStatus':200}), 'unresolved')

    def test_dns_timeout_propagates_without_fallback(self):
        with patch('probe_cloud_process_context.subprocess.run', side_effect=subprocess.TimeoutExpired('resolver', 8)) as run:
            with self.assertRaises(subprocess.TimeoutExpired):
                resolve_public_ipv4({})
            self.assertEqual(run.call_args.kwargs['timeout'], 8)

    def test_empty_or_private_dns_results_are_rejected(self):
        for data in [b'[]', b'["127.0.0.1"]']:
            with patch('probe_cloud_process_context.subprocess.run', return_value=subprocess.CompletedProcess([], 0, data)):
                with self.assertRaises(ValueError):
                    resolve_public_ipv4({})


if __name__ == '__main__':
    unittest.main()
