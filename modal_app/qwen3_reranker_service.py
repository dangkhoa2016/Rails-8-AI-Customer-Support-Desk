"""Qwen3-Reranker-4B: cross-encoder scores for filtered KB candidates only."""
import hashlib
import hmac
import math
import os
import time
from functools import lru_cache

import modal
import json
from pathlib import Path

MODEL_ID = "Qwen/Qwen3-Reranker-4B"
MODEL_REVISION = "22e683669bc0f0bd69640a1354a6d0aebcfeede5"
volume = modal.Volume.from_name("rails8-qwen3-4b-models", create_if_missing=False)
MODEL_DIRECTORY = "/models/reranker-4b"
MODEL_KAGGLE_HANDLE = "dangkhoa2016/qwen-qwen3-reranker-4b/transformers/default/1"

app = modal.App("rails8-support-desk-qwen3-reranker-4b")
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
def reranker_api():
    from fastapi import FastAPI, Header, HTTPException
    from pydantic import BaseModel, Field

    web = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    class RequestPayload(BaseModel):
        query: str = Field(min_length=1)
        documents: list[str] = Field(min_length=1, max_length=12)

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
        from sentence_transformers import CrossEncoder
        return CrossEncoder(
            checked_model_path(), device="cuda",
            model_kwargs={"torch_dtype": torch.float16},
            tokenizer_kwargs={"padding_side": "left"},
            max_length=2048, trust_remote_code=False,
        )

    @web.post("/rerank")
    def rerank(payload: RequestPayload, authorization: str = Header(default="")):
        secret = os.environ.get("RERANK_API_TOKEN", "")
        supplied = authorization.removeprefix("Bearer ")
        if len(secret) < 20 or not hmac.compare_digest(supplied, secret):
            raise HTTPException(status_code=401, detail="unauthorized")
        if not payload.query.strip() or len(payload.query.encode("utf-8")) > 4096:
            raise HTTPException(status_code=422, detail="invalid query size")
        if any(not t.strip() or len(t.encode("utf-8")) > 16384 for t in payload.documents):
            raise HTTPException(status_code=422, detail="invalid document size")
        started = time.perf_counter()
        scores = model().predict(
            [(payload.query, doc) for doc in payload.documents],
            batch_size=2, show_progress_bar=False,
        )
        logits = [float(score) for score in scores]
        if len(logits) != len(payload.documents) or not all(math.isfinite(x) for x in logits):
            raise HTTPException(status_code=500, detail="invalid rerank scores")
        return {
            "model_id": MODEL_ID, "model_revision": MODEL_REVISION, "source_handle": f"huggingface:{MODEL_ID}@{MODEL_REVISION}",
            "source_type": "huggingface_pinned_fallback_after_kaggle_api_1994",
            "score_type": "raw_logit",
            "query_sha256": hashlib.sha256(payload.query.encode("utf-8")).hexdigest(),
            "document_sha256": [
                hashlib.sha256(doc.encode("utf-8")).hexdigest() for doc in payload.documents
            ],
            "scores": logits,
            "inference_ms": round((time.perf_counter() - started) * 1000, 1),
        }

    return web
