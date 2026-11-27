-- =====================================================================
-- 05_phase2_exploration.sql  -  Phase 2: checking the CBK raw data,
--                               finding duplicates, and your first JOIN
-- Run in Workbench with the nse_analyst connection.
--   Ctrl+Enter = run the query your cursor is in.
--
-- NEW IN THIS PHASE
--   * UNION ALL          stack the results of several queries
--   * Duplicate check    GROUP BY <key> HAVING COUNT(*) > 1
--   * TRIM               remove spaces around text
--   * Empty '' vs NULL   two different kinds of "nothing"
--   * FIELD()            position of a value in a list
--   * JOIN               combine rows from two tables
--   * INNER vs LEFT JOIN and the "anti-join"
-- =====================================================================

USE nse_raw;


-- ---------------------------------------------------------------------
-- PART A: DID EVERYTHING LOAD?
-- ---------------------------------------------------------------------

-- A1. Row count per table and file in ONE result.
--     UNION ALL stacks results on top of each other. Rules: every
--     SELECT must have the same number of columns, in the same order.
--     Expected: 406 + 406 (FX), 263 (inflation), 125 (CBR).
SELECT 'cbk_fx_monthly' AS table_name, source_file, COUNT(*) AS row_count
FROM cbk_fx_monthly
GROUP BY source_file
UNION ALL
SELECT 'cbk_inflation', source_file, COUNT(*)
FROM cbk_inflation
GROUP BY source_file
UNION ALL
SELECT 'cbk_central_bank_rate', source_file, COUNT(*)
FROM cbk_central_bank_rate
GROUP BY source_file;

-- A2. Eyeball each table.
SELECT * FROM cbk_fx_monthly        ORDER BY raw_id LIMIT 10;
SELECT * FROM cbk_inflation         ORDER BY raw_id LIMIT 10;
SELECT * FROM cbk_central_bank_rate ORDER BY raw_id LIMIT 10;


-- ---------------------------------------------------------------------
-- PART B: FINDING DUPLICATES  (the most-used data quality query)
-- ---------------------------------------------------------------------
-- Pattern: GROUP BY the columns that SHOULD be unique (the "key"),
-- then HAVING COUNT(*) > 1 shows the keys that appear more than once.

-- B1. Inflation should have one row per year + month.
SELECT period_year,
       period_month_name,
       COUNT(*)                                  AS copies,
       GROUP_CONCAT(source_row ORDER BY source_row) AS csv_lines
FROM cbk_inflation
GROUP BY period_year, period_month_name
HAVING COUNT(*) > 1;

-- YOUR TURN B1: The CBR table should have one row per rate_date.
--               Which dates appear more than once?


-- YOUR TURN B2: Each FX file should have one row per year + month.
--               Check for duplicates. Careful: TWO files share this table,
--               so "unique" means unique per source_file + year + month.
--               (Expected answer: none - an empty result is a pass.)



-- ---------------------------------------------------------------------
-- PART C: TWO KINDS OF "NOTHING" - empty text vs NULL
-- ---------------------------------------------------------------------
-- In the FX files, missing values are empty text '' (not NULL).
-- NULL = "no value at all". '' = "a value that is zero characters long".
-- COUNT(col) skips NULL but COUNTS '' - a classic trap.

-- C1. The Deutsche Mark stopped being quoted after the euro arrived.
--     Compare the three counts.
SELECT COUNT(*)             AS all_rows,
       COUNT(dem)           AS count_dem,        -- counts '' too!
       COUNT(NULLIF(dem, '')) AS months_with_dem -- '' -> NULL, then skipped
FROM cbk_fx_monthly
WHERE source_file LIKE '%average%';

-- C2. The stray '-' from the data quality notes. Try = '-' first...
SELECT period_year, period_month, ats, source_file
FROM cbk_fx_monthly
WHERE ats = '-';
--     ...nothing found! The value has spaces around it (' -   ').
--     TRIM removes spaces from both ends:
SELECT period_year, period_month, ats,
       CONCAT('[', ats, ']')       AS ats_with_brackets,  -- shows the spaces
       CONCAT('[', TRIM(ats), ']') AS ats_trimmed,
       source_file
FROM cbk_fx_monthly
WHERE TRIM(ats) = '-';

-- YOUR TURN C: For the period-average file, find the FIRST year + month
--              that has a euro rate (eur is not empty).
--              Hint: WHERE ... AND eur <> '' ORDER BY ... LIMIT 1
--              Careful: period_year/period_month are TEXT. How does
--              '10' sort against '2'? Use CAST(... AS UNSIGNED) in ORDER BY.



-- ---------------------------------------------------------------------
-- PART D: YOUR FIRST JOIN
-- ---------------------------------------------------------------------
-- A JOIN puts columns from two tables side by side, matching rows on a
-- condition (ON ...). Think of it as: for each FX month, look up the
-- inflation row for the same year + month.
--
-- Problem: FX stores month as '10', inflation stores it as 'October'.
-- FIELD(x, 'January', ..., 'December') returns x's position in the list:
--   FIELD('October', 'January', ..., 'December') = 10

-- D1. USD rate and 12-month inflation side by side, latest months first.
--     f and i are TABLE ALIASES - short names so we can write f.usd.
SELECT f.period_year,
       f.period_month,
       f.usd            AS usd_kes_avg,
       i.inflation_12m
FROM cbk_fx_monthly AS f
INNER JOIN cbk_inflation AS i
        ON  i.period_year = f.period_year
        AND FIELD(i.period_month_name,
                  'January','February','March','April','May','June','July',
                  'August','September','October','November','December') = f.period_month
WHERE f.source_file LIKE '%average%'
ORDER BY CAST(f.period_year AS UNSIGNED) DESC,
         CAST(f.period_month AS UNSIGNED) DESC
LIMIT 24;

-- D2. INNER JOIN vs LEFT JOIN - count the rows.
--     INNER JOIN: only months that exist in BOTH tables.
--     LEFT JOIN:  ALL months from the left table (FX); inflation columns
--                 are NULL where there is no match.
--     PREDICT: FX has 406 months (1993-2026), inflation 262 months (2005-2026).
SELECT 'INNER JOIN' AS join_type, COUNT(*) AS result_rows
FROM cbk_fx_monthly AS f
INNER JOIN cbk_inflation AS i
        ON  i.period_year = f.period_year
        AND FIELD(i.period_month_name,
                  'January','February','March','April','May','June','July',
                  'August','September','October','November','December') = f.period_month
WHERE f.source_file LIKE '%average%'
UNION ALL
SELECT 'LEFT JOIN', COUNT(*)
FROM cbk_fx_monthly AS f
LEFT JOIN cbk_inflation AS i
        ON  i.period_year = f.period_year
        AND FIELD(i.period_month_name,
                  'January','February','March','April','May','June','July',
                  'August','September','October','November','December') = f.period_month
WHERE f.source_file LIKE '%average%';
--     Expected 263 and 407 - each ONE more than you'd predict. Why?
--     The duplicate April 2019 inflation row (B1) matches the April 2019
--     FX row TWICE. Duplicates multiply in joins ("fan-out") - this is
--     why we remove duplicates before joining, in Phase 3.

-- YOUR TURN D: Which FX months have NO inflation data?
--              Use the LEFT JOIN from D2 and keep only the rows where the
--              inflation side found nothing: WHERE ... AND i.raw_id IS NULL
--              (This pattern is called an ANTI-JOIN.)
--              Expected: 144 months = 1993-2004 (12 years x 12 months).
--              Note: NULL is tested with IS NULL, never = NULL.



-- ---------------------------------------------------------------------
-- PART E: THE JUNE 2024 ANOMALY (from docs/data_quality_notes.md)
-- ---------------------------------------------------------------------

-- E1. The annual average can't drop 1.85 points and bounce straight back.
--     The two June 2024 values look swapped.
SELECT period_year, period_month_name, annual_avg_inflation, inflation_12m
FROM cbk_inflation
WHERE period_year = '2024'
  AND period_month_name IN ('May', 'June', 'July')
ORDER BY FIELD(period_month_name, 'May', 'June', 'July');
--     IN ('a','b','c') is shorthand for  = 'a' OR = 'b' OR = 'c'.


-- =====================================================================
-- PHASE 2 FINDINGS
--   1. All 4 CBK files loaded and reconcile: FX 406 + 406 months
--      (Jan 1993 - Oct 2026), inflation 263 rows, CBR 125 rows.
--   2. Duplicates: inflation April 2019; CBR 27/05/2019 and 27/05/2020.
--   3. FX missing values are empty text '', not NULL; one stray ' - '
--      (Austrian schilling, July 1995) is padded with spaces.
--   4. Duplicates multiply rows in joins (263 / 407 instead of 262 / 406).
--   5. Inflation covers 2005+, so 1993-2004 FX months have no match.
--   6. June 2024 inflation values appear swapped.
-- =====================================================================
