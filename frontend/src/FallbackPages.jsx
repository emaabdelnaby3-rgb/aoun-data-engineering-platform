function PageShell({ title, subtitle, children }) {
  return (
    <div dir="rtl" style={{ padding: "32px", minHeight: "100vh", background: "linear-gradient(135deg, #fffaf0, #f0fdf4)" }}>
      <div style={{ maxWidth: "1100px", margin: "0 auto", background: "rgba(255,255,255,0.95)", border: "1px solid #dbeafe", borderRadius: "24px", padding: "28px", boxShadow: "0 20px 45px rgba(15,23,42,0.08)" }}>
        <h1 style={{ margin: 0, fontSize: "34px", fontWeight: 900, color: "#0f172a" }}>{title}</h1>
        <p style={{ marginTop: "10px", color: "#64748b", fontSize: "16px" }}>{subtitle}</p>
        <div style={{ marginTop: "28px" }}>{children}</div>
      </div>
    </div>
  );
}

function StatGrid() {
  const cards = [
    ["\u0627\u0644\u0637\u0644\u0628\u0627\u062a \u0627\u0644\u0645\u0642\u062f\u0645\u0629", "3"],
    ["\u0637\u0644\u0628\u0627\u062a \u062a\u062d\u062a \u0627\u0644\u0645\u0631\u0627\u062c\u0639\u0629", "1"],
    ["\u0645\u0633\u062a\u0646\u062f\u0627\u062a \u0645\u0637\u0644\u0648\u0628\u0629", "2"],
    ["\u062d\u0627\u0644\u0629 \u0627\u0644\u0627\u0633\u062a\u062d\u0642\u0627\u0642", "\u0645\u0624\u0647\u0644"]
  ];

  return (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: "16px" }}>
      {cards.map(([label, value]) => (
        <div key={label} style={{ background: "#fff", border: "1px solid #e2e8f0", borderRadius: "18px", padding: "22px", boxShadow: "0 10px 25px rgba(15,23,42,0.06)" }}>
          <div style={{ color: "#64748b", fontWeight: 700 }}>{label}</div>
          <div style={{ marginTop: "10px", color: "#064e3b", fontSize: "28px", fontWeight: 900 }}>{value}</div>
        </div>
      ))}
    </div>
  );
}

export function BeneficiaryDashboard() {
  return (
    <PageShell title={"\u062f\u0627\u0634\u0628\u0648\u0631\u062f \u0627\u0644\u0645\u0633\u062a\u0641\u064a\u062f"} subtitle={"\u0645\u062a\u0627\u0628\u0639\u0629 \u0627\u0644\u0637\u0644\u0628\u0627\u062a \u0648\u0627\u0644\u0645\u0633\u062a\u0646\u062f\u0627\u062a \u0648\u062d\u0627\u0644\u0629 \u0627\u0644\u0627\u0633\u062a\u062d\u0642\u0627\u0642."}>
      <StatGrid />
    </PageShell>
  );
}

export function ApplyPage() {
  return (
    <PageShell title={"\u062a\u0642\u062f\u064a\u0645 \u0637\u0644\u0628 \u062f\u0639\u0645"} subtitle={"\u0646\u0645\u0648\u0630\u062c \u062f\u064a\u0645\u0648 \u0644\u062a\u0642\u062f\u064a\u0645 \u0637\u0644\u0628 \u062f\u0639\u0645 \u062f\u0627\u062e\u0644 \u0645\u0646\u0635\u0629 \u0639\u0648\u0646."}>
      <StatGrid />
    </PageShell>
  );
}

export function DocumentsPage() {
  return (
    <PageShell title={"\u0627\u0644\u0645\u0633\u062a\u0646\u062f\u0627\u062a"} subtitle={"\u0645\u062a\u0627\u0628\u0639\u0629 \u0645\u0633\u062a\u0646\u062f\u0627\u062a \u0627\u0644\u0645\u0633\u062a\u0641\u064a\u062f \u0648\u062d\u0627\u0644\u0629 \u0627\u0644\u062a\u062d\u0642\u0642."}>
      <StatGrid />
    </PageShell>
  );
}

export function ApplicationsPage() {
  return (
    <PageShell title={"\u0637\u0644\u0628\u0627\u062a\u064a"} subtitle={"\u0645\u062a\u0627\u0628\u0639\u0629 \u062d\u0627\u0644\u0629 \u0637\u0644\u0628\u0627\u062a \u0627\u0644\u062f\u0639\u0645."}>
      <StatGrid />
    </PageShell>
  );
}

export function SupportHistoryPage() {
  return (
    <PageShell title={"\u0633\u062c\u0644 \u0627\u0644\u062f\u0639\u0645"} subtitle={"\u0639\u0631\u0636 \u0627\u0644\u062f\u0639\u0645 \u0627\u0644\u0633\u0627\u0628\u0642 \u0648\u0645\u0646\u0639 \u062a\u0643\u0631\u0627\u0631 \u0627\u0644\u062f\u0639\u0645."}>
      <StatGrid />
    </PageShell>
  );
}

export function BeneficiaryProfilePage() {
  return (
    <PageShell title={"\u0628\u0631\u0648\u0641\u0627\u064a\u0644 \u0627\u0644\u0645\u0633\u062a\u0641\u064a\u062f"} subtitle={"\u0645\u0631\u0627\u062c\u0639\u0629 \u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u0645\u0633\u062a\u0641\u064a\u062f \u0648\u062d\u0627\u0644\u0629 \u0627\u0644\u0627\u0633\u062a\u062d\u0642\u0627\u0642."}>
      <StatGrid />
    </PageShell>
  );
}
