#!/usr/bin/env python3
# Copyright (c) 2026 Design Studio Butterfly Effect
# SPDX-License-Identifier: MIT
"""Build a local source-only review candidate. Does not initialize Git or publish anything."""
import argparse, hashlib, json, re, shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
DEST=ROOT/'ReleaseCandidate/v0.1.0'

def selected():
    root_files=['.gitignore','README.md','LICENSE','THIRD_PARTY_NOTICES.md']
    for name in root_files: yield ROOT/name
    for folder in ['Spatial Modeling','Scripts','Tests','Licenses']:
        for path in (ROOT/folder).rglob('*'):
            if path.is_file() and not path.name.startswith('.') and '__pycache__' not in path.parts:yield path
    yield ROOT/'Config/Project.xcconfig'
    yield ROOT/'Spatial Modeling.xcodeproj/project.pbxproj'
    for name in ['BUILDING.md','DEVICE_TESTING.md','LICENSING.md','HYBRID_MODELING.md','RELEASE_CHECKLIST.md','Media/README.md']:yield ROOT/'Docs'/name
    native=ROOT/'Native/SolidCore'
    for name in ['Cargo.toml','Cargo.lock','rust-toolchain.toml','UPSTREAM.json','PHASE3.json','PHASE32.json']:yield native/name
    for folder in ['Bridge','Conversion']:
        for path in (native/folder).rglob('*'):
            if path.is_file() and '__pycache__' not in path.parts:yield path
    vendor=native/'Vendor/SolidCore'
    for name in ['Cargo.toml','LICENSE','NOTICE','ATTRIBUTION.md','clippy.toml']:yield vendor/name
    # Only source/docs/manifests: omit upstream binary fixtures, images and JSON test corpora.
    for path in (vendor/'crates').rglob('*'):
        if path.is_file() and (path.suffix in {'.rs','.toml','.md'} or path.name in {'LICENSE','NOTICE','ATTRIBUTION.md'}):yield path

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--replace-approved-candidate',action='store_true',help='Replace a marked local candidate only with explicit owner authorization. Does not certify hardware testing or authorize publication.')
    args=parser.parse_args()
    if DEST.exists() and not args.replace_approved_candidate:
        parser.error('Replacing the existing local candidate requires explicit owner authorization and --replace-approved-candidate. Publication is a separate approval.')
    if DEST.exists():
        assert (DEST/'.release-candidate').is_file(),'Refusing to replace an unmarked directory'
        shutil.rmtree(DEST)
    DEST.mkdir(parents=True)
    (DEST/'.release-candidate').write_text('Private review candidate. No repository created or publication authorized.\n')
    files=[]
    for source in sorted(set(selected())):
        assert source.is_file() and not source.is_symlink(),'Missing/unsafe source: '+str(source.relative_to(ROOT))
        relative=source.relative_to(ROOT);target=DEST/relative;target.parent.mkdir(parents=True,exist_ok=True)
        data=source.read_bytes()
        if relative.as_posix()=='Spatial Modeling.xcodeproj/project.pbxproj':
            # Keep the working project's private signing setup; never publish its Team.
            data,count=re.subn(rb'DEVELOPMENT_TEAM = [^;]*;',b'DEVELOPMENT_TEAM = "$(SPATIAL_DEVELOPMENT_TEAM)";',data)
            assert count==2,'Expected Debug/Release signing settings'
        target.write_bytes(data);target.chmod(0o755 if target.suffix in {'.py','.sh'} else 0o644)
        files.append({'path':str(relative),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
    manifest={'repository_owner':'Nippar-DSBE','repository_full_name':'Nippar-DSBE/Spatial-Modeling','repository_url':'https://github.com/Nippar-DSBE/Spatial-Modeling','repository_name':'Spatial-Modeling','planned_visibility':'Public','description':'Native hybrid Mesh and CAD modeling for Apple Vision Pro, powered by Swift, RealityKit, and Rust.','version':'0.1.0','license_approval_pending':False,'hardware_verification_pending':True,'publication_authorized':False,'prebuilt_binaries':False,'stl_export_included':False,'files':files}
    (DEST/'PUBLIC_FILES.json').write_text(json.dumps(manifest,indent=2)+'\n')
    private=ROOT/'Artifacts/Publication-v0.1.0';private.mkdir(parents=True,exist_ok=True)
    (private/'public-files.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Prepared source-only v0.1.0 review candidate: %d files, %.1f MiB. Not published.'%(len(files),sum(f['bytes'] for f in files)/1048576))
