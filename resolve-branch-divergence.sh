#!/bin/sh
# ============================================================================
# resolve-branch-divergence.sh – Interactive tool to fix diverged master.
#
# Shows evidence, lets you choose, and logs the decision.
# ============================================================================

# Rule #1: Logging convention
log_result() {
	_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	_status="FAILURE"
	[ "$2" = "true" ] && _status="SUCCESS"
	printf '[%s] [%s] %s: %s\n' "$_ts" "$_status" "$1" "$3" >&2
}

# --- Step 1: Show current state ---
echo "============================================================================"
echo "                    BRANCH DIVERGENCE DIAGNOSTIC"
echo "============================================================================"
echo ""

git fetch origin 2>/dev/null || {
	echo "❌ git fetch failed – check network or auth"
	log_result "fetch" "false" "git fetch failed"
	exit 1
}
log_result "fetch" "true" "fetched from origin"

echo "--- Local commits not on remote (master) ---"
LOCAL_COMMITS=$(git log --oneline origin/master..master 2>/dev/null)
if [ -n "$LOCAL_COMMITS" ]; then
	echo "$LOCAL_COMMITS"
	LOCAL_COUNT=$(echo "$LOCAL_COMMITS" | wc -l)
else
	echo "(none)"
	LOCAL_COUNT=0
fi
echo ""

echo "--- Remote commits not in local (origin/master) ---"
REMOTE_COMMITS=$(git log --oneline master..origin/master 2>/dev/null)
if [ -n "$REMOTE_COMMITS" ]; then
	echo "$REMOTE_COMMITS"
	REMOTE_COUNT=$(echo "$REMOTE_COMMITS" | wc -l)
else
	echo "(none)"
	REMOTE_COUNT=0
fi
echo ""

echo "--- Untracked files in repo (new scripts, logs) ---"
UNTRACKED=$(git ls-files --others --exclude-standard | head -10)
if [ -n "$UNTRACKED" ]; then
	echo "$UNTRACKED"
	echo "... and $(git ls-files --others --exclude-standard | wc -l) total untracked files"
else
	echo "(none)"
fi
echo ""

echo "--- Last 5 local commits ---"
git log --oneline -5
echo ""

echo "--- Last 5 remote commits ---"
git log --oneline -5 origin/master
echo ""

# --- Step 2: Decide which side has the real work ---
echo "============================================================================"
echo "                    DECISION POINT"
echo "============================================================================"
echo ""
echo "Based on the evidence above:"
echo ""
echo "  [1] Local is ahead (LOCAL_COUNT=$LOCAL_COUNT, REMOTE_COUNT=$REMOTE_COUNT)"
echo "      → You have scripts/logs locally that need to be pushed."
echo "      → Use: git push --force origin master"
echo ""
echo "  [2] Remote is ahead (REMOTE_COUNT=$REMOTE_COUNT, LOCAL_COUNT=$LOCAL_COUNT)"
echo "      → The remote has commits you don't have locally."
echo "      → Use: git reset --hard origin/master"
echo ""
echo "  [3] Both have diverged with different commits"
echo "      → You need to merge or rebase."
echo "      → Use: git pull origin master --no-rebase (then fix conflicts)"
echo ""
echo "  [4] Show more detail before deciding"
echo "      → Shows full diff between local and remote"
echo ""
echo "  [q] Quit without making changes"
echo ""

printf "Enter your choice [1/2/3/4/q]: "
read CHOICE

case "$CHOICE" in
	1)
		echo ""
		echo ">>> You chose: PUSH local changes to remote (force)"
		echo ""
		echo "This will overwrite remote 'master' with your local version."
		echo "Your untracked files will still be untracked."
		echo ""
		printf "Are you sure? Type 'YES' to confirm: "
		read CONFIRM
		if [ "$CONFIRM" = "YES" ]; then
			git push --force origin master
			RC=$?
			if [ $RC -eq 0 ]; then
				log_result "push_force" "true" "forced push succeeded"
				echo ""
				echo "✅ Push successful. Remote is now in sync with local."
				echo "   Raw links will now work:"
				echo "   https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/notes/"
			else
				log_result "push_force" "false" "exit code $RC"
				echo "❌ Push failed with exit code $RC"
			fi
		else
			echo "❌ Confirmation failed – no changes made"
			log_result "push_force" "false" "user cancelled"
		fi
		;;
	2)
		echo ""
		echo ">>> You chose: RESET local to match remote"
		echo ""
		echo "This will discard your local commits and match origin/master."
		echo "Your untracked files (scripts, notes) will remain untouched."
		echo ""
		printf "Are you sure? Type 'YES' to confirm: "
		read CONFIRM
		if [ "$CONFIRM" = "YES" ]; then
			git reset --hard origin/master
			RC=$?
			if [ $RC -eq 0 ]; then
				log_result "reset_hard" "true" "reset to origin/master"
				echo ""
				echo "✅ Reset successful. Local now matches remote."
			else
				log_result "reset_hard" "false" "exit code $RC"
				echo "❌ Reset failed with exit code $RC"
			fi
		else
			echo "❌ Confirmation failed – no changes made"
			log_result "reset_hard" "false" "user cancelled"
		fi
		;;
	3)
		echo ""
		echo ">>> You chose: MERGE remote changes into local"
		echo ""
		echo "This will attempt to merge origin/master into master."
		echo "You may need to resolve conflicts."
		echo ""
		printf "Continue? (y/n): "
		read CONFIRM
		if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
			git pull origin master --no-rebase
			RC=$?
			if [ $RC -eq 0 ]; then
				log_result "merge" "true" "pull succeeded"
				echo ""
				echo "✅ Merge successful. Local now includes remote changes."
				echo "   Push the result: git push origin master"
			else
				log_result "merge" "false" "exit code $RC – conflicts may need manual resolution"
				echo ""
				echo "❌ Merge had conflicts. Resolve them, then:"
				echo "   git add <resolved-files>"
				echo "   git commit"
				echo "   git push origin master"
				echo ""
				echo "   Conflicting files:"
				git diff --name-only --diff-filter=U
			fi
		else
			echo "❌ Cancelled – no changes made"
		fi
		;;
	4)
		echo ""
		echo ">>> Full diff: local vs remote"
		echo "============================================================================"
		git diff master origin/master
		echo "============================================================================"
		echo ""
		echo "Re-run this script to make a decision after reviewing."
		;;
	q|Q)
		echo "Exiting – no changes made"
		log_result "exit" "true" "user quit"
		exit 0
		;;
	*)
		echo "Invalid choice – no changes made"
		log_result "invalid_choice" "false" "choice='$CHOICE'"
		exit 1
		;;
esac

echo ""
echo "============================================================================"
echo "                    FINAL STATE"
echo "============================================================================"
git status --short
echo ""
git log --oneline -3

