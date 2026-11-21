-- =====================================================================
-- 00_setup.sql  (MySQL 8.0+)
-- Run in MySQL Workbench while connected as root.
-- Change both passwords before running, then execute the whole script
-- with the lightning-bolt button (Ctrl+Shift+Enter).
-- =====================================================================

-- 0. Version check: must be 8.0 or higher (window functions, CTEs).
SELECT VERSION() AS mysql_version;

-- 1. Layered architecture. In MySQL, "schema" and "database" mean the
--    same thing, so each layer is its own database:
--      nse_raw       -> files loaded exactly as downloaded, all text
--      nse_staging   -> cleaned, typed, unified data
--      nse_core      -> star schema: dimension + fact tables
--      nse_analytics -> views that Power BI reads (the "public API")
CREATE DATABASE IF NOT EXISTS nse_raw
    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS nse_staging
    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS nse_core
    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS nse_analytics
    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

-- 2. Developer account: full control over the 4 project databases only
--    (not the whole server like root).
CREATE USER IF NOT EXISTS 'nse_analyst'@'localhost'
    IDENTIFIED BY 'change_me_dev_password';
GRANT ALL PRIVILEGES ON nse_raw.*       TO 'nse_analyst'@'localhost';
GRANT ALL PRIVILEGES ON nse_staging.*   TO 'nse_analyst'@'localhost';
GRANT ALL PRIVILEGES ON nse_core.*      TO 'nse_analyst'@'localhost';
GRANT ALL PRIVILEGES ON nse_analytics.* TO 'nse_analyst'@'localhost';

-- 3. Read-only account for Power BI: it can see nse_analytics and
--    nothing else. Views run with their creator's rights (SQL SECURITY
--    DEFINER, the default), so the reader can query views that pull from
--    nse_core without having access to nse_core itself.
CREATE USER IF NOT EXISTS 'powerbi_reader'@'localhost'
    IDENTIFIED BY 'change_me_reader_password';
GRANT SELECT, SHOW VIEW ON nse_analytics.* TO 'powerbi_reader'@'localhost';

-- 4. Allow loading CSV files from your machine (used in Phase 2).
--    SET PERSIST survives server restarts.
SET PERSIST local_infile = 1;

-- 5. Sanity checks
SHOW DATABASES LIKE 'nse\_%';                 -- expect 4 rows
SHOW GRANTS FOR 'nse_analyst'@'localhost';
SHOW GRANTS FOR 'powerbi_reader'@'localhost';
SELECT @@local_infile AS local_infile_enabled; -- expect 1
