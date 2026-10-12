"""Prints one compact line per MCP response from tests/smoke.sh."""
import json, sys
for line in sys.stdin:
    m = json.loads(line)
    if "error" in m:
        print(m["id"], "RPC ERROR:", m["error"]["message"]); continue
    r = m["result"]
    if "tools" in r:
        print(m["id"], [t["name"] for t in r["tools"]]); continue
    if "content" not in r:
        print(m["id"], r.get("protocolVersion"), r.get("serverInfo")); continue
    text = r["content"][0]["text"]
    if r.get("isError"):
        print(m["id"], "TOOL ERROR:", text); continue
    d = json.loads(text)
    entries = d.get("entries")
    if entries is None and "id" in d and "text" in d:
        entries = [d]
    if entries is None:
        print(m["id"], d); continue
    print(m["id"], [(e["id"], e["journal"], e.get("date"), e.get("tags"), e["text"], e.get("truncated")) for e in entries])
