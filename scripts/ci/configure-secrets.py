#!/usr/bin/env python3
"""Explicit local setup; credential values never enter terminal output or repository files."""
import argparse,base64,os,re,shlex,subprocess
from pathlib import Path

def safe_run(args, **kwargs):
    result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,**kwargs)
    if result.returncode:
        raise SystemExit(f'{Path(args[0]).name} failed; details suppressed to protect credentials.')
    return result.stdout

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('credential_directory',type=Path)
    parser.add_argument('--repo',required=True)
    parser.add_argument('--check',action='store_true',help='Validate inputs without uploading secrets')
    args=parser.parse_args()
    if args.repo!='BinaryBearsLLC/SRS-XB30-MacOS':
        raise SystemExit('Unexpected destination. Review the script before authorizing a different repository.')
    safe_run(['gh','repo','view',args.repo,'--json','nameWithOwner'])
    values={}
    for line in (args.credential_directory/'signing.env').read_text().splitlines():
        line=line.strip().removeprefix('export ')
        if not line or line.startswith('#'):continue
        key,sep,value=line.partition('=')
        if sep:
            parsed=shlex.split(value)
            if len(parsed)!=1:raise SystemExit('Unsupported environment format; values not displayed.')
            values[key.strip()]=parsed[0]
    required=['APPLE_CERTIFICATE_PASSWORD','APPLE_API_ISSUER_ID']
    if any(not values.get(k) for k in required):raise SystemExit('Required signing variable missing; values not displayed.')
    keys=list(args.credential_directory.glob('AuthKey_*.p8'))
    if len(keys)!=1:raise SystemExit('Expected exactly one authorized Apple API key file.')
    cert=args.credential_directory/'BinaryBears_App.p12'
    env=os.environ.copy();env['XB30_CERT_PASSWORD']=values['APPLE_CERTIFICATE_PASSWORD']
    pem=safe_run(['openssl','pkcs12','-in',str(cert),'-clcerts','-nokeys','-passin','env:XB30_CERT_PASSWORD'],env=env)
    subject=safe_run(['openssl','x509','-noout','-subject','-nameopt','RFC2253'],input=pem).decode()
    safe_run(['openssl','x509','-noout','-checkend','0'],input=pem)
    match=re.search(r'CN=(Developer ID Application:.*?)(?=,(?:OU|O|C|UID)=|$)',subject.strip())
    if not match:raise SystemExit('A valid Developer ID Application certificate is required.')
    secrets={
      'APPLE_CERTIFICATE_P12_BASE64':base64.b64encode(cert.read_bytes()).decode(),
      'APPLE_CERTIFICATE_PASSWORD':values['APPLE_CERTIFICATE_PASSWORD'],
      'APPLE_SIGNING_IDENTITY':match.group(1).replace('\\,',','),
      'APPLE_API_KEY_BASE64':base64.b64encode(keys[0].read_bytes()).decode(),
      'APPLE_API_KEY_ID':keys[0].stem.removeprefix('AuthKey_'),
      'APPLE_API_ISSUER_ID':values['APPLE_API_ISSUER_ID'],
    }
    for name,value in secrets.items():
        if not args.check:safe_run(['gh','secret','set',name,'--repo',args.repo],input=value.encode())
        print(('Validated: ' if args.check else 'Configured: ')+name)
if __name__=='__main__':main()
