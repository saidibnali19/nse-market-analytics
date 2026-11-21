"""Phase 0 smoke test: can Python reach MySQL and see the 4 project databases?

Run from the project root:  python python/check_connection.py
"""
import os

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

load_dotenv()

# URL.create handles special characters in passwords safely.
url = URL.create(
    "mysql+pymysql",
    username=os.environ["MYSQL_USER"],
    password=os.environ["MYSQL_PASSWORD"],
    host=os.environ.get("MYSQL_HOST", "localhost"),
    port=int(os.environ.get("MYSQL_PORT", "3306")),
)
engine = create_engine(url)

with engine.connect() as conn:
    version = conn.execute(text("SELECT VERSION()")).scalar_one()
    dbs = conn.execute(text("""
        SELECT schema_name FROM information_schema.schemata
        WHERE schema_name IN ('nse_raw', 'nse_staging', 'nse_core', 'nse_analytics')
        ORDER BY schema_name
    """)).scalars().all()

print("Connected to MySQL", version)
print("Project databases found:", dbs)

major = int(version.split(".")[0])
assert major >= 8, "MySQL 8.0+ is required (window functions, CTEs). Please upgrade."
assert len(dbs) == 4, "Expected 4 databases - did sql/00_setup.sql run?"
print("Phase 0 database check passed.")
