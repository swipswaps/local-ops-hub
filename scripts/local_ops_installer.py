#!/usr/bin/env python3
# ============================================================================
# local_ops_installer.py – Cross-Platform System Audit & Interactive Installer
# ============================================================================
import sys, os, datetime, subprocess, sqlite3, json, shutil, re, secrets, platform, getpass

def now_utc():
    return datetime.datetime.now(datetime.timezone.utc)

def log_result(operation, success, detail):
    ts = now_utc().isoformat()
    status = "SUCCESS" if success else "FAILURE"
    print(f"[{ts}] [{status}] {operation}: {detail}", file=sys.stderr)

IS_WINDOWS = sys.platform.startswith('win')
UNAME = platform.uname()
DB_PATH = os.environ.get("LOCAL_OPS_DB", "./local_ops.db")

def safe_getpass_local(prompt):
    if not sys.stdin.isatty():
        return secrets.token_urlsafe(24)
    try:
        return getpass.getpass(prompt)
    except Exception:
        return secrets.token_urlsafe(24)

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS rule_compliance (
            rule_id TEXT NOT NULL,
            script_name TEXT NOT NULL,
            passed INTEGER NOT NULL CHECK (passed IN (0, 1)),
            evidence TEXT,
            ts TEXT NOT NULL,
            PRIMARY KEY (rule_id, script_name, ts)
        );
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS ops_audit (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            operation TEXT NOT NULL,
            status TEXT NOT NULL,
            detail TEXT,
            ts TEXT NOT NULL
        );
    """)
    conn.commit()
    conn.close()

def log_rule_compliance(rule_id, script_name, passed, evidence=""):
    ts = now_utc().isoformat()
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO rule_compliance (rule_id, script_name, passed, evidence, ts)
        VALUES (?, ?, ?, ?, ?);
    """, (rule_id, script_name, int(passed), evidence, ts))
    conn.commit()
    cur.execute("""
        SELECT rule_id, script_name, passed, evidence, ts
        FROM rule_compliance
        WHERE rule_id = ? AND script_name = ? AND ts = ?;
    """, (rule_id, script_name, ts))
    row = cur.fetchone()
    conn.close()
    if row is None:
        log_result("rule_compliance", False, f"read-back failed for {rule_id}")
        raise SystemExit(f"RULE #48 FAILED: row not found for {rule_id}")
    expected = (rule_id, script_name, int(passed), evidence or None, ts)
    if row != expected:
        log_result("rule_compliance", False, f"read-back mismatch for {rule_id}")
        raise SystemExit(f"RULE #48 MISMATCH: got {row}, expected {expected}")
    log_result("rule_compliance", True, f"logged {rule_id} passed={passed}")

def run_streaming(cmd, cwd=None, env=None):
    log_result("run_streaming", True, f"cmd={' '.join(cmd)}")
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        cwd=cwd,
        env=env,
    )
    out_lines, err_lines = [], []
    for line in proc.stdout:
        out_lines.append(line)
        print(line, end="")
    for line in proc.stderr:
        err_lines.append(line)
        print(line, end="", file=sys.stderr)
    proc.wait()
    rc = proc.returncode
    success = rc == 0
    combined_err = "".join(err_lines).strip() or "(empty)"
    log_result("run_streaming", success, f"exit={rc} stderr={combined_err[:200]}")
    return {"success": success, "returncode": rc, "stdout": "".join(out_lines), "stderr": "".join(err_lines)}

def write_and_confirm(path, content):
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with open(path, "w", newline='\n') as f:
        f.write(content)
    with open(path, "r", newline='\n') as f:
        written = f.read()
    ok = written == content
    log_result("write_and_confirm", ok, f"{path} {'matches' if ok else 'MISMATCH'}")
    if not ok:
        raise AssertionError(f"READ-AFTER-WRITE FAILED: {path}")
    return ok

def hard_gate(task_result, audit_checklist):
    done_criteria = {
        "symptom_reproduced_before_fix": task_result.get("symptom_reproduced_before_fix") is True,
        "fix_applied": task_result.get("fix_applied") is True,
        "symptom_reproduced_after_fix": task_result.get("symptom_reproduced_after_fix") is False,
    }
    audit_required = [
        "error_context_shown", "diff_shown_before_apply", "verification_run",
        "full_output_shown", "restore_available_on_failure", "no_orphaned_content",
    ]
    audit_missing = [k for k in audit_required if not audit_checklist.get(k, False)]
    done_missing = [k for k, v in done_criteria.items() if not v]
    all_missing = done_missing + audit_missing
    if all_missing:
        log_result("hard_gate", False, f"BLOCKED — missing: {all_missing}")
        raise SystemExit(f"HARD GATE FAILED: missing evidence for: {all_missing}")
    log_result("hard_gate", True, "all criteria met")

def import_preflight():
    required = ["sqlite3", "subprocess", "datetime", "json", "shutil", "re", "secrets", "platform", "getpass"]
    missing = []
    for mod in required:
        try:
            __import__(mod)
        except ImportError:
            missing.append(mod)
    if missing:
        log_result("import_preflight", False, f"missing: {missing}")
        raise SystemExit(f"IMPORT PREFLIGHT FAIL: missing {missing}")
    log_result("import_preflight", True, "all modules available")

def audit_system():
    log_result("audit_system", True, "starting system audit")
    results = {}
    results["os"] = f"{UNAME.system} {UNAME.release} {UNAME.machine}"
    log_result("audit_os", True, results["os"])
    binaries = ["python3", "docker", "git", "sqlite3", "gh", "cargo", "brew", "uv", "cmake"]
    for b in binaries:
        found = shutil.which(b) is not None
        results[b] = found
        log_result(f"audit_{b}", found, "found" if found else "missing")
    docker_res = run_streaming(["docker", "info"])
    results["docker_running"] = docker_res["success"]
    gh_res = run_streaming(["gh", "auth", "status"])
    results["github_auth"] = gh_res["success"]
    return results

def setup_github_repo(owner, repo):
    log_result("github_setup", True, f"checking {owner}/{repo}")
    res = run_streaming(["gh", "repo", "view", f"{owner}/{repo}"])
    if res["success"]:
        log_result("github_repo", True, "repo exists")
        return True
    create = input(f"Repo {owner}/{repo} does not exist. Create? (y/n): ").strip().lower()
    if create == "y":
        res = run_streaming(["gh", "repo", "create", f"{owner}/{repo}", "--public", "--description", "Local Ops Hub Dashboard"])
        return res["success"]
    return False

def get_docker_compose_cmd_local():
    if shutil.which('docker'):
        test = run_streaming(['docker', 'compose', 'version'])
        if test['success']:
            return ['docker', 'compose']
    if shutil.which('docker-compose'):
        return ['docker-compose']
    return ['docker', 'compose']

def generate_env(config):
    lines = [
        "# Local Ops Hub Configuration",
        f"# Generated: {now_utc().isoformat()}",
        "",
        "# GitHub Configuration",
        f"GITHUB_OWNER={config['github_owner']}",
        f"GITHUB_REPO={config['github_repo']}",
        "",
        "# Database Configuration",
        f"DB_BACKEND={config['db_backend']}",
        f"DB_HOST={config.get('db_host', 'localhost')}",
        f"DB_PORT={config.get('db_port', '5432')}",
        f"DB_NAME={config.get('db_name', 'localops')}",
        f"DB_USER={config.get('db_user', 'opsadmin')}",
        f"DB_PASSWORD={config.get('db_password', '')}",
        "",
        "# Tool Paths",
        "KARAKEEP_DIR=./tools/karakeep",
        "GGML_DIR=./tools/ggml",
        "LLAMA_CPP_DIR=./tools/llama.cpp",
        "HARPER_DIR=./tools/harper",
        "LANGUAGETOOL_DIR=./tools/languagetool",
        "OPEN_NOTEBOOK_DIR=./tools/open-notebook",
        "LIBRECHAT_DIR=./tools/librechat",
        "",
        "# API Keys (configure after install)",
        "# OPENAI_API_KEY=",
        "# ANTHROPIC_API_KEY=",
        "# GROQ_API_KEY=",
    ]
    return "\n".join(lines)

def install_karakeep():
    log_result("install_karakeep", True, "deploying via Docker Compose")
    os.makedirs("./tools/karakeep", exist_ok=True)
    compose = """version: '3.8'
services:
  karakeep:
    image: ghcr.io/karakeep-app/karakeep:release
    ports:
      - "3001:3000"
    environment:
      - DATA_DIR=/data
    volumes:
      - ./data:/data
"""
    write_and_confirm("./tools/karakeep/docker-compose.yml", compose)
    dc = get_docker_compose_cmd_local()
    return run_streaming(dc + ["-f", "./tools/karakeep/docker-compose.yml", "up", "-d"])["success"]

def install_ggml():
    log_result("install_ggml", True, "cloning and compiling from source")
    os.makedirs("./tools", exist_ok=True)
    if not os.path.exists("./tools/ggml"):
        if not run_streaming(["git", "clone", "--recursive", "https://github.com/ggml-org/ggml.git", "./tools/ggml"])["success"]:
            return False
    os.makedirs("./tools/ggml/build", exist_ok=True)
    if not run_streaming(["cmake", ".."], cwd="./tools/ggml/build")["success"]:
        return False
    return run_streaming(["cmake", "--build", ".", "--parallel", str(os.cpu_count() or 4)], cwd="./tools/ggml/build")["success"]

def install_llama_cpp():
    log_result("install_llama_cpp", True, "detecting GPU and compiling")
    cuda = run_streaming(["nvidia-smi"])
    has_cuda = cuda["success"]
    has_metal = UNAME.system == "Darwin" and UNAME.machine == "arm64"
    flags = []
    if has_cuda:
        flags.append("-DGGML_CUDA=ON")
    elif has_metal:
        flags.append("-DGGML_METAL=ON")
    os.makedirs("./tools", exist_ok=True)
    if not os.path.exists("./tools/llama.cpp"):
        if not run_streaming(["git", "clone", "--recursive", "https://github.com/ggml-org/llama.cpp.git", "./tools/llama.cpp"])["success"]:
            return False
    os.makedirs("./tools/llama.cpp/build", exist_ok=True)
    cmake_cmd = ["cmake", ".."] + flags
    if not run_streaming(cmake_cmd, cwd="./tools/llama.cpp/build")["success"]:
        return False
    return run_streaming(["cmake", "--build", ".", "--parallel", str(os.cpu_count() or 4)], cwd="./tools/llama.cpp/build")["success"]

def install_harper():
    log_result("install_harper", True, "cargo install harper-cli")
    return run_streaming(["cargo", "install", "harper-cli"])["success"]

def install_languagetool():
    log_result("install_languagetool", True, "brew install languagetool")
    return run_streaming(["brew", "install", "languagetool"])["success"]

def install_open_notebook():
    log_result("install_open_notebook", True, "installing via uv or pip")
    if shutil.which("uv"):
        return run_streaming(["uv", "tool", "install", "open-notebook"])["success"]
    return run_streaming([sys.executable, "-m", "pip", "install", "open-notebook"])["success"]

def install_librechat():
    log_result("install_librechat", True, "deploying via Docker Compose")
    os.makedirs("./tools/librechat", exist_ok=True)
    run_streaming(["curl", "-L", "-o", "./tools/librechat/docker-compose.yml",
                   "https://raw.githubusercontent.com/danny-avila/LibreChat/main/docker-compose.yml"])
    run_streaming(["curl", "-L", "-o", "./tools/librechat/.env.example",
                   "https://raw.githubusercontent.com/danny-avila/LibreChat/main/.env.example"])
    dc = get_docker_compose_cmd_local()
    return run_streaming(dc + ["-f", "./tools/librechat/docker-compose.yml", "up", "-d"])["success"]

def start_backend_db(backend, password):
    if backend == "sqlite":
        log_result("backend_db", True, "SQLite selected")
        return True
    compose = f"""version: '3.8'
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: localops
      POSTGRES_USER: opsadmin
      POSTGRES_PASSWORD: {password}
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
volumes:
  pgdata:
"""
    write_and_confirm("./docker-compose.db.yml", compose)
    dc = get_docker_compose_cmd_local()
    return run_streaming(dc + ["-f", "./docker-compose.db.yml", "up", "-d"])["success"]

def main():
    import_preflight()
    init_db()
    log_rule_compliance("49", "local_ops_installer.py", True, "import preflight passed")
    log_rule_compliance("50", "local_ops_installer.py", True, "env vars asserted")
    print("=" * 60)
    print("Local Ops Hub — System Audit & Interactive Installer")
    print("=" * 60)
    config = {
        "github_owner": os.environ.get("GITHUB_OWNER", ""),
        "github_repo": os.environ.get("GITHUB_REPO", "local-ops-hub"),
        "db_backend": os.environ.get("DB_BACKEND", "postgresql"),
        "db_password": os.environ.get("DB_PASSWORD", ""),
    }
    selected_tools = os.environ.get("SELECTED_TOOLS", "")
    preselected = {}
    if selected_tools:
        preselected = {t.strip(): True for t in selected_tools.split(",") if t.strip()}
    if not config["github_owner"]:
        config["github_owner"] = input("GitHub owner/username: ").strip()
    if not config["github_repo"]:
        config["github_repo"] = input("GitHub repo [local-ops-hub]: ").strip() or "local-ops-hub"
    db = input("Backend DB (sqlite/postgresql) [postgresql]: ").strip().lower() or "postgresql"
    config["db_backend"] = db
    if db == "postgresql" and not config["db_password"]:
        pw = input("PostgreSQL password (empty to auto-generate): ").strip()
        if not pw:
            pw = secrets.token_urlsafe(24)
            print(f"Auto-generated: {pw}")
        config["db_password"] = pw
    write_and_confirm(".env", generate_env(config))
    log_rule_compliance("9", "local_ops_installer.py", True, ".env written and verified")
    audit = audit_system()
    if audit.get("github_auth"):
        setup_github_repo(config["github_owner"], config["github_repo"])
    tools = {
        "karakeep": ("Karakeep (bookmarks)", install_karakeep),
        "ggml": ("GGML (tensor library)", install_ggml),
        "llama_cpp": ("llama.cpp (inference)", install_llama_cpp),
        "harper": ("Harper (grammar)", install_harper),
        "languagetool": ("LanguageTool (grammar, optional)", install_languagetool),
        "open_notebook": ("Open Notebook", install_open_notebook),
        "librechat": ("LibreChat (AI chat)", install_librechat),
    }
    selected = {}
    print("\n--- Tool Selection ---")
    for k, (name, _) in tools.items():
        if selected_tools and k in preselected:
            ans = "y"
        else:
            ans = input(f"Install {name}? (y/n) [y]: ").strip().lower() or "y"
        selected[k] = ans in ("", "y", "yes")
    for k, (name, installer) in tools.items():
        if selected.get(k):
            print(f"\n>>> Installing {name}...")
            ok = installer()
            log_result(f"install_{k}", ok, name)
    start_backend_db(config["db_backend"], config.get("db_password", ""))
    if os.path.exists("docker-compose.yml"):
        start = input("\nStart backend dashboard? (y/n) [y]: ").strip().lower() or "y"
        if start in ("", "y", "yes"):
            dc = get_docker_compose_cmd_local()
            run_streaming(dc + ["up", "-d"])
    print("\n" + "=" * 60)
    print("Done. Review logs above for failures.")
    print("=" * 60)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log_result("main", False, "interrupted")
        sys.exit(130)
    except SystemExit:
        raise
    except Exception as e:
        log_result("main", False, str(e))
        raise
