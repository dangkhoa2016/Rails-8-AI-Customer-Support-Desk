"""CPU-only, resumable, pinned Qwen model cache on dedicated Modal Volume.
Never runs CUDA. Each file is downloaded and checked against official Hugging Face
SHA256 (LFS) or Git blob SHA1 (non-LFS); each verified file commits separately.
No HTTP endpoints, no access to Rails DB, no old model volumes.
"""
import hashlib
import json
import os
from pathlib import Path
import time
import modal

EXPECTED_META_SHA="20c5b62b395b966d02d8f1448a0ce04d0d2557b98a0727cc1517934df3d509af"
MODEL_ID="Qwen/Qwen3-4B-Instruct-2507"
MODEL_REV="cdbee75f17c01a7cc42f958dc650907174af0554"
VOLUME_NAME="rails8-support-desk-qwen3-instruct-4b-pinned"
MODEL_DIR="/model/model"
app=modal.App("rails8-support-desk-m2-qwen3-instruct-cpu-cache")
volume=modal.Volume.from_name(VOLUME_NAME,create_if_missing=True)
image=modal.Image.debian_slim(python_version="3.11").pip_install(
    "huggingface_hub==0.36.2","hf_xet==1.2.0"
)

def digests(path):
    size=Path(path).stat().st_size
    sha256=hashlib.sha256()
    sha1=hashlib.sha1()
    sha1.update(f"blob {size}\0".encode())
    with open(path,"rb") as fh:
        while block:=fh.read(8*1024*1024):
            sha256.update(block);sha1.update(block)
    return {"bytes":size,"sha256":sha256.hexdigest(),"git_blob_sha1":sha1.hexdigest()}

def verify(path,entry):
    p=Path(path)
    if not p.is_file():return None
    hashes=digests(p)
    if hashes["bytes"]!=entry["bytes"]:return None
    # A Git LFS blob_id is the SHA1 of the small *pointer file*, NOT the
    # SHA1 of the downloaded safetensors payload. Never compare those two.
    # Validate LFS payload by its published SHA256 and size; for ordinary
    # Git blobs use the published Git-object SHA1 and size.
    if entry["lfs_sha256"]:
        if hashes["sha256"]!=entry["lfs_sha256"]:return None
    elif hashes["git_blob_sha1"]!=entry["git_blob_sha1"]:
        return None
    return hashes

@app.function(image=image,cpu=2.0,memory=8192,timeout=900,
              max_containers=1,scaledown_window=2,volumes={"/model":volume})
def fetch_one(entry):
    from huggingface_hub import hf_hub_download
    assert os.environ.get("CUDA_VISIBLE_DEVICES","") in ("","-1"),"CPU only"
    name=entry["name"]
    assert name==Path(name).name and "/" not in name
    assert len(entry["git_blob_sha1"])==40
    os.environ["HF_HUB_DOWNLOAD_TIMEOUT"]="180"
    os.environ["HF_HUB_ETAG_TIMEOUT"]="30"
    started=time.perf_counter()
    path=Path(MODEL_DIR)/name
    hashes=verify(path,entry)
    if hashes is None:
        downloaded=hf_hub_download(repo_id=MODEL_ID,filename=name,
             revision=MODEL_REV,local_dir=MODEL_DIR,force_download=False)
        assert Path(downloaded).resolve()==path.resolve()
        hashes=verify(path,entry)
        if hashes is None:
            raise ValueError(f"official metadata verification FAILED for {name}")
    receipt={"file":name,"source":f"{MODEL_ID}@{MODEL_REV}",
      "status":"OFFICIAL_HASH_AND_SIZE_VERIFIED",
      "bytes":hashes["bytes"],"sha256":hashes["sha256"],
      "git_blob_sha1":hashes["git_blob_sha1"],
      "elapsed_seconds":round(time.perf_counter()-started,3)}
    rec_path=Path(MODEL_DIR)/".verified"/(name+".json")
    rec_path.parent.mkdir(parents=True,exist_ok=True)
    rec_path.write_text(json.dumps(receipt,indent=2)+"\n")
    volume.commit()
    return receipt

@app.function(image=image,cpu=2.0,memory=8192,timeout=900,
              max_containers=1,scaledown_window=2,volumes={"/model":volume})
def finalize(meta):
    assert meta["model_id"]==MODEL_ID and meta["revision"]==MODEL_REV
    assert meta["required_file_count"]==len(meta["files"])==12
    verified=[]
    for entry in meta["files"]:
        d=verify(Path(MODEL_DIR)/entry["name"],entry)
        if d is None:
            raise ValueError(f"CACHE_NOT_READY missing/checksum failure: {entry['name']}")
        verified.append({"name":entry["name"],"sha256":d["sha256"],
                         "bytes":d["bytes"]})
    ready={"status":"READY_ALL_12_OFFICIAL_FILES_HASH_VERIFIED",
        "model_id":MODEL_ID,"revision":MODEL_REV,
        "source_manifest_sha256":EXPECTED_META_SHA,
        "total_bytes":sum(item["bytes"] for item in verified),
        "files":verified,
        "cpu_only":True,"gpu_executed":False}
    output=Path(MODEL_DIR)/"cache-ready.json"
    output.write_text(json.dumps(ready,indent=2)+"\n")
    volume.commit()
    return {"status":ready["status"],
         "total_bytes":ready["total_bytes"],
         "file_count":len(verified),
         "readiness_sha256":hashlib.sha256(output.read_bytes()).hexdigest()}

@app.local_entrypoint()
def main():
    root=Path(__file__).resolve().parents[1]
    source=root/"review/m2_qwen4b_cpu_cache_official_metadata_20261029.json"
    if hashlib.sha256(source.read_bytes()).hexdigest()!=EXPECTED_META_SHA:
        raise RuntimeError("OFFICIAL_CACHE_MANIFEST_SHA_DRIFT")
    meta=json.loads(source.read_bytes())
    assert meta["volume"]==VOLUME_NAME and meta["model_id"]==MODEL_ID
    assert meta["revision"]==MODEL_REV and len(meta["files"])==12
    dest=root/"evidence-m2-qwen4b-cpu-cache-20261029"
    dest.mkdir(exist_ok=True)
    progress=dest/"cpu-prefetch-events-retry1.jsonl"
    if progress.exists(): raise RuntimeError("REFUSING_TO_OVERWRITE_CPU_PREFETCH_EVENTS")
    log=lambda item: (progress.open("a").write(json.dumps(item,ensure_ascii=False)+"\n"))
    log({"stage":"PREFLIGHT","attempt":"retry1_fixed_lfs_sha_verification","manifest_sha256":EXPECTED_META_SHA,
      "model":MODEL_ID,"revision":MODEL_REV,"gpu":"NONE",
      "files":len(meta["files"]),"bytes":meta["total_expected_bytes"]})
    ordered=sorted(meta["files"],key=lambda x:(not x["name"].endswith(".safetensors"),-x["bytes"]))
    for entry in ordered:
        print(f"CPU_CACHE_FETCH {entry['name']} bytes={entry['bytes']}",flush=True)
        start=time.perf_counter()
        try:
            result=fetch_one.remote(entry)
            log({"stage":"FILE_VERIFIED",**result,
                 "invocation_wall_seconds":round(time.perf_counter()-start,3)})
            print("CPU_CACHE_PASS "+result["file"]+
                " sha256="+result["sha256"],flush=True)
        except Exception as e:
            failure={"stage":"CPU_CACHE_FAILED",
                 "file":entry["name"],"type":type(e).__name__,
                 "message":str(e).splitlines()[0][:250],
                 "invocation_wall_seconds":round(time.perf_counter()-start,3)}
            log(failure)
            (dest/"cpu-cache-failure-retry1.json").write_text(json.dumps(failure,indent=2)+"\n")
            print("CPU_CACHE_STOP "+json.dumps(failure),flush=True)
            return
    print("CPU_CACHE_FINAL_VALIDATE all=12",flush=True)
    try:
        result=finalize.remote(meta)
        log({"stage":"ALL_FILES_READY",**result})
        (dest/"cpu-cache-ready-retry1.json").write_text(json.dumps(result,indent=2)+"\n")
        print("CPU_CACHE_COMPLETED "+json.dumps(result),flush=True)
    except Exception as e:
        failure={"stage":"FINAL_VERIFICATION_FAILED",
            "type":type(e).__name__,
            "message":str(e).splitlines()[0][:250]}
        log(failure)
        (dest/"cpu-cache-failure-retry1.json").write_text(json.dumps(failure,indent=2)+"\n")
        print("CPU_CACHE_FINAL_FAILED "+json.dumps(failure),flush=True)
