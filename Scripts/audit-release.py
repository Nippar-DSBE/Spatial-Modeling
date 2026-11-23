#!/usr/bin/env python3
# Copyright (c) 2026 Design Studio Butterfly Effect
# SPDX-License-Identifier: MIT
"""Read-only candidate + existing-history audit. Findings contain locations, never secret values."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
DEST=ROOT/'ReleaseCandidate/v0.1.0'
PATTERNS={
 'private-key':re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
 'github-token':re.compile(rb'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}'),
 'aws-access-key':re.compile(rb'\bAKIA[A-Z0-9]{16}\b'),
 'api-key':re.compile(rb'\bsk-(?:proj-)?[A-Za-z0-9_-]{24,}'),
 'service-token':re.compile(rb'\bxox[baprs]-[A-Za-z0-9-]{16,}|\bAIza[A-Za-z0-9_-]{30,}|\bASIA[A-Z0-9]{16}\b'),
 'personal-signing-team':re.compile(rb'\bDEVELOPMENT_TEAM\s*=\s*"?[A-Z0-9]{10}"?\s*;'),
 'credential-assignment':re.compile(rb'''(?i)\b(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*["'][A-Za-z0-9+/=_-]{16,}["']'''),
 'machine-user-path':re.compile(rb'/(?:Users|home)/[^\s"\'<>]+|' + rb'/private/' + rb'var/folders/[^\s"\'<>]+|' + rb'/Volumes' + rb'/[^\s"\'<>]+|[A-Z]:\\Users\\[^\s"\'<>]+'),
}
FORBIDDEN_SUFFIXES={'.a','.o','.rlib','.dylib','.so','.p12','.pfx','.cer','.pem','.key','.mobileprovision','.provisionprofile','.xcuserstate','.jpg','.png','.mp4','.zip','.gz','.smb','.smd','.step','.stp','.brep','.stl'}
FORBIDDEN_PARTS={'Artifacts','DerivedData','target','.build','xcuserdata','.git','Backups','__pycache__','.aws','.ssh','.codex','.agents'}

def scan(data,path):
    findings=[]
    for label,pattern in PATTERNS.items():
        for match in pattern.finditer(data):findings.append({'path':path,'line':data[:match.start()].count(b'\n')+1,'category':label})
    return findings

def run(output):
    assert (DEST/'PUBLIC_FILES.json').is_file(),'Generate candidate first'
    findings=[];files=[]
    for path in DEST.rglob('*'):
        if path.is_symlink():findings.append({'path':str(path.relative_to(DEST)),'category':'symlink'});continue
        if not path.is_file():continue
        relative=str(path.relative_to(DEST));data=path.read_bytes();files.append(relative)
        if any(part in FORBIDDEN_PARTS for part in path.relative_to(DEST).parts) or path.suffix.lower() in FORBIDDEN_SUFFIXES or '.local.xcconfig' in path.name:
            findings.append({'path':relative,'category':'excluded-private-or-binary-file'})
        if len(data)>=100*1024*1024:findings.append({'path':relative,'category':'oversized-file'})
        if b'\0' in data:findings.append({'path':relative,'category':'unexpected-binary'})
        findings.extend(scan(data,relative))
    manifest=json.loads((DEST/'PUBLIC_FILES.json').read_text())
    expected={f['path'] for f in manifest['files']} | {'PUBLIC_FILES.json','.release-candidate'}
    for unexpected in set(files)-expected:findings.append({'path':unexpected,'category':'not-in-manifest'})
    for f in manifest['files']:
        p=DEST/f['path']
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=f['sha256']:findings.append({'path':f['path'],'category':'manifest-mismatch'})
    # No Git initialization, mutation, remote access, or publication.
    git=subprocess.run(['git','-C',str(ROOT),'rev-parse','--show-toplevel'],capture_output=True,text=True)
    history={'present':git.returncode==0,'blobs_scanned':0}
    if history['present']:
        objects=subprocess.check_output(['git','-C',str(ROOT),'rev-list','--objects','--all'],text=True)
        for item in objects.splitlines():
            oid,_,name=item.partition(' ')
            kind=subprocess.check_output(['git','-C',str(ROOT),'cat-file','-t',oid],text=True).strip()
            if kind!='blob':continue
            data=subprocess.check_output(['git','-C',str(ROOT),'cat-file','-p',oid]);history['blobs_scanned']+=1
            findings.extend(scan(data,'history:'+name))
            if any(part in FORBIDDEN_PARTS for part in Path(name).parts) or Path(name).suffix.lower() in FORBIDDEN_SUFFIXES:
                findings.append({'path':'history:'+name,'category':'private-or-binary-history'})
    result={'scope':'Exact source-only candidate and any pre-existing Git blob history','candidate_files_scanned':len(files),'git_history':history,'findings':findings,
            'passed':not findings,'license_approval_pending':False,'hardware_verification_pending':True,'publication_authorized':False,
            'limitations':['Static pattern and allow-list audit; not a proof against every possible secret format.','Upstream author names/emails in legal attribution and source provenance are intentionally retained.','Ignored local logs, backup records, signing config and generated framework are not publication inputs.']}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,indent=2)+'\n')
    print('Audit: %d candidate files; %d findings; existing Git history: %s.'%(len(files),len(findings),history['present']))
    for item in findings[:30]:print(item)
    return 0 if not findings else 1
if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=ROOT/'Artifacts/Publication-v0.1.0/security-audit.json')
    args=parser.parse_args()
    raise SystemExit(run(args.output))
