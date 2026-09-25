import argparse, boto3, json, os, tarfile, tempfile, time
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--region',default='eu-central-1')
p.add_argument('--instance-type',default='ml.c5.xlarge')
p.add_argument('--workers',type=int,choices=[2,4])
p.add_argument('--all',action='store_true')
p.add_argument('--hourly-rate',type=float,default=0.23,help='Approximate per-instance training $/hour; override with current regional price')
a=p.parse_args()

session=boto3.Session(region_name=a.region); sm=session.client('sagemaker'); s3=session.client('s3'); sts=session.client('sts')
account=sts.get_caller_identity()['Account']
image=f"{account}.dkr.ecr.{a.region}.amazonaws.com/vision-scale-bench:latest"
# Refresh kubeconfig inside the UI/backend container so no host kubeconfig mount is required.
import subprocess
cluster_name=os.environ.get('EKS_CLUSTER_NAME','vision-scale-bench')
subprocess.check_call(['aws','eks','update-kubeconfig','--region',a.region,'--name',cluster_name], stdout=subprocess.DEVNULL)
# Role was created by Terraform.
role=subprocess.check_output(['terraform','-chdir=infra/terraform','output','-raw','sagemaker_role_arn'],text=True).strip()
# Crossplane-generated bucket external name.
bucket=subprocess.check_output(['kubectl','get','buckets.s3.aws.upbound.io','-o','jsonpath={.items[0].metadata.annotations.crossplane\\.io/external-name}'],text=True).strip()
Path('results').mkdir(exist_ok=True)

def run(n):
    name=f"vision-scale-bench-{n}w-{int(time.time())}"
    prefix=f"sagemaker/{name}"
    sm.create_training_job(
      TrainingJobName=name,
      AlgorithmSpecification={'TrainingImage':image,'TrainingInputMode':'File'},
      RoleArn=role,
      OutputDataConfig={'S3OutputPath':f's3://{bucket}/{prefix}'},
      ResourceConfig={'InstanceType':a.instance_type,'InstanceCount':n,'VolumeSizeInGB':10},
      StoppingCondition={'MaxRuntimeInSeconds':900},
      Environment={
        'PLATFORM':'sagemaker','EPOCHS':'2','BATCH_SIZE':'64',
        'MAX_TRAIN_SAMPLES':'8000','MAX_TEST_SAMPLES':'2000'
      },
      Tags=[{'Key':'Project','Value':'vision-scale-bench'}],
    )
    print('Started',name)
    sm.get_waiter('training_job_completed_or_stopped').wait(TrainingJobName=name, WaiterConfig={'Delay':20,'MaxAttempts':50})
    d=sm.describe_training_job(TrainingJobName=name)
    if d['TrainingJobStatus']!='Completed': raise RuntimeError(d.get('FailureReason',d['TrainingJobStatus']))
    model_uri=d['ModelArtifacts']['S3ModelArtifacts']
    b,key=model_uri[5:].split('/',1)
    with tempfile.TemporaryDirectory() as td:
        tgz=Path(td)/'model.tar.gz'; s3.download_file(b,key,str(tgz))
        with tarfile.open(tgz,'r:gz') as tf: tf.extractall(td)
        metrics=json.loads((Path(td)/'metrics.json').read_text())
    train_s=d.get('TrainingTimeInSeconds',0); bill_s=d.get('BillableTimeInSeconds',train_s)
    metrics.update({
      'platform':'sagemaker','workers':n,'instance_type':a.instance_type,
      'training_job_seconds':train_s,'billable_seconds':bill_s,
      'estimated_compute_cost_usd':round(n*a.hourly_rate*bill_s/3600,4),
      'cost_rate_note':'Estimate only; verify current regional price / Cost Explorer.'
    })
    out=Path('results')/f'sagemaker-{n}w.json'; out.write_text(json.dumps(metrics,indent=2)); print(json.dumps(metrics,indent=2))

for n in ([2,4] if a.all or a.workers is None else [a.workers]): run(n)
os.system('python scripts/compare_results.py')
