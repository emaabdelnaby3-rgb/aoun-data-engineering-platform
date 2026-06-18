from pathlib import Path
import re
from datetime import datetime

ROOT = Path.cwd()
app_path = ROOT / "frontend" / "src" / "App.jsx"
css_path = ROOT / "frontend" / "src" / "styles.css"

if not app_path.exists():
    raise SystemExit("ERROR: frontend/src/App.jsx not found. Run this script from the project root.")
if not css_path.exists():
    raise SystemExit("ERROR: frontend/src/styles.css not found. Run this script from the project root.")

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
app = app_path.read_text(encoding="utf-8")
css = css_path.read_text(encoding="utf-8")

(app_path.parent / f"App.jsx.backup_before_final_aoun_ui_{stamp}").write_text(app, encoding="utf-8")
(css_path.parent / f"styles.css.backup_before_final_aoun_ui_{stamp}").write_text(css, encoding="utf-8")

# ---------------------------------------------------------------------
# 1) Make sure required icons are imported from lucide-react
# ---------------------------------------------------------------------
required_icons = ["CheckCircle2", "Heart", "ShieldCheck", "Database", "Users"]
import_match = re.search(r"import\s*\{(?P<body>.*?)\}\s*from\s*['\"]lucide-react['\"];", app, flags=re.S)
if import_match:
    existing = [x.strip() for x in import_match.group("body").replace("\n", " ").split(",") if x.strip()]
    for icon in required_icons:
        if icon not in existing:
            existing.append(icon)
    new_import = "import {\n  " + ", ".join(existing) + ",\n} from 'lucide-react';"
    app = app[:import_match.start()] + new_import + app[import_match.end():]
else:
    raise SystemExit("ERROR: Could not find lucide-react import in App.jsx")

# ---------------------------------------------------------------------
# 2) Replace LoginPage with a stable final version
# ---------------------------------------------------------------------
new_login = r'''function LoginPage({ onLogin }) {
  const [identifier, setIdentifier] = useState('gov@test.com');
  const [password, setPassword] = useState('123456');
  const refs = useAsync(() => phase3Api.referenceData(), []);
  const [error, setError] = useState('');

  async function loginWith(id = identifier) {
    setError('');
    try {
      onLogin(await phase3Api.login({ identifier: id, password }));
    } catch (e) {
      setError(e.message);
    }
  }

  const fallbackDemoUsers = [
    { identifier: 'gov@test.com', label: 'أدمن الحكومة' },
    { identifier: 'food.admin@test.com', label: 'أدمن بنك الطعام' },
    { identifier: 'resala.admin@test.com', label: 'أدمن رسالة' },
    { identifier: 'haya.admin@test.com', label: 'أدمن حياة كريمة' },
    { identifier: 'ahmed@test.com', label: 'مستفيد تجريبي' },
    { identifier: 'donor@test.com', label: 'متبرع تجريبي' },
  ];

  const demoUsers = refs.data?.demo_users?.length ? refs.data.demo_users : fallbackDemoUsers;

  return (
    <div className="aoun-ref-login-page" dir="rtl">
      <div className="aoun-ref-orb orb-one" />
      <div className="aoun-ref-orb orb-two" />
      <div className="aoun-ref-branch top" />

      <main className="aoun-ref-login-layout">
        <Card className="aoun-ref-login-card">
          <div className="aoun-ref-login-head">
            <h1>تسجيل الدخول</h1>
            <p>مرحباً بك في منصة عون</p>
          </div>

          <ErrorBox error={error || refs.error} />

          <div className="aoun-ref-form">
            <Field label="البريد الإلكتروني أو الهاتف">
              <TextInput
                dir="ltr"
                placeholder="example@domain.com"
                value={identifier}
                onChange={(e) => setIdentifier(e.target.value)}
              />
            </Field>

            <Field label="كلمة المرور">
              <TextInput
                dir="ltr"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </Field>

            <Button className="aoun-ref-login-btn" onClick={() => loginWith()}>
              دخول <CheckCircle2 className="h-4 w-4" />
            </Button>
          </div>

          <div className="aoun-ref-demo-divider">
            <span />
            <p>أو استخدم حساب تجريبي</p>
            <span />
          </div>

          <div className="aoun-ref-demo-list">
            {demoUsers.map((u) => (
              <button
                key={u.identifier}
                type="button"
                onClick={() => loginWith(u.identifier)}
                className="aoun-ref-demo-user"
              >
                <span className="aoun-ref-demo-role">{u.label}</span>
                <span className="aoun-ref-demo-email">{u.identifier}</span>
              </button>
            ))}
          </div>

          <p className="aoun-ref-footer">© 2025 عون · جميع الحقوق محفوظة</p>
        </Card>

        <section className="aoun-ref-hero">
          <img src="/aoun-logo.png" alt="Aoun" className="aoun-ref-logo" />

          <div className="aoun-ref-separator">
            <span />
            <Heart className="h-5 w-5" />
            <span />
          </div>

          <h2>﴿ وَتَعَاوَنُوا عَلَى الْبِرِّ وَالتَّقْوَى ﴾</h2>
          <p className="aoun-ref-source">المائدة: 2</p>

          <p className="aoun-ref-description">
            منصة موحدة لإدارة الجمعيات الخيرية، لمتابعة الحالات، منع تكرار الدعم،
            وربط البيانات التشغيلية والتحليلية لتحقيق أثر مستدام.
          </p>

          <div className="aoun-ref-features">
            <div className="aoun-ref-feature">
              <div><Users className="h-6 w-6" /></div>
              <h3>ربط وتكامل</h3>
              <p>توحيد جهود الجمعيات في منصة واحدة.</p>
            </div>

            <div className="aoun-ref-feature">
              <div><Database className="h-6 w-6" /></div>
              <h3>تقارير ذكية</h3>
              <p>تحليلات دقيقة لدعم اتخاذ القرار.</p>
            </div>

            <div className="aoun-ref-feature">
              <div><ShieldCheck className="h-6 w-6" /></div>
              <h3>شفافية وموثوقية</h3>
              <p>بيانات آمنة وموثوقة لضمان الثقة.</p>
            </div>

            <div className="aoun-ref-feature">
              <div><Heart className="h-6 w-6" /></div>
              <h3>أثر مستدام</h3>
              <p>نعمل معاً لصناعة أثر إنساني يدوم.</p>
            </div>
          </div>

          <div className="aoun-ref-quote">
            والله في عون العبد ما كان العبد في عون أخيه
          </div>
        </section>
      </main>
    </div>
  );
}
'''

login_pattern = r"function LoginPage\(\{ onLogin \}\)\s*\{.*?\n\}\n(?=\nfunction\s+[A-Za-z])"
app, replaced = re.subn(login_pattern, lambda m: new_login + "\n", app, flags=re.S, count=1)
if replaced == 0:
    raise SystemExit("ERROR: Could not find LoginPage block in App.jsx")

# ---------------------------------------------------------------------
# 3) Remove old duplicated Aoun login/theme CSS blocks and known mistakes
# ---------------------------------------------------------------------
block_titles = [
    "AOUN REFERENCE LOGIN PAGE",
    "AOUN SOFT ORGANIC THEME OVERRIDES",
    "EXACT AOUN REFERENCE LOGIN LAYOUT OVERRIDE",
    "AOUN LOGIN FRAME + SOFT ANIMATION OVERRIDE",
    "AOUN FINAL LOGIN PROFESSIONAL POLISH",
]
for title in block_titles:
    css = re.sub(
        r"/\* =========================================================\s*" + re.escape(title) + r".*?(?=/\* =========================================================|\Z)",
        "",
        css,
        flags=re.S,
    )

css = css.replace("backdrop-filter: blur(18px {", "backdrop-filter: blur(18px);")
css = css.replace("-webkit-backdrop-filter: blur(18px {", "-webkit-backdrop-filter: blur(18px);")
css = css.replace("box-shadow !important;", "")
css = css.replace("rgba(45, 66, 55, 0.13))", "rgba(45, 66, 55, 0.13)")

final_css = r'''

/* =========================================================
   AOUN FINAL LOGIN PROFESSIONAL POLISH
   frame + continuous animation + balanced typography
   frontend only
   ========================================================= */

.aoun-ref-login-page {
  min-height: 100vh !important;
  width: 100vw !important;
  overflow: auto !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  padding: 28px 34px !important;
  background:
    radial-gradient(circle at 0% 42%, rgba(232, 220, 195, 0.42) 0 15%, transparent 16%),
    radial-gradient(circle at 97% 95%, rgba(205, 224, 209, 0.54) 0 15%, transparent 16%),
    linear-gradient(135deg, #fffdf9 0%, #fbf8f1 47%, #f9fcf9 100%) !important;
  color: #1f3041 !important;
}

.aoun-ref-login-page::before {
  content: "";
  position: fixed;
  inset: 28px;
  border-radius: 42px;
  border: 1px solid rgba(91, 119, 100, 0.12);
  box-shadow: inset 0 1px 0 rgba(255,255,255,.76), 0 28px 88px rgba(43,65,53,.08);
  pointer-events: none;
  animation: aounFrameBreath 7s ease-in-out infinite;
}

.aoun-ref-orb {
  position: fixed;
  border-radius: 999px;
  pointer-events: none;
  filter: blur(2px);
  opacity: .55;
  z-index: 0;
}

.aoun-ref-orb.orb-one {
  width: 320px;
  height: 320px;
  left: -80px;
  top: 20%;
  background: rgba(233, 221, 196, .62);
  animation: aounOrbMoveOne 10s ease-in-out infinite;
}

.aoun-ref-orb.orb-two {
  width: 330px;
  height: 330px;
  right: -90px;
  bottom: -70px;
  background: rgba(203, 224, 209, .72);
  animation: aounOrbMoveTwo 12s ease-in-out infinite;
}

.aoun-ref-branch.top {
  position: fixed !important;
  top: -34px !important;
  right: 34px !important;
  width: 285px !important;
  height: 245px !important;
  opacity: .24 !important;
  transform: rotate(-20deg);
  pointer-events: none;
  background:
    radial-gradient(ellipse at 84% 8%, #8d9d88 0 12px, transparent 13px),
    radial-gradient(ellipse at 70% 26%, #8d9d88 0 13px, transparent 14px),
    radial-gradient(ellipse at 56% 44%, #8d9d88 0 13px, transparent 14px),
    radial-gradient(ellipse at 42% 62%, #8d9d88 0 12px, transparent 13px);
  animation: aounBranchSway 8s ease-in-out infinite;
}

.aoun-ref-login-layout {
  width: min(1500px, calc(100vw - 88px)) !important;
  min-height: min(790px, calc(100vh - 76px)) !important;
  display: grid !important;
  grid-template-columns: 430px minmax(0, 1fr) !important;
  grid-template-areas: "card hero" !important;
  gap: 58px !important;
  align-items: center !important;
  direction: ltr !important;
  padding: 30px 46px !important;
  border-radius: 38px !important;
  background: rgba(255, 255, 255, 0.46) !important;
  border: 1px solid rgba(91, 119, 100, 0.16) !important;
  box-shadow: 0 34px 94px rgba(43, 65, 53, 0.12), inset 0 1px 0 rgba(255,255,255,.76) !important;
  backdrop-filter: blur(24px) !important;
  position: relative !important;
  overflow: hidden !important;
  z-index: 1;
  animation: aounFrameIn .75s ease both;
}

.aoun-ref-login-layout::before {
  content: "";
  position: absolute;
  inset: 14px;
  border-radius: 30px;
  border: 1px solid rgba(255,255,255,.56);
  pointer-events: none;
}

.aoun-ref-login-card {
  grid-area: card !important;
  width: 430px !important;
  max-width: 430px !important;
  direction: rtl !important;
  border-radius: 26px !important;
  padding: 28px 28px 24px !important;
  background: rgba(255,255,255,.75) !important;
  border: 1px solid rgba(91,119,100,.18) !important;
  box-shadow: 0 24px 72px rgba(45,66,55,.13) !important;
  backdrop-filter: blur(24px) !important;
  animation: aounCardSlideIn .8s ease both;
}

.aoun-ref-login-head {
  margin-bottom: 20px !important;
  text-align: center !important;
}

.aoun-ref-login-head h1 {
  margin: 0 !important;
  color: #203141 !important;
  font-size: 27px !important;
  line-height: 1.25 !important;
  font-weight: 950 !important;
  letter-spacing: -0.035em !important;
}

.aoun-ref-login-head p {
  margin-top: 8px !important;
  color: #858d8e !important;
  font-size: 13px !important;
  font-weight: 850 !important;
}

.aoun-ref-form {
  display: grid !important;
  gap: 14px !important;
}

.aoun-ref-form label {
  color: #263943 !important;
  font-size: 12px !important;
  font-weight: 900 !important;
}

.aoun-ref-form input {
  height: 48px !important;
  min-height: 48px !important;
  border-radius: 15px !important;
  font-size: 13px !important;
  background: rgba(255,255,255,.78) !important;
  border: 1px solid rgba(99,121,105,.15) !important;
  box-shadow: inset 0 1px 0 rgba(255,255,255,.9), 0 9px 22px rgba(42,64,53,.04) !important;
}

.aoun-ref-login-btn {
  width: 100% !important;
  height: 50px !important;
  min-height: 50px !important;
  margin-top: 4px !important;
  border-radius: 15px !important;
  font-size: 14px !important;
  font-weight: 950 !important;
  background: linear-gradient(135deg, #668672 0%, #3f7056 100%) !important;
  box-shadow: 0 14px 32px rgba(62,111,85,.22) !important;
  transition: transform .22s ease, box-shadow .22s ease !important;
  animation: aounButtonGlow 3.8s ease-in-out infinite;
}

.aoun-ref-login-btn:hover {
  transform: translateY(-2px) !important;
  box-shadow: 0 20px 42px rgba(62,111,85,.28) !important;
}

.aoun-ref-demo-divider {
  margin: 22px 0 13px !important;
  display: grid !important;
  grid-template-columns: 1fr auto 1fr !important;
  align-items: center !important;
  gap: 12px !important;
  color: #899293 !important;
  font-size: 12px !important;
  font-weight: 850 !important;
}

.aoun-ref-demo-divider span {
  height: 1px !important;
  background: rgba(98,119,105,.15) !important;
}

.aoun-ref-demo-divider p { margin: 0 !important; }

.aoun-ref-demo-list {
  display: grid !important;
  gap: 8px !important;
}

.aoun-ref-demo-user {
  height: 42px !important;
  min-height: 42px !important;
  border-radius: 14px !important;
  padding: 0 15px !important;
  display: flex !important;
  align-items: center !important;
  justify-content: space-between !important;
  gap: 12px !important;
  background: rgba(255,255,255,.64) !important;
  border: 1px solid rgba(99,121,105,.14) !important;
  box-shadow: 0 7px 20px rgba(42,64,53,.035) !important;
  transition: transform .18s ease, border-color .18s ease, background .18s ease !important;
}

.aoun-ref-demo-user:hover {
  transform: translateX(-4px) !important;
  background: rgba(255,255,255,.9) !important;
  border-color: rgba(62,111,85,.28) !important;
}

.aoun-ref-demo-role {
  color: #416b55 !important;
  font-size: 13px !important;
  font-weight: 950 !important;
  white-space: nowrap !important;
}

.aoun-ref-demo-email {
  color: #697b86 !important;
  font-size: 12px !important;
  font-weight: 850 !important;
  direction: ltr !important;
  text-align: left !important;
}

.aoun-ref-footer {
  margin: 20px 0 0 !important;
  text-align: center !important;
  color: #9aa2a3 !important;
  font-size: 12px !important;
  font-weight: 800 !important;
}

.aoun-ref-hero {
  grid-area: hero !important;
  direction: rtl !important;
  width: 100% !important;
  max-width: 870px !important;
  margin: 0 auto !important;
  padding: 0 !important;
  display: flex !important;
  flex-direction: column !important;
  align-items: center !important;
  justify-content: center !important;
  text-align: center !important;
  background: transparent !important;
  animation: aounHeroFadeIn .9s ease both .12s;
}

.aoun-ref-logo {
  width: 220px !important;
  max-width: 220px !important;
  height: auto !important;
  margin: 0 auto 10px !important;
  object-fit: contain !important;
  filter: drop-shadow(0 18px 38px rgba(50,76,61,.12)) !important;
  animation: aounLogoFloat 4.5s ease-in-out infinite;
}

.aoun-ref-separator {
  width: 285px !important;
  max-width: 285px !important;
  margin: 8px auto 18px !important;
  display: grid !important;
  grid-template-columns: 1fr auto 1fr !important;
  align-items: center !important;
  gap: 16px !important;
  color: #54705f !important;
}

.aoun-ref-separator svg {
  animation: aounHeartPulse 2.6s ease-in-out infinite;
}

.aoun-ref-separator span {
  height: 1px !important;
  background: linear-gradient(90deg, transparent, rgba(84,112,95,.30), transparent) !important;
}

.aoun-ref-hero h2 {
  max-width: 760px !important;
  margin: 0 auto !important;
  color: #5a735f !important;
  font-size: clamp(26px, 2.1vw, 31px) !important;
  line-height: 1.55 !important;
  font-weight: 950 !important;
  letter-spacing: -0.035em !important;
}

.aoun-ref-source {
  margin: 4px 0 0 !important;
  color: #6d7f75 !important;
  font-size: 13px !important;
  font-weight: 900 !important;
}

.aoun-ref-description {
  max-width: 710px !important;
  margin: 18px auto 0 !important;
  color: #7c8587 !important;
  font-size: 15px !important;
  line-height: 1.9 !important;
  font-weight: 760 !important;
}

.aoun-ref-features {
  width: min(760px, 100%) !important;
  margin: 27px auto 0 !important;
  display: grid !important;
  grid-template-columns: repeat(4, minmax(0, 1fr)) !important;
  gap: 16px !important;
}

.aoun-ref-feature {
  min-height: 155px !important;
  padding: 18px 14px !important;
  border-radius: 19px !important;
  background: rgba(255,255,255,.70) !important;
  border: 1px solid rgba(99,121,105,.14) !important;
  box-shadow: 0 16px 42px rgba(42,64,53,.06) !important;
  transition: transform .25s ease, box-shadow .25s ease !important;
  animation: aounFeatureUp .75s ease both, aounFeatureFloat 5s ease-in-out infinite;
}

.aoun-ref-feature:nth-child(1) { animation-delay: .18s, 0s; }
.aoun-ref-feature:nth-child(2) { animation-delay: .26s, .45s; }
.aoun-ref-feature:nth-child(3) { animation-delay: .34s, .9s; }
.aoun-ref-feature:nth-child(4) { animation-delay: .42s, 1.35s; }

.aoun-ref-feature:hover {
  transform: translateY(-6px) !important;
  box-shadow: 0 24px 58px rgba(42,64,53,.10) !important;
}

.aoun-ref-feature div {
  width: 54px !important;
  height: 54px !important;
  margin: 0 auto 10px !important;
  border-radius: 50% !important;
  display: grid !important;
  place-items: center !important;
  color: #54705f !important;
  background: rgba(227,232,218,.76) !important;
}

.aoun-ref-feature h3 {
  margin: 0 !important;
  color: #4d6658 !important;
  font-size: 15px !important;
  line-height: 1.42 !important;
  font-weight: 950 !important;
}

.aoun-ref-feature p {
  margin: 7px auto 0 !important;
  color: #8a9290 !important;
  font-size: 12px !important;
  line-height: 1.65 !important;
  font-weight: 750 !important;
}

.aoun-ref-quote {
  width: 520px !important;
  max-width: 88% !important;
  margin-top: 24px !important;
  padding: 14px 26px !important;
  border-radius: 999px !important;
  color: #657a6d !important;
  font-size: 14px !important;
  font-weight: 850 !important;
  background: rgba(255,255,255,.56) !important;
  border: 1px solid rgba(99,121,105,.13) !important;
  box-shadow: 0 12px 32px rgba(42,64,53,.05) !important;
  animation: aounQuoteIn .8s ease both .52s;
}

@keyframes aounFrameIn {
  from { opacity: 0; transform: scale(.985); }
  to { opacity: 1; transform: scale(1); }
}

@keyframes aounCardSlideIn {
  from { opacity: 0; transform: translateX(-26px); }
  to { opacity: 1; transform: translateX(0); }
}

@keyframes aounHeroFadeIn {
  from { opacity: 0; transform: translateY(16px); }
  to { opacity: 1; transform: translateY(0); }
}

@keyframes aounFeatureUp {
  from { opacity: 0; transform: translateY(18px); }
  to { opacity: 1; transform: translateY(0); }
}

@keyframes aounFeatureFloat {
  0%, 100% { translate: 0 0; }
  50% { translate: 0 -5px; }
}

@keyframes aounLogoFloat {
  0%, 100% { transform: translateY(0) scale(1); }
  50% { transform: translateY(-7px) scale(1.01); }
}

@keyframes aounHeartPulse {
  0%, 100% { transform: scale(1); opacity: .75; }
  50% { transform: scale(1.18); opacity: 1; }
}

@keyframes aounQuoteIn {
  from { opacity: 0; transform: translateY(14px) scale(.98); }
  to { opacity: 1; transform: translateY(0) scale(1); }
}

@keyframes aounButtonGlow {
  0%, 100% { box-shadow: 0 14px 32px rgba(62,111,85,.22); }
  50% { box-shadow: 0 18px 44px rgba(62,111,85,.34); }
}

@keyframes aounFrameBreath {
  0%, 100% { opacity: .62; }
  50% { opacity: .9; }
}

@keyframes aounOrbMoveOne {
  0%, 100% { transform: translate(0,0) scale(1); }
  50% { transform: translate(18px,-12px) scale(1.04); }
}

@keyframes aounOrbMoveTwo {
  0%, 100% { transform: translate(0,0) scale(1); }
  50% { transform: translate(-18px,10px) scale(1.05); }
}

@keyframes aounBranchSway {
  0%, 100% { transform: rotate(-20deg) translateY(0); }
  50% { transform: rotate(-17deg) translateY(7px); }
}

@media (max-width: 1200px) {
  .aoun-ref-login-page {
    align-items: flex-start !important;
    padding: 22px !important;
  }

  .aoun-ref-login-page::before {
    inset: 16px !important;
    border-radius: 30px !important;
  }

  .aoun-ref-login-layout {
    width: min(980px, calc(100vw - 44px)) !important;
    min-height: auto !important;
    grid-template-columns: 1fr !important;
    grid-template-areas:
      "hero"
      "card" !important;
    gap: 28px !important;
    padding: 24px !important;
  }

  .aoun-ref-login-card {
    width: min(430px, 100%) !important;
    max-width: 430px !important;
    margin: 0 auto !important;
  }

  .aoun-ref-features {
    width: min(760px, 100%) !important;
    grid-template-columns: repeat(2, 1fr) !important;
  }
}

@media (max-width: 640px) {
  .aoun-ref-login-page {
    padding: 14px !important;
  }

  .aoun-ref-login-layout {
    width: calc(100vw - 28px) !important;
    padding: 18px !important;
    border-radius: 26px !important;
  }

  .aoun-ref-features {
    grid-template-columns: 1fr !important;
  }

  .aoun-ref-logo {
    width: 190px !important;
  }

  .aoun-ref-hero h2 {
    font-size: 24px !important;
  }
}

@media (prefers-reduced-motion: reduce) {
  .aoun-ref-login-layout,
  .aoun-ref-login-card,
  .aoun-ref-hero,
  .aoun-ref-logo,
  .aoun-ref-feature,
  .aoun-ref-quote,
  .aoun-ref-orb,
  .aoun-ref-branch.top,
  .aoun-ref-separator svg,
  .aoun-ref-login-btn {
    animation: none !important;
  }
}
'''

css = css + final_css

app_path.write_text(app, encoding="utf-8")
css_path.write_text(css, encoding="utf-8")

print("OK: Final Aoun UI applied successfully.")
print("Backups created with timestamp:", stamp)
