import tempfile
import pathlib
import subprocess
import sys
import unittest

HERE=pathlib.Path(__file__).resolve().parents[1]
PATCHER=HERE/'script'/'apply_test_404_hotfix.py'
class Test404Hotfix(unittest.TestCase):
    def fixture(self, content):
        tmp=tempfile.TemporaryDirectory()
        base=pathlib.Path(tmp.name)
        path=base/'config/environments/test.rb'
        path.parent.mkdir(parents=True)
        path.write_text(content)
        return tmp,base,path
    def execute(self,base):
        return subprocess.run([sys.executable,str(PATCHER),str(base)],capture_output=True,text=True)
    def test_changes_only_intended_line(self):
        original='Rails.application.configure do\n  config.action_dispatch.show_exceptions = :none\n  config.action_controller.allow_forgery_protection = true\nend\n'
        tmp,base,path=self.fixture(original)
        with tmp:
            got=self.execute(base)
            self.assertEqual(0,got.returncode,got.stderr)
            expected=original.replace('show_exceptions = :none','show_exceptions = :rescuable')
            self.assertEqual(expected,path.read_text())
            self.assertEqual(original,(path.parent/'test.rb.pre-404-hotfix.bak').read_text())
    def test_idempotent(self):
        tmp,base,path=self.fixture('  config.action_dispatch.show_exceptions = :none\n')
        with tmp:
            self.assertEqual(0,self.execute(base).returncode)
            content=path.read_bytes()
            second=self.execute(base)
            self.assertEqual(0,second.returncode)
            self.assertIn('ALREADY_APPLIED',second.stdout)
            self.assertEqual(content,path.read_bytes())
    def test_rejects_unexpected_mode(self):
        tmp,base,path=self.fixture('  config.action_dispatch.show_exceptions = :all\n')
        with tmp:
            got=self.execute(base)
            self.assertNotEqual(0,got.returncode)
            self.assertIn('ABORT',got.stderr)
            self.assertIn(':all',path.read_text())
    def test_rejects_multiple_assignments(self):
        tmp,base,path=self.fixture('config.action_dispatch.show_exceptions = :none\nconfig.action_dispatch.show_exceptions = :none\n')
        with tmp:
            self.assertNotEqual(0,self.execute(base).returncode)
            self.assertEqual(2,path.read_text().count(':none'))
    def test_rejects_missing_rails_test_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            got=self.execute(pathlib.Path(tmp))
            self.assertNotEqual(0,got.returncode)
    def test_preserves_inline_comment(self):
        tmp,base,path=self.fixture('  config.action_dispatch.show_exceptions = :none # test harness\n')
        with tmp:
            self.assertEqual(0,self.execute(base).returncode)
            self.assertIn('= :rescuable  # test harness',path.read_text())

if __name__=='__main__': unittest.main(verbosity=2)
