from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote, unquote
from uuid import uuid4

import boto3
from botocore.client import Config as BotoConfig
from botocore.exceptions import ClientError
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import RedirectResponse

from app.config import settings
from app.database import save_document_upload_event, save_event_to_sql_server
from app.event_utils import build_platform_event
from app.schemas import ApiResponse, DocumentMetadataCreate


router = APIRouter()

ALLOWED_EXTENSIONS = {".pdf", ".png", ".jpg", ".jpeg", ".webp", ".txt", ".doc", ".docx"}
MAX_FILE_SIZE_BYTES = 25 * 1024 * 1024


def get_s3_client():
    return boto3.client(
        "s3",
        endpoint_url=settings.minio_endpoint_url,
        aws_access_key_id=settings.minio_access_key,
        aws_secret_access_key=settings.minio_secret_key,
        region_name=settings.minio_region,
        config=BotoConfig(signature_version="s3v4"),
    )


def ensure_bucket_exists():
    client = get_s3_client()
    try:
        client.head_bucket(Bucket=settings.minio_bucket_name)
    except ClientError:
        client.create_bucket(Bucket=settings.minio_bucket_name)
    return client


def validate_file(file: UploadFile) -> tuple[str, int]:
    original_name = file.filename or "uploaded_file"
    suffix = Path(original_name).suffix.lower()

    if suffix not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type: {suffix}. Allowed: {sorted(ALLOWED_EXTENSIONS)}",
        )

    file.file.seek(0, 2)
    size = file.file.tell()
    file.file.seek(0)

    if size > MAX_FILE_SIZE_BYTES:
        raise HTTPException(status_code=400, detail="File too large. Max size is 25MB.")

    return suffix, size


def create_presigned_url(object_key: str) -> str:
    client = get_s3_client()
    return client.generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.minio_bucket_name, "Key": object_key},
        ExpiresIn=settings.minio_presigned_expiry_seconds,
    )


def object_to_document(item: dict) -> dict:
    object_key = item["Key"]
    client = get_s3_client()

    metadata = {}
    content_type = ""
    try:
        head = client.head_object(Bucket=settings.minio_bucket_name, Key=object_key)
        metadata = head.get("Metadata", {}) or {}
        content_type = head.get("ContentType", "")
    except ClientError:
        pass

    file_name = object_key.split("/")[-1]
    return {
        "document_id": metadata.get("document_id") or file_name.split("_")[0],
        "application_id": metadata.get("application_id", ""),
        "beneficiary_id": metadata.get("beneficiary_id", ""),
        "document_type_id": metadata.get("document_type_id", "OTHER"),
        "original_file_name": metadata.get("original_file_name", file_name),
        "stored_file_name": file_name,
        "file_size_kb": round((item.get("Size") or 0) / 1024, 2),
        "content_type": content_type,
        "bucket_name": settings.minio_bucket_name,
        "object_key": object_key,
        "storage_path": f"s3://{settings.minio_bucket_name}/{object_key}",
        "file_url": f"/api/documents/file?object_key={quote(object_key, safe='')}",
        "document_status": "uploaded",
        "last_modified": item.get("LastModified").isoformat() if item.get("LastModified") else None,
    }


@router.get("/storage-health", response_model=ApiResponse)
def storage_health():
    try:
        client = ensure_bucket_exists()
        client.head_bucket(Bucket=settings.minio_bucket_name)
        return ApiResponse(
            success=True,
            message="MinIO storage is reachable and the bucket is ready.",
            data={
                "storage": "MinIO / S3-compatible",
                "endpoint": settings.minio_endpoint_url,
                "public_endpoint": settings.minio_public_endpoint_url,
                "bucket_name": settings.minio_bucket_name,
                "allowed_extensions": sorted(ALLOWED_EXTENSIONS),
                "max_file_size_mb": round(MAX_FILE_SIZE_BYTES / 1024 / 1024),
            },
        )
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"MinIO storage is not ready: {exc}") from exc


@router.get("", response_model=ApiResponse)
def list_documents():
    client = ensure_bucket_exists()
    response = client.list_objects_v2(
        Bucket=settings.minio_bucket_name,
        Prefix="beneficiary_documents/",
    )

    documents = [
        object_to_document(item)
        for item in response.get("Contents", [])
        if not item["Key"].endswith("/")
    ]

    documents.sort(key=lambda d: d.get("last_modified") or "", reverse=True)

    return ApiResponse(
        success=True,
        message=f"Documents listed from MinIO bucket {settings.minio_bucket_name}.",
        data={
            "bucket_name": settings.minio_bucket_name,
            "count": len(documents),
            "documents": documents,
        },
    )


@router.get("/application/{application_id}", response_model=ApiResponse)
def list_documents_by_application(application_id: str):
    client = ensure_bucket_exists()
    response = client.list_objects_v2(
        Bucket=settings.minio_bucket_name,
        Prefix="beneficiary_documents/",
    )

    documents = []
    for item in response.get("Contents", []):
        if item["Key"].endswith("/"):
            continue
        document = object_to_document(item)
        if document.get("application_id") == application_id:
            documents.append(document)

    documents.sort(key=lambda d: d.get("last_modified") or "", reverse=True)

    return ApiResponse(
        success=True,
        message=f"Documents listed for application {application_id}.",
        data={
            "application_id": application_id,
            "bucket_name": settings.minio_bucket_name,
            "count": len(documents),
            "documents": documents,
        },
    )


@router.post("", response_model=ApiResponse)
def create_document_metadata(payload: DocumentMetadataCreate):
    event = build_platform_event("BENEFICIARY_DOCUMENT_METADATA_CREATED", payload.model_dump())

    save_event_to_sql_server("platform_beneficiary_documents", event)

    return ApiResponse(
        success=True,
        message="Document metadata event saved to SQL Server outbox.",
        data=event,
    )


@router.post("/upload", response_model=ApiResponse)
async def upload_document_file(
    application_id: str = Form(...),
    document_type_id: str = Form(...),
    file: UploadFile = File(...),
    beneficiary_id: str = Form(""),
):
    suffix, size = validate_file(file)

    original_name = file.filename or "uploaded_file"
    document_id = f"DOC-{uuid4().hex[:12]}"
    safe_document_type = document_type_id.replace("/", "_").replace("\\", "_")
    stored_file_name = f"{document_id}_{safe_document_type}{suffix}"

    today = datetime.now(timezone.utc)
    object_key = (
        f"beneficiary_documents/"
        f"year={today.year}/month={today.month:02d}/day={today.day:02d}/"
        f"{stored_file_name}"
    )

    client = ensure_bucket_exists()

    content_type = file.content_type or "application/octet-stream"
    client.upload_fileobj(
        file.file,
        settings.minio_bucket_name,
        object_key,
        ExtraArgs={
            "ContentType": content_type,
            "Metadata": {
                "document_id": document_id,
                "application_id": application_id or "",
                "beneficiary_id": beneficiary_id or "",
                "document_type_id": document_type_id or "",
                "original_file_name": original_name,
            },
        },
    )

    presigned_url = create_presigned_url(object_key)

    payload = {
        "document_id": document_id,
        "application_id": application_id,
        "beneficiary_id": beneficiary_id,
        "document_type_id": document_type_id,
        "original_file_name": original_name,
        "stored_file_name": stored_file_name,
        "file_size_kb": round(size / 1024, 2),
        "content_type": content_type,
        "bucket_name": settings.minio_bucket_name,
        "object_key": object_key,
        "storage_path": f"s3://{settings.minio_bucket_name}/{object_key}",
        "file_url": f"/api/documents/file?object_key={quote(object_key, safe='')}",
        "presigned_url": presigned_url,
        "document_status": "uploaded",
        "uploaded_at": datetime.now(timezone.utc).isoformat(),
    }

    event = build_platform_event("BENEFICIARY_DOCUMENT_FILE_UPLOADED", payload)

    try:
        sql_result = save_document_upload_event(payload, event)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"SQL Server document metadata save failed: {exc}") from exc

    response_data = {
        **event,
        **payload,
        "sql_result": sql_result,
    }

    return ApiResponse(
        success=True,
        message="Document uploaded to MinIO and metadata saved to SQL Server/outbox.",
        data=response_data,
    )


@router.get("/file")
def open_document_file(object_key: str):
    object_key = unquote(object_key)

    try:
        presigned_url = create_presigned_url(object_key)
    except ClientError as exc:
        raise HTTPException(status_code=404, detail=f"Could not open object: {exc}") from exc

    return RedirectResponse(presigned_url)
