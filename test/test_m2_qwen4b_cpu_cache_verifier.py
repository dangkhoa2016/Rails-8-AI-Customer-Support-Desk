#!/usr/bin/env python3
"""Offline regression checks for official Hugging Face LFS/Git blob verification.
All files are tiny fixtures. No GPU, network, Volume or real model weights.
"""
from pathlib import Path
import hashlib,importlib.util,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("m2_cpu_cache",ROOT/"modal_app/m2_qwen4b_cpu_cache.py")
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class LfsAndGitBlobTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.path=Path(self.tmp.name)/"fake.safetensors"
        self.payload=b"synthetic weights fixture only"
        self.path.write_bytes(self.payload)
        n=len(self.payload)
        self.git_sha=hashlib.sha1(f"blob {n}\0".encode()+self.payload).hexdigest()
        self.lfs_sha=hashlib.sha256(self.payload).hexdigest()
        self.entry={'name':'fake.safetensors','bytes':n,
           'git_blob_sha1':self.git_sha,'lfs_sha256':self.lfs_sha}
    def tearDown(self):self.tmp.cleanup()
    def test_lfs_must_match_sha256(self):
        self.assertIsNotNone(module.verify(self.path,self.entry))
    def test_lfs_does_not_wrongly_compare_pointer_sha1(self):
        e=dict(self.entry,git_blob_sha1="0"*40)
        self.assertIsNotNone(module.verify(self.path,e))
    def test_corrupt_lfs_sha256_rejected(self):
        e=dict(self.entry,lfs_sha256="0"*64)
        self.assertIsNone(module.verify(self.path,e))
    def test_lfs_wrong_byte_size_rejected(self):
        e=dict(self.entry,bytes=self.entry['bytes']+1)
        self.assertIsNone(module.verify(self.path,e))
    def test_git_blob_sha1_checked_when_not_lfs(self):
        e=dict(self.entry,lfs_sha256=None)
        self.assertIsNotNone(module.verify(self.path,e))
        e['git_blob_sha1']="0"*40
        self.assertIsNone(module.verify(self.path,e))
    def test_absent_file_never_accepted(self):
        self.assertIsNone(module.verify(Path(self.tmp.name)/"missing",self.entry))
if __name__=="__main__":unittest.main(verbosity=2)
