# NSE Market Analytics (2007–2026)

End-to-end analytics project on ~20 years of Nairobi Securities Exchange daily
stock prices, enriched with Central Bank of Kenya macro data.
**Stack:** MySQL 8 · SQL · Python (ingestion) · Power BI

> Status: 🚧 In progress — Phase 0 (setup)

## Business questions
1. How has the NSE performed over 20 years, and which sectors led or lagged?
2. Which stocks are genuinely liquid, and which are "zombie" counters?
3. How did the market react to key events (2008 crisis, 2016 rate cap, COVID-19, 2023 shilling depreciation)?
4. Do Central Bank Rate changes and inflation move the market?
5. What did a USD-based foreign investor actually earn?
6. Which stocks carry the most volatility and the worst drawdowns?

## Architecture
```
CSV / Excel files ──► nse_raw ──► nse_staging ──► nse_core (star schema) ──► nse_analytics (views) ──► Power BI
```

## Repository layout
| Folder | Contents |
|---|---|
| `data/raw/nse` | NSE price & sector CSVs (not committed — see Data sources) |
| `data/raw/cbk` | CBK exchange rate, inflation, CBR files (not committed) |
| `sql/` | Numbered SQL scripts, run in order |
| `python/` | Ingestion & helper scripts |
| `powerbi/` | The `.pbix` report |
| `docs/` | ERD, data dictionary, screenshots |

## Reproduce
1. Install MySQL Server 8.0+ (with MySQL Workbench), MySQL Connector/NET (for Power BI) and Python 3.11+
2. In Workbench, connected as root, run `sql/00_setup.sql` (set your own passwords first)
3. `python -m venv .venv` → activate → `pip install -r requirements.txt`
4. Copy `.env.example` to `.env`, set your password, run `python python/check_connection.py`
5. Download the data files (below) into `data/raw/`

## Data sources
- Wanjawa, B. — *Nairobi Securities Exchange (NSE) All Stocks Prices*, Mendeley Data (2007–2012, 2013–2020, 2021, 2022, 2023–2024, 2025, 2026 releases)
- Central Bank of Kenya — exchange rates, inflation rates, Central Bank Rate (centralbank.go.ke/statistics)

## Known limitations
- No shares-outstanding data → equal-weighted (not market-cap-weighted) indices
- No dividend data → price returns only
