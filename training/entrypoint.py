import json
import os
import subprocess
import sys


def main():
    hosts = json.loads(os.environ.get("SM_HOSTS", "[]"))
    current = os.environ.get("SM_CURRENT_HOST")
    if hosts and current in hosts:
        node_rank = hosts.index(current)
        nnodes = len(hosts)
        master = hosts[0]
    else:
        node_rank = int(os.environ.get("NODE_RANK", "0"))
        nnodes = int(os.environ.get("WORLD_SIZE", "1"))
        master = os.environ.get("MASTER_ADDR", "127.0.0.1")

    env = os.environ.copy()
    env["MASTER_ADDR"] = master
    env.setdefault("MASTER_PORT", "29500")

    args = [
        "torchrun",
        f"--nnodes={nnodes}",
        "--nproc-per-node=1",
        f"--node-rank={node_rank}",
        f"--master-addr={master}",
        f"--master-port={env['MASTER_PORT']}",
        "-m", "training.train",
        "--epochs", env.get("EPOCHS", "2"),
        "--batch-size", env.get("BATCH_SIZE", "64"),
        "--max-train-samples", env.get("MAX_TRAIN_SAMPLES", "8000"),
        "--max-test-samples", env.get("MAX_TEST_SAMPLES", "2000"),
        "--data-dir", env.get("DATA_DIR", "/data"),
        "--platform", env.get("PLATFORM", "unknown"),
    ]
    print("Launching:", " ".join(args), flush=True)
    raise SystemExit(subprocess.call(args, env=env))


if __name__ == "__main__":
    main()
