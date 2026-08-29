# CX Observe Consumption Extract

Pull a customer's full Azure SKU / service / subscription consumption out of
[CX Observe](https://cxp.azure.com) by TPID, enrich it with Azure Consumed Revenue
from the MSA Power BI model, and produce CSVs plus a ready-to-read Excel pivot workbook.

CX Observe's UI renders only the top N rows per tile. These scripts call the same
REST APIs the portal uses, so you get **everything** — for a recent Morgan Stanley
pull that was 807 SKUs and 1,350 subscriptions instead of the ~20 rows on screen.

> **Data classification — read this first.**
> Everything CX Observe returns is **Microsoft Confidential \ Microsoft FTE**.
> `.gitignore` in this folder is deliberately aggressive so extracted data can
> never be committed. Don't relax it, and label any workbook you share.

---

## Quick start

```powershell
# One command: captures its own token, pulls consumption + ACR, builds the workbook
.\Get-CxoConsumption.ps1 -Tpid 642489 -OutDir .\out
```

```
Capturing tokens from your CX Observe session ...
Customer     : MORGAN STANLEY
Output folder: .\out\642489_MORGAN_STANLEY
[consumptionunits] L1_ServiceFamily ... 21 rows
[consumptionunits] L5_SKU ........... 807 rows
  Service -> Product: 91 calls, 8 at a time ...
  Product -> SKU: 356 calls, 8 at a time ...
Hierarchy: 1086 rows
Pulling ACR from the MSA model ...
  L4 total: $21,576,104.00 ACR ($ ACR, pre-credit/gross)
Building Excel pivot workbook ...
Workbook : ...\642489_MORGAN_STANLEY_Pivot.xlsx
```

Roughly 90 seconds end to end on PowerShell 7. Add `-NoHierarchy` for a ~10s
CSV-only pull.

---

## Requirements

| | |
|---|---|
| **PowerShell** | 7.x recommended (`winget install Microsoft.PowerShell`). Works on 5.1, but the hierarchy pull runs sequentially and takes ~3x longer. |
| **Python** | 3.11+ with `openpyxl` (`pip install openpyxl`) — needed for the Excel workbook. |
| **Edge** | Required for automatic token capture. |
| **PBI-MCP-Proxy** | Needed for ACR only. See [ACR setup](#acr-azure-consumed-revenue) below. |
| **Access** | CX Observe entitlement for the TPIDs you query. Corpnet / signed in. |

---

## The scripts

### `Get-CxoConsumption.ps1`
The main entry point. A bare `-Tpid <id>` call does everything: captures a token,
resolves the customer name, pulls every dimension, builds the hierarchy, and writes
the Excel workbook. The `-No*` switches opt out.

| Parameter | Default | Notes |
|---|---|---|
| `-Tpid` | *required* | MSX Top Parent ID, e.g. `642489`. |
| `-OutDir` | script folder | Absolute, relative, `~`, or `%VAR%`. Created if missing. |
| `-NoHierarchy` | | Skip the Service → Product → SKU rollup **and** the workbook. Fast CSV-only pull. |
| `-NoPivot` | | Keep the hierarchy CSV but skip the Excel workbook. |
| `-NoAcr` | | Skip the ACR pull; workbook shows ACU only. |
| `-NoAutoToken` | | Don't auto-capture a token; fail if none is supplied. |
| `-Token` | | Bearer string, if you'd rather supply one. Takes precedence. |
| `-Months` | `6` | Look-back window. Or use `-StartDate` / `-EndDate`. |
| `-Aspects` | `consumptionunits` | Also `compute` (VM cores) and `storage`. |
| `-NoTpidSubfolder` | | Write straight into `-OutDir`. |
| `-CustomerName` | *looked up* | Override the auto-resolved name. |
| `-Throttle` | `8` | Parallel requests (PS7 only). `1` forces sequential. |
| `-PbiProxyPath` | *auto* | Path to the PBI-MCP-Proxy clone, if not in a default location. |

### `Get-CxoAcr.py`
Pulls ACR by service level from the MSA semantic model through the local
PBI-MCP-Proxy. Invoked automatically by the main script; run standalone to
refresh ACR without re-pulling consumption.

```bash
python Get-CxoAcr.py --tpid 642489 --start 2026-02-01 --end 2026-07-31 -o acr.csv
```

Run it with the **proxy's venv python** (it imports `pbi_mcp_proxy`).

### `Get-CxoToken.ps1`
Launches Edge with the DevTools Protocol, loads the two CX Observe pages that call
the APIs, and reads the `Authorization` header off the live requests. Tokens are
returned in memory — never written to disk or logged.

Uses a dedicated Edge profile at `%LOCALAPPDATA%\CxoConsumption\edge-profile`, so
it never touches your normal browser. Sign in once; later runs are silent.

`Get-CxoConsumption.ps1` calls this automatically when no token is supplied, so you
rarely run it directly.

### `New-CxoPivot.py`
Turns a hierarchy CSV into the Excel workbook. Invoked automatically by the main
script; run it standalone to rebuild a workbook from existing CSVs.

```bash
python New-CxoPivot.py <hierarchy.csv> [-o out.xlsx] [--top 50] [--months 6] [--title "..."]
```

---

## Output

Folder and files are named `<TPID>_<CUSTOMER_NAME>`:

```
out/642489_MORGAN_STANLEY/
├── 642489_MORGAN_STANLEY_all.csv                                # every dimension, combined
├── 642489_MORGAN_STANLEY_consumptionunits_L1_ServiceFamily.csv  #    21 rows
├── 642489_MORGAN_STANLEY_consumptionunits_L2_ServiceName.csv    #    91
├── 642489_MORGAN_STANLEY_consumptionunits_L4_ProductName.csv    #   356
├── 642489_MORGAN_STANLEY_consumptionunits_L5_SKU.csv            #   807
├── 642489_MORGAN_STANLEY_consumptionunits_SubscriptionName.csv  # 1,244
├── 642489_MORGAN_STANLEY_consumptionunits_SubscriptionGuid.csv  # 1,350
├── 642489_MORGAN_STANLEY_product_sku_hierarchy.csv              # 1,086
├── 642489_MORGAN_STANLEY_acr.csv                                #   380 (ACR by level)
└── 642489_MORGAN_STANLEY_Pivot.xlsx
```

**The workbook** has three sheets:

- **Pivot** — collapsible Service → Product → SKU outline with ACU, ACU/mo,
  % of parent, % of total, ACR, ACR/mo, and data bars. Opens at Service/Product
  level; use the `1 2 3` outline buttons to drill in.
- **Data** — flat rows as a named table (`ConsumptionData`) for your own PivotTables.
- **Top SKUs** — top 50 ranked, with parent product and service.

The ACU column is labelled with the period it covers (e.g. `ACU (6 mo)`), and
`ACU / mo` next to it is the monthly average. The period is inferred from the
sibling `_all.csv`; pass `--months` to override when running the pivot standalone.

`% of Parent` is the column that earns its keep: it shows E64ads v5 is 67% of
Eadsv5 Series spend, and AI Credit is 81% of GitHub Copilot.

> The hierarchy CSV also carries a `ProductACU` column — the parent product's total,
> repeated on every SKU row as a denominator. **Never sum it**; it double-counts.
> Sum `SKU_ACU` instead. It's deliberately left out of the workbook.

---

## ACR (Azure Consumed Revenue)

ACU is a normalized usage index, not money. ACR is the actual dollars, and it comes
from a different system — the **MSA** semantic model
(`MSA_AzureConsumption_Enterprise`, artifact `726c8fed-367a-4249-b685-e4e22ca82b3d`),
reached through the local [PBI-MCP-Proxy](https://github.com/mcaps-microsoft/PBI-MCP-Proxy),
which authenticates from your existing `az login`.

### Setup (one time)

```powershell
winget install astral-sh.uv          # optional; pip works too
cd "$HOME\OneDrive - Microsoft\GitHub"
git clone https://github.com/mcaps-microsoft/PBI-MCP-Proxy.git
cd PBI-MCP-Proxy
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e .
```

`uv sync` is the documented path, but uv bundles its own TLS stack and fails on
networks that inspect TLS to `files.pythonhosted.org`. pip uses the Windows cert
store and works. Then right-click `.venv` → **Free up space** so OneDrive stops
syncing ~2,600 files.

The main script finds the proxy automatically in `OneDrive - Microsoft\GitHub\` or
`~\repos\`; use `-PbiProxyPath` for anywhere else.

### ACR stops at Product (L4)

**This is a real limitation, not a bug.** The MSA model has `ServiceLevel1-4` but
no `ServiceLevel5`. The `WWBI_ACRSL5` model does have SL5 — but it holds 49,311
TPIDs and is RLS-scoped to a different portfolio, so accounts you manage return
zero rows even though the report renders.

So SKU rows in the workbook are **intentionally blank** in the ACR columns.
Allocating a product's ACR across its SKUs by ACU share would look precise and be
wrong: SKUs within a product have very different unit economics.

Typical product-name match rate against CX Observe's taxonomy is ~95%. The
unmatched remainder is mostly AHUB reclass rows and `UNKNOWN`, which exist in the
finance taxonomy but not in CX Observe's.

### Pre-credit / gross

MSA reports **pre-credit / gross** ACR, so it reads higher than the finance-net
view in C360 or FinHub. The Pivot sheet carries a red note saying so. Don't
reconcile these figures to an invoice.

### Two traps worth knowing

- **The service truncates at 250 rows by default and says nothing.** An early
  Elevance pull reported $37.6M; the real figure was $68.3M once the cap was
  lifted — 45% missing, including their largest product at $28M. `Get-CxoAcr.py`
  passes `maxRows=1000` explicitly and warns if the cap is hit.
- **Microsoft fiscal years start in July**, so `FY26-Jul` is *July 2025*.
  Filtering on fiscal-month labels silently shifts the window by a year. The
  script filters on `DateID` (`YYYYMMDD`) instead.

---

## How it works

CX Observe's tiles are backed by a single shaped endpoint:

```
POST https://consumption-trafficmanager-wus3-prod.trafficmanager.net
     /api/insights/ch:customer::tpid:<TPID>/aspects/ch:aspect:<aspect>
     ?startDate=..&endDate=..&unit=month&view=pivotedchart&aggregation=Sum
```

```jsonc
{
  "Select": ["workload_dimensions_service_level_5"],   // grouping dimension
  "Filter": "workload_dimensions_service_level_4 eq 'Virtual Machines Eadsv5 Series'",
  "Top": 5000,
  "Facets": [], "OrderBy": [], "QueryType": "Full",
  "SearchMode": "All", "SearchText": "", "Skip": 0, "SearchFields": []
}
```

- `Select` picks the grouping: `workload_dimensions_service_level_1..5`,
  `SubscriptionName`, or `SubscriptionGuid`.
- `Filter` is OData-ish and scopes one dimension by another. That's the whole
  trick behind `-Hierarchy`: one filtered call per product gives you its SKUs.

Aspects that exist: `consumptionunits`, `compute`, `storage`.
(`revenue` returns 403 without extra entitlement.)

Customer names come from the Customer domain with `Filter: "TPID eq '<tpid>'"`.

### Gotchas worth knowing

- **`Skip` is ignored.** Paging doesn't work — `Top` must be large enough for the
  whole set. The scripts use 5000.
- **L3 (Product Category) is empty** in the source data, so the tree is L2 → L4 → L5.
- **`0` ACU means genuinely unused**, not "a little." Verified identical across
  1-, 6-, and 24-month windows — these are catalog rows for SKUs under a product
  the customer touches. About 42% of hierarchy rows. Filter them out for spend
  analysis; they're useful as a whitespace signal (e.g. all Cosmos DB
  multi-master RU/s at zero = no multi-region write adoption).
- **Totals reconcile.** SKU rows sum exactly to the customer total on the tile.

---

## Authentication

The APIs need a delegated token for
`api://31390d6a-f361-4eb0-922a-ca3a563f3ad1/user_impersonation`.

**Automatic token capture is the default.** Two alternatives are dead ends worth
documenting so nobody re-litigates them:

- **Azure CLI** — `AADSTS65001`, the CLI's app ID isn't consented to this API.
- **Device code** (`-DeviceLogin`) — fails on managed-device tenants: *"your admin
  requires the device requesting access to be managed."* The device-code flow
  can't present device identity, so Conditional Access rejects it. The parameter
  still exists for tenants without that policy.

Manual override if you prefer:

```powershell
# F12 > Network > any consumption-trafficmanager request > Request Headers > authorization
$env:CXO_TOKEN = 'Bearer eyJ0...'
$env:CXO_CUSTOMER_TOKEN = 'Bearer eyJ0...'   # optional, for the name lookup
.\Get-CxoConsumption.ps1 -Tpid 642489
```

Tokens last about an hour. **`$env:CXO_TOKEN` takes precedence over auto-capture**,
so a stale one from an earlier session will cause 401s — clear it with
`Remove-Item Env:\CXO_TOKEN`.

---

## Direct Kusto (optional)

Every CX Observe tile has an **Explore in Kusto** link that emits the underlying KQL:

```kusto
P360ConsumptionUnitsPROD()
| where Customer_TPID == "642489"
| summarize ACU = sum(Monthly_1_Quantity) by workload_dimensions_service_level_5
| order by ACU desc
```

Cluster `consumptionrptwus3prod.westus3`, database `consumptiondatadb`.

Two caveats: `consumptiondatadb` needs an entitlement most people don't have
(`Access denied`), and the cluster rejects Azure CLI tokens — it only accepts ADX
Web / Kusto Explorer. **The REST path above avoids both problems**, which is why
these scripts use it.

---

## Sources evaluated for ACR

For anyone who wonders why ACR comes from Power BI and not somewhere more obvious:

| Source | Outcome |
|---|---|
| **MSA (Power BI)** | ✅ **In use.** TPID + ServiceLevel1-4. Pre-credit/gross. |
| CX Observe `ch:aspect:revenue` | ❌ HTTP 403 — no entitlement. |
| Customer 360 GraphQL | ❌ `ACCOUNT_DATA_ACCESS_DENIED` on `azureConsumedRevenue`. Identity queries work, revenue doesn't. |
| FinHub (SSAS cube) | ❌ Global ACR works, but TPID members are RLS-hidden — only the "All" member resolves. |
| WWBI_ACRSL5 (Power BI) | ❌ Has ServiceLevel5, but is RLS-scoped to a different 49,311-TPID portfolio. |

If your entitlements differ, `WWBI_ACRSL5` (`6b73b79c-2173-4ee1-b921-b30e3d306c4f`)
is the one to try — it would unlock true SKU-level ACR.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `401` on every dimension | A stale `$env:CXO_TOKEN` is overriding auto-capture. `Remove-Item Env:\CXO_TOKEN` and re-run. |
| `401` mid-run | Token expired (~1h). Re-run. |
| Token capture times out | Run `.\Get-CxoToken.ps1 -Visible` and finish signing in. |
| Customer name not resolved | Pass `-CustomerName 'NAME'`. |
| No workbook produced | Python or `openpyxl` missing — the pull still succeeds and warns. |
| No ACR columns | PBI-MCP-Proxy venv not found. Check `-PbiProxyPath`, or use `-NoAcr` to silence. |
| ACR pull fails on auth | `az login` expired. Re-run `az login`. |
| ACR total looks low | You hit the row cap. Raise `--max-rows` on `Get-CxoAcr.py`. |
| Run is slow | You're on PS 5.1 (sequential). Install PS7, raise `-Throttle`, or use `-NoHierarchy`. |
| `AADSTS65001` | Expected from Azure CLI; it isn't consented to the CX Observe API. |
