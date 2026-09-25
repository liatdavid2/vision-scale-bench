import json
from pathlib import Path
rows=[]
for p in sorted(Path('results').glob('*-?w.json')):
    try: rows.append(json.loads(p.read_text()))
    except Exception: pass
print('\n=== Benchmark summary ===')
print(f"{'platform':12} {'workers':>7} {'train_s':>10} {'img/s':>10} {'acc':>8} {'est_cost':>10}")
for r in rows:
    print(f"{r.get('platform',''):12} {r.get('workers',0):7} {r.get('training_seconds',0):10.2f} {r.get('images_per_second',0):10.2f} {r.get('val_accuracy',0):8.3f} {r.get('estimated_compute_cost_usd','-')!s:>10}")
for platform in sorted(set(r.get('platform') for r in rows)):
    rs={r.get('workers'):r for r in rows if r.get('platform')==platform}
    if 2 in rs and 4 in rs and rs[4].get('training_seconds'):
        speed=rs[2]['training_seconds']/rs[4]['training_seconds']
        eff=speed/2
        print(f"{platform}: 2->4 speedup={speed:.2f}x, parallel efficiency={eff:.1%}")
