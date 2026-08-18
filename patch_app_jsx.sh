#!/usr/bin/env bash
# ============================================================================
# patch_app_jsx.sh – Safely add DeployVerify to src/App.jsx
# Rules: #1,#7,#8,#9,#16,#38,#41,#48,#49
# ============================================================================

set -u

log_result() {
    local operation="$1" success="$2" detail="$3"
    local ts status
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    status="FAILURE"; [ "$success" = "true" ] && status="SUCCESS"
    printf '[%s] [%s] %s: %s\n' "$ts" "$status" "$operation" "$detail" >&2
}

# Create a Python patch script (no sed, Rule #7)
cat > patch_app_jsx.py << 'PYEOF'
#!/usr/bin/env python3
# ============================================================================
# patch_app_jsx.py – Insert DeployVerify import and component into App.jsx
# Rules: #1,#7,#8,#9,#16,#38,#41,#48,#49
# ============================================================================
import sys
import os
import datetime
import re

def now_utc():
    return datetime.datetime.now(datetime.timezone.utc)

def log_result(op, success, detail):
    ts = now_utc().isoformat()
    status = "SUCCESS" if success else "FAILURE"
    print(f"[{ts}] [{status}] {op}: {detail}", file=sys.stderr)

def read_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()

def write_file(path, content):
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(content)

def verify_file(path, expected_content):
    with open(path, 'r', encoding='utf-8') as f:
        actual = f.read()
    return actual == expected_content

# ----------------------------------------------------------------------------
# 1. Read existing file
# ----------------------------------------------------------------------------
app_path = "src/App.jsx"
if not os.path.exists(app_path):
    log_result("patch_app_jsx", False, f"{app_path} not found")
    sys.exit(1)

original = read_file(app_path)

# ----------------------------------------------------------------------------
# 2. Add import line if not already present
# ----------------------------------------------------------------------------
import_line = "import DeployVerify from './components/DeployVerify';"
if import_line in original:
    log_result("patch_app_jsx", True, "import already present, skipping")
    # Still proceed to add component if missing
else:
    # Find the last import statement and insert after it
    # We'll insert after the line containing "import { ... } from 'lucide-react';"
    # or after the last import.
    lines = original.split('\n')
    last_import_idx = -1
    for i, line in enumerate(lines):
        if line.strip().startswith('import '):
            last_import_idx = i
    if last_import_idx == -1:
        log_result("patch_app_jsx", False, "Could not find import section")
        sys.exit(1)
    # Insert the new import after the last import
    lines.insert(last_import_idx + 1, import_line)
    original = '\n'.join(lines)
    log_result("patch_app_jsx", True, "import added")

# ----------------------------------------------------------------------------
# 3. Add component usage if not already present
# ----------------------------------------------------------------------------
component_marker = "<DeployVerify"
if component_marker in original:
    log_result("patch_app_jsx", True, "component already present, skipping")
else:
    # We need to insert the component after the Operations Dashboard div.
    # Find the closing </div> of the Operations Dashboard card.
    # We'll look for the line with "Operations Dashboard" and then find its parent closing.
    # Simpler: insert before the final </div> of the main container.
    # The main container is the outer div with class "max-w-6xl".
    # We'll locate the last </div> that closes the main container.
    # Actually, the component should be placed after the Operations Dashboard card,
    # but still inside the main container. We'll insert it right before the last
    # two closing </div> (which close the main container and the return).
    # The return ends with:
    #     </div>
    #   );
    # }
    # So we can insert before the last </div> that is followed by ");"
    # We'll find the last occurrence of "    </div>" and insert before it.
    # But there are multiple </div>. We'll look for the one that closes the main container.
    # A more robust way: find the position of the Operations Dashboard div and insert after it.
    # The Operations Dashboard div ends with "</div>" (the card itself) and then there might be
    # another </div> for the main container. We can insert after the card's closing.
    # We'll use a regex to find the Operations Dashboard card block and insert after it.
    import re
    pattern = r'(<div className="bg-slate-900 border border-slate-800 rounded-xl p-6">\s*<h3 className="text-lg font-semibold mb-3 flex items-center gap-2"><RefreshCw className="text-purple-400" /> Operations Dashboard.*?</div>\s*</div>)'
    # The card ends with </div> for the card, and then the main container closes with </div>.
    # We want to insert after the card's closing </div> but before the final </div>.
    # Let's find the card block and insert after it.
    match = re.search(pattern, original, re.DOTALL)
    if match:
        # Insert a new div with the component after the card
        component_div = '''
      <div className="bg-slate-900 border border-slate-800 rounded-xl p-6 mt-6">
        <DeployVerify githubOwner={githubOwner} githubRepo={githubRepo} />
      </div>
'''
        # Insert right after the matched end
        end_pos = match.end()
        new_content = original[:end_pos] + component_div + original[end_pos:]
        original = new_content
        log_result("patch_app_jsx", True, "component inserted after Operations Dashboard")
    else:
        log_result("patch_app_jsx", False, "Could not find Operations Dashboard div")
        sys.exit(1)

# ----------------------------------------------------------------------------
# 4. Write and verify
# ----------------------------------------------------------------------------
write_file(app_path, original)
if verify_file(app_path, original):
    log_result("patch_app_jsx", True, f"{app_path} updated successfully")
else:
    log_result("patch_app_jsx", False, f"{app_path} read-back mismatch")
    sys.exit(1)

print(f"✅ {app_path} patched successfully.")
PYEOF

# Run the patch
python3 patch_app_jsx.py
if [ $? -ne 0 ]; then
    log_result "patch_app_jsx" "false" "Python patch failed"
    exit 1
fi

# Rule #9: verify the file exists and is non-zero
if [ ! -f "src/App.jsx" ]; then
    log_result "patch_app_jsx" "false" "src/App.jsx missing after patch"
    exit 1
fi
SIZE=$(wc -c < src/App.jsx)
if [ "$SIZE" -eq 0 ]; then
    log_result "patch_app_jsx" "false" "src/App.jsx is 0 bytes after patch"
    exit 1
fi
log_result "patch_app_jsx" "true" "src/App.jsx patch applied, size=${SIZE} bytes"

echo ""
echo "✅ src/App.jsx patched. Next steps:"
echo "   Ensure deploy_verify.sh exists in project root."
echo "   Rebuild Docker: docker compose up --build"
