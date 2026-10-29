"""Pinned-upstream fallback for the two reviewed Kaggle Transformers mirrors.

Kaggle public mirror metadata and small files verified. Large-shard download via
public Kaggle API returned error 1994. Cache official Qwen pinned commits instead.
Never transfer Kaggle credentials to Modal. Runtime GPU uses this persistent volume.
"""
import hashlib
import json
from pathlib import Path
import time

import modal

VOLUME_NAME = "rails8-qwen3-4b-models"
MODELS = {
    "embedding-4b": {
        "kaggle": "dangkhoa2016/qwen-qwen3-embedding-4b/transformers/default/1",
        "repo": "Qwen/Qwen3-Embedding-4B",
        "revision": "5cf2132abc99cad020ac570b19d031efec650f2b",
    },
    "reranker-4b": {
        "kaggle": "dangkhoa2016/qwen-qwen3-reranker-4b/transformers/default/1",
        "repo": "Qwen/Qwen3-Reranker-4B",
        "revision": "22e683669bc0f0bd69640a1354a6d0aebcfeede5",
    },
}
app = modal.App("rails8-qwen3-4b-pinned-hf-cache")
volume = modal.Volume.from_name(VOLUME_NAME, create_if_missing=False)
image = modal.Image.debian_slim(python_version="3.11").pip_install(
    "huggingface_hub==0.36.0", "hf_xet==1.1.9",
)


@app.function(image=image, volumes={"/models": volume}, cpu=2, memory=4096,
              timeout=3500, max_containers=1)
def cache_one(name: str):
    from huggingface_hub import snapshot_download

    if name not in MODELS:
        raise ValueError("unsupported model name")
    model = MODELS[name]
    target = Path("/models") / name
    target.mkdir(parents=True, exist_ok=True)
    manifest_file = target / "kaggle-mirror-manifest.json"
    if manifest_file.exists():
        existing = json.loads(manifest_file.read_text())
        records = existing.get("files", [])
        if (existing.get("upstream_revision") == model["revision"] and
                existing.get("upstream_model_id") == model["repo"] and
                len(records) >= 10 and all(
                    (target / row["name"]).is_file() and
                    (target / row["name"]).stat().st_size == row["bytes"]
                    for row in records)):
            return {"name": name, "status": "EXISTING_CACHE", "files": len(records),
                    "total_bytes": existing["total_bytes"]}
        raise RuntimeError("existing model cache manifest invalid; refusing overwrite")
    started = time.monotonic()
    snapshot_download(
        repo_id=model["repo"], revision=model["revision"],
        local_dir=str(target), max_workers=3,
        ignore_patterns=["*.bin", "*.pt", "*.msgpack"],
    )
    required = {
        "config.json", "tokenizer.json", "modules.json",
        "model.safetensors.index.json",
        "model-00001-of-00002.safetensors",
        "model-00002-of-00002.safetensors",
    }
    seen = {p.name for p in target.rglob("*") if p.is_file()}
    if not required.issubset(seen):
        raise RuntimeError("model incomplete: " + repr(sorted(required - seen)))
    data = []
    for file in sorted(target.rglob("*")):
        if not file.is_file() or file == manifest_file or ".cache" in file.parts:
            continue
        digest = hashlib.sha256()
        with file.open("rb") as f:
            for block in iter(lambda: f.read(8 * 1024 * 1024), b""):
                digest.update(block)
        data.append({"name": file.relative_to(target).as_posix(),
                     "bytes": file.stat().st_size, "sha256": digest.hexdigest()})
    total = sum(r["bytes"] for r in data)
    if not (7_500_000_000 <= total <= 8_700_000_000):
        raise RuntimeError("unexpected model size: " + str(total))
    manifest = {
        "source_type": "HUGGINGFACE_PINNED_AFTER_KAGGLE_PUBLIC_ERROR_1994",
        "kaggle_handle": model["kaggle"],
        "upstream_model_id": model["repo"],
        "upstream_revision": model["revision"],
        "total_bytes": total, "files": data,
        "elapsed_seconds": round(time.monotonic() - started, 2),
        "validation": "SHA256 actual downloaded file digests, not model quality validation",
    }
    manifest_file.write_text(json.dumps(manifest, indent=2) + "\n")
    volume.commit()
    return {"name": name, "status": "CACHED_PINNED", "total_bytes": total,
            "files": len(data), "manifest_sha256": hashlib.sha256(manifest_file.read_bytes()).hexdigest(),
            "elapsed_seconds": manifest["elapsed_seconds"]}


@app.local_entrypoint()
def main():
    for name in ("embedding-4b", "reranker-4b"):
        print(json.dumps(cache_one.remote(name), sort_keys=True))
