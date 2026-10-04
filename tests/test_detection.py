# SPDX-License-Identifier: GPL-2.0-or-later
"""Read-only detection regression tests, using synthetic kernels/codecs."""
import pathlib
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]


class DetectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=REPO / '.work')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.release = '7.2.7-zen1-1-zen'
        self.module = self.root / 'modules' / self.release
        self.build = self.module / 'build'
        (self.build / 'include/config').mkdir(parents=True)
        (self.module / 'pkgbase').write_text('linux-zen\n')
        (self.build / 'Module.symvers').write_text('test symbol table\n')
        (self.build / '.config').write_text('CONFIG_SND_HDA_CODEC_CONEXANT=m\n')
        (self.build / 'include/config/kernel.release').write_text(self.release + '\n')
        self.codec = self.root / 'asound/card0/codec#0'
        self.codec.parent.mkdir(parents=True)
        self.codec.write_text('''Codec: Conexant SN6140
Vendor Id: 0x14f11f87
Subsystem Id: 0x19e5327e
GPIO: io=2
  IO[1]: enable=1, dir=1
Node 0x16 [Pin Complex]
  [Jack] HP Out
  Connection: 2
Node 0x17 [Pin Complex]
  [Fixed] Speaker
  Connection: 2
Node 0x18 [Pin Complex]
''')
        (self.root / 'asound/pcm').write_text('00-06: DMIC\n')
        self.prefix = '''
set -euo pipefail
die() { echo "ERROR: $*" >&2; exit 1; }
source "$1/scripts/lib/detect.sh"
sn6140_modules_root="$2/modules"
sn6140_asound_root="$2/asound"
pacman() {
  case "$1:$2" in
    -Qlq:linux-zen) printf '/usr/lib/modules/7.2.7-zen1-1-zen/pkgbase\\n' ;;
    -Q:linux-zen) echo 'linux-zen 7.2.7.zen1-1' ;;
    -Q:linux-zen-headers) echo "linux-zen-headers ${HEADERS_VERSION:-7.2.7.zen1-1}" ;;
    -Qoq:*/pkgbase) echo linux-zen ;;
    -Qoq:*/Module.symvers) echo linux-zen-headers ;;
    *) return 1 ;;
  esac
}
# An upgrade is pending: the running kernel is deliberately older.
uname() { echo '7.1.8-zen1-3-zen'; }
'''

    def run_probe(self, body, ok=True):
        result = subprocess.run(['bash', '-c', self.prefix + body, 'test', str(REPO), str(self.root)],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def test_upgrade_uses_installed_target_not_uname(self):
        output = self.run_probe('detect_installed_kernel; detect_target "$detected_kernel_release"; echo "$detected_kernel_release"')
        self.assertIn(self.release, output)

    def test_headers_package_mismatch(self):
        self.run_probe('HEADERS_VERSION=7.1.8.zen1-3; detect_target 7.2.7-zen1-1-zen', False)

    def test_headers_release_mismatch(self):
        (self.build / 'include/config/kernel.release').write_text('7.1.8-zen1-3-zen\n')
        self.run_probe('detect_target 7.2.7-zen1-1-zen', False)

    def test_missing_symbol_versions(self):
        (self.build / 'Module.symvers').unlink()
        self.run_probe('detect_target 7.2.7-zen1-1-zen', False)

    def test_builtin_driver(self):
        (self.build / '.config').write_text('CONFIG_SND_HDA_CODEC_CONEXANT=y\n')
        self.run_probe('detect_target 7.2.7-zen1-1-zen', False)

    def test_other_kernel(self):
        self.run_probe('detect_target 7.2.7-arch1-1', False)

    def test_known_codec(self):
        self.run_probe('detect_hardware')

    def test_unknown_subsystem(self):
        self.codec.write_text(self.codec.read_text().replace('19e5327e', '19e59999'))
        self.run_probe('detect_hardware', False)

    def test_wrong_pins(self):
        self.codec.write_text(self.codec.read_text().replace('[Jack] HP Out', '[Fixed] Speaker'))
        self.run_probe('detect_hardware', False)

    def test_missing_dmic(self):
        (self.root / 'asound/pcm').write_text('00-00: HDA Analog\n')
        self.run_probe('detect_hardware', False)

    def test_ambiguous_codec(self):
        (self.codec.parent / 'codec#1').write_text(self.codec.read_text())
        self.run_probe('detect_hardware', False)

    def test_manual_override_conflict(self):
        directory = self.module / 'updates/sn6140'
        directory.mkdir(parents=True)
        (directory / 'snd-hda-codec-conexant.ko.zst').write_text('old')
        self.run_probe('check_legacy_override 7.2.7-zen1-1-zen', False)

    def test_no_manual_override(self):
        self.run_probe('check_legacy_override 7.2.7-zen1-1-zen')

    def test_dkms_target_and_non_zen_exclusion(self):
        output = self.run_probe('''
kernelver=7.3.1-zen1-1-zen
source "$1/packaging/arch/dkms.conf"
[[ $kernelver =~ $BUILD_EXCLUSIVE_KERNEL ]]
[[ ! 7.3.1-arch1-1 =~ $BUILD_EXCLUSIVE_KERNEL ]]
[[ ${MAKE[0]} == *"$kernelver" ]]
[[ $PRE_INSTALL == *"$kernelver" ]]
echo "$MAKE"
''')
        self.assertIn('7.3.1-zen1-1-zen', output)


if __name__ == '__main__':
    unittest.main()
