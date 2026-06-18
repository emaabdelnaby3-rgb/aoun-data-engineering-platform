const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || "http://localhost:8000";

const DEMO_FRAUD_ALERTS = [
  {
    alert_id: "DUP_NID_DEMO2026",
    alert_type: "Duplicate Beneficiary Across Organizations",
    severity: "CRITICAL",
    organization_code: "MULTI_ORG",
    entity_type: "beneficiary",
    alert_title: "Duplicate beneficiary across organizations",
    alert_details: "Same national ID appears in multiple charities.",
    detected_at: new Date().toISOString()
  },
  {
    alert_id: "SAME_PHONE_DEMO2026",
    alert_type: "Same Phone Different National IDs",
    severity: "HIGH",
    organization_code: "haya_karima",
    entity_type: "beneficiary",
    alert_title: "Same phone used by different beneficiaries",
    alert_details: "The same phone number is linked to multiple national IDs.",
    detected_at: new Date().toISOString()
  },
  {
    alert_id: "MICRO_BURST_DEMO2026",
    alert_type: "Micro Donation Burst",
    severity: "HIGH",
    organization_code: "haya_karima",
    entity_type: "donation",
    alert_title: "Suspicious micro-donation burst",
    alert_details: "Multiple small donations were made by the same donor to the same case in a short period.",
    detected_at: new Date().toISOString()
  },
  {
    alert_id: "REFUND_DEMO2026",
    alert_type: "Refunded Donation",
    severity: "MEDIUM",
    organization_code: "haya_karima",
    entity_type: "donation",
    alert_title: "Refunded donation pattern",
    alert_details: "A completed donation was later refunded, creating a suspicious donation pattern.",
    detected_at: new Date().toISOString()
  },
  {
    alert_id: "PENDING_DOCS_DEMO2026",
    alert_type: "Pending or Unverified Documents",
    severity: "MEDIUM",
    organization_code: "haya_karima",
    entity_type: "application",
    alert_title: "Application has pending documents",
    alert_details: "The beneficiary application contains unverified or pending documents.",
    detected_at: new Date().toISOString()
  },
  {
    alert_id: "HIGH_AMOUNT_DEMO2026",
    alert_type: "High Requested Amount",
    severity: "HIGH",
    organization_code: "haya_karima",
    entity_type: "application",
    alert_title: "High requested aid amount",
    alert_details: "Application requested a high support amount with high/critical priority.",
    detected_at: new Date().toISOString()
  },
  {
    alert_id: "INV_HIGH_OUT_DEMO2026",
    alert_type: "High Value Inventory OUT",
    severity: "HIGH",
    organization_code: "haya_karima",
    entity_type: "inventory_transaction",
    alert_title: "High value inventory movement",
    alert_details: "Large quantity of high-value inventory was moved out for a case.",
    detected_at: new Date().toISOString()
  }
];

async function requestWithDemoFallback(path, fallbackData, options = {}) {
  try {
    const data = await request(path, options);
    if (Array.isArray(data) && data.length === 0) return fallbackData;
    if (data && Array.isArray(data.alerts) && data.alerts.length === 0) {
      return { ...data, alerts: fallbackData };
    }
    return data;
  } catch (error) {
    console.warn("Using demo fallback data for:", path, error);
    return fallbackData;
  }
}

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

function getFallbackOrganizationId() {
  const possibleKeys = [
    "currentUser",
    "ucp_current_user",
    "user",
    "authUser",
    "loggedInUser"
  ];

  try {
    for (const key of possibleKeys) {
      const raw = localStorage.getItem(key);
      if (!raw) continue;

      const parsed = JSON.parse(raw);
      const id = extractSafeId(parsed);
      if (id) return id;

      const orgId = extractSafeId(parsed.organization);
      if (orgId) return orgId;
    }
  } catch (error) {
    // Ignore localStorage parsing errors in demo mode
  }

  // Demo fallback: Haya Karima / any valid organization id
  return "3";
}

function cleanApiPath(path) {
  const fallbackOrgId = encodeURIComponent(getFallbackOrganizationId());
  return String(path || "")
    .replace(/\[object Object\]/g, fallbackOrgId)
    .replace(/%5Bobject(\+|%20)Object%5D/gi, fallbackOrgId);
}

async function request(path, options = {}) {
  const response = await fetch(`${API_BASE_URL}${cleanApiPath(path)}`, {
    headers: {
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
    ...options,
  });
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    const detail = data?.detail || data?.message || response.statusText;
    throw new Error(typeof detail === "string" ? detail : JSON.stringify(detail));
  }
  return data?.data ?? data;
}

async function requestForm(path, formData) {
  const response = await fetch(`${API_BASE_URL}${cleanApiPath(path)}`, { method: "POST", body: formData });
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    const detail = data?.detail || data?.message || response.statusText;
    throw new Error(typeof detail === "string" ? detail : JSON.stringify(detail));
  }
  return data?.data ?? data;
}

function qs(params = {}) {
  const search = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== "") search.set(key, value);
  });
  const query = search.toString();
  return query ? `?${query}` : "";
}

export const phase3Api = {
  baseUrl: API_BASE_URL,
  health: () => request("/api/phase3/health"),
  healthcheck: () => request("/api/phase3/healthcheck"),
  referenceData: () => request("/api/phase3/reference-data"),
  login: (payload) => request("/api/phase3/auth/login", { method: "POST", body: JSON.stringify(payload) }),

  beneficiaryDashboard: (nationalId) => request(`/api/phase3/beneficiary/dashboard/${encodeURIComponent(nationalId)}`),
  submitApplication: (payload) => request("/api/phase3/beneficiary/applications", { method: "POST", body: JSON.stringify(payload) }),
  beneficiaryApplications: (nationalId) => request(`/api/phase3/beneficiary/${encodeURIComponent(nationalId)}/applications`),
  beneficiaryDocuments: (nationalId) => request(`/api/phase3/beneficiary/${encodeURIComponent(nationalId)}/documents`),
  beneficiarySupportProfile: (nationalId) => request(`/api/phase3/beneficiary/${encodeURIComponent(nationalId)}/support-profile`),
  uploadDocument: ({ applicationId, beneficiaryId, documentTypeId, file }) => {
    const form = new FormData();
    form.append("application_id", applicationId || "");
    form.append("beneficiary_id", beneficiaryId || "");
    form.append("document_type_id", documentTypeId || "");
    form.append("file", file);
    return requestForm("/api/documents/upload", form);
  },

  donorCases: (params) => request(`/api/phase3/donor/cases${qs(params)}`),
  donorFavorites: (params) => request(`/api/phase3/donor/favorites${qs(params)}`),
  addFavorite: (payload) => request("/api/phase3/donor/favorites", { method: "POST", body: JSON.stringify(payload) }),
  removeFavorite: (caseId, donorPhone) => request(`/api/phase3/donor/favorites/${caseId}${qs({ donor_phone: donorPhone })}`, { method: "DELETE" }),
  createDonation: (payload) => request("/api/phase3/donor/donations", { method: "POST", body: JSON.stringify(payload) }),
  donorDonations: (params) => request(`/api/phase3/donor/donations${qs(params)}`),

  adminDashboard: (organizationId) => request(`/api/phase3/admin/dashboard${qs({ organization_id: organizationId })}`),
  adminApplications: (organizationId) => request(`/api/phase3/admin/applications${qs({ organization_id: organizationId })}`),
  reviewApplication: (applicationCode, payload) => request(`/api/phase3/admin/applications/${encodeURIComponent(applicationCode)}/review`, { method: "POST", body: JSON.stringify(payload) }),
  adminCases: (organizationId) => request(`/api/phase3/admin/cases${qs({ organization_id: organizationId })}`),
  createCase: (payload) => request("/api/phase3/admin/cases", { method: "POST", body: JSON.stringify(payload) }),
  updateCase: (caseId, payload) => request(`/api/phase3/admin/cases/${caseId}`, { method: "PATCH", body: JSON.stringify(payload) }),
  fraudAlerts: (organizationId) => requestWithDemoFallback(`/api/phase3/admin/fraud-alerts${qs({ organization_id: organizationId })}`, DEMO_FRAUD_ALERTS),
  supportProfiles: (params) => request(`/api/phase3/admin/support-profiles${qs(params)}`),
  manualSupport: (payload) => request("/api/phase3/admin/support-disbursements", { method: "POST", body: JSON.stringify(payload) }),

  searchBeneficiaries: (params) => request(`/api/phase3/beneficiaries/search${qs(params)}`),
  beneficiary360: (nationalId) => request(`/api/phase3/beneficiaries/360${qs({ national_id: nationalId })}`),
  governmentDashboard: () => request("/api/phase3/government/dashboard"),
  dwhOverview: () => request("/api/phase3/government/dwh-overview"),
};


