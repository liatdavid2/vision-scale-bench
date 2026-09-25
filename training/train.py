import argparse
import json
import os
import time
from pathlib import Path

import torch
import torch.distributed as dist
import torch.nn as nn
import torch.optim as optim
from torch.nn.parallel import DistributedDataParallel as DDP
from torch.utils.data import DataLoader, Subset
from torch.utils.data.distributed import DistributedSampler
from torchvision import datasets, models, transforms


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--epochs", type=int, default=1)
    p.add_argument("--batch-size", type=int, default=64)
    p.add_argument("--max-train-samples", type=int, default=5000)
    p.add_argument("--max-test-samples", type=int, default=1000)
    p.add_argument("--data-dir", default="/data")
    p.add_argument("--platform", default="unknown")
    return p.parse_args()


def init_dist():
    world = int(os.environ.get("WORLD_SIZE", "1"))
    rank = int(os.environ.get("RANK", "0"))
    local_rank = int(os.environ.get("LOCAL_RANK", "0"))
    use_cuda = torch.cuda.is_available()
    backend = "nccl" if use_cuda else "gloo"
    if world > 1:
        dist.init_process_group(backend=backend)
    if use_cuda:
        torch.cuda.set_device(local_rank)
        device = torch.device("cuda", local_rank)
    else:
        device = torch.device("cpu")
    return world, rank, local_rank, backend, device


def download_dataset(data_dir, rank, world):
    # Each node has its own local filesystem in this benchmark. Downloading CIFAR-10
    # independently is cheap and avoids EFS/NFS cost and setup. Torchvision reuses it
    # if already present.
    tfm = transforms.Compose([
        transforms.RandomHorizontalFlip(),
        transforms.ToTensor(),
        transforms.Normalize((0.4914, 0.4822, 0.4465), (0.2470, 0.2435, 0.2616)),
    ])
    test_tfm = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize((0.4914, 0.4822, 0.4465), (0.2470, 0.2435, 0.2616)),
    ])
    train = datasets.CIFAR10(root=data_dir, train=True, download=True, transform=tfm)
    test = datasets.CIFAR10(root=data_dir, train=False, download=True, transform=test_tfm)
    return train, test


def subset(ds, n):
    n = min(n, len(ds))
    return Subset(ds, list(range(n)))


def make_model():
    model = models.resnet18(weights=None, num_classes=10)
    # Better suited to 32x32 CIFAR images than ImageNet's 7x7/stride2 stem.
    model.conv1 = nn.Conv2d(3, 64, kernel_size=3, stride=1, padding=1, bias=False)
    model.maxpool = nn.Identity()
    return model


def reduce_sum(v, device, world):
    t = torch.tensor([v], dtype=torch.float64, device=device)
    if world > 1:
        dist.all_reduce(t, op=dist.ReduceOp.SUM)
    return t.item()


def main():
    args = parse_args()
    torch.manual_seed(7)
    world, rank, local_rank, backend, device = init_dist()

    train_ds, test_ds = download_dataset(args.data_dir, rank, world)
    train_ds = subset(train_ds, args.max_train_samples)
    test_ds = subset(test_ds, args.max_test_samples)

    train_sampler = DistributedSampler(train_ds, num_replicas=world, rank=rank, shuffle=True) if world > 1 else None
    test_sampler = DistributedSampler(test_ds, num_replicas=world, rank=rank, shuffle=False) if world > 1 else None

    train_loader = DataLoader(
        train_ds, batch_size=args.batch_size, shuffle=(train_sampler is None),
        sampler=train_sampler, num_workers=2, pin_memory=torch.cuda.is_available()
    )
    test_loader = DataLoader(
        test_ds, batch_size=args.batch_size, shuffle=False,
        sampler=test_sampler, num_workers=2, pin_memory=torch.cuda.is_available()
    )

    model = make_model().to(device)
    if world > 1:
        model = DDP(model, device_ids=[local_rank] if device.type == "cuda" else None)
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.SGD(model.parameters(), lr=0.05, momentum=0.9, weight_decay=5e-4)

    epoch_times = []
    seen_local = 0
    if world > 1:
        dist.barrier()
    start = time.perf_counter()

    for epoch in range(args.epochs):
        if train_sampler is not None:
            train_sampler.set_epoch(epoch)
        model.train()
        e0 = time.perf_counter()
        for x, y in train_loader:
            x, y = x.to(device), y.to(device)
            optimizer.zero_grad(set_to_none=True)
            out = model(x)
            loss = criterion(out, y)
            loss.backward()
            optimizer.step()
            seen_local += x.size(0)
        if world > 1:
            dist.barrier()
        epoch_times.append(time.perf_counter() - e0)

    training_seconds = time.perf_counter() - start

    model.eval()
    correct = 0
    total = 0
    with torch.no_grad():
        for x, y in test_loader:
            x, y = x.to(device), y.to(device)
            pred = model(x).argmax(dim=1)
            correct += (pred == y).sum().item()
            total += y.numel()

    total_correct = reduce_sum(correct, device, world)
    total_eval = reduce_sum(total, device, world)
    total_seen = reduce_sum(seen_local, device, world)

    if rank == 0:
        metrics = {
            "platform": args.platform,
            "workers": world,
            "backend": backend,
            "device": device.type,
            "epochs": args.epochs,
            "train_samples": len(train_ds),
            "test_samples": len(test_ds),
            "batch_size_per_worker": args.batch_size,
            "training_seconds": round(training_seconds, 4),
            "mean_epoch_seconds": round(sum(epoch_times) / len(epoch_times), 4),
            "images_per_second": round(total_seen / training_seconds, 2),
            "val_accuracy": round(total_correct / max(1.0, total_eval), 4),
        }
        print("RESULT_JSON=" + json.dumps(metrics, sort_keys=True), flush=True)

        # SageMaker automatically packs /opt/ml/model into model.tar.gz.
        model_dir = Path("/opt/ml/model")
        if model_dir.parent.exists():
            model_dir.mkdir(parents=True, exist_ok=True)
            (model_dir / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    if world > 1:
        dist.destroy_process_group()


if __name__ == "__main__":
    main()
