export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || "http://localhost:8000";

let CURRENT_USER = {
  organization_id: 3,
  organization_code: "haya_karima",
  role_code: "CHARITY_ADMIN",
};

function extractSafeId(value) {
  if (value === null || value === undefined) return "";

  if (typeof value === "number" || typeof value === "string") {
    const text = String(value).trim();
    if (!text || text === "[object Object]") return "";
    return text;
  }

  if (typeof value === "object") {
    return extractSafeId(
      value.organization_id ??
      value.organizationId ??
      value.source_organization_id ??
      value.id ??
      value.value ??
      value.organization?.organization_id ??
      value.organization?.id
    );
  }

  return "";
}

export function setCurrentUser(user) {
  CURRENT_USER = {
    ...CURRENT_USER,
    ...(user || {}),
  };
}

export function getCurrentUser() {
  return CURRENT_USER;
}

function getFallbackOrganizationId() {
  return extractSafeId(CURRENT_USER?.organization_id) || "3";
}

function cleanApiPath(path) {
  const fallbackOrgId = encodeURIComponent(getFallbackOrganizationId());

  return String(path || "")
    .replace(/\[object Object\]/g, fallbackOrgId)
    .replace(/%5Bobject(\+|%20)Object%5D/gi, fallbackOrgId);
}

function withOrganizationScope(path, organizationId) {
  const orgId = extractSafeId(organizationId) || extractSafeId(CURRENT_USER?.organization_id);

  if (!orgId) return path;

  const separator = path.includes("?") ? "&" : "?";
  return `${path}${separator}organization_id=${encodeURIComponent(orgId)}`;
}

async function request(path, options = {}) {
  const cleanPath = cleanApiPath(path);

  const headers = {
    ...(options.body instanceof FormData ? {} : { "Content-Type": "application/json" }),
    ...(options.headers || {}),
  };

  const response = await fetch(`${API_BASE_URL}${cleanPath}`, {
    ...options,
    headers,
  });

  const text = await response.text();
  let data = null;

  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }

  if (!response.ok) {
    const detail =
      data?.detail ||
      data?.message ||
      data?.error ||
      `${response.status} ${response.statusText}`;

    throw new Error(typeof detail === "string" ? detail : JSON.stringify(detail));
  }

  return data;
}

function normalizeReviewPayload(payload = {}) {
  return {
    decision: payload.decision ?? payload.application_status ?? payload.status ?? "APPROVED",
    review_notes: payload.review_notes ?? payload.notes ?? payload.staff_notes ?? "",
    reviewer_user_id: payload.reviewer_user_id ?? payload.user_id ?? 1,
    ...payload,
  };
}

async function uploadDocumentRequest({ applicationId, application_id, documentTypeId, document_type_id, beneficiaryId, beneficiary_id, file } = {}) {
  const formData = new FormData();

  if (applicationId || application_id) formData.append("application_id", applicationId || application_id);
  if (documentTypeId || document_type_id) formData.append("document_type_id", documentTypeId || document_type_id);
  if (beneficiaryId || beneficiary_id) formData.append("beneficiary_id", beneficiaryId || beneficiary_id);
  if (file) formData.append("file", file);

  const response = await fetch(`${API_BASE_URL}/api/documents/upload`, {
    method: "POST",
    body: formData,
  });

  const data = await response.json().catch(() => null);

  if (!response.ok) {
    throw new Error(data?.detail || data?.message || "Document upload failed");
  }

  return data;
}

export const platformApi = {
  request,

  setCurrentUser,
  getCurrentUser,

  createBeneficiaryApplication: (payload) =>
    request("/api/beneficiary-applications", {
      method: "POST",
      body: JSON.stringify(payload || {}),
    }),

  reviewBeneficiaryApplication: (applicationId, payload) =>
    request(`/api/beneficiary-applications/${encodeURIComponent(applicationId)}/review`, {
      method: "POST",
      body: JSON.stringify(normalizeReviewPayload(payload)),
    }),

  reviewApplication: (applicationId, payload) =>
    request(`/api/beneficiary-applications/${encodeURIComponent(applicationId)}/review`, {
      method: "POST",
      body: JSON.stringify(normalizeReviewPayload(payload)),
    }),

  createDonation: (payload) =>
    request("/api/donations", {
      method: "POST",
      body: JSON.stringify(payload || {}),
    }),

  createCase: (payload) =>
    request("/api/cases", {
      method: "POST",
      body: JSON.stringify(payload || {}),
    }),

  createInventoryTransaction: (payload) =>
    request("/api/inventory-transactions", {
      method: "POST",
      body: JSON.stringify(payload || {}),
    }),

  uploadDocumentFile: uploadDocumentRequest,

  listOrganizations: () => request("/api/organizations"),
  listSupportTypes: () => request("/api/support-types"),

  listApplications: () => request(withOrganizationScope("/api/applications")),
  listCases: () => request(withOrganizationScope("/api/cases")),

  listDonations: () => request(withOrganizationScope("/api/donations")),

  listInventoryTransactions: () =>
    request(withOrganizationScope("/api/inventory-transactions")),

  listEventOutbox: () => request(withOrganizationScope("/api/events/outbox")),

  getGovernmentDashboard: () => request("/api/dashboard/government"),

  getCharityNetworkDashboard: () =>
    request(withOrganizationScope("/api/dashboard/charity-network")),

  listDocuments: () => request(withOrganizationScope("/api/documents")),

  listDocumentsByApplication: (applicationId) =>
    request(`/api/documents/application/${encodeURIComponent(applicationId)}`),

  getGovernorates: () => request("/api/reference/governorates"),

  getCities: (governorate) =>
    request(
      `/api/reference/cities${
        governorate ? `?governorate=${encodeURIComponent(governorate)}` : ""
      }`
    ),

  getOrganizations: () => request("/api/reference/organizations"),

  getBranches: (organizationId, governorate) => {
    const params = new URLSearchParams();
    const orgId = extractSafeId(organizationId);

    if (orgId) params.append("organization_id", orgId);
    if (governorate) params.append("governorate", governorate);

    const query = params.toString();
    return request(`/api/reference/branches${query ? `?${query}` : ""}`);
  },

  getPaymentMethods: () => request("/api/reference/payment-methods"),

  getDocumentTypes: (supportTypeId) =>
    request(
      `/api/reference/document-types${
        supportTypeId ? `?support_type_id=${encodeURIComponent(supportTypeId)}` : ""
      }`
    ),

  getInventoryItems: () => request("/api/reference/inventory-items"),

  getOpenCases: (organizationId) => {
    const scopedOrganizationId = extractSafeId(organizationId) || extractSafeId(CURRENT_USER.organization_id);

    return request(
      `/api/reference/open-cases${
        scopedOrganizationId ? `?organization_id=${encodeURIComponent(scopedOrganizationId)}` : ""
      }`
    );
  },

  getCaseReferences: (organizationId) => {
    const scopedOrganizationId = extractSafeId(organizationId) || extractSafeId(CURRENT_USER.organization_id);

    return request(
      `/api/reference/case-references${
        scopedOrganizationId ? `?organization_id=${encodeURIComponent(scopedOrganizationId)}` : ""
      }`
    );
  },

  getReferenceIds: ({ organizationId, supportTypeId, governorate } = {}) => {
    const params = new URLSearchParams();

    const scopedOrganizationId = extractSafeId(organizationId) || extractSafeId(CURRENT_USER.organization_id);

    if (scopedOrganizationId) params.append("organization_id", scopedOrganizationId);
    if (supportTypeId) params.append("support_type_id", supportTypeId);
    if (governorate) params.append("governorate", governorate);

    const query = params.toString();
    return request(`/api/reference/reference-ids${query ? `?${query}` : ""}`);
  },

  getInventoryStock: ({ organizationId, branchId, itemId } = {}) => {
    const params = new URLSearchParams();

    const scopedOrganizationId = extractSafeId(organizationId) || extractSafeId(CURRENT_USER.organization_id);

    if (scopedOrganizationId) params.append("organization_id", scopedOrganizationId);
    if (branchId) params.append("branch_id", branchId);
    if (itemId) params.append("item_id", itemId);

    const query = params.toString();
    return request(`/api/reference/inventory-stock${query ? `?${query}` : ""}`);
  },

  getFraudAlerts: () => request("/api/reference/fraud-alerts"),
  getAuditLogs: () => request("/api/reference/audit-logs"),

  getBeneficiaryDashboardSummary: () =>
    request("/api/beneficiaries/dashboard/summary"),

  searchBeneficiaries: (keyword = "") =>
    request(
      `/api/beneficiaries/search${
        keyword ? `?q=${encodeURIComponent(keyword)}` : ""
      }`
    ),

  getBeneficiary360: ({ national_id, beneficiary_id } = {}) => {
    const params = new URLSearchParams();

    if (national_id) params.append("national_id", national_id);
    if (beneficiary_id) params.append("beneficiary_id", beneficiary_id);

    const query = params.toString();
    return request(`/api/beneficiaries/360${query ? `?${query}` : ""}`);
  },

  getBeneficiaryTimeline: (beneficiaryId) =>
    request(`/api/beneficiaries/${encodeURIComponent(beneficiaryId)}/timeline`),

  getBeneficiarySupportHistory: (beneficiaryId) =>
    request(`/api/beneficiaries/${encodeURIComponent(beneficiaryId)}/support-history`),

  getCrossOrganizationBeneficiaries: () =>
    request("/api/beneficiaries/reports/cross-organization"),

  getDuplicateBeneficiaryCandidates: () =>
    request("/api/beneficiaries/reports/duplicates"),
};

export default platformApi;

