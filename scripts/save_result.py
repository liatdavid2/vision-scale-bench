import argparse, json
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('--json',required=True); p.add_argument('--platform',required=True); p.add_argument('--workers',type=int,required=True); p.add_argument('--job-seconds',type=float,default=None)
a=p.parse_args(); d=json.loads(a.json); d['platform']=a.platform; d['workers']=a.workers
if a.job_seconds is not None: d['end_to_end_seconds']=a.job_seconds
Path('results').mkdir(exist_ok=True)
path=Path('results')/f"{a.platform}-{a.workers}w.json"; path.write_text(json.dumps(d,indent=2),encoding='utf-8'); print(path)
