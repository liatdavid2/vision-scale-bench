import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Activity, Boxes, BrainCircuit, Cloud, Database, GitCompare, Layers3, Play, RefreshCw, ServerCog, TerminalSquare, Wrench, Trash2 } from 'lucide-react';
import './styles.css';

const API = import.meta.env.DEV ? 'http://localhost:7474' : '';

const components = [
  { icon: BrainCircuit, title: 'PyTorch DDP', subtitle: 'The distributed training engine', text: 'Runs ResNet-18 across multiple GPU processes. Each worker gets a different slice of CIFAR-10 and synchronizes gradients with the other workers.' },
  { icon: Boxes, title: 'EKS / Kubernetes', subtitle: 'The Kubernetes execution path', text: 'Runs the same DDP workload as Kubernetes pods on NVIDIA T4 GPU nodes. The benchmark compares 2 workers with 4 workers.' },
  { icon: Cloud, title: 'SageMaker Training', subtitle: 'The managed AWS execution path', text: 'Runs the same training container as managed SageMaker jobs, comparing 2 GPU instances with 4 GPU instances.' },
  { icon: Layers3, title: 'Helm Chart', subtitle: 'Packages the Kubernetes workload', text: 'Defines replicas, image, GPU requests, dataset size and training parameters. The benchmark changes the worker count through Helm values.' },
  { icon: Database, title: 'Crossplane', subtitle: 'Creates S3 + ECR declaratively', text: 'Runs inside Kubernetes and provisions the shared S3 bucket and ECR repository from Kubernetes YAML.' },
  { icon: ServerCog, title: 'Terraform', subtitle: 'Bootstraps and destroys the foundation', text: 'Creates VPC, EKS, GPU node group and IAM. The Destroy button uses Terraform to remove the temporary AWS infrastructure when the demo is finished.' }
];

function fmtSeconds(value) { if (value == null) return '—'; const n = Number(value); return Number.isFinite(n) ? `${n.toFixed(1)} s` : '—'; }
function fmtNumber(value, digits=1) { if (value == null) return '—'; const n = Number(value); return Number.isFinite(n) ? n.toFixed(digits) : '—'; }
function fmtCost(value) { if (value == null) return '—'; const n = Number(value); return Number.isFinite(n) ? `$${n.toFixed(4)}` : '—'; }

function PlatformCard({platform, title, subtitle, icon: Icon, running, onRun}) {
  return <section className="platform-card">
    <div className="platform-head"><div className="icon-box"><Icon size={24}/></div><div><h3>{title}</h3><p>{subtitle}</p></div></div>
    <div className="run-flow"><div className="run-node"><strong>Run A</strong><span>2 {platform === 'eks' ? 'workers' : 'instances'}</span></div><div className="arrow">→</div><div className="run-node"><strong>Run B</strong><span>4 {platform === 'eks' ? 'workers' : 'instances'}</span></div></div>
    <div className="small-spec">CIFAR-10 · ResNet-18 · 1 epoch · 5K train / 1K test · NVIDIA T4</div>
    <button className="run-btn" disabled={running} onClick={() => onRun(platform)}>{running ? <RefreshCw size={18} className="spin"/> : <Play size={18}/>} {running ? 'Operation running…' : `Run ${title} benchmark`}</button>
  </section>
}

function ResultsTable({results}) {
  const rows = [...results].sort((a,b) => `${a.platform}-${a.workers}`.localeCompare(`${b.platform}-${b.workers}`));
  return <div className="table-wrap"><table><thead><tr><th>Platform</th><th>Scale</th><th>Training time</th><th>Images/s</th><th>Accuracy</th><th>Job time</th><th>Est. cost</th></tr></thead><tbody>{rows.length ? rows.map((r,i) => <tr key={i}><td><span className={`pill ${r.platform}`}>{r.platform}</span></td><td>{r.workers ?? r.world_size ?? '—'}</td><td>{fmtSeconds(r.training_seconds)}</td><td>{fmtNumber(r.images_per_second)}</td><td>{r.val_accuracy == null ? '—' : `${(Number(r.val_accuracy)*100).toFixed(1)}%`}</td><td>{fmtSeconds(r.training_job_seconds ?? r.end_to_end_seconds ?? r.job_seconds)}</td><td>{fmtCost(r.estimated_compute_cost_usd)}</td></tr>) : <tr><td colSpan="7" className="empty">No benchmark results yet.</td></tr>}</tbody></table></div>
}

function App(){
  const [job,setJob] = useState(null);
  const [results,setResults] = useState([]);
  const [error,setError] = useState('');
  const running = job && ['queued','running'].includes(job.status);

  const refreshResults = async () => { try { const r = await fetch(`${API}/api/results`); if (r.ok) setResults(await r.json()); } catch {} };
  useEffect(() => { refreshResults(); }, []);
  useEffect(() => {
    if (!running) return;
    const timer = setInterval(async () => {
      try { const r = await fetch(`${API}/api/jobs/${job.id}`); const j = await r.json(); setJob(j); if (!['queued','running'].includes(j.status)) refreshResults(); }
      catch (e) { setError(String(e)); }
    }, 1500);
    return () => clearInterval(timer);
  }, [job?.id, running]);

  const startBenchmark = async (platform) => {
    setError('');
    try { const r = await fetch(`${API}/api/run/${platform}`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({profile:'gpu'})}); const data = await r.json(); if (!r.ok) throw new Error(data.detail || 'Could not start benchmark'); setJob(data); }
    catch(e) { setError(e.message); }
  };

  const infrastructure = async (action) => {
    if (action === 'destroy' && !window.confirm('Destroy the AWS infrastructure for this project? This removes EKS/VPC/GPU nodes/IAM and the benchmark S3/ECR resources.')) return;
    setError('');
    try { const r = await fetch(`${API}/api/infrastructure/${action}`, {method:'POST'}); const data = await r.json(); if (!r.ok) throw new Error(data.detail || `Could not ${action} infrastructure`); setJob(data); }
    catch(e) { setError(e.message); }
  };

  const logText = useMemo(() => job?.logs?.join('\n') || 'Setup, run a benchmark, or destroy infrastructure to see live logs here.', [job]);

  return <div className="app">
    <header className="hero"><div className="eyebrow"><Activity size={16}/> AWS distributed vision benchmark</div><h1>Vision Scale Bench</h1><p>Compare the same PyTorch vision workload on <strong>EKS/Kubernetes</strong> and <strong>SageMaker Training</strong>, scaling from 2 to 4 NVIDIA T4 GPUs while measuring performance and estimated cost.</p><div className="tags"><span>CIFAR-10</span><span>ResNet-18</span><span>PyTorch DDP</span><span>2 → 4</span><span>GPU only</span><span>Target demo ≤ ~$1</span></div></header>

    <main>
      <section className="section">
        <div className="section-title"><div><span className="step">00</span><h2>AWS infrastructure</h2></div><p>Create the environment before the first run, then destroy it when the demo is finished.</p></div>
        <div className="infra-grid">
          <article className="infra-card"><div className="platform-head"><div className="icon-box"><Wrench size={22}/></div><div><h3>Setup AWS Infrastructure</h3><p>Terraform → EKS/VPC/IAM · Crossplane → S3/ECR · build & push training image</p></div></div><p className="infra-copy">Creates the temporary AWS foundation, installs Crossplane, provisions shared resources, pushes the CUDA training image, and finally scales GPU workers back to 0 until a benchmark is started.</p><button className="run-btn" disabled={running} onClick={() => infrastructure('setup')}><Wrench size={18}/> {running ? 'Operation running…' : 'Setup AWS Infrastructure'}</button></article>
          <article className="infra-card danger"><div className="platform-head"><div className="icon-box danger-icon"><Trash2 size={22}/></div><div><h3>Destroy AWS Infrastructure</h3><p>Cleanup after the demo</p></div></div><p className="infra-copy">Deletes benchmark S3/ECR resources and runs Terraform destroy for EKS, VPC, GPU node group and IAM. A confirmation dialog appears before the action starts.</p><button className="destroy-btn" disabled={running} onClick={() => infrastructure('destroy')}><Trash2 size={18}/> {running ? 'Operation running…' : 'Destroy AWS Infrastructure'}</button></article>
        </div>
        {error && <div className="error">{error}</div>}
      </section>

      <section className="section"><div className="section-title"><div><span className="step">01</span><h2>Run benchmarks</h2></div><p>Each button launches the full 2-vs-4 GPU comparison for one platform.</p></div><div className="platform-grid"><PlatformCard platform="eks" title="EKS / Kubernetes" subtitle="Helm-deployed DDP workers on Spot NVIDIA T4 nodes; GPU workers scale to zero after the run" icon={Boxes} running={running} onRun={startBenchmark}/><PlatformCard platform="sagemaker" title="SageMaker" subtitle="Managed Spot Training on NVIDIA T4 using the same container" icon={Cloud} running={running} onRun={startBenchmark}/></div></section>

      <section className="section"><div className="section-title"><div><span className="step">02</span><h2>Live run status</h2></div><div className={`status ${job?.status || 'idle'}`}>{job?.status || 'idle'}</div></div><div className="terminal"><div className="terminal-head"><TerminalSquare size={16}/><span>{job ? `${job.platform} · ${job.id.slice(0,8)}` : 'operation log'}</span></div><pre>{logText}</pre></div></section>

      <section className="section"><div className="section-title"><div><span className="step">03</span><h2>Performance & cost results</h2></div><button className="ghost" onClick={refreshResults}><RefreshCw size={15}/> Refresh</button></div><ResultsTable results={results}/></section>

      <section className="section architecture"><div className="section-title"><div><span className="step">04</span><h2>What each part does</h2></div><p>The role of every technology in this project.</p></div><div className="arch-flow"><div>Terraform<br/><span>bootstrap</span></div><b>→</b><div>EKS<br/><span>cluster</span></div><b>→</b><div>Helm<br/><span>workload</span></div><b>→</b><div>PyTorch DDP<br/><span>training</span></div><div className="branch">Crossplane → S3 + ECR</div><div className="branch">Alternative path → SageMaker Training</div></div><div className="component-grid">{components.map(({icon:Icon,title,subtitle,text}) => <article className="component" key={title}><div className="component-icon"><Icon size={21}/></div><h3>{title}</h3><h4>{subtitle}</h4><p>{text}</p></article>)}</div></section>

      <section className="section cost-note"><GitCompare size={24}/><div><h3>What the experiment answers</h3><p>Does doubling distributed GPU workers from 2 to 4 reduce training time enough to justify the additional compute cost — and how does Kubernetes orchestration compare with managed SageMaker Training for the exact same workload?</p></div></section>
    </main>
  </div>
}

createRoot(document.getElementById('root')).render(<App/>);
