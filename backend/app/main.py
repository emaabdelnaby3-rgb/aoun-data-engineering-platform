from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import donations, applications, inventory, cases, documents, read_api, reference, beneficiaries, phase2_business, phase3_complete

app = FastAPI(
    title="Unified Charity Platform API",
    version="3.0.0",
    description="Unified Charity Platform API - Phase 3 complete Arabic frontend/backend/database/DWH integration"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def root():
    return {
        "message": "Unified Charity Platform API is running",
        "docs": "/docs",
        "sql_server": "unified_charity_platform_clean",
        "phase": "Phase 3 - Complete Arabic platform integration",
    }


@app.get("/health")
def health():
    return {"status": "healthy"}


app.include_router(applications.router, prefix="/api/beneficiary-applications", tags=["Beneficiary Applications"])
app.include_router(donations.router, prefix="/api/donations", tags=["Donations"])
app.include_router(cases.router, prefix="/api/cases", tags=["Cases"])
app.include_router(inventory.router, prefix="/api/inventory-transactions", tags=["Inventory"])
app.include_router(documents.router, prefix="/api/documents", tags=["Documents"])
app.include_router(read_api.router, prefix="/api", tags=["SQL Server Read APIs"])
app.include_router(reference.router, prefix="/api/reference", tags=["Reference Data + Fraud"])
app.include_router(beneficiaries.router, prefix="/api/beneficiaries", tags=["Beneficiary 360"])

app.include_router(phase2_business.router, prefix="/api/phase2", tags=["Phase 2 Arabic Business APIs"])

app.include_router(phase3_complete.router, prefix="/api/phase3", tags=["Phase 3 Complete Arabic Platform APIs"])
