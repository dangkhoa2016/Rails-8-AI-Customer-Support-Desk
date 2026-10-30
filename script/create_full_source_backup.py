#!/usr/bin/env python3
"""Create self-contained synthetic Rails project backup without runtime secrets."""
import datetime as dt
import hashlib
import json
import os
import pathlib
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = pathlib.Path("/content/rails8-support-backups")
EXCLUDE_DIRS = {
    ".git", "vendor", "node_modules", "log", "tmp", "storage",
    ".bundle", ".venv", "venv", "__pycache__", ".pytest_cache",
    ".mypy_cache", ".ruff_cache", ".cache", "coverage", ".idea",
}
EXCLUDE_BASENAMES = {
    ".env", ".env.notebook", ".env.local", ".env.production",
    ".env.development", ".env.test", ".DS_Store", "master.key",
    "credentials.yml.enc", "id_rsa", "id_ed25519",
}
PRIVATE_EXTENSIONS = {".pem", ".p12", ".pfx", ".key", ".sqlite3-journal"}
EXPECTED_DB = "rails8_ai_support_desk_development"


def run(*args, capture=False):
    p = subprocess.run(args, cwd=ROOT, check=True,
        stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
        stderr=subprocess.PIPE, text=True)
    return p.stdout.strip() if capture else ""


def digest(blob):
    return hashlib.sha256(blob).hexdigest()


def project_files():
    for current, dirs, files in os.walk(ROOT):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDE_DIRS)
        for name in sorted(files):
            path = pathlib.Path(current) / name
            rel = path.relative_to(ROOT)
            if name in EXCLUDE_BASENAMES or path.suffix.lower() in PRIVATE_EXTENSIONS:
                continue
            if name.startswith(".env.") and name != ".env.example":
                continue
            if path.is_symlink() or not path.is_file():
                continue
            yield rel, path


def main():
    if ROOT.name != "Rails-8-AI-Customer-Support-Desk":
        raise RuntimeError("wrong project")
    db = os.environ.get("PGDATABASE", "")
    if db != EXPECTED_DB:
        raise RuntimeError("unexpected database; refusing backup")
    assert run("git", "rev-parse", "--show-toplevel", capture=True) == str(ROOT)
    assert run("git", "rev-parse", "--is-shallow-repository", capture=True) == "false"
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    OUT.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(OUT, 0o700)
    stem = f"RAILS8_AI_SUPPORT_DESK_FULL_BACKUP_{stamp}"
    final = OUT / (stem + ".zip")
    git_bundle = OUT / (stem + ".git.bundle")
    dump = OUT / (stem + ".postgres.dump")
    if any(p.exists() for p in (final, git_bundle, dump)):
        raise RuntimeError("refusing backup overwrite")
    run("git", "bundle", "create", str(git_bundle), "--all")
    run("git", "bundle", "verify", str(git_bundle))
    run("pg_dump", "--format=custom", "--no-owner", "--no-acl",
        "--file=" + str(dump), db)
    run("pg_restore", "--list", str(dump))
    counts = run("psql", "-X", "-q", "-A", "-t", "-c",
        "SELECT (SELECT count(*) FROM tickets),"
        "(SELECT count(*) FROM ticket_messages),"
        "(SELECT count(*) FROM knowledge_chunk_embeddings),"
        "(SELECT count(*) FROM knowledge_article_versions WHERE status='approved')",
        capture=True)
    if counts != "240|440|84|12":
        raise RuntimeError(f"unexpected database counts: {counts}")
    status = run("git", "status", "--porcelain=v1", "--untracked-files=all", capture=True)
    head = run("git", "rev-parse", "HEAD", capture=True)
    metadata = {
        "name": "Rails 8 AI Customer Support Desk full-source backup",
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "project_root_on_colab": str(ROOT),
        "git_head": head, "git_dirty": bool(status),
        "git_status_porcelain": status.splitlines(),
        "db_name": db,
        "db_counts": dict(zip(("tickets","messages","embeddings","approved_kb_versions"),
            [int(x) for x in counts.split("|")])),
        "included": "Full worktree including uncommitted files, evidence, checkpoints, Git history and PostgreSQL snapshot",
        "excluded": "Private secrets, .env.notebook, vendor, runtime logs, caches, temp, .git directory",
        "project_files": {}, "auxiliary_files": {},
    }
    restore_vi = (
        "# Khôi phục Rails 8 AI Customer Support Desk\n\n"
        "1. Giải nén ZIP. Thư mục project/ chứa toàn bộ worktree hiện tại, gồm cả thay đổi chưa commit.\n"
        "2. auxiliary/git-history.bundle giữ lịch sử Git. Có thể dùng git clone với bundle, "
        "sau đó copy project/ vào clone, tránh git reset --hard làm mất file chưa commit.\n"
        "3. Cài Ruby, Rails, PostgreSQL và pgvector theo README. vendor/ có thể cài lại.\n"
        "4. Chỉ restore auxiliary/postgres-development.dump vào database development trống "
        "đã được xác minh và backup, dùng pg_restore --no-owner --no-acl.\n"
        "5. Tạo lại private .env.notebook, preview password, Modal credentials riêng. "
        "Chúng không nằm trong ZIP để tránh rò rỉ.\n"
        "6. Xác minh manifest SHA256, chạy Rails tests và kiểm tra tenant isolation. "
        "Không mở sealed80 answerability hoặc tự gửi phản hồi khách.\n"
    )
    restore_en = (
        "# Restore Rails 8 AI Customer Support Desk\n\n"
        "Unzip this archive. project/ is the source worktree including uncommitted and "
        "untracked changes. auxiliary/git-history.bundle preserves the complete Git "
        "history. Clone the bundle and overlay project/ without discarding changes. "
        "Install Ruby, Rails, PostgreSQL and pgvector. Restore "
        "auxiliary/postgres-development.dump only into a verified empty development "
        "database using pg_restore --no-owner --no-acl. Reconfigure private environment "
        "files and Modal credentials separately. Do not enable sealed80 answerability.\n"
    )
    source_entries = list(project_files())
    if len(source_entries) < 100:
        raise RuntimeError("source file count unexpectedly low")
    with zipfile.ZipFile(final, "x", compression=zipfile.ZIP_DEFLATED,
                         compresslevel=6, allowZip64=True) as archive:
        for rel, path in source_entries:
            blob = path.read_bytes()
            archive.writestr("project/" + rel.as_posix(), blob)
            metadata["project_files"][rel.as_posix()] = {
                "sha256": digest(blob), "bytes": len(blob),
            }
        for name, path in (("git-history.bundle", git_bundle),
                           ("postgres-development.dump", dump)):
            blob = path.read_bytes()
            archive.writestr("auxiliary/" + name, blob)
            metadata["auxiliary_files"][name] = {
                "sha256": digest(blob), "bytes": len(blob),
            }
        archive.writestr("RESTORE_README_VI.md", restore_vi)
        archive.writestr("RESTORE_README_EN.md", restore_en)
        archive.writestr("BACKUP_MANIFEST.json",
            json.dumps(metadata, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
    os.chmod(final, 0o600)
    with zipfile.ZipFile(final) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("ZIP CRC verification failed")
        manifest = json.loads(archive.read("BACKUP_MANIFEST.json"))
        for name, spec in manifest["project_files"].items():
            if digest(archive.read("project/" + name)) != spec["sha256"]:
                raise RuntimeError("source ZIP verification failed: " + name)
        for name, spec in manifest["auxiliary_files"].items():
            if digest(archive.read("auxiliary/" + name)) != spec["sha256"]:
                raise RuntimeError("auxiliary ZIP verification failed: " + name)
        paths = set(archive.namelist())
        assert "project/.env.notebook" not in paths
        assert "project/tmp/local_secret.txt" not in paths
        assert "project/vendor" not in paths
    sha = digest(final.read_bytes())
    sha_path = OUT / (stem + ".sha256")
    sha_path.write_text(sha + "  " + final.name + "\n")
    os.chmod(sha_path, 0o600)
    summary = {
        "status": "PASS_FULL_SOURCE_GIT_POSTGRES_BACKUP",
        "file": str(final), "sha256": sha,
        "size_bytes": final.stat().st_size,
        "project_source_files": len(source_entries),
        "git_head": head, "worktree_dirty": bool(status),
        "db_counts": metadata["db_counts"],
        "git_bundle_bytes": git_bundle.stat().st_size,
        "postgres_dump_bytes": dump.stat().st_size,
        "secrets_excluded": True, "crc_and_sha256_verified": True,
    }
    print(json.dumps(summary, sort_keys=True, ensure_ascii=False, indent=2))
    (OUT / (stem + ".verification.json")).write_text(
        json.dumps(summary, sort_keys=True, indent=2) + "\n")


if __name__ == "__main__":
    main()
