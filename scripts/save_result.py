import argparse, json
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('--json',required=True)
p.add_argument('--platform',required=True)
p.add_argument('--workers',type=int,required=True)
p.add_argument('--job-seconds',type=float,default=None)
p.add_argument('--instance-hourly-rate',type=float,default=None)
p.add_argument('--cluster-hourly-rate',type=float,default=0.10)
a=p.parse_args()
d=json.loads(a.json)
d['platform']=a.platform
d['workers']=a.workers
if a.job_seconds is not None:
    d['end_to_end_seconds']=a.job_seconds
    if a.instance_hourly_rate is not None:
        d['estimated_compute_cost_usd']=round(
            (a.workers*a.instance_hourly_rate + a.cluster_hourly_rate) * a.job_seconds/3600, 4
        )
        d['cost_rate_note']='Estimate from measured end-to-end time, current/fallback EC2 Spot rate, plus EKS control-plane rate. Check Cost Explorer for billed cost.'
Path('results').mkdir(exist_ok=True)
path=Path('results')/f"{a.platform}-{a.workers}w.json"
path.write_text(json.dumps(d,indent=2),encoding='utf-8')
print(path)
