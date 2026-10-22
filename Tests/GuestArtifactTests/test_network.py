from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'guest'))
import check_network


class NetworkIsolationTests(unittest.TestCase):
    def fixture(self, root):
        interfaces = root / 'net'
        interfaces.mkdir()
        for name, flags in [('lo', '0x9'), ('gre0', '0x80')]:
            interface = interfaces / name
            interface.mkdir()
            (interface / 'flags').write_text(flags)
        (interfaces / 'bonding_masters').write_text('')
        ipv4 = root / 'route'
        ipv4.write_text('Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT\n')
        ipv6 = root / 'ipv6_route'
        ipv6.write_text('0 0 0 0 0 0 0 0 0 lo\n')
        return interfaces, ipv4, ipv6

    def test_inactive_kernel_virtual_devices_are_not_external_connectivity(self):
        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary))
            result = check_network.inspect(*paths)
            self.assertEqual(result['network_interfaces'], 'gre0,lo')
            self.assertTrue(check_network.is_isolated(result))

    def test_hardware_up_or_route_each_fail_closed(self):
        for kind in ['hardware', 'up', 'ipv4', 'ipv6']:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temporary:
                paths = self.fixture(Path(temporary))
                if kind == 'hardware':
                    (paths[0] / 'gre0/device').symlink_to('/missing-device')
                elif kind == 'up':
                    (paths[0] / 'gre0/flags').write_text('0x81')
                elif kind == 'ipv4':
                    paths[1].write_text(paths[1].read_text() + 'gre0 00000000 00000000 0001\n')
                else:
                    paths[2].write_text('0 0 0 0 0 0 0 0 0 gre0\n')
                self.assertFalse(check_network.is_isolated(check_network.inspect(*paths)))

    def test_missing_evidence_is_not_isolation(self):
        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary))
            (paths[0] / 'gre0/flags').unlink()
            with self.assertRaises(FileNotFoundError):
                check_network.inspect(*paths)
