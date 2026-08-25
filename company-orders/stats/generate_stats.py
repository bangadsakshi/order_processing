import html
import json
import sys
import urllib.request

api = sys.argv[1].rstrip("/")
output = sys.argv[2] if len(sys.argv) > 2 else "index.html"

with urllib.request.urlopen(f"{api}/stats", timeout=20) as r:
    s = json.loads(r.read().decode())

page = f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>X-Company Order Statistics</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{{font-family:Arial,sans-serif;max-width:900px;margin:40px auto;padding:20px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:16px}}
.card{{border:1px solid #ddd;border-radius:10px;padding:20px}}
.value{{font-size:32px;font-weight:bold}}
</style>
</head>
<body>
<h1>X-Company Order Processing Statistics</h1>
<div class="grid">
<div class="card">Total Orders<div class="value">{s["total_orders"]}</div></div>
<div class="card">Pending<div class="value">{s["pending_orders"]}</div></div>
<div class="card">Completed<div class="value">{s["completed_orders"]}</div></div>
<div class="card">Failed<div class="value">{s["failed_orders"]}</div></div>
<div class="card">Top Product<div class="value">{html.escape(str(s["most_frequently_ordered_product"]))}</div></div>
</div>
</body>
</html>"""

with open(output, "w", encoding="utf-8") as f:
    f.write(page)

print(output)
