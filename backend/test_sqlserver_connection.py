from app.database import get_connection


def main():
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT DB_NAME() AS database_name")
        print("Connected to:", cursor.fetchone()[0])

        cursor.execute("SELECT COUNT(*) FROM dbo.organizations")
        print("organizations:", cursor.fetchone()[0])

        cursor.execute("SELECT COUNT(*) FROM dbo.platform_users")
        print("platform_users:", cursor.fetchone()[0])

        cursor.execute("SELECT COUNT(*) FROM dbo.charity_cases")
        print("charity_cases:", cursor.fetchone()[0])


if __name__ == "__main__":
    main()
