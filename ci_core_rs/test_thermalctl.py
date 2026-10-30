"""Execute the actual helper against isolated directories and fake Android APIs."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ThermalTransactionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='picters-thermal-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.state = self.root / 'state'
        self.config = self.root / 'vendor' / 'config'
        self.tx = self.config.parent / '.picters-transaction'
        self.config.mkdir(parents=True)
        self.original = b'original-profile'
        (self.config / 'thermal-normal.conf').write_bytes(self.original)
        (self.config / 'unmanaged.conf').write_bytes(b'unmanaged')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'], FIXTURE=str(self.root))
        (self.root / 'pid').write_text('100')
        (self.root / 'boot').write_text('boot-A')
        self.stub('id', 'echo 0')
        self.stub('chown', ':')
        self.stub('restorecon', ':')
        self.stub('getprop', '''case "$1" in
ro.product.device) echo pudding;;
ro.vendor.build.fingerprint) echo fixture-vendor;;
init.svc.mi_thermald) echo running;;
esac''')
        self.stub('pidof', 'cat "$FIXTURE/pid"')
        self.stub('setprop', '''if [ -f "$FIXTURE/fail-restart" ]; then
rm "$FIXTURE/fail-restart"; exit 1
fi
value=$(cat "$FIXTURE/pid")
echo $((value + 1)) > "$FIXTURE/pid"''')
        source = (Path(__file__).parent / 'src' / 'thermalctl.sh').read_text()
        source = source.replace('STATE=/data/adb/picters_modules_manager/thermal', f'STATE={self.state}')
        source = source.replace('CONFIG=/data/vendor/thermal/config', f'CONFIG={self.config}')
        source = source.replace('TX=/data/vendor/thermal/.picters-transaction', f'TX={self.tx}')
        source = source.replace('/proc/sys/kernel/random/boot_id', str(self.root / 'boot'))
        self.helper = self.root / 'thermalctl.sh'
        self.helper.write_text(source)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\nset -eu\n' + body + '\n')
        path.chmod(0o755)

    def stage(self, value=b'A' * 16, persist=False):
        stage = self.state / 'stage'
        (stage / 'files').mkdir(parents=True, exist_ok=True)
        (stage / 'files' / 'thermal-normal.conf').write_bytes(value)
        (stage / 'files' / 'thermal-video.conf').write_bytes(value)
        manifest = ''.join(hashlib.sha256(value).hexdigest() + '  ' + name + '\n'
                           for name in ['thermal-normal.conf', 'thermal-video.conf'])
        (stage / 'manifest.sha256').write_text(manifest)
        (stage / 'vendor-fingerprint').write_text('fixture-vendor\n')
        (stage / 'target').write_text('55\n')
        (stage / 'persist').write_text('1\n' if persist else '0\n')

    def run_helper(self, command, ok=True, arguments=()):
        result = subprocess.run(['sh', str(self.helper), command, *arguments], env=self.env,
                                capture_output=True, text=True, timeout=10)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def assert_original(self):
        self.assertEqual((self.config / 'thermal-normal.conf').read_bytes(), self.original)
        self.assertFalse((self.config / 'thermal-video.conf').exists())

    def test_apply_update_restore_preserves_unmanaged_changes(self):
        self.stage()
        self.run_helper('apply')
        self.assertEqual((self.config / 'thermal-normal.conf').read_bytes(), b'A' * 16)
        (self.config / 'unmanaged.conf').write_bytes(b'changed elsewhere')
        self.stage(b'B' * 16)
        self.run_helper('apply')
        self.run_helper('restore')
        self.assert_original()
        self.assertEqual((self.config / 'unmanaged.conf').read_bytes(), b'changed elsewhere')
        self.assertFalse((self.state / 'session').exists())

    def test_new_config_directory_has_system_readable_mode(self):
        shutil.rmtree(self.config)
        self.stage()
        self.run_helper('apply')
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o750)
        self.assertEqual((self.config / 'thermal-normal.conf').stat().st_mode & 0o777, 0o640)
        self.run_helper('restore')
        self.assertFalse((self.config / 'thermal-normal.conf').exists())

    def test_checksum_and_fingerprint_failure_never_touch_live_files(self):
        self.stage()
        stage = self.state / 'stage'
        (stage / 'vendor-fingerprint').write_text('other-vendor')
        self.run_helper('apply', ok=False)
        self.assert_original()
        self.stage()
        (stage / 'files' / 'thermal-normal.conf').write_bytes(b'X' * 16)
        self.run_helper('apply', ok=False)
        self.assert_original()

    def test_service_failure_restores_files_and_metadata(self):
        self.stage()
        (self.root / 'fail-restart').touch()
        self.run_helper('apply', ok=False)
        self.assert_original()
        self.assertFalse(self.tx.exists())
        self.assertFalse((self.state / 'session').exists())

    def test_external_managed_edit_is_preserved_and_blocks_restore(self):
        self.stage()
        self.run_helper('apply')
        (self.config / 'thermal-normal.conf').write_bytes(b'external override')
        self.run_helper('restore', ok=False)
        self.assertEqual((self.config / 'thermal-normal.conf').read_bytes(), b'external override')
        self.assertTrue((self.state / 'session' / 'original' / 'thermal-normal.conf').exists())

    def test_nonpersistent_boot_restores_and_persistent_boot_keeps_files(self):
        self.stage(persist=True)
        self.run_helper('apply')
        self.run_helper('boot')
        self.assertEqual((self.config / 'thermal-normal.conf').read_bytes(), b'A' * 16)
        (self.state / 'session' / 'persist').write_text('0')
        self.run_helper('boot')
        self.assert_original()

    def test_persistence_toggle_updates_only_the_active_session(self):
        self.stage()
        self.run_helper('apply')
        self.run_helper('persist', arguments=('1',))
        status = self.run_helper('status').stdout
        self.assertIn('target=55', status)
        self.assertIn('persist=1', status)
        self.run_helper('persist', ok=False, arguments=('2',))
        self.run_helper('boot')
        self.assertEqual((self.config / 'thermal-normal.conf').read_bytes(), b'A' * 16)

    def test_killed_transaction_is_recovered_on_next_boot(self):
        real_mv = shutil.which('mv')
        self.stub('mv', f'''"{real_mv}" "$@"
if [ "$2" = "{self.config}" ] && [ -f "$FIXTURE/kill-swap" ]; then
rm "$FIXTURE/kill-swap"
kill -9 "$PPID"
fi''')
        self.stage()
        (self.root / 'kill-swap').touch()
        self.run_helper('apply', ok=False)
        self.assertTrue(self.tx.exists())
        (self.root / 'boot').write_text('boot-B')
        self.run_helper('boot')
        self.assert_original()
        self.assertFalse(self.tx.exists())


if __name__ == '__main__':
    unittest.main()
