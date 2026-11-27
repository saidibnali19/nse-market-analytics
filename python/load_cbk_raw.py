"""Load the 4 Central Bank of Kenya CSVs into nse_raw, unchanged.

Run from the project root (with .venv active):
    python python/load_cbk_raw.py

What it does
  * Finds the 4 CBK files in data/raw/cbk by keywords in their names,
    so the exact file names don't matter.
  * Checks each file's header against the header we expect. If CBK ever
    changes its columns (schema drift), the load stops with a clear
    message instead of silently putting values in the wrong columns.
  * Skips the title row above the header in the exchange-rate files.
  * Keeps every value as text, records source_file + source_row.
  * Re-runnable: empties the 3 CBK tables first, then reloads.
  * Prints a per-file reconciliation: rows read vs rows in MySQL.
"""
from __future__ import annotations

import csv
import io
import re
import sys
from pathlib import Path

# Reuse the helpers we already wrote for the NSE loader.
from load_nse_raw import ROOT, connect, read_text

CBK_DIR = ROOT / "data" / "raw" / "cbk"

FX_HEADER = [
    "Year", "Month", "United States dollar", "Sterling pound", "Euro",
    "South Africa Rand", "Uganda shilling\\2", "Tanzania shilling\\2",
    "Rwanda Franc", "Burundi Franc", "AE Dirham", "Deutch Mark",
    "Canadian dollar", "French franc", "Swiss franc", "Dutch guilder",
    "Italian lira", "Belgium franc", "Japanese yen (100)", "Swdish kroner",
    "Norwegian kroner", "Danish kroner", "Austrian schilling", "Finn marka",
    "Spanish peseta", "Indian rupee", "Hong  kong dollar", "Singapore dollar",
    "Saudi riyal", "Chinese Yuan", "Australian dollar",
]
FX_COLS = [
    "period_year", "period_month", "usd", "gbp", "eur", "zar", "ugx", "tzs",
    "rwf", "bif", "aed", "dem", "cad", "frf", "chf", "nlg", "itl", "bef",
    "jpy_per_100", "sek", "nok", "dkk", "ats", "fim", "esp", "inr", "hkd",
    "sgd", "sar", "cny", "aud",
]


def name_has(*words: str):
    """Build a matcher: True if every word appears in the file name."""
    return lambda simple_name: all(w in simple_name for w in words)


# One entry per file we expect. skip_lines = rows above the header.
DATASETS = [
    {"label": "FX period average", "table": "cbk_fx_monthly",
     "match": name_has("exchange", "average"), "skip_lines": 1,
     "header": FX_HEADER, "cols": FX_COLS},
    {"label": "FX end period", "table": "cbk_fx_monthly",
     "match": name_has("exchange", "end"), "skip_lines": 1,
     "header": FX_HEADER, "cols": FX_COLS},
    {"label": "Inflation", "table": "cbk_inflation",
     "match": name_has("inflation"), "skip_lines": 0,
     "header": ["Year", "Month", "Annual Average Inflation", "12-Month Inflation"],
     "cols": ["period_year", "period_month_name", "annual_avg_inflation", "inflation_12m"]},
    {"label": "Central Bank Rate", "table": "cbk_central_bank_rate",
     "match": lambda n: ("central" in n and "rate" in n) or "cbr" in n.split(),
     "skip_lines": 0,
     "header": ["Date", "Rate"], "cols": ["rate_date", "cbr_pct"]},
]
TABLES = sorted({d["table"] for d in DATASETS})


def simplify(file_name: str) -> str:
    """'102769479_Monthly Exchange rate (period average).csv'
    -> '102769479 monthly exchange rate period average csv'"""
    return re.sub(r"[^a-z0-9]+", " ", file_name.lower()).strip()


def norm(cell: str) -> str:
    """Compare headers ignoring case and extra spaces."""
    return " ".join(cell.split()).lower()


def find_files() -> dict[str, Path]:
    """Match each dataset to exactly one CSV. Stop if any is missing or ambiguous."""
    csvs = sorted(CBK_DIR.glob("*.csv"))
    found, problems = {}, []
    for ds in DATASETS:
        hits = [p for p in csvs if ds["match"](simplify(p.name))]
        if len(hits) == 1:
            found[ds["label"]] = hits[0]
        elif not hits:
            problems.append(f"  {ds['label']}: no matching file in {CBK_DIR}")
        else:
            names = ", ".join(p.name for p in hits)
            problems.append(f"  {ds['label']}: {len(hits)} files match ({names}) - keep one")
    used = set(found.values())
    for p in csvs:
        if p not in used:
            print(f"  note: ignoring {p.name} (not one of the 4 CBK datasets)")
    if problems:
        raise SystemExit("Could not match CBK files:\n" + "\n".join(problems))
    return found


def parse_file(path: Path, ds: dict) -> tuple[list[tuple], dict]:
    text, encoding = read_text(path)
    reader = csv.reader(io.StringIO(text, newline=""))
    n_cols = len(ds["cols"])
    stats = {"encoding": encoding, "blank": 0, "short": 0, "long": 0}

    for _ in range(ds["skip_lines"]):
        next(reader, None)

    header = next(reader, None) or []
    got = [norm(h) for h in header[:n_cols]]
    want = [norm(h) for h in ds["header"]]
    if got != want or len(header) != n_cols:
        diffs = [f"    col {i + 1}: expected {w!r}, found {g!r}"
                 for i, (w, g) in enumerate(zip(want, got + [""] * n_cols)) if w != g]
        if len(header) != n_cols:
            diffs.append(f"    expected {n_cols} columns, found {len(header)}")
        raise SystemExit(f"Header mismatch in {path.name} ({ds['label']}):\n" + "\n".join(diffs))

    rows = []
    for values in reader:
        line_no = reader.line_num
        if not any(v.strip() for v in values):
            stats["blank"] += 1
            continue
        extra = None
        if len(values) < n_cols:
            stats["short"] += 1
            values = values + [None] * (n_cols - len(values))
        elif len(values) > n_cols:
            stats["long"] += 1
            extra = "|".join(values[n_cols:])
            values = values[:n_cols]
        rows.append((*values, extra, path.name, line_no))
    return rows, stats


def insert_sql(table: str, cols: list[str]) -> str:
    all_cols = cols + ["extra_values", "source_file", "source_row"]
    return (f"INSERT INTO {table} ({', '.join(all_cols)}) "
            f"VALUES ({', '.join(['%s'] * len(all_cols))})")


def main() -> int:
    files = find_files()
    parsed = []
    for ds in DATASETS:  # parse everything BEFORE touching the database
        path = files[ds["label"]]
        rows, stats = parse_file(path, ds)
        parsed.append((ds, path, rows, stats))

    conn = connect()
    report = []
    try:
        with conn.cursor() as cur:
            for table in TABLES:
                cur.execute(f"TRUNCATE TABLE {table}")
            for ds, path, rows, stats in parsed:
                cur.executemany(insert_sql(ds["table"], ds["cols"]), rows)
                cur.execute(f"SELECT COUNT(*) FROM {ds['table']} WHERE source_file = %s",
                            (path.name,))
                count_row = cur.fetchone()
                in_db = count_row[0] if count_row else 0
                report.append((ds["table"], path.name, len(rows), in_db, stats))
                print(f"  loaded {ds['label']:<18} {path.name:<55} {in_db:>5} rows")
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    print("\nRECONCILIATION")
    print(f"{'table':<23}{'file':<55}{'csv rows':>9}{'in MySQL':>9}  notes")
    ok = True
    for table, name, read, in_db, s in report:
        notes = [f"encoding={s['encoding']}"] if s["encoding"] != "utf-8" else []
        notes += [f"{s[k]} {k}" for k in ("blank", "short", "long") if s[k]]
        flag = "" if read == in_db else "  <-- MISMATCH"
        ok &= read == in_db
        print(f"{table:<23}{name:<55}{read:>9}{in_db:>9}  {', '.join(notes)}{flag}")
    print("\nAll files reconcile." if ok else "\nSome files did NOT reconcile - see MISMATCH lines.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
