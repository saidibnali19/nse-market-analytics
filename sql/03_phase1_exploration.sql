-- =====================================================================
-- 03_phase1_exploration.sql  -  Phase 1: SQL fundamentals on real data
-- Run in Workbench with your nse_analyst connection.
--
-- HOW TO USE THIS FILE
--   Put your cursor inside ONE query and press Ctrl+Enter to run just
--   that query. Read the comment, PREDICT the result, then run it.
--   Write your answers to the "YOUR TURN" exercises underneath each one.
--
-- MONGO -> SQL CHEAT SHEET
--   db.coll.find({a: 1})              SELECT * FROM t WHERE a = 1
--   .find({}, {a: 1, b: 1})           SELECT a, b FROM t
--   .sort({a: -1}).limit(10)          ORDER BY a DESC LIMIT 10
--   .countDocuments()                 SELECT COUNT(*) FROM t
--   .distinct("a")                    SELECT DISTINCT a FROM t
--   $match -> $group -> $match        WHERE -> GROUP BY -> HAVING
--   $group: {_id: "$a", n: {$sum:1}}  SELECT a, COUNT(*) AS n ... GROUP BY a
--   $regex: /^abc/                    WHERE col LIKE 'abc%'
--
-- ORDER SQL RUNS IN (not the order you write it):
--   FROM -> WHERE -> GROUP BY -> HAVING -> SELECT -> ORDER BY -> LIMIT
-- =====================================================================

USE nse_raw;


-- ---------------------------------------------------------------------
-- PART A: SELECT, LIMIT, COUNT
-- ---------------------------------------------------------------------

-- A1. Look at the data. Never query a table you haven't eyeballed.
SELECT *
FROM stock_prices
LIMIT 20;

-- A2. How many rows in total? Compare with your baseline:
--     313,277 rows in docs/raw_file_row_counts.txt
SELECT COUNT(*) AS total_rows
FROM stock_prices;

-- A3. Rows per file - your first GROUP BY.
SELECT source_file,
       COUNT(*) AS row_count
FROM stock_prices
GROUP BY source_file
ORDER BY source_file;

-- YOUR TURN A: How many rows are in stock_sectors, per source_file?



-- ---------------------------------------------------------------------
-- PART B: WHERE, LIKE, DISTINCT
-- ---------------------------------------------------------------------

-- B1. One stock: Safaricom (code SCOM). Its first rows.
SELECT trade_date, stock_code, stock_name, day_price, volume, source_file
FROM stock_prices
WHERE stock_code = 'SCOM'
LIMIT 20;

-- B2. How many distinct stock codes have ever traded?
SELECT COUNT(DISTINCT stock_code) AS distinct_codes
FROM stock_prices;

-- B3. Find stocks by name pattern. % = any characters.
--     Which listed companies have "Bank" in their name?
SELECT DISTINCT stock_code, stock_name
FROM stock_prices
WHERE stock_name LIKE '%Bank%'
ORDER BY stock_code;

-- YOUR TURN B1: How many rows have no volume recorded (volume = '-')?

-- YOUR TURN B2: List the distinct codes and names of companies whose
--               name contains "Insurance" OR "Holdings".



-- ---------------------------------------------------------------------
-- PART C: GROUP BY + HAVING
-- ---------------------------------------------------------------------

-- C1. The market indices hidden in the stock data.
--     In LIKE, ^ is just a normal character, so '^%' = "starts with ^".
SELECT stock_code,
       stock_name,
       COUNT(*)          AS trading_days,
       MIN(source_file)  AS first_file,
       MAX(source_file)  AS last_file
FROM stock_prices
WHERE stock_code LIKE '^%'
GROUP BY stock_code, stock_name
ORDER BY trading_days DESC;

-- C2. Which indices exist in which year? This answers our 2022 question.
--     REGEXP_SUBSTR pulls the first 4-digit year out of the file name.
SELECT REGEXP_SUBSTR(source_file, '20[0-9]{2}') AS file_year,
       stock_code,
       COUNT(*) AS trading_days
FROM stock_prices
WHERE stock_code LIKE '^%'
GROUP BY file_year, stock_code
ORDER BY file_year, stock_code;

-- C3. HAVING filters GROUPS (WHERE filters ROWS, before grouping).
--     Codes that have been known by more than one name = renames.
SELECT stock_code,
       COUNT(DISTINCT stock_name)                         AS name_count,
       GROUP_CONCAT(DISTINCT stock_name SEPARATOR ' | ')  AS names_used
FROM stock_prices
GROUP BY stock_code
HAVING COUNT(DISTINCT stock_name) > 1
ORDER BY name_count DESC, stock_code;

-- YOUR TURN C1: Top 10 stock codes by number of rows (most trading days).

-- YOUR TURN C2: Stock codes (excluding indices) with fewer than 250 rows
--               in total - short-lived or barely-traded counters.
--               Hint: WHERE stock_code NOT LIKE '^%' ... HAVING ...



-- ---------------------------------------------------------------------
-- PART D: THE DATA TYPE TRAP  (why the raw layer is not for analysis)
-- ---------------------------------------------------------------------

-- D1. Safaricom's highest and lowest price ever... or is it?
--     PREDICT FIRST: Safaricom has traded roughly between KES 3 and KES 45.
SELECT MAX(day_price) AS max_price,
       MIN(day_price) AS min_price
FROM stock_prices
WHERE stock_code = 'SCOM';
--     Why is this wrong? day_price is VARCHAR, so MySQL compares
--     alphabetically, character by character: '9.5' > '45' because
--     '9' > '4'. Same thing as sorting ["10", "9"] as strings in JS.

-- D2. Fix it: strip thousands separators, then CAST to a number.
--     NULLIF turns the '-' placeholder into NULL so it can't break the cast.
SELECT MAX(CAST(REPLACE(NULLIF(day_price, '-'), ',', '') AS DECIMAL(12,2))) AS max_price,
       MIN(CAST(REPLACE(NULLIF(day_price, '-'), ',', '') AS DECIMAL(12,2))) AS min_price
FROM stock_prices
WHERE stock_code = 'SCOM';

-- D3. Same problem with volume: "1,600" is text. Total shares of
--     Safaricom traded per file (year), converted properly.
SELECT source_file,
       SUM(CAST(REPLACE(NULLIF(volume, '-'), ',', '') AS DECIMAL(20,2))) AS shares_traded
FROM stock_prices
WHERE stock_code = 'SCOM'
GROUP BY source_file
ORDER BY source_file;

-- YOUR TURN D: For the 2025 file only, which 10 stocks (not indices)
--              had the highest total shares traded? Use the D3 pattern.
--              Hint: WHERE source_file LIKE '%2025%'


-- =====================================================================
-- When you finish: in Phase 3 we do these conversions ONCE, properly,
-- into nse_staging - so nobody ever has to write REPLACE/CAST again.
-- =====================================================================
