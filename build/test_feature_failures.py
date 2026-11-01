#!/usr/bin/env python3
"""Exercise real feature helpers with failed downloads and patches."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).with_name('apply_features.sh')
HELPERS = SOURCE.read_text().split('############################################################', 1)[0]

class FeatureFailureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'bin').mkdir()
        self.env = {**os.environ, 'CACHE':str(self.root / 'cache'), 'PATH':str(self.root / 'bin')+':'+os.environ['PATH']}

    def executable(self, name, body):
        p = self.root / 'bin' / name
        p.write_text('#!/bin/bash\n'+body)
        p.chmod(0o755)

    def run_shell(self, commands):
        return subprocess.run(['bash', '-c', HELPERS+'\n'+commands, str(SOURCE)],
            cwd=self.root, env=self.env, text=True, capture_output=True)

    def test_partial_download_not_executed(self):
        self.executable('curl', 'while [[ $# -gt 0 ]]; do if [[ $1 == -o ]]; then shift; printf "touch executed\\n" > "$1"; break; fi; shift; done\nexit 22\n')
        r = self.run_shell('run_setup unused bbg || die "download failed"; log "bbg ok"')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((self.root / 'executed').exists())
        self.assertNotIn('bbg ok', r.stdout)

    def test_setup_failure_propagates(self):
        self.executable('curl', 'while [[ $# -gt 0 ]]; do if [[ $1 == -o ]]; then shift; printf "exit 7\\n" > "$1"; break; fi; shift; done\n')
        r = self.run_shell('run_setup unused bbg || die "setup failed"; log "bbg ok"')
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn('bbg ok', r.stdout)

    def test_fetch_failure_does_not_checkout_stale_source(self):
        (self.root / 'dependency/.git').mkdir(parents=True)
        self.executable('git', 'if [[ $* == *fetch* ]]; then exit 1; fi\ntouch checked-out\n')
        r = self.run_shell('clone_pin unused deadbeef dependency || die "fetch failed"')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((self.root / 'checked-out').exists())

    def test_mode_switch_requires_clean_source(self):
        (self.root / '.resukisu-patch-state.json').write_text('{}')
        self.env['MODE'] = 'lkm'
        r = self.run_shell('log "unexpected success"')
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn('unexpected success', r.stdout)

    def test_missing_patch_fails(self):
        r = self.run_shell('require_patch missing.patch required')
        self.assertNotEqual(r.returncode, 0)

    def test_partial_patch_keeps_rejects(self):
        (self.root / 'one').write_text('old\n')
        (self.root / 'two').write_text('different\n')
        (self.root / 'change.patch').write_text('--- a/one\n+++ b/one\n@@ -1 +1 @@\n-old\n+new\n--- a/two\n+++ b/two\n@@ -1 +1 @@\n-expected\n+new\n')
        r = self.run_shell('require_patch change.patch required')
        self.assertNotEqual(r.returncode, 0)
        self.assertTrue((self.root / 'two.rej').is_file())
        self.assertIn('expected', (self.root / 'two.rej').read_text())

    def test_patch_repeat_is_idempotent(self):
        (self.root / 'one').write_text('old\n')
        (self.root / 'change.patch').write_text('--- a/one\n+++ b/one\n@@ -1 +1 @@\n-old\n+new\n')
        r = self.run_shell('require_patch change.patch required; require_patch change.patch required')
        self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
        self.assertEqual((self.root / 'one').read_text(), 'new\n')
        self.assertIn('=already', r.stdout)


if __name__ == '__main__':
    unittest.main()
