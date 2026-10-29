"""Cache the TWO public Kaggle Transformers/default/1 mirrors to an isolated Modal Volume.

NO Kaggle authentication is sent to Modal. These model variations are public.
Actual content hashes are computed after transfer; reruns verify existing manifests.
Usage:
    modal run --env rails-8-ai-customer-support-desk modal_app/cache_kaggle_4b.py

The two model IDs and explicit Kaggle variation version are deliberately fixed.
"""
import hashlib
import json
from pathlib import Path
import time

import modal

ENVIRONMENT = "rails-8-ai-customer-support-desk"
VOLUME_NAME = "rails8-qwen3-4b-models"
MODELS = {
    "embedding-4b": {
        "handle": "dangkhoa2016/qwen-qwen3-embedding-4b/transformers/default/1",
        "upstream_model_id": "Qwen/Qwen3-Embedding-4B",
        "upstream_revision": "5cf2132abc99cad020ac570b19d031efec650f2b",
        "expected_bytes": 8059521798,
    },
    "reranker-4b": {
        "handle": "dangkhoa2016/qwen-qwen3-reranker-4b/transformers/default/1",
        "upstream_model_id": "Qwen/Qwen3-Reranker-4B",
        "upstream_revision": "22e683669bc0f0bd69640a1354a6d0aebcfeede5",
        "expected_bytes": 8059548276,
    },
}

app = modal.App("rails8-qwen3-4b-public-kaggle-cache")
volume = modal.Volume.from_name(VOLUME_NAME, create_if_missing=False)
image = modal.Image.debian_slim(python_version="3.11").pip_install("kagglehub==1.0.3")


@app.function(image=image, volumes={"/models": volume}, cpu=2, memory=4096,
              timeout=3500, max_containers=1)
def cache_one(name: str):
    import kagglehub

    if name not in MODELS:
        raise ValueError("unexpected model variation")
    item = MODELS[name]
    destination = Path("/models") / name
    manifest_path = destination / "kaggle-mirror-manifest.json"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        expected = manifest.get("files", [])
        if (manifest.get("kaggle_handle") == item["handle"] and
                len(expected) >= 10 and
                all((destination / file["name"]).is_file() and
                    (destination / file["name"]).stat().st_size == file["bytes"]
                    for file in expected)):
            return {"model": name, "status": "CACHE_PRESENT", "total_bytes": manifest["total_bytes"],
                    "files": len(expected), "sha256_manifest": hashlib.sha256(manifest_path.read_bytes()).hexdigest()}
        raise RuntimeError("existing cache manifest invalid; refusing silent overwrite")

    destination.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    # Public-model download. No account credentials are mounted into the function.
    kagglehub.model_download(item["handle"], output_dir=str(destination))
    files = sorted(p for p in destination.rglob("*") if p.is_file() and p != manifest_path)
    required = {"config.json", "tokenizer.json", "modules.json", "model.safetensors.index.json",
                "model-00001-of-00002.safetensors", "model-00002-of-00002.safetensors"}
    present = {p.name for p in files}
    if not required.issubset(present):
        raise RuntimeError("Kaggle download incomplete; required files missing: " +
                           str(sorted(required - present)))
    file_metadata = []
    for file in files:
        digest = hashlib.sha256()
        with file.open("rb") as handle:
            for block in iter(lambda: handle.read(8 * 1024 * 1024), b""):
                digest.update(block)
        file_metadata.append({
            "name": file.relative_to(destination).as_posix(),
            "bytes": file.stat().st_size,
            "sha256": digest.hexdigest(),
        })
    total_bytes = sum(info["bytes"] for info in file_metadata)
    if total_bytes < 7_500_000_000 or total_bytes > 8_700_000_000:
        raise RuntimeError("unexpected model size " + str(total_bytes))
    manifest = {
        "kaggle_handle": item["handle"],
        "upstream_model_id": item["upstream_model_id"],
        "upstream_revision": item["upstream_revision"],
        "total_bytes": total_bytes,
        "files": file_metadata,
        "elapsed_seconds": round(time.monotonic() - started, 2),
        "validation": "downloaded file digest evidence; upstream byte equivalence not independently proven",
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    volume.commit()
    return {"model": name, "status": "CACHED", "total_bytes": total_bytes,
            "files": len(files), "sha256_manifest": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
            "elapsed_seconds": manifest["elapsed_seconds"]}


@app.local_entrypoint()
def main():
    for name in ("embedding-4b", "reranker-4b"):
        print(json.dumps(cache_one.remote(name), sort_keys=True))
