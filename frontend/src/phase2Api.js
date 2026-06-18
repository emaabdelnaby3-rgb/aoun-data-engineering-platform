const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || "http://localhost:8000";

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


async function requestForm(path, formData, options = {}) {
  const response = await fetch(`${API_BASE_URL}${cleanApiPath(path)}`, {
    method: options.method || "POST",
    body: formData,
    ...(options.fetchOptions || {}),
  });

  const data = await response.json().catch(() => null);

  if (!response.ok) {
    const detail = data?.detail || data?.message || response.statusText;
    throw new Error(typeof detail === "string" ? detail : JSON.stringify(detail));
  }

  return data?.data ?? data;
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

export const phase2Api = {
  health: () => request("/api/phase2/health"),

  storageHealth: () => request("/api/documents/storage-health"),

  uploadDocument: ({ applicationId, documentTypeId, beneficiaryId, file }) => {
    const formData = new FormData();
    formData.append("application_id", applicationId);
    formData.append("document_type_id", documentTypeId);
    formData.append("beneficiary_id", beneficiaryId || "");
    formData.append("file", file);
    return requestForm("/api/documents/upload", formData);
  },

  listDocuments: () => request("/api/documents"),

  listDocumentsByApplication: (applicationId) =>
    request(`/api/documents/application/${encodeURIComponent(applicationId)}`),


  submitApplication: (payload) =>
    request("/api/phase2/beneficiary/applications", {
      method: "POST",
      body: JSON.stringify(payload),
    }),

  trackApplications: (nationalId) =>
    request(`/api/phase2/beneficiary/${encodeURIComponent(nationalId)}/applications`),

  getBeneficiarySupportProfile: (nationalId) =>
    request(`/api/phase2/beneficiary/${encodeURIComponent(nationalId)}/support-profile`),

  listAdminApplications: (organizationId) =>
    request(`/api/phase2/admin/applications${organizationId ? `?organization_id=${organizationId}` : ""}`),

  reviewApplication: (applicationCode, payload) =>
    request(`/api/phase2/admin/applications/${encodeURIComponent(applicationCode)}/review`, {
      method: "POST",
      body: JSON.stringify(payload),
    }),

  listDonorCases: ({ organizationId, onlyAvailable = false, supportTypeId } = {}) => {
    const params = new URLSearchParams();
    if (organizationId) params.set("organization_id", organizationId);
    if (onlyAvailable) params.set("only_available", "true");
    if (supportTypeId) params.set("support_type_id", supportTypeId);
    return request(`/api/phase2/donor/cases?${params.toString()}`);
  },

  addFavorite: (payload) =>
    request("/api/phase2/donor/favorites", {
      method: "POST",
      body: JSON.stringify(payload),
    }),

  listFavorites: ({ donorUserId, donorPhone } = {}) => {
    const params = new URLSearchParams();
    if (donorUserId) params.set("donor_user_id", donorUserId);
    if (donorPhone) params.set("donor_phone", donorPhone);
    return request(`/api/phase2/donor/favorites?${params.toString()}`);
  },

  createDonation: (payload) =>
    request("/api/phase2/donor/donations", {
      method: "POST",
      body: JSON.stringify(payload),
    }),

  listSupportProfiles: ({ organizationId, onlyNotEligible = false, search } = {}) => {
    const params = new URLSearchParams();
    if (organizationId) params.set("organization_id", organizationId);
    if (onlyNotEligible) params.set("only_not_eligible", "true");
    if (search) params.set("search", search);
    return request(`/api/phase2/support-profiles?${params.toString()}`);
  },

  charityDashboard: (organizationId) =>
    request(`/api/phase2/admin/dashboard?organization_id=${organizationId}`),

  governmentDashboard: () => request("/api/phase2/government/dashboard"),

  recordManualSupport: (payload) =>
    request("/api/phase2/support-disbursements/manual", {
      method: "POST",
      body: JSON.stringify(payload),
    }),
};

