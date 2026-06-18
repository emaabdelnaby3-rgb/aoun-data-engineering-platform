from typing import Any, Optional
from pydantic import BaseModel, Field


class ApiResponse(BaseModel):
    success: bool
    message: str
    data: Optional[Any] = None


class BeneficiaryApplicationCreate(BaseModel):
    full_name: str
    national_id: str
    phone: Optional[str] = None
    email: Optional[str] = None
    gender: Optional[str] = None
    birth_date: Optional[str] = None
    governorate: Optional[str] = None
    city: Optional[str] = None
    family_size: Optional[int] = Field(default=1, ge=1)
    monthly_income: Optional[float] = Field(default=0, ge=0)
    support_requested: Optional[str] = None
    support_type_id: Optional[int] = None


class ReviewApplicationRequest(BaseModel):
    decision: str
    notes: Optional[str] = None
    create_case: bool = False
    required_amount: Optional[float] = None
    priority_level: Optional[str] = "MEDIUM"


class DonationCreate(BaseModel):
    donor_name: str
    phone: str
    email: Optional[str] = None
    amount: float = Field(gt=0)
    currency: str = "EGP"
    payment_method_id: str
    campaign_name: Optional[str] = None
    donation_target_type: Optional[str] = "CASE"
    case_id: Optional[str] = None
    organization_id: Optional[str] = None
    idempotency_key: Optional[str] = None
    general_notes: Optional[str] = None


class CaseCreate(BaseModel):
    beneficiary_id: Optional[str] = None
    application_id: Optional[str] = None
    organization_id: Optional[str] = None
    branch_id: Optional[str] = None
    case_type: Optional[str] = None
    support_type_id: Optional[int] = None
    title: Optional[str] = None
    description: Optional[str] = None
    estimated_monthly_support: Optional[float] = Field(default=0, ge=0)
    required_amount: Optional[float] = Field(default=None, ge=0)
    priority_level: Optional[str] = "MEDIUM"
    governorate: Optional[str] = None


class InventoryTransactionCreate(BaseModel):
    organization_id: str
    branch_id: Optional[str] = None
    item_id: str
    transaction_type: str
    quantity: float = Field(gt=0)
    unit_cost: Optional[float] = None
    reference_type: Optional[str] = None
    reference_id: Optional[str] = None
    notes: Optional[str] = None


class DocumentMetadataCreate(BaseModel):
    application_id: str
    beneficiary_id: Optional[str] = None
    document_type_id: str
    file_name: Optional[str] = None
    file_url: Optional[str] = None
