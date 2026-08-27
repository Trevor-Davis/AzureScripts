#!/usr/bin/env python3
"""
Build an Excel pivot workbook from a CX Observe product/SKU hierarchy CSV.

Consumes the *_product_sku_hierarchy.csv produced by Get-CxoConsumption.ps1 -Hierarchy
and writes <same stem>_Pivot.xlsx containing:

  Pivot     collapsible Service -> Product -> SKU outline with % of parent / % of total
  Data      flat rows as a named Excel table (build your own PivotTable off this)
  Top SKUs  top N SKUs ranked, with parent product and service

Usage:
    python New-CxoPivot.py <hierarchy.csv> [-o output.xlsx] [--top 50]

The source data is Microsoft Confidential \\ Microsoft FTE. Label the workbook
before sharing it.
"""
import argparse
import csv
import os
import sys
from collections import OrderedDict

try:
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
    from openpyxl.worksheet.table import Table, TableStyleInfo
    from openpyxl.formatting.rule import DataBarRule
except ImportError:
    sys.exit("openpyxl is required:  pip install openpyxl")

HDR_FILL = PatternFill("solid", fgColor="1F3864")
SVC_FILL = PatternFill("solid", fgColor="D9E2F3")
PRD_FILL = PatternFill("solid", fgColor="F2F2F2")
TOT_FILL = PatternFill("solid", fgColor="FFF2CC")
THIN = Side(style="thin", color="BFBFBF")


def load(path):
    rows = []
    with open(path, newline="", encoding="utf-8-sig") as fh:
        rdr = csv.DictReader(fh)
        need = {"ServiceName_L2", "ProductName_L4", "SKU_L5", "SKU_ACU"}
        missing = need - set(rdr.fieldnames or [])
        if missing:
            sys.exit(f"{path} is missing expected column(s): {', '.join(sorted(missing))}")
        for r in rdr:
            raw = (r.get("SKU_ACU") or "").strip()
            try:
                acu = float(raw) if raw else 0.0
            except ValueError:
                acu = 0.0
            rows.append({
                "svc": (r["ServiceName_L2"] or "(unassigned)").strip(),
                "prod": (r["ProductName_L4"] or "").strip(),
                "sku": (r["SKU_L5"] or "").strip(),
                "acu": acu,
            })
    if not rows:
        sys.exit(f"No data rows found in {path}")
    return rows


def build(rows, out_path, title, top_n):
    tree = OrderedDict()
    for r in rows:
        tree.setdefault(r["svc"], OrderedDict()).setdefault(r["prod"], []).append(r)

    svc_tot = {s: sum(x["acu"] for ps in p.values() for x in ps) for s, p in tree.items()}
    prod_tot = {(s, pr): sum(x["acu"] for x in sk)
                for s, p in tree.items() for pr, sk in p.items()}
    ordered_svcs = sorted(tree, key=lambda s: -svc_tot[s])

    wb = Workbook()

    # ---------------------------------------------------------------- Data
    ws = wb.active
    ws.title = "Data"
    ws.append(["Service (L2)", "Product (L4)", "SKU (L5)", "ACU", "% of Product", "% of Total"])
    for s in ordered_svcs:
        for pr in sorted(tree[s], key=lambda p: -prod_tot[(s, p)]):
            for x in sorted(tree[s][pr], key=lambda v: -v["acu"]):
                ws.append([s, pr, x["sku"], x["acu"], None, None])

    n = ws.max_row
    for i in range(2, n + 1):
        ws.cell(i, 5).value = f"=IFERROR(D{i}/SUMIFS($D$2:$D${n},$B$2:$B${n},$B{i}),0)"
        ws.cell(i, 6).value = f"=IFERROR(D{i}/SUM($D$2:$D${n}),0)"
        ws.cell(i, 4).number_format = "#,##0.00"
        ws.cell(i, 5).number_format = "0.00%"
        ws.cell(i, 6).number_format = "0.00%"

    tbl = Table(displayName="ConsumptionData", ref=f"A1:F{n}")
    tbl.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
    ws.add_table(tbl)
    for c, w in zip("ABCDEF", (34, 42, 34, 16, 13, 13)):
        ws.column_dimensions[c].width = w
    ws.freeze_panes = "A2"

    # ---------------------------------------------------------------- Pivot
    pv = wb.create_sheet("Pivot")
    pv["A1"] = title
    pv["A1"].font = Font(size=14, bold=True, color="1F3864")
    pv["A2"] = ("Azure Consumption Units (ACU). Source: CX Observe. "
                "Confidential \\ Microsoft FTE.")
    pv["A2"].font = Font(size=9, italic=True, color="595959")

    r0 = 4
    for j, h in enumerate(
            ["Service / Product / SKU", "Level", "ACU", "% of Parent", "% of Total"], 1):
        c = pv.cell(r0, j, h)
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = HDR_FILL
        c.alignment = Alignment(horizontal="center", vertical="center")

    DL = f"Data!$D$2:$D${n}"
    SVC_RNG = f"Data!$A$2:$A${n}"
    PRD_RNG = f"Data!$B$2:$B${n}"

    r = r0 + 1
    total_row = r
    pv.cell(r, 1, "TOTAL").font = Font(bold=True, size=11)
    pv.cell(r, 2, "Total")
    pv.cell(r, 3, f"=SUM({DL})").font = Font(bold=True)
    pv.cell(r, 4, 1)
    pv.cell(r, 5, 1)
    for j in range(1, 6):
        pv.cell(r, j).fill = TOT_FILL
    r += 1

    for s in ordered_svcs:
        sr = r
        pv.cell(r, 1, s).font = Font(bold=True)
        pv.cell(r, 2, "Service")
        pv.cell(r, 3, f'=SUMIFS({DL},{SVC_RNG},$A{r})').font = Font(bold=True)
        pv.cell(r, 4, f"=IFERROR(C{r}/$C${total_row},0)")
        pv.cell(r, 5, f"=IFERROR(C{r}/$C${total_row},0)")
        for j in range(1, 6):
            pv.cell(r, j).fill = SVC_FILL
        r += 1

        for pr in sorted(tree[s], key=lambda p: -prod_tot[(s, p)]):
            prr = r
            safe_s = s.replace('"', '""')
            safe_p = pr.replace('"', '""')
            pv.cell(r, 1, "    " + pr).font = Font(bold=True, color="404040")
            pv.cell(r, 2, "Product")
            pv.cell(r, 3, f'=SUMIFS({DL},{SVC_RNG},"{safe_s}",{PRD_RNG},"{safe_p}")')
            pv.cell(r, 4, f"=IFERROR(C{r}/C{sr},0)")
            pv.cell(r, 5, f"=IFERROR(C{r}/$C${total_row},0)")
            for j in range(1, 6):
                pv.cell(r, j).fill = PRD_FILL
            pv.row_dimensions[r].outlineLevel = 1
            r += 1

            for x in sorted(tree[s][pr], key=lambda v: -v["acu"]):
                pv.cell(r, 1, "        " + x["sku"])
                pv.cell(r, 2, "SKU")
                pv.cell(r, 3, x["acu"])
                pv.cell(r, 4, f"=IFERROR(C{r}/C{prr},0)")
                pv.cell(r, 5, f"=IFERROR(C{r}/$C${total_row},0)")
                pv.row_dimensions[r].outlineLevel = 2
                pv.row_dimensions[r].hidden = True
                r += 1

    last = r - 1
    for i in range(r0 + 1, r):
        pv.cell(i, 3).number_format = "#,##0.00"
        pv.cell(i, 4).number_format = "0.0%"
        pv.cell(i, 5).number_format = "0.0%"
        pv.cell(i, 2).alignment = Alignment(horizontal="center")
        for j in range(1, 6):
            pv.cell(i, j).border = Border(bottom=THIN)

    pv.sheet_properties.outlinePr.summaryBelow = False
    for c, w in zip("ABCDE", (56, 10, 16, 12, 12)):
        pv.column_dimensions[c].width = w
    pv.freeze_panes = "A5"
    pv.conditional_formatting.add(
        f"C{r0 + 2}:C{last}",
        DataBarRule(start_type="num", start_value=0, end_type="max", color="638EC6"))

    # ---------------------------------------------------------------- Top SKUs
    ts = wb.create_sheet("Top SKUs")
    ts.append(["Rank", "SKU (L5)", "Product (L4)", "Service (L2)", "ACU", "% of Total"])
    for j in range(1, 7):
        ts.cell(1, j).font = Font(bold=True, color="FFFFFF")
        ts.cell(1, j).fill = HDR_FILL
    for i, x in enumerate(sorted(rows, key=lambda v: -v["acu"])[:top_n], 1):
        ts.append([i, x["sku"], x["prod"], x["svc"], x["acu"], None])
        ts.cell(i + 1, 6).value = f"=IFERROR(E{i+1}/SUM(Data!$D$2:$D${n}),0)"
        ts.cell(i + 1, 5).number_format = "#,##0.00"
        ts.cell(i + 1, 6).number_format = "0.00%"
    for c, w in zip("ABCDEF", (7, 36, 40, 30, 16, 12)):
        ts.column_dimensions[c].width = w
    ts.freeze_panes = "A2"
    if ts.max_row > 1:
        ts.conditional_formatting.add(
            f"E2:E{ts.max_row}",
            DataBarRule(start_type="num", start_value=0, end_type="max", color="63BE7B"))

    wb.save(out_path)
    return n - 1, last - r0, sum(r["acu"] for r in rows)


def main():
    ap = argparse.ArgumentParser(description="Build a pivot workbook from a CX Observe hierarchy CSV.")
    ap.add_argument("csv_path", help="*_product_sku_hierarchy.csv")
    ap.add_argument("-o", "--output", help="output .xlsx (default: <stem>_Pivot.xlsx)")
    ap.add_argument("--top", type=int, default=50, help="rows on the Top SKUs sheet (default 50)")
    ap.add_argument("--title", help="title shown on the Pivot sheet")
    args = ap.parse_args()

    src = os.path.abspath(args.csv_path)
    if not os.path.isfile(src):
        sys.exit(f"Not found: {src}")

    stem = os.path.basename(src)
    for suffix in ("_product_sku_hierarchy.csv", ".csv"):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
            break

    out = args.output or os.path.join(os.path.dirname(src), f"{stem}_Pivot.xlsx")
    title = args.title or f"{stem.replace('_', ' ')} - Azure Consumption by Service > Product > SKU"

    data_rows, pivot_rows, grand = build(load(src), out, title, args.top)
    print(f"saved       : {out}")
    print(f"data rows   : {data_rows}")
    print(f"pivot rows  : {pivot_rows}")
    print(f"grand total : {grand:,.2f} ACU")


if __name__ == "__main__":
    main()
