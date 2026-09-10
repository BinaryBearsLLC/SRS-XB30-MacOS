#!/usr/bin/env python3
"""Sample one development app PID; CPU is measured from process CPU-time deltas."""
import sys,time,subprocess,json,statistics
from pathlib import Path
pid=int(sys.argv[1]); log=Path(sys.argv[2]);output=Path(sys.argv[3]);samples=[]
def cpu_seconds(text):
 parts=[float(v) for v in text.split(':')];return sum(v*60**i for i,v in enumerate(reversed(parts)))
deadline=time.monotonic()+125
while time.monotonic()<deadline:
 phase='connecting'
 if log.exists():
  marks=[v.split('PROFILE ',1)[1] for v in log.read_text(errors='replace').splitlines() if v.startswith('PROFILE ')]
  if marks:phase=marks[-1]
 raw=subprocess.run(['ps','-p',str(pid),'-o','time=,rss='],capture_output=True,text=True).stdout.split()
 if len(raw)<2:break
 samples.append({'t':time.monotonic(),'cpu_seconds':cpu_seconds(raw[0]),'rss_mib':int(raw[1])/1024,'phase':phase})
 if phase=='complete':break
 time.sleep(1)
summary={}
for phase in ['connecting','hidden','visible','edits','restored']:
 rows=[s for s in samples if s['phase']==phase]
 if len(rows)<2:continue
 elapsed=rows[-1]['t']-rows[0]['t']
 summary[phase]={'seconds':round(elapsed,2),'cpu_percent_one_core':round(100*(rows[-1]['cpu_seconds']-rows[0]['cpu_seconds'])/elapsed,2),'rss_mib_median':round(statistics.median(r['rss_mib'] for r in rows),1),'rss_mib_peak':round(max(r['rss_mib'] for r in rows),1)}
output.write_text(json.dumps({'pid':pid,'summary':summary,'samples':samples},indent=2))
print(json.dumps(summary,indent=2))
