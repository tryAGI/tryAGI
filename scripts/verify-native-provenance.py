#!/usr/bin/env python3
"""Verify recorded native assets and source inputs without rebuilding or rebaselining."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def native_files(root):
    return sorted(p.relative_to(root).as_posix() for p in (root / 'natives').rglob('*')
                  if p.is_file() and re.search(r'\.(dll|dylib|so(?:\.\d+)*)$', p.name))


def verify(root, require_complete=False):
    root = root.resolve()
    manifest = json.loads((root / 'NATIVE_PROVENANCE.json').read_text())
    errors = []
    gaps = []
    if manifest.get('schema_version') != 1:
        raise ValueError('unsupported manifest schema')
    expected = [a['path'] for a in manifest['artifacts']]
    if len(expected) != len(set(expected)):
        errors.append('duplicate native artifact paths')
    if set(expected) != set(native_files(root)):
        errors.append('native artifact inventory differs from manifest')
    for entry in manifest['artifacts'] + manifest['inputs']:
        path = (root / entry['path']).resolve()
        if Path(entry['path']).is_absolute() or not path.is_relative_to(root):
            errors.append(f"unsafe path: {entry['path']}")
            continue
        if not path.is_file() or digest(path) != entry['sha256'] or ('size' in entry and path.stat().st_size != entry['size']):
            errors.append(f"missing or changed: {entry['path']}")
    for snapshot in manifest.get('source_trees', []):
        tracked = subprocess.check_output(['git', 'ls-files', '--', snapshot['path']],
                                          cwd=root, text=True).splitlines()
        listed = [i['path'] for i in manifest['inputs']
                  if i['path'].startswith(snapshot['path'].rstrip('/') + '/')]
        if set(tracked) != set(listed):
            errors.append(f"source inventory differs: {snapshot['path']}")
    ids = {c['id'] for c in manifest['components']}
    for entry in manifest['artifacts']:
        if not entry['components'] or not set(entry['components']).issubset(ids):
            errors.append(f"unknown component: {entry['path']}")
        if entry['build_attestation'] != 'verified':
            gaps.append(entry['path'])
    return errors, gaps


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repositories', nargs='+', type=Path)
    parser.add_argument('--require-complete', action='store_true',
                        help='also fail when historical build provenance is incomplete')
    args = parser.parse_args()
    failed = False
    for repository in args.repositories:
        root = repository.resolve()
        try:
            errors, gaps = verify(root)
            print(f'{root.name}: {len(errors)} integrity errors; {len(gaps)} historical build-attestation gaps')
            for error in errors:
                print(f'  ERROR: {error}')
            if gaps:
                print('  Hashes establish the recorded baseline, not source-to-binary reproducibility.')
            failed |= bool(errors) or (args.require_complete and bool(gaps))
        except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
            print(f'{root.name}: ERROR: {error}', file=sys.stderr)
            failed = True
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
