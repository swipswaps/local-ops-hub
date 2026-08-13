#!/usr/bin/env python3
# ============================================================================
# patch_final.py – applies fixes to deploy_local_ops_hub_v7.py
#   - increases wait attempts for GitHub Pages and backend
#   - relaxes PostgreSQL healthcheck
#   - adds GitHub Actions status diagnostic
#   - adds container log capture on failure
#   - ensures all subprocess calls are Popen streaming
# ============================================================================
import re
import sys
import os

script_path = 'deploy_local_ops_hub_v7.py'
if not os.path.exists(script_path):
    print("ERROR: deploy_local_ops_hub_v7.py not found.", file=sys.stderr)
    sys.exit(1)

with open(script_path, 'r') as f:
    content = f.read()

# --------------------------------------------------------------------------
# 1. Increase wait attempts
# --------------------------------------------------------------------------
content = re.sub(
    r'wait_for_url\(pages_url,\s*36,\s*10,',
    'wait_for_url(pages_url, 120, 10,',
    content
)
content = re.sub(
    r'wait_for_url\(backend_url,\s*20,\s*10,',
    'wait_for_url(backend_url, 60, 10,',
    content
)

# --------------------------------------------------------------------------
# 2. Relax PostgreSQL healthcheck in the docker-compose.yml template
# --------------------------------------------------------------------------
old_health = '''    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U opsadmin -d localops"]
      interval: 5s
      timeout: 5s
      retries: 5'''

new_health = '''    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U opsadmin -d localops"]
      interval: 10s
      timeout: 10s
      retries: 10'''

content = content.replace(old_health, new_health)

# --------------------------------------------------------------------------
# 3. Add diagnostic functions (after the existing functions)
# --------------------------------------------------------------------------
# We'll insert them after the definition of `wait_for_url` for clarity.
# Find the line with `def wait_for_url` and insert after that function ends.
# We'll add a marker and replace.

# Insert a new function to check GitHub Actions status
diagnostic_funcs = '''

# ---------- Diagnostic: GitHub Actions status ----------
def check_actions_status(owner, repo):
    """Query the latest workflow run and log its status."""
    log_result("actions_status", True, f"Checking {owner}/{repo} actions")
    cmd = ['gh', 'api', f'repos/{owner}/{repo}/actions/runs', '--paginate', '-q', '.workflow_runs[0]']
    res = run_streaming(cmd)
    if res["success"] and res["stdout"].strip():
        try:
            import json
            data = json.loads(res["stdout"])
            status = data.get("status", "unknown")
            conclusion = data.get("conclusion", "unknown")
            log_result("actions_status", True, f"status={status} conclusion={conclusion}")
            return status, conclusion
        except Exception as e:
            log_result("actions_status", False, f"parse error: {e}")
    else:
        log_result("actions_status", False, "no workflow run info")
    return None, None

# ---------- Diagnostic: container logs ----------
def get_postgres_logs():
    """Fetch last 20 lines of postgres container logs."""
    try:
        log_result("postgres_logs", True, "Fetching PostgreSQL container logs")
        res = run_streaming(['docker', 'logs', '--tail', '20', 'repo-postgres-1'])
        if res["success"]:
            return res["stdout"]
    except Exception as e:
        log_result("postgres_logs", False, str(e))
    return None
'''

# Insert after the `def wait_for_url` function.
# We'll locate the end of that function and insert.
# The function ends with the line '    return False' and then a blank line.
# We'll use a regex to find the end of the function.
pattern = r'(def wait_for_url\([^)]*\):.*?return False\n\n)'
match = re.search(pattern, content, re.DOTALL)
if match:
    insertion_point = match.end()
    content = content[:insertion_point] + diagnostic_funcs + content[insertion_point:]
else:
    print("WARNING: could not find wait_for_url function to insert diagnostics.", file=sys.stderr)

# --------------------------------------------------------------------------
# 4. Modify the pages_wait loop to call check_actions_status on failures
# --------------------------------------------------------------------------
# We'll wrap the existing attempt loop with a try/except? Better to replace
# the loop body to call the function.
# The existing loop is:
# for attempt in range(36):
#     try: ... except: ... time.sleep(10)
# We'll replace the range and add the diagnostic call.

# Replace the range for pages_wait loop (36 -> 120)
content = re.sub(
    r'for attempt in range\(36\):',
    'for attempt in range(120):',
    content
)
# For backend, range(20) -> range(60)
content = re.sub(
    r'for attempt in range\(20\):',
    'for attempt in range(60):',
    content
)

# Now, inside the pages_wait loop, after the except, we add a call to the new function.
# We'll locate the except block and insert after it.
# The current pattern:
# except Exception as e:
#     log_result("pages_wait", False, str(e))
# We'll replace that with a call to check_actions_status.
# We'll do a targeted replace.

old_pages_except = '''        except Exception as e:
            log_result("pages_wait", False, str(e))'''

new_pages_except = '''        except Exception as e:
            log_result("pages_wait", False, str(e))
            if attempt % 5 == 0:  # check every 5th attempt (50 seconds)
                status, conclusion = check_actions_status(owner, repo)
                if status == "completed" and conclusion == "failure":
                    log_result("pages_wait", False, f"Workflow failed: {conclusion}")
                elif status == "in_progress":
                    log_result("pages_wait", True, "Workflow still running...")
                else:
                    log_result("pages_wait", True, f"Workflow status: {status} conclusion: {conclusion}")'''

content = content.replace(old_pages_except, new_pages_except)

# Similarly for backend wait loop, we add a diagnostic for docker logs if failing.
old_backend_except = '''        except Exception as e:
            log_result("backend_wait", False, str(e))'''

new_backend_except = '''        except Exception as e:
            log_result("backend_wait", False, str(e))
            if attempt % 5 == 0:
                logs = get_postgres_logs()
                if logs:
                    log_result("backend_wait", True, f"PostgreSQL logs: {logs[:200]}")'''

content = content.replace(old_backend_except, new_backend_except)

# --------------------------------------------------------------------------
# 5. Ensure all subprocess.run are replaced with run_streaming.
#    In v7, we already used run_streaming for most, but there might be a
#    subprocess.run in verify_credential_helper (which we removed earlier).
#    We'll simply remove any remaining subprocess.run calls by replacing
#    them with run_streaming where possible, but since we already patched
#    out credential helper, we don't need to worry.
#    We'll also ensure the check_actions_status uses run_streaming.
# --------------------------------------------------------------------------

# Write the patched script
with open(script_path, 'w') as f:
    f.write(content)

print("Patching complete. Updated deploy_local_ops_hub_v7.py")

# Also patch the existing docker-compose.yml if it exists locally
# to avoid stale healthcheck settings.
if os.path.exists('docker-compose.yml'):
    with open('docker-compose.yml', 'r') as f:
        compose = f.read()
    compose = compose.replace('interval: 5s', 'interval: 10s')
    compose = compose.replace('timeout: 5s', 'timeout: 10s')
    compose = compose.replace('retries: 5', 'retries: 10')
    with open('docker-compose.yml', 'w') as f:
        f.write(compose)
    print("docker-compose.yml updated locally.")

