# Data Quality Notes

Issues found while inspecting the raw files (Phase 0). Each one is handled
in the cleaning step (Phase 3), not by editing the raw files.

## NSE daily prices (20 files, 2007–2026, ~313k rows)

| #   | Issue                                                                                              | Where              | Handling                                                              |
| --- | -------------------------------------------------------------------------------------------------- | ------------------ | --------------------------------------------------------------------- |
| 1   | Header names differ between releases (`Adjust` / `Adjusted` / `Adjusted Price`, `DATE` / `Date`)   | Across releases    | Load columns by position, not by name                                 |
| 2   | Two date formats: `1/2/2007` (M/D/YYYY) and `2-Jan-13` (D-Mon-YY)                                  | 2007–2012 vs 2013+ | Parse each format explicitly; validate first trading day of each year |
| 3   | Numbers stored as text with thousands separators (`"1,600"`, `"1,900.00"`)                         | All years          | Strip commas, cast to DECIMAL                                         |
| 4   | `-` used for missing values                                                                        | All years          | Convert to NULL (0 for volume)                                        |
| 5   | `Change%` unsigned in older files (a −4.5 change shown as `6.25%`)                                 | Up to ~2021        | Ignore source column; recalculate from prices                         |
| 6   | `12m Low` / `12m High` stale (e.g. Eaagads `8.2` / `14` every year 2013–2021)                      | 2013–2021          | Drop; recalculate 52-week high/low with window functions              |
| 7   | Company names vary (`Eaagads` vs `Eaagads Ltd`)                                                    | Across years       | Use stock `CODE` as the key                                           |
| 8   | Market indices (`^N20I`, `^NASI`, …) mixed in with stock rows                                      | All years          | Split into a separate index table                                     |
| 9   | Far fewer index rows in 2022 (714 vs 1,291–1,776 in neighbouring years)                            | 2022               | Investigate which indices are missing                                 |
| 10  | No sector file for 2007–2012                                                                       | 2007–2012          | Stocks delisted before 2013 get sector `Unknown`                      |
| 26  | Rights issues trade under separate codes ending `-R` (CFC-R, KCB-R, KPLC-R, …) for only 10–25 days | Phase 1            | Flag as `is_rights_issue`; exclude from company analysis              |
| 27  | Some codes have very few rows (ALP 74, KPC 75, FMLY 6)                                             | Phase 1            | Check first/last trade dates: new listing, suspension or delisting    |
| 28  | Several companies renamed under the same code (e.g. CFCI: CFC Insurance → Liberty Kenya Holdings)  | Phase 1, query C3  | Use the most recent name per code in `dim_stock`                      |

## CBK exchange rates (2 files, monthly, Jan 1993 – Oct 2026)

| #   | Issue                                                                                                                                                      | Handling                                                       |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| 11  | Title row above the real header                                                                                                                            | Skip first line on load                                        |
| 12  | Wide format (one column per currency)                                                                                                                      | Unpivot to `month, currency, rate`                             |
| 13  | Footnote markers and typos in currency names (`Uganda shilling\2`, `Swdish kroner`, `Hong  kong dollar`)                                                   | Clean names in a currency mapping                              |
| 14  | Discontinued currencies (Deutsche Mark, French franc, …) blank after early 2002; one stray `' -   '` (padded with spaces) in Austrian schilling, July 1995 | `TRIM`, then treat as NULL; exclude discontinued currencies    |
| 24  | Missing values are empty text `''`, not NULL, so `COUNT(col)` counts them                                                                                  | `NULLIF(TRIM(col), '')` before casting                         |
| 25  | UGX, TZS, RWF and BIF are quoted as units **per 1 KES** (the inverse of every other currency). Only UGX and TZS are footnoted (`\2`) in the CBK header.    | Invert (1 / rate) in staging so every currency is KES per unit |

## CBK Central Bank Rate (125 rows, Aug 2008 – Oct 2026)

| #   | Issue                                      | Handling                                             |
| --- | ------------------------------------------ | ---------------------------------------------------- |
| 15  | Rows in reverse chronological order        | Sort on load                                         |
| 16  | Duplicate dates: 27/05/2019, 27/05/2020    | Deduplicate                                          |
| 17  | Rows are policy meeting dates, not changes | Build `valid_from` / `valid_to` ranges with `LEAD()` |
| 18  | No data before 06/08/2008                  | CBR is NULL for 2007 – mid-2008                      |

## CBK inflation (263 rows, Jan 2005 – Oct 2026)

| #   | Issue                                                                                                                                                                       | Handling                                            |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| 19  | Duplicate row: April 2019                                                                                                                                                   | Deduplicate (262 unique months)                     |
| 20  | **June 2024 values appear swapped**: annual average 4.64 / 12-month 6.22, versus May 6.49 / 5.10 and July 5.97 / 4.31. Reported headline inflation for June 2024 was ~4.6%. | Correct to annual average 6.22, 12-month 4.64       |
| 21  | September 2021 annual average (5.35) inconsistent with neighbouring months                                                                                                  | Flag; use 12-month inflation as the primary measure |
| 22  | Month stored as text (`October`)                                                                                                                                            | Convert to month number                             |

## All CBK CSVs exported from Excel

| #   | Issue                                          | Handling                       |
| --- | ---------------------------------------------- | ------------------------------ |
| 23  | Files begin with a UTF-8 byte-order mark (BOM) | Read with `utf-8-sig` encoding |
