# Phase 2 File Map

```text
backend/sql/10_PHASE_2_BUSINESS_SCHEMA.sql
```
Adds the Phase 2 database migration: priority scoring, donor favorites, monthly eligibility, support profiles, and public case views.

```text
backend/app/routers/phase2_business.py
```
Adds the new FastAPI routes under `/api/phase2`.

```text
backend/app/main.py
```
Registers the Phase 2 router and updates the API version to 2.0.0.

```text
frontend/src/phase2Api.js
```
Frontend API helper for the new Phase 2 endpoints.

```text
frontend/src/App.jsx
```
Keeps the Arabic RTL UI and updates the phase label to Phase 2.

```text
README_PHASE_2_DATABASE_BACKEND.md
```
Run instructions, endpoint list, and JSON examples.
```
