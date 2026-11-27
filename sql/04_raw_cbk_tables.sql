-- =====================================================================
-- 04_raw_cbk_tables.sql  (MySQL 8.0+)
-- Run in Workbench using your nse_analyst connection.
--
-- Raw tables for the 4 Central Bank of Kenya files. Same rules as the
-- NSE raw tables: every value is text, columns mapped by position,
-- and every row keeps source_file + source_row (lineage).
-- =====================================================================

USE nse_raw;

-- ---------------------------------------------------------------------
-- Monthly KES exchange rates. BOTH CBK files load here:
--   "...period average.csv" -> average rate during the month
--   "...end period.csv"     -> rate on the last day of the month
-- source_file tells them apart.
--
-- Kept WIDE (one column per currency) exactly like the file. Reshaping
-- to long format (month, currency, rate) is a Phase 3 SQL exercise.
--
-- Column names use ISO currency codes. Original CBK header in brackets.
-- Rates are KES per 1 unit of foreign currency, EXCEPT the four East
-- African currencies, which are quoted the other way round (units of
-- that currency per 1 KES). UGX and TZS are marked \2 in the CBK header;
-- RWF and BIF are not marked, but their values show the same thing
-- (e.g. ~11 RWF per KES, not ~11 KES per RWF).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS cbk_fx_monthly;
CREATE TABLE cbk_fx_monthly (
    raw_id        INT UNSIGNED NOT NULL AUTO_INCREMENT,
    period_year   VARCHAR(10),   -- [Year]
    period_month  VARCHAR(10),   -- [Month] 1-12
    usd           VARCHAR(20),   -- [United States dollar]
    gbp           VARCHAR(20),   -- [Sterling pound]
    eur           VARCHAR(20),   -- [Euro]
    zar           VARCHAR(20),   -- [South Africa Rand]
    ugx           VARCHAR(20),   -- [Uganda shilling\2]   UGX per KES
    tzs           VARCHAR(20),   -- [Tanzania shilling\2] TZS per KES
    rwf           VARCHAR(20),   -- [Rwanda Franc]        RWF per KES
    bif           VARCHAR(20),   -- [Burundi Franc]       BIF per KES
    aed           VARCHAR(20),   -- [AE Dirham]
    dem           VARCHAR(20),   -- [Deutch Mark]         discontinued
    cad           VARCHAR(20),   -- [Canadian dollar]
    frf           VARCHAR(20),   -- [French franc]        discontinued
    chf           VARCHAR(20),   -- [Swiss franc]
    nlg           VARCHAR(20),   -- [Dutch guilder]       discontinued
    itl           VARCHAR(20),   -- [Italian lira]        discontinued
    bef           VARCHAR(20),   -- [Belgium franc]       discontinued
    jpy_per_100   VARCHAR(20),   -- [Japanese yen (100)]  KES per 100 JPY
    sek           VARCHAR(20),   -- [Swdish kroner]
    nok           VARCHAR(20),   -- [Norwegian kroner]
    dkk           VARCHAR(20),   -- [Danish kroner]
    ats           VARCHAR(20),   -- [Austrian schilling]  discontinued
    fim           VARCHAR(20),   -- [Finn marka]          discontinued
    esp           VARCHAR(20),   -- [Spanish peseta]      discontinued
    inr           VARCHAR(20),   -- [Indian rupee]
    hkd           VARCHAR(20),   -- [Hong  kong dollar]
    sgd           VARCHAR(20),   -- [Singapore dollar]
    sar           VARCHAR(20),   -- [Saudi riyal]
    cny           VARCHAR(20),   -- [Chinese Yuan]
    aud           VARCHAR(20),   -- [Australian dollar]
    extra_values  VARCHAR(500)  NULL,
    source_file   VARCHAR(255)  NOT NULL,
    source_row    INT UNSIGNED  NOT NULL,
    loaded_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (raw_id)
);

-- ---------------------------------------------------------------------
-- Monthly inflation (KNBS figures published by CBK)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS cbk_inflation;
CREATE TABLE cbk_inflation (
    raw_id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
    period_year           VARCHAR(10),   -- [Year]
    period_month_name     VARCHAR(20),   -- [Month] e.g. 'October'
    annual_avg_inflation  VARCHAR(20),   -- [Annual Average Inflation]
    inflation_12m         VARCHAR(20),   -- [12-Month Inflation] headline rate
    extra_values          VARCHAR(500)  NULL,
    source_file           VARCHAR(255)  NOT NULL,
    source_row            INT UNSIGNED  NOT NULL,
    loaded_at             TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (raw_id)
);

-- ---------------------------------------------------------------------
-- Central Bank Rate decisions (one row per policy meeting)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS cbk_central_bank_rate;
CREATE TABLE cbk_central_bank_rate (
    raw_id        INT UNSIGNED NOT NULL AUTO_INCREMENT,
    rate_date     VARCHAR(20),   -- [Date] DD/MM/YYYY
    cbr_pct       VARCHAR(20),   -- [Rate]
    extra_values  VARCHAR(500)  NULL,
    source_file   VARCHAR(255)  NOT NULL,
    source_row    INT UNSIGNED  NOT NULL,
    loaded_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (raw_id)
);

-- Check: three new empty tables
SELECT 'cbk_fx_monthly' AS table_name, COUNT(*) AS row_count FROM cbk_fx_monthly
UNION ALL
SELECT 'cbk_inflation', COUNT(*) FROM cbk_inflation
UNION ALL
SELECT 'cbk_central_bank_rate', COUNT(*) FROM cbk_central_bank_rate;
