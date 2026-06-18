# Unified Charity Platform MVP

Ready frontend + backend scaffold for the charity platform.

## Frontend
React + Vite Arabic RTL UI with the full platform flow.

Run:
```bash
cd frontend
npm install
npm run dev
to run frontend 
cd C:\Users\Admin\Desktop\Project_grad\unified_charity_platform_mvp\frontend
npm run dev
```
Open: http://localhost:5173

## Backend
FastAPI scaffold with placeholder routes. You complete the real API logic for SQL Server and Kafka.

Run:
```bash
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

to run backend : 
cd C:\Users\Admin\Desktop\Project_grad\unified_charity_platform_mvp\backend
.venv\Scripts\activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000


```


Open: http://localhost:8000/docs

## API parts to complete
- backend/app/database.py
- backend/app/kafka_producer.py
- backend/app/routers/*.py

## SQL
Use sql_server_tables.sql as a starter script for the platform operational tables.
