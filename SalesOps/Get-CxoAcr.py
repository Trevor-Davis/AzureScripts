#!/usr/bin/env python3
"""
Pull Azure Consumed Revenue (ACR) for a TPID from the MSA Power BI semantic model
and write it as CSV for merging into the CX Observe pivot workbook.

Source
------
MSA_AzureConsumption_Enterprise  (artifact 726c8fed-367a-4249-b685-e4e22ca82b3d)
Reached through the local PBI-MCP-Proxy, which authenticates from your `az login`.

Grain
-----
ACR is available to Service Level 4 (Product) only. The MSA model has no
ServiceLevel5 column, and the WWBI_ACRSL5 model that does have one is RLS-scoped
to a different account portfolio. So ACR joins the pivot at Product, not SKU.

Caveat
------
MSA reports PRE-CREDIT / GROSS ACR. It will read higher than the finance-net view
in C360 or FinHub. Do not reconcile it against an invoice.

Usage
-----
    python Get-CxoAcr.py --tpid 642489 --start 2026-02-01 --end 2026-07-31 -o acr.csv
"""
import argparse
import csv
import json
import os
import re
import sys
from datetime import datetime

ARTIFACT_MSA = "726c8fed-367a-4249-b685-e4e22ca82b3d"

# Levels the MSA model actually exposes. ServiceLevel5 does not exist here.
LEVELS = {
    "L1_ServiceFamily": "ServiceLevel1",
    "L2_ServiceName": "ServiceLevel2",
    "L4_ProductName": "ServiceLevel4",
}


def load_proxy(proxy_path=None):
    """Import pbi_mcp_proxy, adding the local clone to sys.path if needed."""
    try:
        from pbi_mcp_proxy import call_fabric
        return call_fabric
    except ImportError:
        pass

    candidates = []
    if proxy_path:
        candidates.append(proxy_path)
    candidates += [
        os.path.expandvars(r"%USERPROFILE%\OneDrive - Microsoft\GitHub\PBI-MCP-Proxy"),
        os.path.expandvars(r"%USERPROFILE%\repos\PBI-MCP-Proxy"),
    ]
    for base in candidates:
        src = os.path.join(base, "src")
        if os.path.isdir(src):
            sys.path.insert(0, src)
            try:
                from pbi_mcp_proxy import call_fabric
                return call_fabric
            except ImportError:
                sys.path.pop(0)

    sys.exit(
        "Could not import pbi_mcp_proxy.\n"
        "Run this with the proxy's venv python, e.g.\n"
        r'  "...\PBI-MCP-Proxy\.venv\Scripts\python.exe" Get-CxoAcr.py --tpid 642489'
    )


def money(v):
    """'$1,234' or 1234.0 -> float. Returns 0.0 for blanks."""
    if v is None:
        return 0.0
    if isinstance(v, (int, float)):
        return float(v)
    s = re.sub(r"[^0-9.\-()]", "", str(v))
    if not s:
        return 0.0
    neg = s.startswith("(") and s.endswith(")")
    s = s.strip("()")
    try:
        f = float(s)
    except ValueError:
        return 0.0
    return -f if neg else f


def run_dax(call_fabric, artifact, dax, max_rows=1000):
    """Run one DAX query. max_rows must be passed explicitly - the service
    defaults to 250 rows and truncates silently, which drops real spend."""
    reply = call_fabric("tools/call", {
        "name": "ExecuteQuery",
        "arguments": {"artifactId": artifact, "daxQueries": [dax], "maxRows": max_rows},
    })
    first = reply[0] if isinstance(reply, list) else reply
    if "error" in first:
        raise RuntimeError(str(first["error"])[:300])
    text = first["result"]["content"][0]["text"]
    payload = json.loads(text)
    if "executionResult" not in payload:
        raise RuntimeError(f"Unexpected response: {text[:300]}")
    table = payload["executionResult"]["tables"][0]
    cols = [c["name"] for c in table["columns"]]
    return cols, table["rows"]


def date_id(s):
    return int(datetime.strptime(s[:10], "%Y-%m-%d").strftime("%Y%m%d"))


def main():
    ap = argparse.ArgumentParser(description="Pull ACR by service level for a TPID (MSA model).")
    ap.add_argument("--tpid", required=True)
    ap.add_argument("--start", required=True, help="YYYY-MM-DD (inclusive)")
    ap.add_argument("--end", required=True, help="YYYY-MM-DD (inclusive)")
    ap.add_argument("-o", "--output", required=True, help="output CSV path")
    ap.add_argument("--measure", default="$ ACR",
                    help="'$ ACR' (default, pre-credit/gross), '$ Gross ACR', or '$ PreCredit ACR'")
    ap.add_argument("--artifact", default=ARTIFACT_MSA)
    ap.add_argument("--max-rows", type=int, default=1000,
                    help="row cap per query (service default is 250 and truncates silently)")
    ap.add_argument("--proxy-path", help="path to the PBI-MCP-Proxy clone")
    args = ap.parse_args()

    if not re.fullmatch(r"\d+", str(args.tpid)):
        sys.exit(f"TPID must be numeric: {args.tpid}")

    call_fabric = load_proxy(args.proxy_path)
    d0, d1 = date_id(args.start), date_id(args.end)
    if d0 > d1:
        sys.exit("--start must be on or before --end")

    # NOTE: filter on DateID, not FiscalMonth. Microsoft fiscal years start in July,
    # so "FY26-Jul" is July 2025 - using fiscal labels silently shifts the window.
    out_rows = []
    for label, column in LEVELS.items():
        dax = (
            f"EVALUATE SUMMARIZECOLUMNS('F_ACR'[{column}], "
            f"FILTER(ALL('F_ACR'), 'F_ACR'[TPID] = {args.tpid}), "
            f"FILTER(ALL('DimDate'), 'DimDate'[DateID] >= {d0} && 'DimDate'[DateID] <= {d1}), "
            f'"ACR", [{args.measure}])'
        )
        try:
            _, rows = run_dax(call_fabric, args.artifact, dax, max_rows=args.max_rows)
        except Exception as exc:
            print(f"  {label}: FAILED - {exc}", file=sys.stderr)
            continue

        if len(rows) >= args.max_rows:
            print(f"  WARNING: {label} hit the {args.max_rows}-row cap; results may be "
                  f"truncated. Raise --max-rows.", file=sys.stderr)

        n = 0
        for r in rows:
            name = r[0]
            acr = money(r[1])
            if name is None:
                continue
            out_rows.append({
                "Tpid": args.tpid, "Dimension": label, "Name": name,
                "ACR": round(acr, 2), "Measure": args.measure,
                "StartDate": args.start, "EndDate": args.end,
            })
            n += 1
        print(f"  {label}: {n} rows")

    if not out_rows:
        sys.exit("No ACR rows returned - check the TPID is in scope for this model.")

    with open(args.output, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["Tpid", "Dimension", "Name", "ACR",
                                           "Measure", "StartDate", "EndDate"])
        w.writeheader()
        w.writerows(out_rows)

    total = sum(r["ACR"] for r in out_rows if r["Dimension"] == "L4_ProductName")
    print(f"saved   : {args.output}")
    print(f"rows    : {len(out_rows)}")
    print(f"L4 total: ${total:,.2f} ACR ({args.measure}, pre-credit/gross)")


if __name__ == "__main__":
    main()
