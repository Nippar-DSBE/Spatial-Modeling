#!/usr/bin/env python3
# Copyright (c) 2026 Design Studio Butterfly Effect
# SPDX-License-Identifier: MIT
"""Verify the actual bundled license texts against the locked source packages; no network."""
import argparse, hashlib, json, os, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def sha(data): return hashlib.sha256(data).hexdigest()
def lock_packages():
    result = []
    for block in (ROOT/'Native/SolidCore/Cargo.lock').read_text().split('[[package]]')[1:]:
        name = re.search(r'^name = "([^"]+)"', block, re.M).group(1)
        version = re.search(r'^version = "([^"]+)"', block, re.M).group(1)
        result.append((name, version))
    return result

def audit(cache_home):
    packages = json.loads((ROOT/'Licenses/SolidCore/dependencies.json').read_text())
    assert set(lock_packages()) == {(p['name'],p['version']) for p in packages} | {('solidcore-probe-bridge','0.1.0'),('spatial-mesh-cad','0.1.0')}, 'Lockfile coverage mismatch'
    reports = []
    for package in packages:
        name,version = package['name'],package['version']
        if name.startswith('solidcore'):
            source = ROOT/'Native/SolidCore/Vendor/SolidCore'
        else:
            candidates = list((cache_home/'registry/src').glob('*/'+name+'-'+version))
            assert len(candidates)==1, 'Need cached source package: '+name+'-'+version
            source=candidates[0]
            manifest=(source/'Cargo.toml').read_text()
            declaration=re.search(r'^license = "([^"]+)"',manifest,re.M)
            assert declaration and declaration.group(1)==package['license'], 'License declaration mismatch: '+name
        texts=[]
        for relative in package['license_files']:
            path=ROOT/relative
            raw=path.read_bytes();text=raw.decode('utf-8')
            assert len(text)>50, 'Missing or truncated license/notice text: '+relative
            original_name = path.name.removeprefix('SolidCore-')
            originals=list(source.rglob(original_name)) if name.startswith('solidcore') else [source/original_name]
            matches=[p for p in originals if p.is_file() and p.read_bytes()==raw]
            assert matches,'Bundled license is not identical to source: '+relative
            texts.append({'file':relative,'sha256':sha(raw),'bytes':len(raw),'matches_original':True})
        reports.append({**package,'verified_texts':texts})
    kernel=ROOT/'Native/SolidCore/Vendor/SolidCore'
    assert (kernel/'NOTICE').read_bytes()==(ROOT/'Licenses/SolidCore/SolidCore-NOTICE').read_bytes()
    assert (kernel/'LICENSE').read_bytes()==(ROOT/'Licenses/SolidCore/SolidCore-LICENSE').read_bytes()
    assert (ROOT/'Native/SolidCore/Conversion/LICENSE').read_bytes()==(ROOT/'LICENSE').read_bytes()
    runtime = ROOT/'Licenses/Rust-1.99.1'
    provenance = json.loads((runtime/'PROVENANCE.json').read_text())
    for name,digest in provenance['files'].items():
        assert sha((runtime/name).read_bytes())==digest, 'Rust runtime notice changed: '+name
    assert (runtime/'COPYRIGHT-library.html').read_bytes()==(ROOT/'Spatial Modeling/Resources/RustStandardLibraryNotices.html').read_bytes()
    return {'locked_packages':len(lock_packages()),'third_party_packages':len(reports),'all_license_texts_match_original':True,
            'solidcore_commit':json.loads((ROOT/'Native/SolidCore/UPSTREAM.json').read_text())['solidcore_commit'],
            'packages':reports,'rust_runtime_notices_verified':True,'original_app_license':'MIT; Copyright (c) 2026 Design Studio Butterfly Effect; owner approved','bridge_license':'Apache-2.0','local_conversion_crate_license':'MIT; Copyright (c) 2026 Design Studio Butterfly Effect'}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=ROOT/'Artifacts/Phase3.2/license-audit.json');args=parser.parse_args()
    cargo=Path(os.environ.get('CARGO_HOME',str(Path.home()/'.cargo')))
    dedicated=Path.home()/'.local/share/solidcore-probe/cargo'
    if not (cargo/'registry/src').exists() and dedicated.exists():cargo=dedicated
    result=audit(cargo);args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,indent=2)+'\n')
    print('PASS: %d locked packages; %d third-party packages; every bundled license text matches its original.'%(result['locked_packages'],result['third_party_packages']))
