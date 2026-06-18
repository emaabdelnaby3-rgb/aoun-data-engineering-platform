from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "Unified Charity Platform API"
    environment: str = "local"

    # SQL Server Operational DB
    sql_server_driver: str = "ODBC Driver 17 for SQL Server"
    sql_server_host: str = "localhost"
    sql_server_port: int = 1433
    sql_server_database: str = "unified_charity_platform_clean"
    sql_server_user: str = "charity_app_user"
    sql_server_password: str = "CharityApp@2026"
    sql_server_trusted_connection: bool = False
    sql_server_trust_server_certificate: bool = True

    kafka_bootstrap_servers: str = "localhost:9092"
    kafka_topic_donations: str = "charity.online_donations"
    kafka_topic_applications: str = "charity.beneficiary_applications"
    kafka_topic_inventory: str = "charity.inventory_transactions"

    # MinIO / S3-compatible object storage
    minio_endpoint_url: str = "http://localhost:9000"
    minio_public_endpoint_url: str = "http://localhost:9000"
    minio_access_key: str = "ChangeMe_MinIO_2026!"
    minio_secret_key: str = "ChangeMe_MinIO_2026!123"
    minio_bucket_name: str = "charity-documents"
    minio_region: str = "us-east-1"
    minio_presigned_expiry_seconds: int = 3600

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()

