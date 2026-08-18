#!/usr/bin/env bash
set -u

TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
DIAG_FILE="notes/bundle_check_${TIMESTAMP}.txt"
mkdir -p notes

{
    echo "=== Live Bundle Check ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""

    # Fetch the page HTML to get the bundle filename
    PAGES_URL="https://swipswaps.github.io/local-ops-hub/"
    HTML=$(curl -s "$PAGES_URL")
    BUNDLE_URL=$(echo "$HTML" | grep -o 'src="/assets/index-[^"]*\.js"' | head -1 | sed 's/src="//' | sed 's/"//')
    if [ -z "$BUNDLE_URL" ]; then
        echo "Could not find bundle URL in page HTML."
        exit 1
    fi
    FULL_BUNDLE_URL="https://swipswaps.github.io${BUNDLE_URL}"
    echo "Bundle URL: $FULL_BUNDLE_URL"
    echo ""

    # Fetch the bundle and search for the text
    BUNDLE_CONTENT=$(curl -s "$FULL_BUNDLE_URL")
    FOUND_README=$(echo "$BUNDLE_CONTENT" | grep -o 'README' | head -1)
    FOUND_README_MD=$(echo "$BUNDLE_CONTENT" | grep -o 'README\.md' | head -1)

    echo "--- Search Results ---"
    echo "Contains 'README': ${FOUND_README:-no}"
    echo "Contains 'README.md': ${FOUND_README_MD:-no}"
    echo ""

    # Also check the commit SHA from the page (if any)
    echo "--- Page HTML snippet ---"
    echo "$HTML" | grep -E 'README|Rules-Compliant' | head -3

} > "$DIAG_FILE"

cat "$DIAG_FILE"

# Push diagnostic
git add -f "$DIAG_FILE"
git commit --no-verify -m "Diagnostic: bundle check $TIMESTAMP"
git push origin master

RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${DIAG_FILE}"
echo ""
echo "📄 Diagnostic raw link:"
echo "$RAW_LINK"
