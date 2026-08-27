# CX Observe Consumption Extract

Pull a customer's full Azure SKU / service / subscription consumption out of
[CX Observe](https://cxp.azure.com) by TPID, as CSV plus a ready-to-read Excel
pivot workbook.

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
# One command: captures its own token, pulls everything, builds the workbook
.\Get-CxoConsumption.ps1 -Tpid 642489 -AutoToken -Hierarchy -OutDir .\out
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
Building Excel pivot workbook ...
Workbook : ...\642489_MORGAN_STANLEY_Pivot.xlsx
```

Roughly one minute end to end on PowerShell 7.

---

## Requirements

| | |
|---|---|
| **PowerShell** | 7.x recommended (`winget install Microsoft.PowerShell`). Works on 5.1, but the hierarchy pull runs sequentially and takes ~3x longer. |
| **Python** | 3.x with `openpyxl` (`pip install openpyxl`) — only needed for the Excel workbook. |
| **Edge** | Required for `-AutoToken`. |
| **Access** | CX Observe entitlement for the TPIDs you query. Corpnet / signed in. |

---

## The scripts

### `Get-CxoConsumption.ps1`
The main entry point. Pulls consumption and writes the CSVs.

| Parameter | Default | Notes |
|---|---|---|
| `-Tpid` | *required* | MSX Top Parent ID, e.g. `642489`. |
| `-AutoToken` | | Capture tokens automatically. **Recommended.** |
| `-Token` | | Bearer string, if you'd rather paste one. |
| `-Hierarchy` | | Adds the Service → Product → SKU rollup **and the Excel workbook**. |
| `-NoPivot` | | Keep the hierarchy CSV but skip the workbook. |
| `-Months` | `6` | Look-back window. Or use `-StartDate` / `-EndDate`. |
| `-Aspects` | `consumptionunits` | Also `compute` (VM cores) and `storage`. |
| `-OutDir` | script folder | Absolute, relative, `~`, or `%VAR%`. Created if missing. |
| `-NoTpidSubfolder` | | Write straight into `-OutDir`. |
| `-CustomerName` | *looked up* | Override the auto-resolved name. |
| `-Throttle` | `8` | Parallel requests (PS7 only). `1` forces sequential. |

### `Get-CxoToken.ps1`
Launches Edge with the DevTools Protocol, loads the two CX Observe pages that call
the APIs, and reads the `Authorization` header off the live requests. Tokens are
returned in memory — never written to disk or logged.

Uses a dedicated Edge profile at `%LOCALAPPDATA%\CxoConsumption\edge-profile`, so
it never touches your normal browser. Sign in once; later runs are silent.

`Get-CxoConsumption.ps1 -AutoToken` calls this for you, so you rarely run it directly.

### `New-CxoPivot.py`
Turns a hierarchy CSV into the Excel workbook. Invoked automatically by
`-Hierarchy`; run it standalone to rebuild a workbook from existing CSVs.

```bash
python New-CxoPivot.py <hierarchy.csv> [-o out.xlsx] [--top 50] [--title "..."]
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
├── 642489_MORGAN_STANLEY_product_sku_hierarchy.csv              # 1,086 (with -Hierarchy)
└── 642489_MORGAN_STANLEY_Pivot.xlsx
```

**The workbook** has three sheets:

- **Pivot** — collapsible Service → Product → SKU outline with ACU, % of parent,
  % of total, and data bars. Opens at Service/Product level; use the `1 2 3`
  outline buttons to drill in.
- **Data** — flat rows as a named table (`ConsumptionData`) for your own PivotTables.
- **Top SKUs** — top 50 ranked, with parent product and service.

`% of Parent` is the column that earns its keep: it shows E64ads v5 is 67% of
Eadsv5 Series spend, and AI Credit is 81% of GitHub Copilot.

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

**`-AutoToken` is the path that works.** Two alternatives are dead ends worth
documenting so nobody re-litigates them:

- **Azure CLI** — `AADSTS65001`, the CLI's app ID isn't consented to this API.
- **Device code** (`-DeviceLogin`) — fails on managed-device tenants: *"your admin
  requires the device requesting access to be managed."* The device-code flow
  can't present device identity, so Conditional Access rejects it. The parameter
  still exists for tenants without that policy.

Manual fallback if you prefer:

```powershell
# F12 > Network > any consumption-trafficmanager request > Request Headers > authorization
$env:CXO_TOKEN = 'Bearer eyJ0...'
$env:CXO_CUSTOMER_TOKEN = 'Bearer eyJ0...'   # optional, for the name lookup
.\Get-CxoConsumption.ps1 -Tpid 642489 -Hierarchy
```

Tokens last about an hour.

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

## Troubleshooting

| Symptom | Fix |
|---|---|
| `No token available` | Add `-AutoToken`. |
| Token capture times out | Re-run with `-Visible` and finish signing in. |
| `401` mid-run | Token expired (~1h). Re-run. |
| Customer name not resolved | Pass `-CustomerName 'NAME'`, or supply `$env:CXO_CUSTOMER_TOKEN`. |
| No workbook produced | Python or `openpyxl` missing — the pull still succeeds and warns. |
| Hierarchy is slow | You're on PS 5.1. Install PS7, or raise `-Throttle`. |
| `AADSTS65001` | Expected from Azure CLI. Use `-AutoToken`. |
