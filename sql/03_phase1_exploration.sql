-- =====================================================================
-- 03_phase1_exploration.sql  -  Phase 1: SQL fundamentals on real data
-- Run in Workbench with the nse_analyst connection.
--
-- HOW TO USE THIS FILE
--   Ctrl+Enter        runs the ONE query your cursor is in
--   Ctrl+Shift+Enter  runs the whole file (one result tab per query)
--
-- MONGO -> SQL CHEAT SHEET
--   db.coll.find({a: 1})              SELECT * FROM t WHERE a = 1
--   .find({}, {a: 1, b: 1})           SELECT a, b FROM t
--   .sort({a: -1}).limit(10)          ORDER BY a DESC LIMIT 10
--   .countDocuments()                 SELECT COUNT(*) FROM t
--   .distinct("a")                    SELECT DISTINCT a FROM t
--   $match -> $group -> $match        WHERE -> GROUP BY -> HAVING
--   $group: {_id: "$a", n: {$sum:1}}  SELECT a, COUNT(*) AS n ... GROUP BY a
--   $regex: /^abc/                    WHERE col LIKE 'abc%'  or  REGEXP '^abc'
--
-- ORDER YOU WRITE IT  (Sweet Friends Will Gladly Help Others Learn):
--   SELECT -> FROM -> WHERE -> GROUP BY -> HAVING -> ORDER BY -> LIMIT
-- ORDER MYSQL RUNS IT:
--   FROM -> WHERE -> GROUP BY -> HAVING -> SELECT -> ORDER BY -> LIMIT
--
-- RULES LEARNED
--   * Before GROUP BY, ask "one row per WHAT?" - that goes in GROUP BY.
--   * Every SELECT column is either in GROUP BY or inside an aggregate.
--   * WHERE filters rows (before grouping); HAVING filters groups (after).
--   * DISTINCT applies to the whole row, not one column.
--   * Text in single quotes ('-'); numbers never in quotes (250).
--   * COUNT(*) counts rows; COUNT(col) counts non-NULL values of col.
--   * No ORDER BY = no guaranteed order.
-- =====================================================================

USE nse_raw;


-- ---------------------------------------------------------------------
-- PART A: SELECT, LIMIT, COUNT
-- ---------------------------------------------------------------------

-- A1. Look at the data. Never query a table you haven't eyeballed.
SELECT *
FROM stock_prices
LIMIT 20;

-- A2. Total rows. Baseline: 313,277 lines counted in the CSVs, minus
--     2 blank lines (2014, 2018 files) = 313,275 expected.
SELECT COUNT(*) AS total_rows
FROM stock_prices;

-- A3. Rows per file - first GROUP BY.
SELECT source_file,
       COUNT(*) AS row_count
FROM stock_prices
GROUP BY source_file
ORDER BY source_file;

-- YOUR TURN A: How many rows are in stock_sectors, per source_file?
-- Answer: 7 files, 500 rows.
SELECT source_file,
       COUNT(*) AS row_count
FROM stock_sectors
GROUP BY source_file
ORDER BY source_file;


-- ---------------------------------------------------------------------
-- PART B: WHERE, LIKE, DISTINCT
-- ---------------------------------------------------------------------

-- B1. One stock: Safaricom (code SCOM).
SELECT trade_date, stock_code, stock_name, day_price, volume, source_file
FROM stock_prices
WHERE stock_code = 'SCOM'
ORDER BY raw_id
LIMIT 20;

-- B2. How many distinct stock codes have ever traded?
SELECT COUNT(DISTINCT stock_code) AS distinct_codes
FROM stock_prices;

-- B3. Companies with "Bank" in their name.
SELECT DISTINCT stock_code, stock_name
FROM stock_prices
WHERE stock_name LIKE '%Bank%'
ORDER BY stock_code;

-- YOUR TURN B1: How many rows have no volume recorded (volume = '-')?
-- Answer: 69,552 (~22% of all rows - many NSE stocks are illiquid).
SELECT COUNT(*) AS no_volume_rows
FROM stock_prices
WHERE volume = '-';

-- YOUR TURN B2: Companies whose name contains "Insurance" OR "Holdings".
-- Answer: 20 rows. Note KNRE matches via "Re-Insurance" (substring match)
-- and CFC-R is a rights issue, not a company.
SELECT DISTINCT stock_code, stock_name
FROM stock_prices
WHERE stock_name LIKE '%Holdings%'
   OR stock_name LIKE '%Insurance%'
ORDER BY stock_code;

-- Same result with a regular expression ( | means OR ).
SELECT DISTINCT stock_code, stock_name
FROM stock_prices
WHERE stock_name REGEXP 'Insurance|Holdings'
ORDER BY stock_code;


-- ---------------------------------------------------------------------
-- PART C: GROUP BY + HAVING
-- ---------------------------------------------------------------------

-- C1. The market indices hidden in the stock data.
--     In LIKE, ^ is a normal character, so '^%' = "starts with ^".
SELECT stock_code,
       stock_name,
       COUNT(*)          AS trading_days,
       MIN(source_file)  AS first_file,
       MAX(source_file)  AS last_file
FROM stock_prices
WHERE stock_code LIKE '^%'
GROUP BY stock_code, stock_name
ORDER BY trading_days DESC;

-- C2. Which indices exist in which year? (investigates the 2022 gap)
--     REGEXP_SUBSTR pulls the first 4-digit year out of the file name.
SELECT REGEXP_SUBSTR(source_file, '20[0-9]{2}') AS file_year,
       stock_code,
       COUNT(*) AS trading_days
FROM stock_prices
WHERE stock_code LIKE '^%'
GROUP BY file_year, stock_code
ORDER BY file_year, stock_code;

-- C3. Codes known by more than one name = renames.
SELECT stock_code,
       COUNT(DISTINCT stock_name)                         AS name_count,
       GROUP_CONCAT(DISTINCT stock_name SEPARATOR ' | ')  AS names_used
FROM stock_prices
GROUP BY stock_code
HAVING COUNT(DISTINCT stock_name) > 1
ORDER BY name_count DESC, stock_code;

-- YOUR TURN C1: Top 10 stocks by trading days.
-- Improved: days_listed (rows) vs days_traded (rows with real volume).
-- ~4,852 days listed = present for the whole 2007-2026 period.
SELECT stock_code,
       COUNT(*)                                       AS days_listed,
       SUM(CASE WHEN volume <> '-' THEN 1 ELSE 0 END) AS days_traded
FROM stock_prices
WHERE stock_code NOT LIKE '^%'
GROUP BY stock_code
ORDER BY days_traded DESC, stock_code
LIMIT 10;

-- YOUR TURN C2: Stocks (not indices) with fewer than 250 rows.
-- Answer: 16 codes. The -R codes (CFC-R, KCB-R, KPLC-R...) are rights
-- issues lasting 10-25 days; ALP, KPC, FMLY need first/last-date checks.
SELECT stock_code,
       COUNT(*) AS trade_days
FROM stock_prices
WHERE stock_code NOT LIKE '^%'
GROUP BY stock_code
HAVING COUNT(*) < 250
ORDER BY stock_code;


-- ---------------------------------------------------------------------
-- PART D: THE DATA TYPE TRAP  (why the raw layer is not for analysis)
-- ---------------------------------------------------------------------

-- D1. WRONG ON PURPOSE: MAX/MIN on text compares character by character,
--     so '9.5' > '45' because '9' > '4'.
SELECT MAX(day_price) AS max_price,
       MIN(day_price) AS min_price
FROM stock_prices
WHERE stock_code = 'SCOM';

-- D2. Fixed, read inside-out:
--     NULLIF('-' -> NULL) -> REPLACE(strip commas) -> CAST(to DECIMAL) -> MAX
SELECT MAX(CAST(REPLACE(NULLIF(day_price, '-'), ',', '') AS DECIMAL(12,2))) AS max_price,
       MIN(CAST(REPLACE(NULLIF(day_price, '-'), ',', '') AS DECIMAL(12,2))) AS min_price
FROM stock_prices
WHERE stock_code = 'SCOM';

-- D3. Safaricom shares traded per file (year).
SELECT source_file,
       SUM(CAST(REPLACE(NULLIF(volume, '-'), ',', '') AS DECIMAL(20,2))) AS shares_traded
FROM stock_prices
WHERE stock_code = 'SCOM'
GROUP BY source_file
ORDER BY source_file;

-- YOUR TURN D: Top 10 stocks (not indices) by shares traded in 2025.
-- Answer: Safaricom 1.91bn, then Kenya Re 0.80bn - a cheap stock, so high
-- share counts. Share volume is not money traded (see E2).
SELECT stock_code,
       stock_name,
       SUM(CAST(REPLACE(NULLIF(volume, '-'), ',', '') AS DECIMAL(20,2))) AS shares_traded
FROM stock_prices
WHERE source_file LIKE '%2025%'
  AND stock_code NOT LIKE '^%'
GROUP BY stock_code, stock_name
ORDER BY shares_traded DESC
LIMIT 10;


-- ---------------------------------------------------------------------
-- PART E: LEVEL-UP  (conditional aggregation, row-level arithmetic)
-- ---------------------------------------------------------------------

-- E1. % of rows with no trading, per file - a fair comparison across
--     files of different sizes. CASE WHEN = SQL's if/else.
SELECT source_file,
       COUNT(*)                                                         AS total_rows,
       SUM(CASE WHEN volume = '-' THEN 1 ELSE 0 END)                    AS no_volume_rows,
       ROUND(100 * SUM(CASE WHEN volume = '-' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_no_volume
FROM stock_prices
WHERE stock_code NOT LIKE '^%'
GROUP BY source_file
ORDER BY source_file;

-- E2. Turnover (KES value traded) in 2025 = SUM(shares x price per day).
--     The multiplication happens per row, inside SUM.
SELECT stock_code,
       ROUND(SUM(
             CAST(REPLACE(NULLIF(volume, '-'), ',', '') AS DECIMAL(20,2))
           * CAST(REPLACE(NULLIF(day_price, '-'), ',', '') AS DECIMAL(12,2))
       ), 0) AS turnover_kes
FROM stock_prices
WHERE source_file LIKE '%2025%'
  AND stock_code NOT LIKE '^%'
GROUP BY stock_code
ORDER BY turnover_kes DESC
LIMIT 10;


-- =====================================================================
-- PHASE 1 FINDINGS
--   1. 313,275 price rows and 500 sector rows loaded; reconciles with
--      the CSV baseline (difference = 2 blank lines).
--   2. ~22% of stock rows have no volume: many counters rarely trade.
--   3. Stocks listed for the full 2007-2026 period have ~4,852 rows.
--   4. Rights issues (-R codes) are short-lived instruments and must be
--      excluded from company analysis.
--   5. Several companies were renamed under the same code (C3), so the
--      stock CODE is the key, never the name.
--   6. Share volume favours cheap stocks; turnover (KES) is the better
--      liquidity measure.
--   7. Every numeric column is text in raw: Phase 3 converts them ONCE
--      into nse_staging so REPLACE/CAST chains disappear.
-- =====================================================================