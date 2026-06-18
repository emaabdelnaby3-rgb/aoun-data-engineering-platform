"""Quick local connection test for Phase 3.
Run from backend folder:
    python test_phase3_connection.py
"""
from app.config import settings
from app.database import get_connection

print("SQL settings:")
print(" host:", settings.sql_server_host)
print(" port:", settings.sql_server_port)
print(" database:", settings.sql_server_database)
print(" trusted:", settings.sql_server_trusted_connection)
print(" user:", settings.sql_server_user)

with get_connection() as conn:
    cur = conn.cursor()
    cur.execute("SELECT DB_NAME(), COUNT(*) FROM dbo.organizations")
    print("connection ok:", cur.fetchone())
    cur.execute("SELECT COUNT(*) FROM dbo.v_public_donor_cases")
    print("public donor cases:", cur.fetchone()[0])
    cur.execute("SELECT COUNT(*) FROM dbo.v_beneficiary_support_profiles")
    print("support profiles:", cur.fetchone()[0])

print("Phase 3 database connection is ready.")
