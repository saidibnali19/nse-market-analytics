-- =====================================================================
-- 02_raw_tables.sql  (MySQL 8.0+)
-- Run in Workbench using your nse_analyst connection.
--
-- RAW LAYER RULES
--   1. Every data column is text (VARCHAR). We store values exactly as
--      they appear in the CSV: "1,600", "-", "2-Jan-13". Converting to
--      numbers and dates happens later, in nse_staging, where we can
--      see and count what failed to convert.
--   2. Columns are mapped BY POSITION, so the header differences between
--      releases (Adjust / Adjusted / Adjusted Price) don't matter.
--   3. Every row records where it came from (source_file + source_row),
--      so any value can be traced back to the exact line in the CSV.
-- =====================================================================

USE nse_raw;

DROP TABLE IF EXISTS stock_prices;
CREATE TABLE stock_prices (
    raw_id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    -- the 13 CSV columns, in file order
    trade_date      VARCHAR(20),
    stock_code      VARCHAR(20),
    stock_name      VARCHAR(150),
    low_12m         VARCHAR(30),
    high_12m        VARCHAR(30),
    day_low         VARCHAR(30),
    day_high        VARCHAR(30),
    day_price       VARCHAR(30),
    previous_price  VARCHAR(30),
    change_value    VARCHAR(30),
    change_pct      VARCHAR(30),
    volume          VARCHAR(30),
    adjusted_price  VARCHAR(30),
    -- lineage / audit columns
    extra_values    VARCHAR(500)  NULL,  -- anything beyond column 13 (malformed rows)
    source_file     VARCHAR(255)  NOT NULL,
    source_row      INT UNSIGNED  NOT NULL, -- line number in the CSV (header = 1)
    loaded_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (raw_id),
    KEY ix_source_file (source_file),
    KEY ix_stock_code  (stock_code)
);

DROP TABLE IF EXISTS stock_sectors;
CREATE TABLE stock_sectors (
    raw_id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    sector          VARCHAR(100),
    stock_code      VARCHAR(20),
    stock_name      VARCHAR(150),
    extra_values    VARCHAR(500)  NULL,
    source_file     VARCHAR(255)  NOT NULL,
    source_row      INT UNSIGNED  NOT NULL,
    loaded_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (raw_id)
);

-- Check: both tables exist and are empty
SELECT 'stock_prices'  AS table_name, COUNT(*) AS row_count FROM stock_prices
UNION ALL
SELECT 'stock_sectors', COUNT(*) FROM stock_sectors;
