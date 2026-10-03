import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest

spec = importlib.util.spec_from_file_location('provenance', Path(__file__).parents[1] / 'verify-native-provenance.py')
provenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provenance)


class NativeProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'natives').mkdir()
        self.asset = self.root / 'natives/libfixture.so'
        self.asset.write_bytes(b'fixture')
        self.manifest = {'schema_version': 1, 'components': [{'id': 'fixture'}], 'inputs': [],
                         'artifacts': [{'path': 'natives/libfixture.so', 'sha256': provenance.digest(self.asset),
                                        'components': ['fixture'], 'build_attestation': 'unknown'}]}
        self.write_manifest()

    def write_manifest(self):
        (self.root / 'NATIVE_PROVENANCE.json').write_text(json.dumps(self.manifest))

    def test_baseline_passes_but_reports_provenance_gap(self):
        errors, gaps = provenance.verify(self.root)
        self.assertEqual(errors, [])
        self.assertEqual(gaps, ['natives/libfixture.so'])

    def test_strict_cli_fails_on_unattested_build(self):
        script = Path(__file__).parents[1] / 'verify-native-provenance.py'
        result = subprocess.run([sys.executable, str(script), '--require-complete', str(self.root)], capture_output=True)
        self.assertEqual(result.returncode, 1)

    def test_changed_binary_is_rejected(self):
        self.asset.write_bytes(b'tampered')
        self.assertTrue(provenance.verify(self.root)[0])

    def test_unrecorded_binary_is_rejected(self):
        (self.root / 'natives/unrecorded.dll').write_bytes(b'new')
        self.assertTrue(provenance.verify(self.root)[0])

    def test_path_escape_is_rejected(self):
        self.manifest['inputs'] = [{'path': '../outside', 'sha256': '0' * 64}]
        self.write_manifest()
        self.assertTrue(any('unsafe path' in e for e in provenance.verify(self.root)[0]))

    def test_duplicate_artifact_is_rejected(self):
        self.manifest['artifacts'] *= 2
        self.write_manifest()
        self.assertTrue(any('duplicate' in e for e in provenance.verify(self.root)[0]))


if __name__ == '__main__':
    unittest.main()
