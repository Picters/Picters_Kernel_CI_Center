"""Exercise the actual policy helper with isolated fake Android/driver APIs."""
from pathlib import Path
import os
import signal
import subprocess
import tempfile
import time
import unittest


class ChargingPolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='picters-charging-policy-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.state = self.root / 'state'
        self.sys = self.root / 'sys'
        self.sys.mkdir()
        self.thermal = self.root / 'thermal'
        self.thermal.write_text('off')
        (self.sys / 'capabilities').write_text('PMM_MCA_TARGET_V1 leased own_votes\n')
        (self.sys / 'power_target').write_text('0')
        (self.sys / 'status').write_text('target_w=0 input_ma=0 battery_ma=0 error=0\n')
        (self.root / 'expected-kernel').write_text('fixture-kernel')
        self.stub('id', 'echo 0')
        self.stub('uname', 'echo fixture-kernel')
        self.stub('getprop', 'case "$1" in ro.product.device) echo pudding;; *) echo fixture-vendor;; esac')
        self.stub('sleep', 'exec /usr/bin/sleep 0.02')
        self.stub('sha256sum', '''case "$1" in
*mca_voter.ko) echo ceff20058204d5a7b0afbb48914621f2dba71d85c3a77d5a623dfae90d418277;;
*mca_strategy_buckchg.ko) echo ab9edb92cdd5a58d38ee4ae509435ab94b42587fea8004618998e9ad1fdb851c;;
*mca_strategy_quickchg.ko) echo 95f9802c72595131f7b155bd9ed05ef924dd85d819e57bc23ffdc6da0011eb8e;;
esac''')
        source = (Path(__file__).parent / 'src/chargingctl.sh').read_text()
        source = source.replace('STATE=/data/adb/picters_modules_manager/charging', f'STATE={self.state}')
        source = source.replace('THERMAL=/data/adb/picters_modules_manager/thermal/session/target', f'THERMAL={self.thermal}')
        source = source.replace('SYS=/sys/kernel/picters_charging', f'SYS={self.sys}')
        source = source.replace('/sys/module/', str(self.root / 'modules') + '/')
        for module in ['mca_voter', 'mca_strategy_buckchg', 'mca_strategy_quickchg']:
            (self.root / 'modules' / module).mkdir(parents=True)
        source = source.replace('  printf \'%s\\n\' "$value" > "$SYS/power_target"', '''  [ ! -f "$MODDIR/reject" ] || [ "$value" != 55 ] || return 1
  printf '%s\\n' "$value" >> "$MODDIR/writes"
  printf '%s\\n' "$value" > "$SYS/power_target"
  printf 'target_w=%s input_ma=0 battery_ma=0 error=0\\n' "$value" > "$SYS/status"''')
        self.helper = self.root / 'chargingctl.sh'
        self.helper.write_text(source)
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'])
        self.addCleanup(self.stop_worker)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    def run_helper(self, *args, ok=True):
        result = subprocess.run(['sh', str(self.helper), *args], env=self.env,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return result

    def stop_worker(self):
        owner = self.state / 'daemon.lock/owner'
        if owner.exists():
            pid = int(owner.read_text().split()[0])
            cmdline = Path(f'/proc/{pid}/cmdline')
            if cmdline.exists() and str(self.helper).encode() in cmdline.read_bytes():
                os.kill(pid, signal.SIGTERM)

    def wait_released(self):
        for _ in range(100):
            if not (self.state / 'daemon.lock').exists():
                return
            time.sleep(0.02)
        self.fail('Worker did not release its lifecycle lock')

    def test_target_off_stock_and_reboot_policy(self):
        self.run_helper('apply', '55', '1')
        self.assertIn('power_target=55', self.run_helper('status').stdout)
        self.run_helper('apply', 'off', '1')
        self.assertEqual((self.sys / 'power_target').read_text().strip(), '0')
        self.assertIn('charging=1', self.run_helper('status').stdout)
        self.run_helper('restore')
        self.wait_released()
        self.assertFalse((self.state / 'policy').exists())
        self.run_helper('apply', '60', '0')
        self.run_helper('restore')
        self.wait_released()
        (self.state / 'policy').write_text('60\n0\nfixture-vendor\n')
        self.run_helper('boot')
        self.assertFalse((self.state / 'policy').exists())
        (self.state / 'policy').write_text('60\n1\nfixture-vendor\n')
        self.run_helper('boot')
        self.assertEqual((self.sys / 'power_target').read_text().strip(), '60')
        self.run_helper('restore')
        self.wait_released()

    def test_thermal_and_module_disable_restore_the_own_request(self):
        for trigger in ['thermal', 'disable']:
            self.thermal.write_text('off')
            (self.root / 'disable').unlink(missing_ok=True)
            self.run_helper('apply', '55', '0')
            if trigger == 'thermal':
                self.thermal.write_text('50')
            else:
                (self.root / 'disable').touch()
            self.wait_released()
            self.assertEqual((self.sys / 'power_target').read_text().strip(), '0')
            self.assertFalse((self.state / 'policy').exists())

    def test_unsupported_abi_and_invalid_inputs_cannot_change_target(self):
        for target in ['0', '121', '-1', '5.5', 'off;echo']:
            self.run_helper('apply', target, '0', ok=False)
        self.stub('sha256sum', 'echo unknown')
        self.run_helper('apply', '55', '0', ok=False)
        self.assertFalse((self.root / 'writes').exists())

    def test_rejected_update_preserves_previous_configuration(self):
        self.run_helper('apply', '60', '1')
        (self.root / 'reject').touch()
        self.run_helper('apply', '55', '0', ok=False)
        self.assertEqual((self.state / 'policy').read_text(), '60\n1\nfixture-vendor\n')
        self.assertEqual((self.sys / 'power_target').read_text().strip(), '60')
        self.run_helper('restore')
        self.wait_released()

    def test_saved_request_is_not_reported_active_after_driver_loses_it(self):
        self.run_helper('apply', '55', '0')
        for _ in range(100):
            if len((self.root / 'writes').read_text().splitlines()) >= 2:
                break
            time.sleep(0.02)
        self.stop_worker()
        self.wait_released()
        (self.sys / 'power_target').write_text('0')
        (self.sys / 'status').write_text('target_w=0 input_ma=0 battery_ma=0 error=0\n')
        self.assertIn('charging=0', self.run_helper('status').stdout)
        self.run_helper('restore')


if __name__ == '__main__':
    unittest.main()
