# ============================================================================
# backend/main.py – FastAPI Backend Dashboard for Local Operations
# Rules: #1,#7,#8,#27,#32,#41,#48
# ============================================================================
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import os, sys, datetime, sqlite3

app = FastAPI(title="Local Ops Dashboard API", version="1.0.0")

DB_BACKEND = os.getenv("DB_BACKEND", "sqlite")
DB_PATH = os.getenv("DB_PATH", "./operations.db")
DATABASE_URL = os.getenv("DATABASE_URL")

def now_utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def log_result(operation, success, detail):
    ts = now_utc()
    status = "SUCCESS" if success else "FAILURE"
    print(f"[{ts}] [{status}] {operation}: {detail}", file=sys.stderr)

def get_db_conn():
    if DB_BACKEND == "postgresql" and DATABASE_URL:
        import psycopg2
        return psycopg2.connect(DATABASE_URL)
    return sqlite3.connect(DB_PATH)

def init_db():
    conn = get_db_conn()
    cur = conn.cursor()
    if DB_BACKEND == "sqlite":
        cur.execute("""
            CREATE TABLE IF NOT EXISTS ops_audit (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                operation TEXT NOT NULL,
                status TEXT NOT NULL,
                detail TEXT,
                ts TEXT NOT NULL
            );
        """)
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
    else:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS ops_audit (
                id SERIAL PRIMARY KEY,
                operation TEXT NOT NULL,
                status TEXT NOT NULL,
                detail TEXT,
                ts TEXT NOT NULL
            );
        """)
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
    conn.commit()
    conn.close()
    log_result("init_db", True, f"tables ensured ({DB_BACKEND})")

@app.on_event("startup")
def startup_event():
    init_db()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/status")
def get_status():
    return {"status": "operational", "timestamp": now_utc(), "database": DB_BACKEND}

@app.get("/health")
def health_check():
    try:
        conn = get_db_conn()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.fetchone()
        conn.close()
        return {"status": "ok", "timestamp": now_utc(), "db": DB_BACKEND}
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))

@app.get("/operations")
def list_operations(limit: int = 100):
    conn = get_db_conn()
    cur = conn.cursor()
    if DB_BACKEND == "sqlite":
        cur.execute("SELECT * FROM ops_audit ORDER BY ts DESC LIMIT ?", (limit,))
    else:
        cur.execute("SELECT * FROM ops_audit ORDER BY ts DESC LIMIT %s", (limit,))
    rows = cur.fetchall()
    conn.close()
    return {"operations": rows}

@app.post("/operations/rollback")
def trigger_rollback():
    ts = now_utc()
    conn = get_db_conn()
    cur = conn.cursor()
    if DB_BACKEND == "sqlite":
        cur.execute("INSERT INTO ops_audit (operation, status, detail, ts) VALUES (?, ?, ?, ?)",
                    ("rollback", "SUCCESS", "Triggered automated rollback", ts))
    else:
        cur.execute("INSERT INTO ops_audit (operation, status, detail, ts) VALUES (%s, %s, %s, %s)",
                    ("rollback", "SUCCESS", "Triggered automated rollback", ts))
    conn.commit()
    conn.close()
    log_result("rollback", True, "executed")
    return {"success": True, "message": "Rollback recorded", "timestamp": ts}

@app.post("/operations/install")
def record_install(tool: str, status: str, detail: str = ""):
    ts = now_utc()
    conn = get_db_conn()
    cur = conn.cursor()
    if DB_BACKEND == "sqlite":
        cur.execute("INSERT INTO ops_audit (operation, status, detail, ts) VALUES (?, ?, ?, ?)",
                    (f"install_{tool}", status, detail, ts))
    else:
        cur.execute("INSERT INTO ops_audit (operation, status, detail, ts) VALUES (%s, %s, %s, %s)",
                    (f"install_{tool}", status, detail, ts))
    conn.commit()
    conn.close()
    return {"success": True, "timestamp": ts}
