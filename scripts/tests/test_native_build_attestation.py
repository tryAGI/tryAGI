import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('attestation', Path(__file__).parents[1] / 'native-build-attestation.py')
attestation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(attestation)
verify_spec = importlib.util.spec_from_file_location('provenance', Path(__file__).parents[1] / 'verify-native-provenance.py')
provenance = importlib.util.module_from_spec(verify_spec)
verify_spec.loader.exec_module(provenance)


class NativeBuildAttestationTests(unittest.TestCase):
    def setUp(self):
        if not shutil.which('cc'):
            self.skipTest('native compiler unavailable')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / 'natives').mkdir()
        self.marker = self.root / 'started'
        self.marker.touch()
        self.source = self.root / 'fixture.c'
        self.source.write_text('int fixture(void) { return 42; }\n')
        self.output = self.root / 'natives/libfixture.so'
        self.rid = ('osx' if sys.platform == 'darwin' else 'linux') + ('-arm64' if platform.machine() in ('arm64', 'aarch64') else '-x64')
        command = ['cc', '-dynamiclib' if sys.platform == 'darwin' else '-shared', '-fPIC', str(self.source), '-o', str(self.output)]
        if sys.platform == 'darwin':
            command = ['host-build-admission', '--'] + command
        subprocess.run(command, check=True, capture_output=True, timeout=180)
        self.manifest = {'schema_version': 1, 'components': [{'id': 'fixture'}], 'inputs': [],
                         'artifacts': [{'path': 'natives/libfixture.so', 'sha256': attestation.digest(self.output),
                                        'components': ['fixture'], 'package_paths': [f'runtimes/{self.rid}/native/libfixture.so'],
                                        'build_attestation': 'unknown'}]}
        (self.root / 'NATIVE_PROVENANCE.json').write_text(json.dumps(self.manifest))

    def record(self, **overrides):
        args = dict(root=self.root, rid=self.rid, kind='build', started=self.marker,
                    sources=[self.source], tools=['cc'], parameters=['flags=-shared/-dynamiclib -fPIC'],
                    command='cc fixture.c -o natives/libfixture.so')
        args.update(overrides)
        return attestation.record(**args)

    def test_real_build_receipt_contains_inputs_compiler_and_outputs(self):
        path = self.record()
        receipt = json.loads(path.read_text())
        self.assertEqual(path.stem, attestation.digest(path))
        self.assertEqual(receipt['sources'][0]['sha256'], attestation.digest(self.source))
        self.assertTrue(receipt['toolchain'][0]['version'])
        self.assertEqual(receipt['outputs'][0]['sha256'], attestation.digest(self.output))
        self.assertEqual(attestation.check(self.root, receipt), 'build')
        self.assertEqual(provenance.verify(self.root), ([], []))

    def test_stale_output_cannot_be_attested(self):
        stamp = self.marker.stat().st_mtime_ns
        os.utime(self.output, ns=(stamp - 1, stamp - 1))
        with self.assertRaisesRegex(ValueError, 'stale output'):
            self.record()
        self.assertFalse((self.root / 'natives/attestations').exists())

    def test_missing_source_does_not_create_receipt(self):
        with self.assertRaisesRegex(ValueError, 'missing source'):
            self.record(sources=[self.root / 'missing'])
        self.assertFalse((self.root / 'natives/attestations').exists())

    def test_import_is_distinguished_from_compilation(self):
        receipt = json.loads(self.record(kind='import').read_text())
        self.assertEqual(attestation.check(self.root, receipt), 'import')
        self.assertIn('unknown', receipt['upstream_compiler_provenance'])
        self.assertEqual(provenance.verify(self.root), ([], ['natives/libfixture.so']))

    def test_wrong_rid_is_rejected(self):
        self.manifest['artifacts'][0]['package_paths'] = ['runtimes/win-x64/native/libfixture.so']
        (self.root / 'NATIVE_PROVENANCE.json').write_text(json.dumps(self.manifest))
        with self.assertRaisesRegex(ValueError, 'architecture/format'):
            self.record(rid='win-x64')

    def test_tampered_output_invalidates_receipt(self):
        receipt = json.loads(self.record().read_text())
        self.output.write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'output differs'):
            attestation.check(self.root, receipt)


if __name__ == '__main__':
    unittest.main()
