Get-Content .\data_engineering\de12_powerbi_views\sql\01_create_powerbi_views.sql |
docker exec -i ucp_sqlserver /opt/mssql-tools18/bin/sqlcmd `
  -C `
  -S localhost `
  -U sa `
  -P "ChangeMe_StrongPassword_2026!"

