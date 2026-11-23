"""Load every NSE price and sector CSV into the nse_raw database, unchanged.

Run from the project root (with .venv active):
    python python/load_nse_raw.py

What it does
  * Finds every CSV under data/raw/nse (including subfolders).
  * Files with "all_stocks" in the name  -> nse_raw.stock_prices  (13 columns)
    Files with "sectors"    in the name  -> nse_raw.stock_sectors (3 columns)
  * Maps columns BY POSITION and keeps every value as text.
  * Records source_file + source_row for every row (lineage).
  * Re-runnable: empties both tables first, then reloads everything.
  * Prints a per-file reconciliation: rows read from the CSV vs rows in MySQL.
"""
from __future__ import annotations

import csv
import io
import os
import sys
from pathlib import Path

import pymysql
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
NSE_DIR = ROOT / "data" / "raw" / "nse"

PRICE_COLS = [
    "trade_date", "stock_code", "stock_name", "low_12m", "high_12m",
    "day_low", "day_high", "day_price", "previous_price", "change_value",
    "change_pct", "volume", "adjusted_price",
]
SECTOR_COLS = ["sector", "stock_code", "stock_name"]

TABLES = {
    "prices": ("stock_prices", PRICE_COLS),
    "sectors": ("stock_sectors", SECTOR_COLS),
}


# ---------------------------------------------------------------- parsing
def read_text(path: Path) -> tuple[str, str]:
    """Return (file_text, encoding_used). Handles Excel's BOM and
    falls back to Windows-1252 for files that aren't valid UTF-8."""
    raw = path.read_bytes()
    try:
        return raw.decode("utf-8-sig"), "utf-8"
    except UnicodeDecodeError:
        return raw.decode("cp1252"), "cp1252"


def classify(path: Path) -> str | None:
    name = path.name.lower()
    if "all_stocks" in name:
        return "prices"
    if "sectors" in name:
        return "sectors"
    return None


def parse_file(path: Path, n_cols: int) -> tuple[list[tuple], dict]:
    """Turn one CSV into rows ready for INSERT, plus stats.

    Each row = n_cols values + extra_values + source_file + source_row.
    Short rows are padded with NULL; values beyond n_cols are kept in
    extra_values so nothing is silently thrown away.
    """
    text, encoding = read_text(path)
    reader = csv.reader(io.StringIO(text, newline=""))
    stats = {"encoding": encoding, "blank": 0, "short": 0, "long": 0}
    rows: list[tuple] = []

    header = next(reader, None)
    if header is None:
        return rows, stats

    for values in reader:
        line_no = reader.line_num  # line number in the file (header = 1)
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


# ---------------------------------------------------------------- loading
def connect():
    load_dotenv(ROOT / ".env")
    return pymysql.connect(
        host=os.environ.get("MYSQL_HOST", "localhost"),
        port=int(os.environ.get("MYSQL_PORT", "3306")),
        user=os.environ["MYSQL_USER"],
        password=os.environ["MYSQL_PASSWORD"],
        database="nse_raw",
        charset="utf8mb4",
        autocommit=False,
    )


def insert_sql(table: str, cols: list[str]) -> str:
    all_cols = cols + ["extra_values", "source_file", "source_row"]
    placeholders = ", ".join(["%s"] * len(all_cols))
    return f"INSERT INTO {table} ({', '.join(all_cols)}) VALUES ({placeholders})"


def main() -> int:
    files = sorted(
        (p for p in NSE_DIR.rglob("*.csv") if classify(p)),
        key=lambda p: (classify(p), p.name),
    )
    if not files:
        print(f"No NSE CSV files found under {NSE_DIR}")
        return 1

    names = [p.name for p in files]
    dupes = {n for n in names if names.count(n) > 1}
    if dupes:
        print("Same file name found in more than one folder - remove the copies:")
        for n in sorted(dupes):
            print("  ", n)
        return 1

    conn = connect()
    report = []
    try:
        with conn.cursor() as cur:
            # TRUNCATE commits immediately in MySQL, so if a later file fails
            # the tables are left partly loaded. That's fine here: just fix
            # the problem and run the script again.
            for table, _ in TABLES.values():
                cur.execute(f"TRUNCATE TABLE {table}")

            for path in files:
                kind = classify(path)
                if kind is None:
                    continue
                table, cols = TABLES[kind]
                rows, stats = parse_file(path, len(cols))
                cur.executemany(insert_sql(table, cols), rows)
                cur.execute(
                    f"SELECT COUNT(*) FROM {table} WHERE source_file = %s",
                    (path.name,),
                )
                count_row = cur.fetchone()
                if count_row is None:
                    raise RuntimeError(f"Count query returned no result for {table}")
                in_db = count_row[0]
                report.append((table, path.name, len(rows), in_db, stats))
                print(f"  loaded {path.name:<50} {in_db:>7,} rows")
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    # ---------------------------------------------------- reconciliation
    print("\nRECONCILIATION")
    print(f"{'table':<14}{'file':<50}{'csv rows':>10}{'in MySQL':>10}  notes")
    ok = True
    for table, name, read, in_db, s in report:
        notes = []
        if s["encoding"] != "utf-8":
            notes.append(f"encoding={s['encoding']}")
        for k in ("blank", "short", "long"):
            if s[k]:
                notes.append(f"{s[k]} {k}")
        status = "" if read == in_db else "  <-- MISMATCH"
        ok &= read == in_db
        print(f"{table:<14}{name:<50}{read:>10,}{in_db:>10,}  {', '.join(notes)}{status}")

    for table, _ in TABLES.values():
        total = sum(r[3] for r in report if r[0] == table)
        print(f"TOTAL {table}: {total:,}")
    print("\nAll files reconcile." if ok else "\nSome files did NOT reconcile - see MISMATCH lines.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
