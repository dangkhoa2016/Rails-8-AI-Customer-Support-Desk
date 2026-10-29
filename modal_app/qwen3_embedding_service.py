"""Qwen3-Embedding-4B, pinned model, Modal A10, no deployment by default."""
import hashlib
import hmac
import os
import time
from functools import lru_cache

import modal
import json
from pathlib import Path

MODEL_ID = "Qwen/Qwen3-Embedding-4B"
MODEL_REVISION = "5cf2132abc99cad020ac570b19d031efec650f2b"
DIMENSIONS = 2560
volume = modal.Volume.from_name("rails8-qwen3-4b-models", create_if_missing=False)
MODEL_DIRECTORY = "/models/embedding-4b"
MODEL_KAGGLE_HANDLE = "dangkhoa2016/qwen-qwen3-embedding-4b/transformers/default/1"

app = modal.App("rails8-support-desk-qwen3-embedding-4b")
image = modal.Image.debian_slim(python_version="3.11").pip_install(
    "torch==2.6.0", "transformers==4.57.1", "sentence-transformers==5.4.0",
    "fastapi==0.115.12", "pydantic==2.11.3",
)


@app.function(
    image=image, gpu="A10", timeout=600, scaledown_window=120, max_containers=1,
    secrets=[modal.Secret.from_name("rails8-support-desk-ai")],
    volumes={"/models": volume.with_mount_options(read_only=True)},
)
@modal.asgi_app(requires_proxy_auth=True)
def embedding_api():
    from fastapi import FastAPI, Header, HTTPException
    from pydantic import BaseModel, Field
    from typing import Literal

    web = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    class RequestPayload(BaseModel):
        texts: list[str] = Field(min_length=1, max_length=8)
        kind: Literal["document", "query"]

    def checked_model_path():
        base = Path(MODEL_DIRECTORY)
        manifest = base / "kaggle-mirror-manifest.json"
        if not manifest.is_file():
            raise RuntimeError("Model volume not populated; run cache_kaggle_4b.py")
        provenance = json.loads(manifest.read_text())
        if (provenance.get("kaggle_handle") != MODEL_KAGGLE_HANDLE or
                provenance.get("upstream_model_id") != MODEL_ID or
                provenance.get("upstream_revision") != MODEL_REVISION):
            raise RuntimeError("Kaggle mirror provenance mismatch")
        return str(base)

    @lru_cache(maxsize=1)
    def model():
        import torch
        from sentence_transformers import SentenceTransformer
        obj = SentenceTransformer(
            checked_model_path(), device="cuda",
            model_kwargs={"torch_dtype": torch.float16},
            tokenizer_kwargs={"padding_side": "left"}, trust_remote_code=False,
        )
        obj.max_seq_length = 2048
        return obj

    @web.post("/embed")
    def embed(payload: RequestPayload, authorization: str = Header(default="")):
        secret = os.environ.get("EMBED_API_TOKEN", "")
        supplied = authorization.removeprefix("Bearer ")
        if len(secret) < 20 or not hmac.compare_digest(supplied, secret):
            raise HTTPException(status_code=401, detail="unauthorized")
        if any(not t.strip() or len(t.encode("utf-8")) > 16384 for t in payload.texts):
            raise HTTPException(status_code=422, detail="invalid content length")
        started = time.perf_counter()
        vectors = model().encode(
            payload.texts, prompt_name="query" if payload.kind == "query" else None,
            normalize_embeddings=True, batch_size=min(2, len(payload.texts)),
            show_progress_bar=False,
        ).tolist()
        if any(len(v) != DIMENSIONS for v in vectors):
            raise HTTPException(status_code=500, detail="embedding dimension mismatch")
        return {
            "model_id": MODEL_ID, "model_revision": MODEL_REVISION, "source_handle": f"huggingface:{MODEL_ID}@{MODEL_REVISION}",
            "source_type": "huggingface_pinned_fallback_after_kaggle_api_1994",
            "dimensions": DIMENSIONS, "kind": payload.kind,
            "input_sha256": [hashlib.sha256(t.encode("utf-8")).hexdigest() for t in payload.texts],
            "vectors": vectors, "inference_ms": round((time.perf_counter() - started) * 1000, 1),
        }

    return web
