# CLAUDE.md — Kashef (KCSC ERPNext Mobile Client)

> **للذكاء الاصطناعي:** هذا الملف هو المرجع الوحيد لفهم المشروع. اقرأه كاملاً قبل أي تعديل.
> عند إجراء تغيير جوهري، **عدّل هذا الملف فوراً** وأضف إدخالاً في قسم [سجل التغييرات](#سجل-التغييرات).

---

## 1. هوية المشروع

| الحقل | القيمة |
|-------|--------|
| Package | `kcsc_ai` |
| Version | `1.0.0+1` (إصدار جديد — تمت إعادة التصفير 2026-06-23) |
| Flutter SDK | `≥ 3.11.3` |
| اللغة الافتراضية | العربية (RTL) |
| Backend | Frappe/ERPNext — `https://erpnext-16.kcsc.com.jo` |
| AI | Claude API (Anthropic) + MCP عبر Frappe |
| n8n | `https://n8n.kcsc.com.jo` |
| بيئة التطوير | Windows 11 |

**الوصف:** تطبيق Flutter متعدد المنصات (Android, iOS, Web, Desktop) يوفر واجهة موبايل لـ ERPNext الخاص بـ KCSC. يتيح تصفح مساحات العمل، عرض التقارير، لوحات المعلومات، والتفاعل مع مساعد ذكاء اصطناعي مبني على Claude عبر بروتوكول MCP. اسم المساعد الذكي: **Kashef (كاشف)**.

---

## 2. هيكل الملفات

```
lib/
├── main.dart                    # Entry point — AppColors، MyApp، HomePage، routing
├── auth_state.dart              # AuthState.isLoggedIn (in-memory، بلا استمرارية)
├── api_service.dart             # كل HTTP calls — المصدر الوحيد للتواصل مع ERPNext
├── app_colors.dart              # ثوابت الألوان — المرجع الرسمي (التعريف المكرر في main.dart حُذف)
├── app_localizations.dart       # نظام الترجمة EN/AR (190+ نص، يدوي)
├── app_drawer.dart              # القائمة الجانبية المشتركة
├── login_page.dart              # صفحة تسجيل الدخول الرئيسية
├── user_login_page.dart         # ⚠️ LEGACY — غير مستخدمة، لا تعدّلها
├── settings_page.dart           # إدارة الإعدادات والبيانات الاعتمادية
├── company_selection_page.dart  # تأكيد الشركة للجلسة
├── modules_page.dart            # عرض مساحات ERPNext (GridView، عمودان) — ⚠️ مخفية من التنقل (الملف محفوظ)
├── module_reports_page.dart     # قائمة التقارير — المرجع لنمط فحص الصلاحيات
├── module_permission_page.dart  # شاشة رفض الصلاحيات
├── report_view_page.dart        # عرض التقارير الديناميكي مع فلاتر
├── dashboards_page.dart         # قائمة لوحات المعلومات — search + responsive grid (2 أعمدة ≥700px) + ApiService.get() — ⚠️ مخفية من التنقل (الملف محفوظ)
├── dashboard_detail_page.dart   # عرض لوحة معلومات — fl_chart + FAC-first + responsive (sidebar web / scroll mobile) + Company filter + Pending widget — ⚠️ مخفية من التنقل (الملف محفوظ)
├── accounting_dashboard.dart    # ⚠️ UI ثابت — غير مكتمل، لا تُكمل بدون تنسيق
├── ai_assistant_page.dart       # مساعد Claude AI عبر MCP — القلب الذكي للتطبيق؛ بطاقات الموديولات الستة مُخفاة — شاشة ترحيب فقط
├── chat_history_page.dart       # عرض وتحميل سجل المحادثات المحفوظة في ERPNext (Note)
├── message_renderer.dart        # عرض غني: جداول HTML + رسوم fl_chart + أزرار PDF/Excel/بريد + `<open_document>` tags
├── workflow_models.dart         # نماذج بيانات: PendingDoc + WorkflowSource enum (facTool/workflowAction/dynamicScan)
├── fac_mcp_service.dart         # FAC MCP Direct Client — يستدعي أدوات FAC مباشرة بدون AI (Singleton)
├── fac_validator.dart           # FAC Permission Validation — has_permission + validateBeforeApply + canAccessDocType
├── workflow_repository.dart     # طبقة البيانات: SOURCE 0 (FAC) → A (Workflow Action) → B (Dynamic Scan)
├── workflow_service.dart        # Singleton — getWorkflow/getTransitions/applyWorkflow/safeApplyWorkflow
├── realtime_workflow_service.dart # Singleton — Socket.IO + Polling (WorkflowRepository) + listeners
├── document_viewer_page.dart    # عارض مستندات read-only — FAC runWorkflow → safeApplyWorkflow fallback
├── pending_approvals_page.dart  # قائمة الموافقات — FAC MCP HTTP مباشر + i18n كامل AR/EN + AppBar احترافي (white arrow + systemOverlayStyle + elevation) + subtitle
├── approved_page.dart           # المستندات المعتمدة — Workflow Action (Completed) + تجميع + Cancel عبر FAC + i18n كامل AR/EN + AppBar احترافي
├── n8n_chat_page.dart           # ⚠️ صفحة ثابتة — بدون أي API calls بعد إزالة كود المراقبة؛ تعرض زر انتقال لـ n8n Chat. الكلاس N8nChatPage محفوظ للتوافق مع المسار /n8n-chat
├── n8n_chat_service.dart        # N8nWebhookChatService — اتصال مباشر بـ n8n webhook + يقرأ URL من SharedPreferences ('n8n_chat_url' — يُضبط في Settings) + retry ×2 + timeout 15s + session ID + getWebhookUrl(). صفر dependency على ERPNext أو ApiService
└── n8n_webhook_chat_page.dart   # Chat Page معاد بناؤها من صفر — فقاعات user/bot + RTL تلقائي + typing dots + retry on error + suggestion chips + new chat + _NotConfiguredBanner (يظهر عند غياب URL في الإعدادات → زر فتح الإعدادات). معزولة تماماً

kcsc_erp/kcsc_erp/api/
├── mobile_api.py        # KCSC Mobile API — whitelisted ERPNext endpoints
└── n8n_proxy.py         # n8n Chat Proxy — يستقبل رسائل Flutter ويُحوّلها لـ n8n webhook server-side (يحل CORS)
                         #   Method: kcsc_erp.api.n8n_proxy.chat
                         #   Retry: حتى 3 محاولات عند Timeout/ConnectionError
                         #   Logging: frappe.log_error لكل نوع خطأ

images/
├── KCSC_Logo.png        # شعار قديم — محفوظ كمرجع
└── kashef_logo.jpeg     # الشعار الرسمي الحالي — أيقونة التطبيق + الشعار الافتراضي (خلفية بيضاء، أيقونة عين زرقاء)

test/
└── widget_test.dart             # اختبارات MyApp و AppColors
```

---

## 3. البنية المعمارية

### 3.1 إدارة الحالة
- **النمط:** `StatefulWidget` مباشر — **لا تُدخل** Provider / Bloc / Riverpod / GetX
- **في الذاكرة:** `AuthState.isLoggedIn` (تُفقد عند إغلاق التطبيق — سلوك مقصود)
- **دائم:** `SharedPreferences` لكل الإعدادات والبيانات الاعتمادية
- **Singleton Services:** `WorkflowService()` — استثناء مقصود لتخزين كاش الـ workflow بين الصفحات

### 3.2 تدفق البيانات
```
SharedPreferences ←→ Settings Page
Login Page → ApiService → AuthState → Navigator
كل الصفحات → ApiService → HTTP → Frappe/ERPNext API
AI Assistant → Claude API (مباشر) | MCP Endpoint (عبر Frappe)
n8n Chat → HTTP مباشر → n8n webhook (يتطلب CORS headers على nginx الخاص بـ n8n.kcsc.com.jo)

Pending Approvals → WorkflowRepository →
  SOURCE 0: FacMcpService → "Get Pending Approvals" tool → FAC MCP (JSON-RPC 2.0)
  SOURCE A: frappe.client.get_list → Workflow Action table
  SOURCE B: frappe.client.get_list → DocType scan → get_transitions

Document Viewer → FAC runWorkflow (إن وُجد) | safeApplyWorkflow fallback
```

**Singleton Services** (مشتركة بين جميع الصفحات):
- `WorkflowService()` — كاش per-doctype للـ workflow metadata والـ transitions
- `WorkflowRepository()` — يجمع SOURCE 0/A/B، كاش 30s/60s، dedup، pagination
- `FacMcpService()` — يدير جلسة MCP مع FAC، كاش tools list
- `RealtimeWorkflowService()` — Socket.IO + polling، listeners للتحديث الفوري

### 3.3 التوجيه (Routing)
تعريف في `MaterialApp.routes` داخل `main.dart`، حماية يدوية في كل صفحة:

| المسار | النوع | ملاحظة |
|--------|-------|---------|
| `/` | عام | الصفحة الرئيسية |
| `/login` | عام | |
| `/settings` | عام | |
| `/dashboard` | 🔒 محمي | |
| `/company-selection` | 🔒 محمي | |
| `/modules` | 🔒 محمي | ⚠️ مخفي من التنقل — المسار محفوظ |
| `/ai-assistant` | أداة | Claude + MCP |
| `/n8n-chat` | أداة | صفحة ثابتة (placeholder) — بدون API calls — تُحوّل لـ /n8n-webhook-chat |
| `/n8n-webhook-chat` | أداة | `N8nWebhookChatPage` — واجهة دردشة مع n8n webhook |
| `/document-viewer` | 🔒 محمي | `arguments: {'doctype': X, 'docname': Y}` → `DocumentViewerPage` |
| `/pending-approvals` | 🔒 محمي | `PendingApprovalsPage` — Workflow Actions للمستخدم الحالي |
| `/approved-approvals` | 🔒 محمي | `ApprovedApprovalsPage` — Workflow Action (Completed) آخر 30 يوم + Cancel عبر FAC |

**مرجع الحماية:** راجع `ModuleReportsPage` لنمط فحص الصلاحيات قبل التنقل.

---

## 4. خدمة API (`api_service.dart`)

### 4.1 المصادقة
| الطريقة | الآلية | الأولوية |
|---------|--------|---------|
| Token-based | `Api-Key` + `Api-Secret` في header | **الأعلى** |
| Session-based | `POST /api/method/login` → `sid` + `csrf_token` من cookie | الافتراضي |

- **Auto-retry:** تلقائياً عند 401 / 403
- **Timeout:** 15 ثانية (GET) — 30 ثانية (POST)
- **قاعدة:** لا تستخدم `http.get/post` مباشرة خارج `ApiService` أبداً

### 4.2 نقاط API المستخدمة

| الوظيفة | Method | Endpoint |
|---------|--------|---------|
| تسجيل الدخول | POST | `/api/method/login` |
| مساحات العمل | GET | `/api/method/frappe.desk.desktop.get_workspace_sidebar_items` |
| قائمة التقارير | GET | `/api/resource/Report` |
| فلاتر التقرير | GET | `/api/method/frappe.desk.query_report.get_script` |
| فحص الصلاحيات | GET | `/api/resource/{doctype}?limit=1` |
| قائمة الداشبوردات | GET | `/api/resource/Dashboard` |
| بيانات الداشبورد | GET | `/api/method/frappe.desk.doctype.dashboard_chart.dashboard_chart.get` |
| **إنشاء Dashboard Chart** | **POST** | **`/api/resource/Dashboard Chart`** |
| MCP | POST | `/api/method/{ai_endpoint}` |
| Claude API | POST | `https://api.anthropic.com/v1/messages` |
| **فحص Workflow نشط** | **GET** | **`/api/resource/Workflow?filters=[["document_type","=","X"],["is_active","=",1]]`** |
| **انتقالات Workflow المتاحة** | **POST** | **`/api/method/frappe.model.workflow.get_transitions`** — body: `{'doc': jsonEncode(doc)}` |
| **تطبيق إجراء Workflow** | **POST** | **`/api/method/frappe.model.workflow.apply_workflow`** — body: `{'doc': jsonEncode(doc), 'action': action}` |
| **موافقات معلقة (SOURCE A)** | **POST** | **`/api/method/frappe.client.get_list`** — `doctype: Workflow Action, filters: [status=Open, user=me]` |
| **فحص صلاحية قراءة** | **GET** | **`/api/method/frappe.client.has_permission?doctype=X&docname=Y&ptype=read`** — يُعيد `{message: 1}` |
| **تقديم مستند (Submit)** | **POST** | **`/api/method/frappe.client.submit`** — fallback عند غياب workflow |
| **إلغاء مستند (Cancel)** | **POST** | **`/api/method/frappe.client.cancel`** — fallback عند غياب workflow |
| **عدد الموافقات (Realtime)** | **POST** | **`/api/method/frappe.client.get_list`** — `fields:['name']` فقط لحساب العدد |
| **FAC MCP — تهيئة** | **POST** | **`/api/method/{ai_endpoint}`** — body: `{jsonrpc: "2.0", method: "initialize", params: {...}}` |
| **FAC MCP — قائمة الأدوات** | **POST** | **`/api/method/{ai_endpoint}`** — body: `{method: "tools/list", params: {}}` |
| **FAC MCP — استدعاء أداة** | **POST** | **`/api/method/{ai_endpoint}`** — body: `{method: "tools/call", params: {name: "...", arguments: {...}}}` |
| **FAC — Get Pending Approvals** | **POST** | عبر FAC MCP بالاسم الحرفي `"Get Pending Approvals"` — يُعيد قائمة المستندات المعلقة |

### 4.3 معالجة الأخطاء
```dart
final result = await apiService.get('/api/resource/...');
// تحقق دائماً من:
if (result['exc'] != null) { /* استثناء Frappe */ }
if (result['message'] == null) { /* استجابة فارغة */ }
```

---

## 5. نظام الإعدادات (SharedPreferences)

> ⚠️ **أمان:** المفاتيح الحساسة مخزنة كـ plaintext. للإنتاج: استبدل بـ `flutter_secure_storage`.

```dart
// ── ERPNext ─────────────────────────────────────
'erpnext_url'             // https://erpnext-16.kcsc.com.jo
'erpnext_username'
'erpnext_password'        // ⚠️ حساس
'erpnext_company'         // اقرأ دائماً من هنا، لا تطلبها من المستخدم
'erpnext_api_key'         // اختياري — أولوية على كلمة المرور
'erpnext_api_secret'      // ⚠️ حساس
'erpnext_session_cookie'  // sid — ينتهي بانتهاء الجلسة
'erpnext_csrf_token'

// ── الذكاء الاصطناعي ────────────────────────────
'ai_provider'             // 'claude' | 'chatgpt' | 'claude_first' | 'chatgpt_first' — الوضع المختار (افتراضي: claude)
'claude_api_key'          // ⚠️ حساس — مفتاح Anthropic
'ai_endpoint'             // مسار MCP على الخادم
'ai_model'                // نموذج Claude المختار — انظر §7
'chatgpt_api_key'         // ⚠️ حساس — مفتاح OpenAI لـ ChatGPT
'chatgpt_model'           // نموذج ChatGPT (gpt-5-mini | gpt-4.5-preview | gpt-4o | gpt-4o-mini | gpt-4-turbo | gpt-3.5-turbo | o1 | o3-mini)
'openai_api_key'          // ⚠️ حساس — مفتاح OpenAI لـ Whisper STT (اختياري)

// ── n8n ─────────────────────────────────────────
'n8n_chat_url'            // Webhook URL — يُقرأ من N8nWebhookChatService.getWebhookUrl() ويُستخدم في الاتصال المباشر بـ n8n
'n8n_api_key'             // ⚠️ حساس — غير مستخدم حالياً (كان لـ REST API المحذوف)
'n8n_session_id'          // session ID للـ chat — يُولَّد تلقائياً عند أول تشغيل ويبقى ثابتاً

// ── التطبيق ─────────────────────────────────────
'app_language'            // 'ar' | 'en'
'custom_logo_path'        // مسار ملف الشعار المخصص (فارغ = kashef_logo.jpeg الافتراضي)

// ── المحادثات ────────────────────────────────────
'active_ai_module'        // اسم الموديول النشط (HR / Accounting / ...)
'active_ai_module_label'  // اسم العرض للموديول النشط
'persisted_chat_claude'   // آخر 10 رسائل claude (JSON) — استئناف بدون HTTP
'persisted_chat_openai'   // آخر 10 رسائل openai (JSON) — استئناف بدون HTTP
```

---

## 6. نظام التقارير

### 6.1 تحميل الفلاتر (أولوية تنازلية)
```
1. get_script              → تحليل JavaScript لاستخراج الفلاتر (الأدق)
2. get_filters_and_columns → فلاتر مباشرة من API
3. Fallback                → نطاق تاريخ + شركة (الحد الأدنى)
```

### 6.2 أنواع الفلاتر

| النوع | الوصف |
|-------|-------|
| `link` | بحث وربط بـ doctype |
| `select` | قائمة منسدلة |
| `date` | منتقي تاريخ |
| `data` | نص حر |
| `custom` | مُحلَّل من JavaScript |

### 6.3 استمرارية الفلاتر (SharedPreferences)
```
مفتاح القيم:        report_filters_{اسم_التقرير}
مفتاح التعريفات:    report_defs_{اسم_التقرير}

_saveFilters()      → تُستدعى قبل كل تشغيل للتقرير (قيم)
_loadSavedFilters() → تُستدعى بعد تحميل تعريفات الفلاتر (قيم)
_saveDefs()         → تُستدعى بعد جلب التعريفات من الخادم (تعريفات)
_loadCachedDefs()   → تُستدعى عند فتح التقرير — تتخطى HTTP إن وُجدت (تعريفات)
```
- **التعريفات**: تُخزَّن كـ JSON بعد أول جلب. تفتح الشاشة فوراً دون HTTP.
- **زر Refresh** في AppBar يجبر إعادة الجلب من الخادم (`forceRefresh: true`).
- **القيم المحفوظة** تُطبَّق **فوق** الـ defaults
- حقل `Company` (Link → Company) **لا يُحفظ** — دائماً من الإعدادات
- قيم `Fiscal Year` تُعبَّأ تلقائياً بالسنة الحالية عند أول فتح

### 6.4 معالجة أخطاء التحقق (auto-heal)
| الخطأ | الإجراء |
|-------|---------|
| `Start Year and End Year are mandatory` | إضافة `start_year` + `end_year` كـ Link → Fiscal Year |
| `From Date and To Date are mandatory` | إضافة `period_start_date` + `period_end_date` |
| `KeyError: None` | إضافة `filter_based_on` + `periodicity` |
| `Missing required filter: X` | إضافة الحقل X تلقائياً |

### 6.5 عرض النتائج
- جدول قابل للتمرير (أفقياً وعمودياً)
- عدد أعمدة ديناميكي
- شارة بعدد الصفوف

---

## 7. المساعد الذكي — AI Assistant (`ai_assistant_page.dart`)

### 7.1 اختيار المزود (Claude أو ChatGPT)
المزود يُحدَّد من الإعدادات (`ai_provider`). كلا المزودَين يستخدمان نفس MCP Server لجلب الأدوات وتنفيذها.

```
[1] initialize     → إنشاء جلسة MCP مع الخادم
[2] tools/list     → جلب الأدوات المتاحة (FAC MCP — 23 أداة)
[3] AI API         → إرسال الرسالة + قائمة الأدوات (Claude أو ChatGPT)
[4] tool_use       → AI يقرر أداة وينفذها عبر MCP
[5] tool_result    → نتيجة الأداة تُرسل للـ AI
[6] تكرار          → حتى stop_reason == "end_turn" (Claude) أو finish_reason == "stop" (ChatGPT)
```

**فرق التنسيق بين المزودَين:**
| | Claude | ChatGPT |
|---|---|---|
| tool format | `input_schema` | `parameters` داخل `function` |
| tool result | `role:user` + `type:tool_result` | `role:tool` + `tool_call_id` |
| stop signal | `stop_reason: end_turn` | `finish_reason: stop` |
| history | `_claudeHistory` | `_openAiHistory` |

### 7.2 النماذج المدعومة

**Claude:**
| النموذج | الاستخدام |
|---------|---------|
| `claude-sonnet-4-6` | **الافتراضي** — أفضل توازن للـ agentic tasks |
| `claude-opus-4-6` | للمهام المعقدة |
| `claude-haiku-4-5` | للاستجابة السريعة |

**ChatGPT:**
| النموذج | الاستخدام |
|---------|---------|
| `gpt-5-mini` | أحدث — GPT-5 Mini |
| `gpt-4.5-preview` | GPT-4.5 Preview |
| `gpt-4o` | **الافتراضي** — أفضل توازن |
| `gpt-4o-mini` | أسرع وأقل تكلفة |
| `gpt-4-turbo` | GPT-4 Turbo |
| `gpt-3.5-turbo` | للاستجابة السريعة |
| `o1` | استدلال متقدم |
| `o3-mini` | استدلال سريع |

### 7.3 ميزات
- **اختيار المزود** — Claude أو ChatGPT من الإعدادات، يظهر النموذج الحالي في AppBar
- **أولوية المزود** — 4 أوضاع: Claude فقط / ChatGPT فقط / Claude أولاً (fallback) / ChatGPT أولاً (fallback)
- **FAC أولاً دائماً** — النظام يعتمد على أدوات FAC/MCP كأولوية قصوى لكل العمليات
- **إرسال البريد الإلكتروني عبر FAC** — AI يكتشف أدوات البريد في FAC ويستخدمها مباشرة
- **تصدير الملفات عبر FAC** — Excel/PDF/Word/CSV عبر أدوات FAC المتاحة
- **إرسال صوتي تلقائي** — تسجيل m4a (Android) أو webm/opus (Web) عبر `record` → Whisper API → نص → إرسال؛ يستخدم `kIsWeb` للتفريق بين المنصتين
- **عرض الجداول HTML-style** — `_HtmlTable` (DataTable + SingleChildScrollView horizontal)
- **عرض الرسوم البيانية** — `<chart>JSON</chart>` → fl_chart (bar/line/pie)
- **AI يسأل عن نوع الرسم أولاً** — إذا حدّد المستخدم النوع ولديه البيانات يولّد فوراً
- **حفظ الرسم في ERPNext** — زر "حفظ في الداشبورد" → `Dashboard Chart` (نوع Custom)
- **سياق الشركة تلقائي** — اسم الشركة من SharedPreferences يُدمج في كل prompt
- تاريخ المحادثة في الذاكرة (per-session، maxHistory=60) — منفصل لكل مزود
- **حفظ تلقائي في ERPNext** — كل رسالة تُحفظ فوراً كـ Note (تنسيق AICHAT_V1)
- **استئناف المحادثات** — `chat_history_page.dart` يعرض السجل السابق ويُعيد تحميله
- **ذاكرة بين الجلسات** — آخر 10 رسائل تُحفظ في SharedPreferences وتُستعاد فوراً بدون HTTP
- **شاشة ترحيب نظيفة** — بطاقات الموديولات الستة (Purchasing/Accounting/HR/Inventory/Manufacturing/Sales) مُخفاة بالكامل — `_ModuleInfo`/`_ModuleCard`/`_modules` محذوفة، `_InlineModuleGrid` → `SizedBox.shrink()`
- **رسالة ترحيب احترافية** — تُحقن تلقائياً عند الفتح/المحادثة الجديدة/تغيير الموديول
- **Module Specialization** — زر موديولات في AppBar يفعّل وكيلاً متخصصاً لكل موديول
- **دعم مرفقات متعددة** — كاميرا/معرض/ملف/ملفاتي في النظام/من المحادثة (WhatsApp style)
- **زر Stop** — إيقاف الـ AI فوراً بين tool calls أثناء المعالجة
- **رفع الملفات إلى ERPNext** — قبل إرسالها للـ AI مع تمرير file_url للـ AI
- إعادة المحاولة تلقائياً عند انتهاء الجلسة (session expiry)
- **RULE 5 — Workflow & Document Viewer** — AI يُدرج `<open_document doctype="X" docname="Y"/>` عند ذكر مستند محدد؛ يستخدم `run_workflow` FAC أولاً ثم يفتح الـ viewer كـ fallback

### 7.4 تنسيق Dashboard Chart عند الحفظ
```dart
POST /api/resource/Dashboard Chart
{
  "chart_name": "عنوان الرسم",
  "chart_type": "Custom",
  "type": "Bar|Line|Pie",
  "custom_options": "{\"data\":{\"labels\":[...],\"datasets\":[{\"name\":\"...\",\"values\":[...]}]},\"type\":\"bar\"}"
}
// datasets: AI يستخدم "label"+"data"، Frappe يحتاج "name"+"values"
```

### 7.5 نقاط الاتصال
- **MCP عبر Frappe:** `POST {erpnext_url}/api/method/{ai_endpoint}`
- **Claude مباشر:** `POST https://api.anthropic.com/v1/messages`
- **ChatGPT مباشر:** `POST https://api.openai.com/v1/chat/completions`

### 7.6 دعم Workflow الديناميكي — البنية الكاملة

#### نموذج البيانات (`workflow_models.dart`)
```dart
enum WorkflowSource {
  facTool,        // SOURCE 0 — FAC "Get Pending Approvals" (أعلى أولوية)
  workflowAction, // SOURCE A — Workflow Action record
  dynamicScan,    // SOURCE B — اكتُشف بمسح DocType مباشرة
}

class PendingDoc {
  final String doctype;
  final String docname;
  final String workflowState;
  final String creation;
  final WorkflowSource source;
  String get key => '$doctype::$docname'; // مفتاح dedup
  String get creationShort => ...;        // YYYY-MM-DD
}
```

#### FAC MCP Client (`fac_mcp_service.dart`)
Singleton يستدعي FAC مباشرة بدون AI عبر JSON-RPC 2.0.

```dart
FacMcpService().getPendingApprovals()        // → List<PendingDoc>? (null = FAC غير متاح)
FacMcpService().runWorkflow(doc, action)     // → Map? (null = أداة غير موجودة)
FacMcpService().getDocument(doctype, name)   // → Map? (get_document tool)
FacMcpService().fetch(args)                  // → dynamic (fetch tool)
FacMcpService().search(args)                 // → dynamic (search tool)
FacMcpService().searchDoctype(args)          // → dynamic (search_doctype tool)
FacMcpService().listAvailableTools()         // → List<String> (للتشخيص)
FacMcpService().reset()                      // عند logout
```

**أسماء الأدوات الحرفية (مؤكدة من tools/list) — حساسة لحالة الأحرف:**
```
get_pending_approvals   ← الاسم الحرفي الصحيح (وليس "Get Pending Approvals")
run_workflow
get_document
fetch
search
search_doctype
```

**⚠️ تحذير حرج:** اسم الأداة حساس لحالة الأحرف والشرطات السفلية.  
`"get_pending_approvals"` ≠ `"Get Pending Approvals"` حتى بعد `toLowerCase()`.  
أي خطأ في الاسم يجعل `_facAvailable = false` ويسقط النظام لـ SOURCE A + B.

- **اكتشاف بـ exact match:** `_findTool()` يبحث بمطابقة حرفية كاملة (لا `contains()`)
- **Auto-login:** يعيد تسجيل الدخول تلقائياً عند 401/403
- **`_facAvailable` reset:** يُعاد ضبطه في `WorkflowRepository.invalidate()` لإعادة المحاولة
- **Debug logging:** كل خطوة مُسجَّلة (`debugPrint`) بما فيها أسماء الأدوات المتاحة

#### FAC Permission Validator (`fac_validator.dart`)
```dart
FacValidator().hasReadPermission(doctype, docname)  // → bool
FacValidator().getValidatedTransitions(doc)          // → List<WorkflowTransition>
FacValidator().validateBeforeApply(doc, action)      // → String? (null = مسموح)
FacValidator().canAccessDocType(doctype)             // → bool
```

#### WorkflowRepository (`workflow_repository.dart`)
طبقة البيانات المركزية — تجمع ثلاثة مصادر وتُعيد قائمة مُرتَّبة مُرقَّمة.

```
SOURCE 0 (FAC)  → FacMcpService().getPendingApprovals()   — كاش 30 ث
SOURCE A         → frappe.client.get_list(Workflow Action) — كاش 30 ث
SOURCE B         → DocType scan + get_transitions          — كاش 60 ث (خلفية)

أولوية الدمج: SOURCE 0 > SOURCE A > SOURCE B (dedup بـ doctype::docname)
```

```dart
WorkflowRepository().fetchPending(userId, ...)  // → List<PendingDoc> (paginated)
WorkflowRepository().fetchCount(userId)          // → int (للشارات)
WorkflowRepository().uniqueDoctypes()            // → List<String> (للفلاتر)
WorkflowRepository().invalidate()               // مسح كامل (بعد workflow action)
WorkflowRepository().invalidateA()              // مسح SOURCE 0+A فقط (realtime)
```

**SOURCE B — قواعد المسح:**
- يجلب DocTypes نشطة عليها workflow (`is_active=1`)
- لكل DocType: `docstatus != 2` + limit=30 + استثناء الحالات الختامية
- لكل مستند: `get_transitions()` → إذا فارغة → تجاهل

#### WorkflowService (`workflow_service.dart`)
Singleton مشترك. كاش per-doctype للـ workflow metadata.

```dart
WorkflowService().getWorkflowForDocType(doctype)   // → WorkflowInfo? (null = لا workflow)
WorkflowService().getTransitions(doc)              // → List<WorkflowTransition>
WorkflowService().applyWorkflow(doc, action)       // → Map (updated doc)
WorkflowService().safeApplyWorkflow(doc, action)   // → Map — يتحقق FAC أولاً، يمنع 417
WorkflowService().invalidate(doctype)              // مسح كاش doctype محدد
WorkflowService().invalidateAll()                  // مسح كامل (logout)
```

#### DocumentViewerPage (`document_viewer_page.dart`)
- يُحمَّل بـ `Navigator.pushNamed(context, '/document-viewer', arguments: {'doctype': X, 'docname': Y})`
- `_smartFields()`: يُخفي حقول النظام الداخلية، يُقدّم `_priorityFields` أولاً، حد 12 حقلاً
- `workflowStateColor(state)`: green=approve/active، red=reject/cancel، amber=pending/open، blue=default
- إذا workflow نشط → أزرار الانتقالات الديناميكية (Wrap layout)
- إذا لا workflow → أزرار docstatus (Submit/Cancel حسب الحالة)
- **تنفيذ الإجراء:** `FacMcpService().runWorkflow()` أولاً → `safeApplyWorkflow()` fallback
- زر تأكيد قبل تنفيذ أي إجراء + Snackbar بالنتيجة

#### PendingApprovalsPage (`pending_approvals_page.dart`)
- **HTTP مباشر** — يستدعي MCP endpoint مباشرةً بدون WorkflowRepository أو FacMcpService
- **`_mcpPost(endpoint, method, params)`** — top-level helper يستخدم `ApiService.getAiAuthHeaders()` + `ApiService.getErpNextUrl()` بنفس pattern `_mcpRequest`: يتحقق من كل status codes (401→re-login تلقائي، غير 200→throw)، يكتشف `exc_type`/`_server_messages`
- **`_extractPa(rpc)`** — Universal extractor يدعم 6 أشكال لاستجابة FAC بالأولوية:
  - CASE 1: `rpc.result.content[0].text` (JSON string) — الأكثر شيوعاً
  - CASE 2: `rpc.message` (JSON string)
  - CASE 3: `rpc.message` (Map مباشر)
  - CASE 4: `rpc.pending_approvals` (جذر مباشر)
  - CASE 5: `rpc.result.structuredContent`
  - CASE 6: `rpc.data` (nested)
- **`_fetchFac()`**: initialize (non-fatal) → `tools/call get_pending_approvals` → `_extractPa()` → parse `document_name/workflow_state/available_actions`
- **`_fetchFallback()`**: `ApiService.postForm(frappe.client.get_list, Workflow Action)` — بدون `action` field
- **`_executeAction()`**: dialog تأكيد → FAC `run_workflow` عبر `_mcpPost` → `WorkflowService().safeApplyWorkflow` fallback
- **State:** `Map<String, List<_Doc>> _data` + `bool _isFallback` + `bool _busy` (guard ضد تداخل الطلبات)
- **`_Item` model:** flat list builder — `_Item.header` / `_Item.doc` / `_Item.spacer`
- **Skeleton loading:** `_SkeletonCard` مع `AnimationController` pulsing (0.35→0.8 opacity)
- **Filter chips:** دائماً مرئية (حتى عند doctype واحد) — `l.wfAllTypes` + chip لكل DocType
- **الألوان:** `AppColors` كاملة — Approve=`AppColors.success`، Reject=`AppColors.error`، غيره=`AppColors.warning`؛ Card border=`c.surfaceHigh` لضمان الرؤية في dark mode
- **Count badge** برتقالي في AppBar | **Group header:** `c.primary` + count pill بـ `c.onPrimary`
- **Card:** `c.surface` + `c.surfaceHigh` border + `c.textPrimary` للنص — لا white-on-white في أي ثيم
- **بحث:** TextField debounce 300ms على `name + state`؛ `_busy` flag يمنع تداخل `_load()` المتزامن
- Auto-refresh 30s + `RealtimeWorkflowService().addListener()` + pull-to-refresh + card tap → `/document-viewer`
- Debug logging شامل في كل مرحلة: FAC response، parser case، parsed count، rebuild، filter results

#### RealtimeWorkflowService (`realtime_workflow_service.dart`)
- Socket.IO → `workflow_update` event → `broadcastLocal()` → `WorkflowRepository.invalidate()`
- Polling كل 15 ث → `WorkflowRepository.fetchCount()` (SOURCE 0+A)
- `_facAvailable` flag — يُعطّل SOURCE 0 بعد أول فشل (يُفعّل من جديد عند `reset()`)
- Fallback عند فشل Socket.IO (token auth / CORS)

#### تكامل مع AI Chat
- System prompt RULE 5: AI يُدرج `<open_document doctype="X" docname="Y"/>` عند ذكر مستند محدد
- `message_renderer.dart` يحلّل الـ tag ويُظهر `_OpenDocumentButton` (بطاقة مادية قابلة للضغط)
- `_openDocument()` في `ai_assistant_page.dart` تنتقل لـ `/document-viewer`

#### تكامل مع صفحة التقارير
- `report_view_page.dart` يجلب `ref_doctype` من بيانات التقرير
- صفوف الجدول قابلة للضغط إذا وُجد `ref_doctype` + عمود `name`
- الضغط ينتقل مباشرة لـ `DocumentViewerPage(doctype: _refDoctype, docname: docname)`

### 7.7 نظام لوحات المعلومات (Dashboard System)

#### dashboards_page.dart — قائمة اللوحات
- `ApiService.get('/api/resource/Dashboard')` — جلب الكل، تجميع حسب module
- Search bar مع clear button + Responsive grid (`LayoutBuilder` — عمودان ≥700px)
- Pull-to-refresh + silent auto-refresh كل 5 دقائق
- `Material + InkWell` بدل `ListTile` لتأثير ضغط صحيح

#### dashboard_detail_page.dart — تفاصيل اللوحة

**طبقة `_DashService` (FAC-first + ERPNext fallback + 5-min cache):**
```dart
_DashService.fetchChartMeta(chartName)     // metadata + filters من ERPNext
_DashService.fetchChartData(chartName, {   // data من frappe.desk.dashboard_chart.get
  timespan, timegrain, useDateRange,
  fromDate, toDate, company, extraFilters
})
_DashService.fetchPendingCount()           // FAC أولاً → ERPNext fallback
_DashService.fetchCompanies()             // قائمة الشركات لـ dropdown
_DashService.invalidate()                 // مسح كاش كامل
```

**أنواع الـ Widgets:**
| Widget | الوصف |
|--------|-------|
| `_KpiCard` | Count/Sum/Average — رقم كبير + أيقونة |
| `_BarChartCard` | fl_chart BarChart — touch + tooltip |
| `_LineChartCard` | fl_chart LineChart — isCurved + area fill |
| `_PieChartCard` | fl_chart PieChart/Donut — legend + touch |
| `_DataTableCard` | DataTable قابل للتوسع (5 صفوف → الكل) |
| `_PendingWidget` | عدد الموافقات + رابط لـ `/pending-approvals` |

**Responsive Layout:**
- `< 768px` → `CustomScrollView` عمودي + `_FilterStrip` أعلى + bottom sheet للفلاتر
- `≥ 768px` → `Row`: `_FilterSidebar` (220px، قابل للطي 48px) + grid (2 أو 3 أعمدة)

**نظام الفلاتر:**
- **عالمي:** Company (dropdown) + Timespan (Last Week/Month/Quarter/Year) + Timegrain (Daily→Yearly) + Date Range (custom)
- **per-chart:** `_ChartFiltersSheet` — تعديل يدوي للفلاتر [fieldname, op, value]
- حفظ في `SharedPreferences` عبر مفتاح `erpnext_company`

**AppBar:** `iconTheme(white)` + `systemOverlayStyle.light` + `elevation:2` + subtitle آخر تحديث

#### n8n Workflow Automation Dashboard (`n8n_chat_page.dart`)

> **نوع الصفحة:** لوحة تحكم كاملة — ليست chat page بعد الآن. الكلاس `N8nChatPage` محفوظ للتوافق مع المسار `/n8n-chat`.

**⚠️ الصفحة أصبحت Placeholder ثابت (2026-05-22):**
- تم إزالة كل كود مراقبة n8n (workflows/executions/stats/API calls) بسبب CORS errors على Flutter Web
- الصفحة الآن `StatelessWidget` بدون أي HTTP calls
- تعرض زراً واحداً ينتقل للمستخدم إلى `/n8n-webhook-chat`
- الكلاس `N8nChatPage` محفوظ للتوافق مع المسار `/n8n-chat` في main.dart

**لا توجد SharedPreferences** — الصفحة ثابتة بالكامل.

#### n8n Webhook Chat Interface (`n8n_webhook_chat_page.dart` + `n8n_chat_service.dart`)

> **نوع الصفحة:** واجهة دردشة WhatsApp/ChatGPT كاملة متصلة بـ n8n webhook مباشرة. المسار: `/n8n-webhook-chat` ← `DrawerSection.n8nWebhookChat`.

**`N8nWebhookChatService` — طبقة الخدمة (`n8n_chat_service.dart`):**
```dart
N8nWebhookChatService.getWebhookUrl()          // يقرأ 'n8n_chat_url' من SharedPreferences
N8nWebhookChatService.instance.sendMessage({message, sessionId, language})
                                               // يقرأ URL تلقائياً → HTTP POST مباشر + retry ×2
N8nWebhookChatService.loadOrCreateSession()    // جلب/إنشاء session ID ('n8n_session_id')
N8nWebhookChatService.resetSession()           // توليد session ID جديد (New Chat)
```

**⚠️ سلوك عند غياب الـ URL:**
- `sendMessage()` يرمي `Exception('n8n_not_configured')` فوراً
- الـ chat page تتحقق عند الفتح → تعرض `_NotConfiguredBanner` مع زر "فتح الإعدادات"

**معمارية الاتصال (بعد 2026-05-22):**
```
Flutter Web/Mobile
    ↓  http.post مباشر (يحتاج CORS headers على n8n nginx)
POST https://n8n.kcsc.com.jo/webhook/.../chat
    ↓  n8n يُعالج الطلب ويتصل بـ ERPNext من جانبه
Response: {"output": "bot reply"}
```

**⚠️ شرط CORS:** يجب إضافة هذا في nginx الخاص بـ n8n.kcsc.com.jo:
```nginx
location /webhook/ {
    if ($request_method = 'OPTIONS') {
        add_header Access-Control-Allow-Origin  'https://poc.kcsc.com.jo';
        add_header Access-Control-Allow-Methods 'POST, OPTIONS';
        add_header Access-Control-Allow-Headers 'Content-Type, Accept';
        add_header Content-Length 0;
        return 204;
    }
    add_header Access-Control-Allow-Origin  'https://poc.kcsc.com.jo' always;
    add_header Access-Control-Allow-Methods 'POST, OPTIONS'           always;
    add_header Access-Control-Allow-Headers 'Content-Type, Accept'    always;
    proxy_pass http://127.0.0.1:5678;
}
```

**Request/Response:**
```json
// طلب (JSON مباشر)
{"message": "...", "session_id": "kcsc_..._xxx", "language": "ar | en"}
// رد من n8n
{"output": "bot reply"}
```

**مكوّنات الصفحة:**
| Widget | الوصف |
|--------|-------|
| `_MessageBubble` | فقاعة الرسالة — يمين للمستخدم (`c.userBubble`)، يسار للبوت (`c.surface`) + `_detectDir()` للـ RTL |
| `_TypingBubble` | فقاعة "n8n يفكر…" مع `_TypingDots` pulsing (scale + opacity) |
| `_TypingDots` | ثلاث نقاط متحركة بـ `AnimationController` — phase offset 0.22 لكل نقطة |
| `_SendBtn` | دائرة متحركة — spinner أثناء التحميل، `Icons.send_rounded` في الوضع العادي |
| `_EmptyState` | avatar + عنوان + 3 `_SuggestionChip` جاهزة للضغط |
| `_SuggestionChip` | chip بحدود `c.primary` + أيقونة bolt تُرسل الرسالة مباشرة |

**الأنيميشن:**
- `TweenAnimationBuilder<double>` per new message: fade-in + slide من جهة المُرسِل (±28px)، مدة 380ms
- مفتاح `ValueKey('anim_${msg.id}')` يمنع إعادة التشغيل عند `setState`
- بعد 650ms يُزال الـ ID من `_animatingIds` → widget يصبح ثابت بدون أثر بصري

**الميزات:**
- **RTL تلقائي** — `_detectDir()` تفحص أول code-point: نطاق عربي/عبري → `TextDirection.rtl`
- **Long-press copy** — `Clipboard.setData` + SnackBar على كل فقاعة
- **Session** — `Random.secure()` + timestamp → `kcsc_{ms}_{12chars}` محفوظ في `n8n_webhook_session_id`
- **Retry** — حتى 2 محاولات مع backoff 1s/2s قبل عرض رسالة الخطأ
- **New Chat** — Dialog تأكيد → `resetSession()` → مسح القائمة
- **Suggestion chips** — 3 اقتراحات جاهزة تُرسل فوراً عند الضغط (i18n: `n8nSuggestion1/2/3`)

**مفاتيح i18n المُضافة (12 مفتاح):**
`n8nChatTitle` / `n8nChatSubtitle` / `n8nThinking` / `n8nChatError` / `n8nChatErrorBadge` / `n8nChatPlaceholder` / `n8nChatEmpty` / `n8nNewChat` / `n8nNewChatConfirm` / `n8nSuggestion1` / `n8nSuggestion2` / `n8nSuggestion3`

**SharedPreferences المُستخدمة:**
- `n8n_webhook_session_id` — session ID (يُحفظ عند أول تشغيل، يُجدَّد عند New Chat)

**Drawer:**
- `DrawerSection.n8nWebhookChat` جديد في enum
- `_NavItem(icon: support_agent_rounded, label: l.n8nChatTitle)` تحت n8n Dashboard

**ملاحظة:** الصفحة تتصل بـ n8n **مباشرةً** عبر `http.post` — صفر dependency على `ApiService` أو ERPNext. n8n نفسه يتولى الاتصال بـ ERPNext من جانب السيرفر. يتطلب CORS headers على nginx الخاص بـ n8n.kcsc.com.jo.

---

## 8. نظام الألوان والتصميم

### 8.1 AppColors
> استخدم **`app_colors.dart` فقط**.

```dart
// ── الألوان الأساسية ───────────────────────────────────────────────────
// Light: primary=blue-600 (#2563EB) / Dark: primary=blue-500 (#3B82F6)
AppColors.of(context).primary      // أزرق — للأزرار والعناصر التفاعلية
AppColors.of(context).primaryDark  // أزرق داكن — للحالات المضغوطة

// ── الخلفيات ──────────────────────────────────────────────────────────
AppColors.of(context).background   // الخلفية الرئيسية
AppColors.of(context).surface      // البطاقات، الـ Drawer، فقاعة AI
AppColors.of(context).surfaceHigh  // حقول الإدخال، الشرائح، التنقل النشط

// ── النصوص ────────────────────────────────────────────────────────────
AppColors.of(context).textPrimary   // النص الرئيسي
AppColors.of(context).textSecondary // التلميحات، الطوابع الزمنية
AppColors.of(context).onPrimary     // نص فوق الأزرق (أبيض)

// ── فقاعة المستخدم ────────────────────────────────────────────────────
AppColors.of(context).userBubble   // Color(0xFF60A5FA) — blue-400 — فقاعة رسالة المستخدم

// ── AI / Markdown ─────────────────────────────────────────────────────
AppColors.of(context).aiText       // نص ردود الـ AI
AppColors.of(context).aiHighlight  // تمييز العناصر في ردود الـ AI

// ── الحالات (static) ──────────────────────────────────────────────────
AppColors.success  // Color(0xFF22C55E) — green-500
AppColors.warning  // Color(0xFFF59E0B) — amber-500
AppColors.error    // Color(0xFFEF4444) — red-500
```

**قاعدة:** لا تستخدم قيم hex مباشرة في الـ widgets — دائماً عبر `AppColors`.

### 8.2 إرشادات التصميم
- **Material Design 3** — `useMaterial3: true`
- **الخط الافتراضي** — `fontFamily: 'Cairo'` مُضبوط في `app_theme.dart` لكلا الثيمَين (يحل "Could not find a set of Noto fonts" على Flutter Web)
- **RTL/LTR** — تلقائي بناءً على `app_language`
- **SafeArea** — مُطبَّقة على `body:` في جميع الصفحات (15 صفحة) — **لا تحذفها**
- **شبكة الوحدات** — `GridView.count` بعمودين
- **فقاعات الدردشة** — عرض 78% من الشاشة
- **RTL أولاً** — التطبيق مُصمَّم للعربية، تحقق دائماً من التوافق
- **AppBar الملوّن** — عند استخدام `backgroundColor: c.primary` أو `AppColors.success`، أضف دائماً:
  ```dart
  iconTheme: const IconThemeData(color: Colors.white), // يُصلح سهم الرجوع
  systemOverlayStyle: SystemUiOverlayStyle.light,       // شريط الحالة أبيض
  elevation: 2, shadowColor: Colors.black.withValues(alpha: 0.2),
  ```
  السبب: `appBarTheme.iconTheme(color: textSecondary)` في `app_theme.dart` يُلغي `foregroundColor` المحلي — `iconTheme` المحلي يتجاوزه.

---

## 9. الترجمة والتوطين

- **الملف:** `app_localizations.dart` (يدوي، بلا `.arb`)
- **اللغات:** `ar` (افتراضي) + `en`
- **230+ نص** — تبديل فوري، يُحفظ في SharedPreferences
- **`report_view_page.dart`** + **`pending_approvals_page.dart`** + **`approved_page.dart`** + **`dashboard_detail_page.dart`** — جميع نصوص الواجهة عبر `AppLocalizations` (لا نصوص مُضمَّنة)
- **مفاتيح i18n جديدة (2026-05-15):** `wfSearchHint`/`wfFallbackMode`/`wfFallbackDetails`/`wfLocalizeAction()`/`wfLastNDays(n)`/`wfExecutingMsg`/`wfActionDoneMsg`/`wfActionCancelledMsg`/`dashSearchHint`/`dashCompany`/`dashViewAll`/`dashNoPermission`
- **مفاتيح i18n جديدة (2026-05-16):** `appLogoSection`/`removeLogo`/`logoUpdated`/`noImageContent`/`exportTooltip`/`importTooltip`/`backupSubject`/`noFileContent`/`notSettingsFile`/`notKcscSettings`/`exportFailed(e)`/`importSuccess(n)`/`importFailed(e)`/`providerClaudeOnly`/`providerChatGptOnly`/`providerClaudeFirst`/`providerChatGptFirst`/`providerDesc*()`/`chatGptInfo`/`apiTokenOptional`

```dart
// الاستخدام الصحيح
final l10n = AppLocalizations.of(context);
Text(l10n.someKey)
// أضف المفتاح في كلا القاموسين (en + ar) دائماً
```

---

## 10. الاعتماديات الرئيسية

```yaml
http: ^1.1.0               # HTTP client — كل الطلبات عبر ApiService
shared_preferences: ^2.2.2  # تخزين محلي للإعدادات
record: ^6.0.0              # تسجيل صوتي (m4a/aac) → يُرسل لـ Whisper API
intl: any                   # تدويل وتنسيق التواريخ
path_provider: ^2.1.3       # الوصول لنظام الملفات (ملفات مؤقتة للتسجيل + التصدير)
fl_chart: ^0.68.0           # رسوم بيانية في AI Assistant + Dashboard (bar/line/pie/donut) — يحل محل Custom Painters في Dashboard
file_picker: ^8.1.2         # اختيار ملفات (SAF — بدون صلاحيات) + استيراد الإعدادات
pdf: ^3.10.8               # توليد PDF من الجداول (خط Cairo للعربية)
printing: ^5.12.0          # مشاركة/طباعة PDF عبر share sheet
url_launcher: ^6.3.0       # فتح تطبيق البريد الإلكتروني (mailto)
share_plus: ^12.0.1        # مشاركة الملفات (PDF/CSV/Excel)
image_picker: ^1.0.7       # التقاط صور من الكاميرا أو معرض الجهاز
archive: ^3.4.9            # استخراج نصوص من DOCX/XLSX/PPTX (ZipDecoder + UTF-8)
http_parser: ^4.0.2        # تحديد Content-Type عند رفع الملفات لـ ERPNext
flutter_launcher_icons: ^0.14.3  # توليد أيقونات التطبيق (dev dependency)
```
> `speech_to_text` حُذف — استُبدل بـ `record` + Whisper لدعم كل اللغات بدون حزم مثبتة

---

## 11. أنماط الكود — دليل سريع

### إضافة صفحة جديدة
```
1. أنشئ lib/new_page.dart  → StatefulWidget
2. أضف المسار في main.dart  → MaterialApp.routes
3. أضف الترجمات            → app_localizations.dart (en + ar معاً)
4. أضف رابطاً              → app_drawer.dart (إن احتجت)
5. طبّق حماية الصلاحيات    → راجع ModuleReportsPage كمرجع
```

### استدعاء API
```dart
// ✅ صحيح — ApiService methods هي static
final result = await ApiService.get('/api/resource/DocType');
if (result['exc'] != null) { /* عالج الخطأ */ }

// ✅ POST
final res = await ApiService.post('/api/resource/DocType', {'fieldname': 'value'});

// ✅ POST form-encoded
final res = await ApiService.postForm('/api/method/frappe.client.get_list', {'doctype': 'X'});

// ❌ خطأ — لا تستخدم http مباشرة
final response = await http.get(Uri.parse('...'));
```

### استدعاء FAC MCP مباشرة (بدون AI)
```dart
// ✅ استخدم FacMcpService لاستدعاء أدوات FAC من أي صفحة
final docs = await FacMcpService().getPendingApprovals();
// docs == null → FAC غير مثبت → استخدم Fallback

// ✅ WorkflowRepository لقائمة الموافقات
final pending = await WorkflowRepository().fetchPending(userId: userId);

// ✅ FacValidator للتحقق من الصلاحيات قبل العرض
final err = await FacValidator().validateBeforeApply(doc, action);
if (err != null) { /* عرض الخطأ */ }
```

### إضافة لون جديد
```dart
// ✅ في app_colors.dart فقط
static const Color newColor = Color(0xFFXXXXXX);

// ❌ لا تضع الـ hex مباشرة في الـ widget
Container(color: Color(0xFFXXXXXX))
```

---

## 12. القواعد الصارمة (لا استثناء)

| # | القاعدة |
|---|---------|
| 1 | **StatefulWidget فقط** — ممنوع إدخال Provider / Bloc / Riverpod / GetX |
| 2 | **AppColors حصراً** — لا hex مباشر في الـ widgets |
| 3 | **AppLocalizations حصراً** — لا نصوص مُضمَّنة في الـ widgets |
| 4 | **ApiService حصراً** — لا `http.get/post` خارجه |
| 5 | **فحص الصلاحيات** — قبل أي تنقل لصفحة محمية |
| 6 | **الشركة من SharedPreferences** — لا تطلبها من المستخدم |
| 7 | **RTL أولاً** — اختبر كل widget جديد في وضع RTL |
| 8 | **عدّل CLAUDE.md** — عند أي تغيير جوهري في البنية |
| 9 | **FAC أولاً للـ Workflow** — `FacMcpService` ثم `safeApplyWorkflow` كـ fallback — لا `applyWorkflow` مباشرة |
| 10 | **WorkflowRepository للموافقات** — لا تستعلم Workflow Action مباشرة من الصفحات — استخدم `WorkflowRepository` |

---

## 13. المشاكل المعروفة والديون التقنية

| الملف / المكوّن | المشكلة | الأولوية |
|----------------|---------|---------|
| ~~`app_colors.dart` + `main.dart`~~ | ~~`AppColors` مُعرَّف في موضعين~~ | ✅ تم الحل |
| ~~`test/widget_test.dart`~~ | ~~يشير لـ `main_old.dart` المحذوف~~ | ✅ تم الحل |
| ~~`pending_approvals_page.dart`~~ | ~~يعتمد فقط على Workflow Action — يفوّت Draft docs~~ | ✅ تم الحل — SOURCE 0+A+B |
| ~~`document_viewer_page.dart`~~ | ~~`applyWorkflow` مباشر — قد يُعيد 417~~ | ✅ تم الحل — FAC + safeApplyWorkflow |
| ~~`dashboards_page.dart` + `dashboard_detail_page.dart`~~ | ~~يستخدم `http` مباشرة بدون FAC وبدون fl_chart — custom painters قديمة~~ | ✅ تم الحل — إعادة بناء كاملة: fl_chart + FAC-first + responsive |
| ~~`pending_approvals_page.dart` + `approved_page.dart`~~ | ~~نصوص مُضمَّنة بالإنجليزي فقط — لا i18n لأزرار الإجراءات~~ | ✅ تم الحل — `wfLocalizeAction` + 8 مفاتيح جديدة |
| `accounting_dashboard.dart` | UI ثابت بيانات ثابتة، التنقل الداخلي غير مُطبَّق | 🔴 عالية |
| `FacMcpService` — Backend | يحتاج FAC مثبتاً على الخادم؛ إذا غير مثبت → يعمل بـ SOURCE A+B فقط | 🟡 متوسطة |
| `RealtimeWorkflowService` — Socket.IO | يحتاج `hooks.py` + `api.py` على الخادم (انظر `FAC_REALTIME_SETUP.md`) | 🟡 متوسطة |
| `SharedPreferences` | بيانات حساسة بلا تشفير — يحتاج `flutter_secure_storage` | 🟡 متوسطة |
| `AuthState` | لا استمرارية — يُفقد عند إغلاق التطبيق | 🟡 متوسطة |
| `user_login_page.dart` | Legacy — غير مدمجة في التدفق الرئيسي | 🟢 منخفضة |
| `fikra_app/fikra_app/` | نسخة مكررة قديمة — مستبعدة عبر `analysis_options.yaml`، يُنصح بحذفها | 🟡 متوسطة |
| `_sendEmailViaSystem()` | يعتمد على `frappe.core.doctype.communication.email.make` — قد يحتاج System Manager | 🟡 متوسطة |
| `extract_file_content` — FAC OCR (خادم) | PaddleOCR يفشل لأن subprocess يُشغَّل بـ `sys.executable` (Frappe Python 3.14 بلا paddlepaddle) بدلاً من `/opt/ocr-service/venv/bin/python` — **الحل في التطبيق:** Claude يستخدم native vision للصور بدلاً من FAC OCR (انظر §14 سجل 2026-05-12) | 🟡 متوسطة — يعمل عبر native vision |

---

## 14. سجل التغييرات

> أضف هنا كل تغيير جوهري مع التاريخ والسبب.

| التاريخ | التغيير | السبب |
|---------|---------|-------|
| 2025-03 | إنشاء الملف الأولي | توثيق المشروع |
| 2025-03 | إعادة هيكلة CLAUDE.md | تحسين الكفاءة والوضوح للذكاء الاصطناعي |
| 2026-03-24 | توحيد `AppColors` — حذف التعريف المكرر من `main.dart`، import من `app_colors.dart` | تطبيق قاعدة §12 |
| 2026-03-24 | إصلاح `accounting_dashboard.dart` — استبدال `http` المباشر بـ `ApiService.get()` + ألوان `AppColors` | تطبيق قواعد §12 (#2، #4) |
| 2026-03-24 | إصلاح `widget_test.dart` — حذف import المكسور، اختبارات حقيقية لـ `MyApp` و `AppColors` | إزالة الدين التقني |
| 2026-03-24 | `report_view_page.dart` — إضافة معالج خطأ "Start Year and End Year are mandatory" + `_ensureLink` + auto-fill `Fiscal Year` | إصلاح Balance Sheet |
| 2026-03-24 | إضافة `SafeArea` لجميع صفحات المشروع (12 صفحة) | حماية المحتوى من notch وشريط الـ system UI |
| 2026-03-24 | `report_view_page.dart` — استمرارية الفلاتر عبر `SharedPreferences` (`_saveFilters` / `_loadSavedFilters`) | حفظ قيم الفلاتر بين الجلسات |
| 2026-03-24 | `report_view_page.dart` — تخزين تعريفات الفلاتر مؤقتاً (`_saveDefs` / `_loadCachedDefs`) + زر Refresh لإجبار إعادة الجلب | فتح فوري بدون HTTP |
| 2026-03-24 | `report_view_page.dart` + `app_localizations.dart` — استبدال جميع النصوص المُضمَّنة بـ `AppLocalizations` (عربي/إنجليزي) | تطبيق قاعدة §3 والدعم الثنائي للغة |
| 2026-03-24 | `settings_page.dart` — حذف `hide AppColors` من import `main.dart` (بعد إزالة التعريف المكرر) | إصلاح خطأ `undefined_hidden_name` |
| 2026-03-24 | `analysis_options.yaml` — استبعاد `fikra_app/**` من التحليل | إخفاء أخطاء النسخة المكررة القديمة |
| 2026-03-24 | `accounting_dashboard.dart`, `login_page.dart`, `user_login_page.dart` — استبدال `withOpacity()` بـ `withValues(alpha:)` | إزالة deprecation warnings |
| 2026-03-24 | `ai_assistant_page.dart` — إضافة إرسال صوتي تلقائي: تكلم → يُرسل تلقائياً عند التوقف، زر المايك يتحول لـ Stop، hint يُظهر "سيُرسل تلقائياً" | تحسين تجربة المستخدم الصوتية |
| 2026-03-24 | `ai_assistant_page.dart` — حذف محدد اللغة الصوتية كلياً، إزالة `localeId` من `listen()` → الكشف التلقائي بواسطة نظام التشغيل | دعم جميع اللغات واللهجات بدون تدخل المستخدم |
| 2026-03-24 | `pubspec.yaml` + `lib/message_renderer.dart` — إضافة `fl_chart ^0.68.0` وملف عرض غني يدعم جداول Markdown ورسوم bar/line/pie من ردود Claude | عرض البيانات كجداول ورسوم بيانية |
| 2026-03-24 | `ai_assistant_page.dart` — تحديث system prompt لإرشاد Claude لاستخدام `<chart>JSON</chart>` وجداول Markdown، استبدال `SelectableText` بـ `MessageRenderer` | ربط عرض الرسوم والجداول بالمساعد الذكي |
| 2026-03-24 | `ai_assistant_page.dart` — نقل أيقونة المايك داخل حقل النص كـ `suffixIcon`، ربط `localeId` بـ `app_language` من SharedPreferences (`ar`→`ar_SA` / `en`→`en_US`) | إعادة تصميم واجهة الإدخال + دعم لغة الصوت تلقائياً |
| 2026-03-24 | `message_renderer.dart` — استبدال `_MarkdownTable` بـ `_HtmlTable`: ترويسة ملونة، تظليل متناوب، كشف تلقائي للأعمدة الرقمية (محاذاة يمين + monospace) | عرض جداول بتنسيق HTML احترافي |
| 2026-03-24 | `message_renderer.dart` — إضافة `onCreateChart` callback لـ `MessageRenderer` و `_ChartWidget`، زر "حفظ في الداشبورد" على كل رسم بياني | السماح بحفظ الرسوم في ERPNext مباشرة من المحادثة |
| 2026-03-24 | `ai_assistant_page.dart` — إضافة `_createDashboardChart()`: نافذة تأكيد + تحويل تنسيق Claude→Frappe + `ApiService.post('/api/resource/Dashboard Chart')` | إنشاء Dashboard Chart في ERPNext من رسوم Claude |
| 2026-03-24 | `ai_assistant_page.dart` — حذف `localeId` كلياً من `_speech.listen()` وحذف حقل `_appLang` | إرسال صوتي/كتابي بأي لغة دون تقييد أو تغيير إعدادات |
| 2026-03-24 | `message_renderer.dart` — استبدال `Table+IntrinsicColumnWidth` بـ `DataTable` داخل `SingleChildScrollView horizontal` | إصلاح جذري: الأول لا يعمل مع التمرير الأفقي في Flutter |
| 2026-03-24 | `ai_assistant_page.dart` — إعادة كتابة system prompt: إلزام Claude بسؤال المستخدم عن نوع الرسم (bar/line/pie) قبل توليد `<chart>`، تعليمات صريحة لتنسيق الوسم | كانت الرسوم لا تظهر لأن Claude لم يكن يُلزَم بالتنسيق |
| 2026-03-24 | `ai_assistant_page.dart` — `_toggleListen()`: استبدال "بدون localeId" بجلب أول locale متاح من `_speech.locales()` (أولوية ar → en → أول) | منع OS language-picker dialog على Android |
| 2026-03-24 | `pubspec.yaml` + `settings_page.dart` — إضافة `file_picker ^8.1.2`، استبدال `_importSettings()` لاستخدام `FilePicker.platform.pickFiles()` بدلاً من مسار مباشر | إصلاح `Permission denied errno=13` على Android 10+ عند استيراد الإعدادات |
| 2026-03-24 | `settings_page.dart` — `_backupFile()`: تغيير مجلد التصدير من `/storage/emulated/0/Download` (محظور Android 10+) إلى `getExternalStorageDirectory()` (لا يحتاج صلاحيات) | إصلاح فشل التصدير على Android 10+ |
| 2026-03-24 | `AndroidManifest.xml` — إضافة `INTERNET` + `RECORD_AUDIO` صراحةً | بدونهما في release build: فشل الاتصال بالشبكة + فشل الميكروفون |
| 2026-03-24 | `ai_assistant_page.dart` — `_InputBarState`: استبدال `_appLang` بـ `_speechLang` مستقل (مفتاح `speech_language`)، إضافة زر `AR`/`EN` بجانب الميكروفون للتبديل الفوري | فصل لغة الصوت عن لغة الواجهة — المستخدم يختار لغة الميكروفون بضغطة واحدة |
| 2026-03-24 | `ai_assistant_page.dart` — إعادة كتابة `_InputBarState` كلياً: جلب جميع اللغات المثبتة عبر `_speech.locales()` عند التهيئة، عرض Bottom Sheet لاختيار اللغة، حفظ `speech_locale_id` في SharedPreferences، تمرير `localeId` مباشرة لـ `_speech.listen()` — لا استنتاج ولا fallback خاطئ | إصلاح جذري: التعرف الخاطئ على العربية (→ صيني/هراء) كان بسبب افتراض لغة غير مثبتة؛ الحل: عرض ما هو مثبت فعلاً على الجهاز |
| 2026-03-24 | `ai_assistant_page.dart` — حذف زر اختيار اللغة وكل منطق `_availableLocales`/`_selectedLocaleId`/`_pickLocale`/`_localeLabel` كلياً، استدعاء `_speech.listen()` بدون `localeId` | المستخدم لا يريد أي اختيار — الميكروفون يعمل مباشرة بأي لغة بناءً على إعدادات Voice Input في نظام Android |
| 2026-03-24 | `pubspec.yaml` — حذف `speech_to_text`، إضافة `record ^6.0.0`؛ `ai_assistant_page.dart` — إعادة كتابة `_InputBarState` كلياً: `AudioRecorder` يسجّل m4a → `POST api.openai.com/v1/audio/transcriptions` (Whisper) → كشف لغة تلقائي → نص → إرسال؛ `settings_page.dart` — إضافة حقل `openai_api_key`؛ `app_localizations.dart` — إضافة `transcribing` + `whisperKeyMissing` | إصلاح جذري نهائي: Whisper يتعرف على أي لغة (عربي/إنجليزي/غيره) بدون تثبيت حزم على الجهاز |
| 2026-03-24 | `settings_page.dart` — إضافة منتقي مزود الذكاء الاصطناعي (Claude / ChatGPT) مع حقول مستقلة لكل مزود (API Key + Model selector)؛ `ai_assistant_page.dart` — إضافة `_toOpenAITools()` + `_callChatGPT()` + `_runChatGPTLoop()` + تفريع في `_sendMessage()` بناءً على `ai_provider`؛ `app_localizations.dart` — إضافة مفاتيح `aiProvider`، `chatgptModel`، `chatgptApiKey`، `addAiKey` | دعم ChatGPT (OpenAI) كمزود بديل لـ Claude في المساعد الذكي مع MCP |
| 2026-03-24 | `ai_assistant_page.dart` — تناظر Claude↔ChatGPT: (1) `_EmptyState` يعرض النموذج الصحيح لكل مزود، (2) `max_tokens: 4096` لـ ChatGPT، (3) `buildHistory()` يحمي من orphaned tool messages مثل `buildSendList()` في Claude | تطبيق تناظر كامل بين المزودَين في كل التحسينات
| 2026-03-24 | `settings_page.dart` — إعادة كتابة `_importSettings()` كلياً: استخدام `withReadStream: true` فقط (حذف `withData`)، قراءة عبر `await for (chunk in readStream)` + `utf8.decode()` بدل `String.fromCharCodes` — يصلح الكسر بالعربية وخطأ Permission denied على Android 10+ | `String.fromCharCodes(utf8Bytes)` يكسر متعدد البايت (العربية)؛ `withData` وحده غير موثوق على كل الأجهزة |
| 2026-03-24 | `settings_page.dart` — إضافة نص توضيحي تحت provider selector يُظهر المزود المختار حالياً وإرشاد للمستخدم لإدخال الـ API Key | المستخدم لم يكن يعرف أن ChatGPT موجود في الإعدادات ويحتاج ضغطة على الزر لظهور الحقول |
| 2026-03-24 | `flutter build apk --release` — بناء APK (53.7 MB) | إصلاح الاستيراد + وضوح إعدادات ChatGPT |
| 2026-03-24 | `ai_assistant_page.dart` — استخراج `_runClaudeLoop()` كـ method مستقلة مماثلة لـ `_runChatGPTLoop()`؛ إعادة كتابة `_sendMessage()` بـ `switch` يدعم 4 أوضاع: `claude`، `chatgpt`، `claude_first` (Claude ثم ChatGPT fallback)، `chatgpt_first` (ChatGPT ثم Claude fallback)؛ تحديث AppBar و warning banner | دعم الأولوية والـ fallback التلقائي بين المزودَين |
| 2026-03-24 | `settings_page.dart` — تغيير provider selector من 2 زر إلى شبكة 2×2 تحتوي: Claude فقط، ChatGPT فقط، Claude أولاً، ChatGPT أولاً؛ حقول Claude تظهر لكل وضع ما عدا chatgpt، حقول ChatGPT تظهر لكل وضع ما عدا claude | يسمح بإدخال كلا المفتاحَين في أوضاع الـ fallback |
| 2026-03-24 | `app_localizations.dart` — إضافة `tryingProvider(p)` + `fallbackToProvider(p)` | رسائل حالة الـ fallback في المساعد الذكي |
| 2026-03-24 | `flutter build apk --release` — بناء APK (53.7 MB) | ميزة الأولوية + fallback تلقائي |
| 2026-03-24 | `ai_assistant_page.dart` — إضافة `_company` يُحمَّل من `erpnext_company` في `_loadConfig()`؛ استبدال `static const _systemPrompt` بـ `_buildSystemPrompt()` ديناميكي يدمج اسم الشركة تلقائياً؛ إعادة كتابة الـ prompt ليشمل أدوار: مبيعات، مشتريات، محاسبة، تدقيق، مخزون، تصنيع، موارد بشرية، مشاريع — مع قاعدة صارمة للبقاء داخل ERPNext | المساعد يعمل الآن بسياق الشركة الصحيح ويغطي جميع وظائف النظام |
| 2026-03-24 | `flutter build apk --release` — بناء APK (53.8 MB) | system prompt شامل + اسم الشركة |
| 2026-03-25 | `ai_assistant_page.dart` — إصلاح مشكلتين في system prompt: (1) قاعدة "خارج النظام" كانت تطبَّق على التواريخ والتوضيحات خطأً — الآن مقيّدة بالأسئلة الخارجية تماماً كالطقس والأخبار فقط؛ (2) الرسم البياني لا يتولّد بعد اختيار النوع — أُضيف تعليم صريح: إذا حدّد المستخدم النوع ولديك البيانات ولّد الرسم فوراً دون سؤال | خطأ "لسنة 2026" + خطأ إعادة طلب البيانات بعد اختيار pie |
| 2026-03-25 | `ai_assistant_page.dart` — زيادة `maxHistory` من 6 إلى 20 للـ ChatGPT و Claude — يحفظ سياق البيانات والرسوم في المحادثات الطويلة | فقدان السياق كان يسبب طلب البيانات من جديد بعد اختيار نوع الرسم |
| 2026-03-25 | `app_drawer.dart` — إخفاء رابط "الوحدات" من الـ drawer (مع الإبقاء على الملف والمسار)؛ `main.dart` + `login_page.dart` — تحويل التوجيه بعد تسجيل الدخول من `/modules` إلى `/ai-assistant` | صفحة modules مخفية من التنقل بناءً على طلب المستخدم |
| 2026-03-25 | `flutter build apk --release` — بناء APK (53.8 MB) | إخفاء modules + إصلاح prompt |
| 2026-03-25 | `ai_assistant_page.dart` — تحديث `_buildSystemPrompt()`: إضافة قسم "FAC أولاً دائماً" كأولوية قصوى، قسم إرسال البريد الإلكتروني عبر FAC (اكتشاف أدوات البريد → استدعاء مع recipient/subject/body)، قسم تصدير الملفات (Excel/PDF/Word) عبر FAC، تسلسل العمل المعياري مع FAC (4 خطوات) | المساعد يعتمد على FAC كأولوية أولى لكل شيء بما فيه الإيميل والتصدير |
| 2026-03-25 | `ai_assistant_page.dart` — تشديد القاعدة 6 في system prompt: رفض فوري لأي سؤال خارج ERPNext بصيغة ثابتة "أنا مساعد ERPNext متخصص..."، إضافة قاعدة 7 تحدد النطاق المسموح صراحةً — لا استثناء ولا مرونة | المستخدم لا يريد أي إجابة خارج نطاق النظام |
| 2026-03-25 | `ai_assistant_page.dart` — إضافة `_timezone` + `_country` + `_loadSystemSettings()` تجلب `time_zone` و `country` من `GET /api/resource/System Settings/System Settings` عند فتح الصفحة؛ إعادة كتابة `_buildSystemPrompt()` كلياً: سياق النظام (شركة/timezone/country) في أعلى الـ prompt، قاعدة FAC ذهبية مع STOP/YES/NO decision tree، رفض صارم بجملة واحدة فقط | FAC الأولوية المطلقة في كل خطوة + timezone/country تلقائياً من النظام |
| 2026-03-25 | `flutter build apk --release` — بناء APK (53.8 MB) | FAC أولوية مطلقة + timezone/country |
| 2026-03-25 | `ai_assistant_page.dart` — إضافة قسم "تصدير الملفات" في system prompt: حظر صريح لأي محاولة تصدير خارج FAC، قائمة أسماء أدوات FAC المحتملة (export_report/generate_pdf/create_pdf/...) مع خطوات بحث إلزامية، أمثلة على الردود الممنوعة ("I encountered a technical issue..."/"I recommend Excel...") | AI كان يحاول تصدير PDF بنفسه بدل استخدام FAC ويقترح بدائل |
| 2026-03-25 | `flutter build apk --release` — بناء APK (53.8 MB) | إصلاح تصدير PDF عبر FAC |
| 2026-03-25 | `ai_assistant_page.dart` — تشديد قسم البريد في system prompt: حظر صريح لـ "I'm unable to send emails"/"You may download manually"/"send through your email provider"، قائمة أسماء أدوات FAC المحتملة (send_email/send_mail/frappe.sendmail/...)، خطوات بحث إلزامية قبل أي رد | AI كان يرفض إرسال البريد مباشرة بدل البحث في أدوات FAC |
| 2026-03-25 | `flutter build apk --release` — بناء APK (53.8 MB) | إصلاح إرسال البريد عبر FAC |
| 2026-03-25 | `pubspec.yaml` — إضافة `pdf ^3.10.8` + `printing ^5.12.0`؛ `message_renderer.dart` — إضافة زر PDF على كل جدول: `_exportPdf()` يولّد PDF من بيانات الجدول ويفتح نافذة المشاركة عبر `Printing.sharePdf()` — يعمل بدون FAC كحل client-side | FAC لا يملك أداة تصدير PDF؛ الحل: زر PDF مدمج في كل جدول |
| 2026-03-25 | `message_renderer.dart` — إضافة `showPdfButton` لـ `_HtmlTable`؛ `<export_pdf/>` tag يُفعّل الزر فقط عند وجوده؛ خط Cairo (Google Fonts) لدعم العربية في PDF؛ `ai_assistant_page.dart` — تحديث prompt: AI يضيف `<export_pdf/>` فقط عند طلب المستخدم الصريح للتصدير | الخط العربي كان يظهر مربعات؛ زر PDF كان يظهر على كل الجداول تلقائياً |
| 2026-03-25 | `flutter build apk --release` — بناء APK (58.8 MB) | إصلاح خط PDF العربي + زر PDF عند الطلب فقط |
| 2026-03-25 | `pubspec.yaml` — إضافة `url_launcher ^6.3.0`؛ `AndroidManifest.xml` — إضافة mailto intent queries؛ `message_renderer.dart` — تحليل `<send_email to="..." subject="...">body</send_email>` + `_EmailButton` يفتح تطبيق البريد مع TO/Subject/Body جاهزة؛ `ai_assistant_page.dart` — تحديث prompt: AI يضع `<send_email>` tag عند طلب الإرسال وعدم توفر أداة FAC | FAC لا يملك أداة بريد؛ الحل: التطبيق يفتح تطبيق البريد المحلي جاهزاً بالبيانات |
| 2026-03-25 | `flutter build apk --release` — بناء APK (58.8 MB) | إرسال بريد عبر تطبيق الجهاز |
| 2026-03-25 | `message_renderer.dart` — إضافة `_cleanBody()` في `_EmailButton`: تحويل جداول Markdown (| col |) إلى نص نظيف بمسافات — حذف أسطر الفاصل (|---|---) وتوحيد الخلايا بـ 4 مسافات | جسم البريد كان يُرسل الـ Markdown خاماً (أقواس وشرطات) بدلاً من نص مقروء |
| 2026-03-25 | `flutter build apk --release` — بناء APK (58.9 MB) | إصلاح تنسيق جسم البريد الإلكتروني |
| 2026-03-25 | `message_renderer.dart` — إصلاح عدم ثبات إرسال البريد: `mailto:` URI يفشل صامتاً عند تجاوز ~1800 حرف؛ الحل: 3 محاولات بالترتيب: (1) body كاملة، (2) body مقطوعة مع ملاحظة، (3) subject فقط؛ `launchUrl` مع `LaunchMode.externalApplication` + try/catch لكل محاولة | البيانات الكبيرة كانت تجعل URI طويلاً جداً فيتوقف الإرسال بصمت |
| 2026-03-25 | `flutter build apk --release` — بناء APK (58.9 MB) | إصلاح ثبات إرسال البريد |
| 2026-03-25 | `message_renderer.dart` — تقسيم `_exportPdf` إلى `_buildPdfBytes` (Uint8List) + `_sharePdf` (share sheet) + `_savePdf` (حفظ مباشر إلى external storage)؛ زران بجانب الجدول عند طلب PDF: "مشاركة PDF" + "حفظ في الجهاز" مع Snackbar يعرض المسار وزر "فتح" | المستخدم يريد حفظ الملف مباشرة على الهاتف بدون share sheet |
| 2026-03-25 | `flutter build apk --release` — بناء APK (58.9 MB) | حفظ PDF مباشرة في الجهاز |
| 2026-03-25 | `ai_assistant_page.dart` — إضافة `response_format=verbose_json` لـ Whisper لكشف اللغة؛ تغيير `onSend` signature إلى `void Function([String?])`؛ تمرير `detectedLang` من Whisper إلى `_sendMessage`؛ بناء `aiText` يضيف `[Voice message — detected language: X. You MUST reply in X only.]` كسياق مخفي للـ AI | الرسالة الصوتية بالإنجليزي كانت تُرسَل وتُجاب بالعربية لأن الـ AI لم يكن يعرف لغة الرسالة |
| 2026-03-25 | `flutter build apk --release` — بناء APK (58.9 MB) | إصلاح لغة الرد على الرسائل الصوتية |
| 2026-03-25 | `message_renderer.dart` — إضافة `_SystemEmailButton` widget + `_sysEmailRx` regex لتحليل `<system_email to="..." subject="...">body</system_email>`؛ `ai_assistant_page.dart` — إضافة `_sendEmailViaSystem()` يستدعي `POST /api/resource/Communication` مع `send_email:1`، إضافة `onSendSystemEmail` لـ `_MessageBubble` و `MessageRenderer`؛ تحديث system prompt: AI يستخدم `<system_email>` أولاً (إرسال من ERPNext مباشرة) ثم `<send_email>` كبديل | إرسال البريد من حساب ERPNext الافتراضي مباشرة بدون تطبيق خارجي |
| 2026-03-25 | `flutter build apk --release` — بناء APK (58.9 MB) | إرسال بريد server-side من ERPNext |
| 2026-03-25 | `ai_assistant_page.dart` — إعادة كتابة `_sendEmailViaSystem()`: استبدال `POST /api/resource/Communication` بـ FAC `run_python_code` الذي ينفذ `frappe.sendmail(recipients=[...], subject=..., message=..., now=True)` — يدعم عناوين متعددة مفصولة بفواصل | `Communication` doctype لا يُرسل البريد فوراً دائماً؛ `frappe.sendmail` مع `now=True` يُرسل مباشرة من الحساب الافتراضي |
| 2026-03-25 | `flutter build apk --release` — بناء APK (58.9 MB) | إرسال البريد عبر FAC run_python_code |
| 2026-03-25 | `ai_assistant_page.dart` — إصلاح جذري لـ `_sendEmailViaSystem()`: حذف `run_python_code` (sandbox للقراءة فقط — لا يمكن كتابة DB ولا network)؛ الاستبدال بـ `POST /api/method/frappe.core.doctype.communication.email.make` وهو method مُسجَّل `@frappe.whitelist()` في Frappe يُنشئ Communication ويُرسل البريد فوراً | `run_python_code` sandbox يمنع كتابة DB لذا `frappe.sendmail` لم يكن يعمل أبداً داخله |
| 2026-03-25 | `flutter build apk --release` — بناء APK (58.9 MB) | إصلاح إرسال البريد من النظام |
| 2026-03-25 | `message_renderer.dart` — إضافة `_bodyToHtml()` تحوّل markdown (جداول + نص) إلى HTML مع ترويسة ملونة `#0B1CE0`؛ إضافة `_buildAttachmentPdf()` تولّد PDF من raw table lines؛ تحويل `_SystemEmailButton` من `StatelessWidget` إلى `StatefulWidget`: يحوّل body إلى HTML، يولّد PDF من table lines عند وجود `<export_pdf/>`، يُمرّرهما معاً للـ callback مع زر "إرسال من النظام مع مرفق PDF"؛ `ai_assistant_page.dart` — تحديث `_sendEmailViaSystem()` لقبول `Uint8List? pdfBytes`، إضافة `_uploadEmailAttachment()` يرفع الملف عبر `POST upload_file` ويُدرج `file_url` في `attachments` | body البريد كان نص خام؛ والمستخدم طلب إرسال الملفات المصدّرة كمرفق |
| 2026-03-25 | `flutter build apk --release` — بناء APK (58.9 MB) | HTML body + PDF attachment في البريد |
| 2026-03-25 | `api_service.dart` — إضافة `postForm()` يُرسل `application/x-www-form-urlencoded` (بدلاً من JSON) مع CSRF؛ استخراج `_extractError()` مشتركة؛ `ai_assistant_page.dart` — تغيير `_sendEmailViaSystem()` من `ApiService.post` إلى `ApiService.postForm` لـ `communication.email.make` مع `send_email: '1'` (string) + إضافة `file_name` في attachments JSON | `frappe.core.doctype.communication.email.make` يتوقع form-encoded لا JSON — كان يفشل صامتاً مع Content-Type: application/json |
| 2026-03-25 | `flutter build apk --release` — بناء APK (58.9 MB) | إصلاح إرسال البريد بعد تحويل encoding |
| 2026-03-25 | `pubspec.yaml` — إضافة `share_plus: ^12.0.1`، حذف `speech_to_text` (غير مستخدم — استُبدل بـ record+Whisper سابقاً)؛ `message_renderer.dart` — حذف `showPdfButton` من `_HtmlTable`: أزرار تصدير دائماً مرئية على كل جدول؛ استبدال "حفظ في الجهاز" (مسار مخفي) بزرَّي "مشاركة PDF" (`Printing.sharePdf`) + "مشاركة Excel" (CSV عبر `SharePlus.instance.share`)؛ إزالة `<export_pdf/>` كشرط لإظهار الأزرار؛ `MessageRenderer.build()` — إرسال `emailTableLines` دائماً للـ `_SystemEmailButton` (لا يشترط `<export_pdf/>` بعد الآن)؛ `ai_assistant_page.dart` — تحديث system prompt: قسم التصدير يوضح أن الأزرار دائماً مرئية، قسم البريد يوضح أن الجدول في نفس الرد يُرفق تلقائياً كـ PDF | PDF/Excel لم يظهر إلا عند `<export_pdf/>`؛ لا يوجد تصدير Excel؛ "حفظ في الجهاز" كان يحفظ في مسار مخفي |
| 2026-03-25 | `flutter build apk --release` — بناء APK (59.1 MB) | تصدير PDF+Excel دائم + مشاركة صحيحة |
| 2026-03-26 | `settings_page.dart` — إضافة نماذج ChatGPT الجديدة: `gpt-5-mini` (أعلى القائمة)، `gpt-4.5-preview`، `o1`، `o3-mini`؛ حذف `speech_to_text` من `pubspec.yaml` (كان متبقياً رغم استبداله بـ record+Whisper) | دعم أحدث نماذج OpenAI — `ai_assistant_page.dart` يقرأ النموذج من SharedPreferences ويمرره مباشرة للـ API |
| 2026-03-26 | `flutter build apk --release` — بناء APK (59.1 MB) | نماذج ChatGPT الجديدة |
| 2026-03-27 | `message_renderer.dart` — تحويل `_HtmlTable` من `StatelessWidget` إلى `StatefulWidget`: إضافة `onSendEmailWithAttachment` callback؛ إضافة `_showEmailDialog()` يعرض AlertDialog لإدخال إيميل+موضوع ثم يولّد PDF ويرسله كمرفق؛ إضافة `_savePdfToDevice()` + `_saveCsvToDevice()` يحفظان الملف في external storage مع snackbar + زر "مشاركة"؛ إضافة `_buildHtmlBody()` لبناء HTML من بيانات الجدول؛ تغيير أزرار التصدير إلى 5 أزرار: [PDF] [حفظ PDF] [Excel] [حفظ Excel] [إرسال بالبريد]؛ `MessageRenderer._render()` يمرر `onSendSystemEmail` إلى `_HtmlTable`؛ `ai_assistant_page.dart` — تحديث system prompt | المستخدم يريد إرسال الملف المصدَّر كمرفق بالبريد مباشرة من الجدول + حفظه في الجهاز |
| 2026-03-27 | `flutter build apk --release` — بناء APK (59.1 MB) | أزرار تصدير كاملة + إرسال بالبريد مع مرفق + حفظ في الجهاز |
| 2026-03-27 | إعادة تصميم شاملة للواجهة — `app_colors.dart`: لوحة ألوان داكنة احترافية (slate-900/800/700 + blue-500)؛ `main.dart`: `ThemeData` داكن مع ألوان موحّدة؛ `app_drawer.dart`: إصلاح تعارض النصوص (black87 على خلفية داكنة)؛ `ai_assistant_page.dart`: فقاعات محادثة جديدة (user=أزرق مصمت / AI=surface مع حدود) + شريط إدخال محسّن؛ `login_page.dart`: تصميم مركزي أنظف؛ `settings_page.dart`: `_SettingsField` + `_LangButton` + `_SectionHeader` بالألوان الجديدة | تطبيق طلب المستخدم بتصميم أكثر احترافية وسهولة |
| 2026-03-27 | `flutter build apk --release` — بناء APK (59.1 MB) | إعادة التصميم الشاملة |
| 2026-03-27 | `ai_assistant_page.dart` — إعادة كتابة system prompt بالإنجليزية: (1) RULE 0 — اكتشاف لغة المستخدم والرد بها حصراً (أعلى أولوية)؛ (2) RULE 1 — ردود محصورة بالسؤال فقط بدون بيانات إضافية أو تحليل غير مطلوب؛ حذف قاعدة "عند البيانات المالية: قدّم المجموع + نسبة التغيير + مقارنة" التي كانت تسبب بيانات زيادة | المستخدم يريد ردوداً مباشرة بلغة سؤاله وبدون إضافات غير مطلوبة |
| 2026-03-27 | `flutter build apk --release` — بناء APK (59.1 MB) | ردود محصورة + لغة المستخدم |
| 2026-03-27 | `ai_assistant_page.dart` — إصلاح fallback في `chatgpt_first` و`claude_first`: المزود الأول يرمي exception عند إرجاع `noReplyReceived` → fallback للمزود الثاني يُفعَّل تلقائياً؛ رفع `maxChars` لنتائج الأدوات من 3000 إلى 12000 حرف؛ تطبيع `content: null` إلى `''` في رسائل assistant قبل إرسالها لـ OpenAI | "No response received." في وضع `chatgpt_first` كان بسبب عدم رمي exception — fallback لم يُفعَّل أبداً؛ تقارير Stock Balance وغيرها كانت تُقتطع بـ 3000 حرف |
| 2026-03-27 | `pubspec.yaml` — رفع الإصدار إلى `1.0.29+29`؛ `flutter build apk --release` — بناء APK (59.1 MB) | تحديث versionCode لضمان قبول Android للتثبيت |
| 2026-03-31 | حفظ المحادثات في ERPNext: `api_service.dart` — إضافة `put()` + `delete()`؛ `app_localizations.dart` — 11 مفتاح جديد؛ `lib/chat_history_page.dart` — صفحة جديدة تعرض سجل المحادثات المحفوظة (قائمة/تحميل/حذف)؛ `ai_assistant_page.dart` — `_sessionNote` + `_autoSave()` يحفظ/يحدّث Note في ERPNext بعد كل رد، `_openHistory()` يفتح صفحة السجل ويعيد تحميل المحادثة المختارة، زر 📋 في AppBar، مؤشر حفظ متحرك؛ تنسيق التخزين: `<!-- AICHAT_V1 -->{json}<!-- /AICHAT_V1 -->` داخل Note.content | حفظ تلقائي وتصفح واستئناف أي محادثة سابقة |
| 2026-04-01 | إعادة تسمية المشروع: `pubspec.yaml` — `name: fikra_app` → `name: sadid_ai`؛ `build.gradle.kts` — `namespace` + `applicationId` → `com.example.sadid_ai`؛ `AndroidManifest.xml` — `android:label` → `"Sadid AI"`؛ `MainActivity.kt` — نقل من `com/example/fikra_app/` إلى `com/example/sadid_ai/` + تحديث `package` declaration | طلب المستخدم |
| 2026-04-01 | `chat_history_page.dart` — إضافة فلتر `["owner","=","$username"]` لعزل محادثات كل مستخدم عن غيره (خصوصية متعددة الأجهزة)؛ `ai_assistant_page.dart` — إضافة RULE 2 (بقاء في سياق الموضوع، عدم تكرار الأسئلة) + RULE 3 (3 محاولات بدائل قبل الاستسلام عند Permission error) + قاعدة التحية (مرحبا → رد قصير فقط بدون FAC)؛ `pubspec.yaml` — `1.0.34+34` | خصوصية محادثات + ثبات السياق + معالجة صلاحيات |
| 2026-03-31 | `ai_assistant_page.dart` — تسريع شامل: (1) كاش أدوات MCP — `_cachedMcpTools` يمنع إعادة جلب الأدوات في كل رسالة (توفير طلب HTTP واحد دائماً)؛ (2) `initialize` مرة واحدة فقط per session عبر `_mcpInitialized`؛ (3) تنفيذ متوازٍ للأدوات `Future.wait()` بدل تسلسلي لكلا Claude وChatGPT؛ (4) تخفيف verbose logging من 8 سطر لسطر واحد لكل طلب؛ `pubspec.yaml` — `1.0.33+33` | إصلاح جذري لـ "No response received" والنسيان: (1) رفع `maxHistory` من 20 إلى 60 لكلا المزودَين؛ (2) إصلاح تلوث التاريخ: الرسالة الفارغة من `stop` لا تُضاف لـ `_openAiHistory`/`_claudeHistory` — بدلاً من ذلك يُضاف الـ nudge مباشرة للتاريخ ليبقى صحيحاً (user/assistant بالتناوب)؛ (3) الرسالة الحقيقية تُضاف للتاريخ فقط بعد التحقق من وجود محتوى — يمنع تتابع assistant messages يكسر الاستمرارية في المحادثات الطويلة؛ `pubspec.yaml` — `1.0.32+32` | إصلاح الكتابة العربية في حقل الإدخال عند لغة التطبيق إنجليزي: إضافة `_updateTextDir()` listener يكتشف أول حرف من النص (نطاق Unicode 0590-08FF = RTL) ويضبط `textDirection` ديناميكياً على الـ TextField — يدعم التبديل التلقائي بين العربية والإنجليزية بنفس الحقل | Directionality=LTR كانت تُجبر العربية على التمثيل المعكوس عند واجهة الإنجليزية |
| 2026-03-31 | `ai_assistant_page.dart` — توسيع system prompt: إضافة قسم "Human Resources — Full Module" يغطي 5 أدوار: HR Manager (دورة حياة الموظف كاملة، رواتب، أداء، امتثال)، HR Employee (العمليات اليومية، إجازات، حضور، سلف)، HR Consultant (تشخيص فجوات، مقارنة رواتب، تخطيط قوى عاملة)، Employee self-service (كشوفات، إجازات، مطالبات)، HR Analyst (تقارير headcount/payroll/attendance/attrition)؛ `pubspec.yaml` — رفع الإصدار إلى `1.0.30+30`؛ `flutter build apk --release` — بناء APK (59.1 MB) | تحليل موديول الموارد البشرية من جميع الأدوار |
| 2026-04-01 | `ai_assistant_page.dart` — تقوية RULE 3: توسيع شروط التفعيل لتشمل "Cannot access DocType"، توضيح الأدوات البديلة في كل محاولة (get_value, get_list, run_query)؛ إضافة RULE 4 الجديدة: إصلاح تلقائي لأخطاء إنشاء/تحديث المستندات (validation error, mandatory field, duplicate) — 3 إعادة محاولة قبل الإبلاغ، حظر صريح لعرض خيارات (1/2/3)؛ تقوية nudge للحالات الصامتة: "Do NOT call any more tools. Do NOT say you cannot help. Just write the answer directly." | إصلاح: AI يعطي خيارات بدل إعادة المحاولة + AI يستسلم عند Permission error + "No response received" بعد العمليات المعقدة |
| 2026-04-02 | `ai_assistant_page.dart` — تقوية RULE 3: إضافة قاعدة `db.set_value` الحرجة — يستلزم System Manager وسيفشل دائماً مع المستخدمين العاديين؛ عند أي خطأ صلاحيات مع `db.set_value` يُبدَّل فوراً بـ `update_document` (يعمل بصلاحيات Write عادية)؛ حظر صريح لإعادة محاولة `db.set_value` بعد الفشل؛ تعليمات للتحديثات الجماعية (KRA rows) باستخدام `update_document` مرة واحدة على المستند الأب؛ `pubspec.yaml` — `1.0.52+52`؛ APK (59.9 MB) | AI كان يستخدم `db.set_value` (يحتاج System Manager) بدلاً من `update_document` → "No response received" |
| 2026-04-02 | `ai_assistant_page.dart` — إصلاح 3 أخطاء: (1) `my_files`/`from_chat` كانت تقع في الـ `else` (document) branch فتفتح FilePicker/Google Drive — الحل: نقل الفحص قبل الـ if/else chain؛ (2) `bytes` كانت `final` فلا تقبل التعديل عند التنزيل — الحل: تحويلها لـ mutable؛ (3) إصلاح download من المحادثة: استبدال `selected[indexOf]` الخاطئ بـ `a.bytes = List.from(resp.bodyBytes)` مباشرة؛ (4) إضافة `_ensureBytes()` تُستدعى في `_sendMessage` قبل base64Encode لضمان تحميل البايتات من ERPNext عند إرسال مرفق من التاريخ؛ `pubspec.yaml` — `1.0.52+52`؛ APK (59.9 MB) | my_files/from_chat فتحا Google Drive + خطأ رفع صور المحادثة |
| 2026-04-02 | `ai_assistant_page.dart` + `pubspec.yaml` + `app_localizations.dart` — إصلاح جذري لمشكلة حفظ الصور بـ 0 bytes في ERPNext: (1) إضافة `http_parser ^4.0.2`؛ (2) إضافة `_normMime()` static لتوحيد MIME؛ (3) رفع الملفات إلى ERPNext **قبل** إرسالها للـ AI عبر `await _uploadAttachmentsToErpNext` مع `contentType` صحيح؛ (4) بناء `fileUrlContext` يُخبر الـ AI بـ `file_url` الدقيق لكل مرفق ليستخدمه في FAC بدون إعادة رفع؛ (5) استبدال `aiText` بـ `aiTextWithFiles` في كل الـ loops؛ (6) تحديث RULE 0.5 في system prompt: AI يستخدم `file_url` المُقدَّم مباشرة لربط الملف بالوثائق؛ `pubspec.yaml` — `1.0.53+53`؛ APK (59.9 MB) | الملف كان يُرفع بعد رد الـ AI فيظهر بـ 0 bytes وبدون MIME صحيح؛ الـ AI لم يكن يعرف رابط الملف ليستخدمه في FAC |
| 2026-04-02 | `ai_assistant_page.dart` — إصلاح "Invalid base64 image_url": (1) إضافة `normMime()` محلية تُحوّل `image/jpg` → `image/jpeg` قبل base64Encode (OpenAI يرفض `image/jpg`)؛ (2) إضافة فحص `bytes.isEmpty` قبل بناء كتل الصور لكلا Claude وChatGPT — عند بايتات فارغة يُضاف نص توضيحي بدلاً من محاولة encode فارغة؛ (3) إضافة `errorBuilder` لـ `Image.memory()` في `_AttachmentGrid._buildImageTile()` يعرض أيقونة placeholder بدلاً من صندوق فارغ أزرق عند فشل الرسم؛ `pubspec.yaml` — `1.0.52+52`؛ APK (59.9 MB) | OpenAI كان يرفض `image/jpg` + base64 فارغ = exception صامت + صندوق أزرق فارغ |
| 2026-04-02 | `ai_assistant_page.dart` + `app_localizations.dart` — إضافة خيارَين جديدَين في Bottom Sheet المرفقات: (1) **ملفاتي في النظام** `_MyFilesSheet`: يجلب ملفات ERPNext عبر `GET /api/resource/File`، عرض شبكي 3×3 مع بحث، اختيار متعدد بعلامة ✓، تنزيل بايتات الملف عند التأكيد؛ (2) **من المحادثة** `_ConversationImagesSheet`: يعرض جميع الصور الموجودة في المحادثة الحالية في شبكة، اختيار متعدد، تنزيل الصور من ERPNext بـ session cookie عند الحاجة؛ `pubspec.yaml` — `1.0.51+51`؛ APK (59.9 MB) | تخزين الملفات في النظام وإعادة استخدامها واستخدام صور المحادثة لاحقاً |
| 2026-04-02 | `flutter build apk --release` — بناء APK (59.8 MB) — `1.0.50+50` | إصدار نهائي شامل: مرفقات متعددة + حفظ ERPNext + عرض WhatsApp + قراءة ملفات + كاميرا/معرض/ملف |
| 2026-04-02 | `pubspec.yaml` — رفع الإصدار إلى `1.0.46+46`؛ `flutter build apk --release` — بناء APK (59.3 MB) | إصدار شامل لجميع تحديثات 2026-04-01/02 |
| 2026-04-02 | `ai_assistant_page.dart` + `app_localizations.dart` — دعم مرفقات متعددة: إضافة `_Attachment` class بـ `bytes/name/mime/erpUrl`؛ `_Message.attachments` قائمة بدلاً من حقول فردية؛ `_pendingAttachments` بدلاً من `_attachmentBytes/Name/Mime`؛ `_pickAttachment()` يدعم اختيار متعدد من المعرض والملفات؛ `_AttachmentGrid` widget بتخطيط WhatsApp (1/2/شبكة 2×2 مع "+N")؛ `_InputBar` يعرض شريط أفقي قابل للتمرير للمرفقات المعلقة مع زر X لكل منها؛ `_uploadAttachmentsToErpNext()` يرفع الملفات للخادم في الخلفية ويحفظ `erpUrl`؛ `_autoSave()` يُضمّن روابط المرفقات (v:2)؛ `_openHistory()` يستعيد المرفقات من الـ URL؛ صور ERPNext تُحمَّل بـ `Image.network` + session cookie؛ `app_localizations.dart` — إضافة `multipleSelection` + `savedToSystem`؛ `pubspec.yaml` — `1.0.50+50`؛ APK (59.8 MB) | دعم إرفاق عدة صور وملفات في رسالة واحدة مع حفظها في ERPNext وعرضها بأسلوب WhatsApp |
| 2026-04-02 | `ai_assistant_page.dart` — عرض الصور في فقاعة المحادثة (WhatsApp style): `_MessageBubble` يعرض الصورة بعرض كامل قابلة للضغط لفتح `_showFullImage` (Dialog مع `InteractiveViewer` للتكبير + زر إغلاق)؛ الملفات تظهر كبطاقة بأيقونة + اسم؛ إضافة RULE 0.5 في system prompt: AI يحلل الصورة/الملف فور الاستلام → يستخرج البيانات → يبحث في FAC ويُنفّذ العملية المناسبة (فاتورة/موظف/مستند) تلقائياً عند "اعمل الازم"؛ `pubspec.yaml` — `1.0.49+49`؛ APK (59.7 MB) | الصورة تظهر في المحادثة والنظام يقرأها ويعمل الازم عبر FAC |
| 2026-04-02 | `ai_assistant_page.dart` — إضافة `_extractFileText()`: استخراج نص الملفات للـ AI — نصية (txt/csv/json/xml/md/py/js...) تُفكّ بـ UTF-8 مباشرة، XLSX/DOCX (ZIP magic PK\x03\x04) تُستخرج نصوص XML بـ latin1 + regex؛ الملف يُرسل كـ ` ```content``` ` في الرسالة بدلاً من `[Attached file: name]`؛ الصور بدون caption تُضاف تعليمة "Please analyze this image." تلقائياً؛ `pubspec.yaml` — `1.0.48+48`؛ APK (59.7 MB) | AI يقرأ محتوى الملفات المرفقة ويحللها بدلاً من رؤية الاسم فقط |
| 2026-04-02 | `pubspec.yaml` — إضافة `image_picker ^1.0.7`؛ `AndroidManifest.xml` — إضافة CAMERA + READ_MEDIA_IMAGES/VIDEO؛ `ai_assistant_page.dart` — إعادة تصميم `_pickAttachment()` بأسلوب WhatsApp: Bottom Sheet مع 3 خيارات (كاميرا/معرض/ملف)، للصور: `_showImagePreview()` تعرض معاينة كاملة قابلة للتكبير + حقل caption + زر إرسال فوري؛ `app_localizations.dart` — إضافة `camera`/`gallery`/`document`/`addCaption`؛ `pubspec.yaml` — `1.0.47+47`؛ APK (59.7 MB) | المستخدم يريد تجربة إرفاق ملفات بأسلوب WhatsApp |
| 2026-04-02 | `login_page.dart` — إصلاح خلط BiDi في رسائل الخطأ: إضافة `_detectDir()` في `_InfoBanner` تكتشف اتجاه النص من أول حرف (نطاق عربي → RTL، غيره → LTR) وتمرره لـ `Text.textDirection` — يصلح ترتيب كلمات "VPN" وسط النص العربي | كلمة "VPN" الإنجليزية وسط الرسالة العربية كانت تكسر Unicode BiDi فيظهر النص بترتيب خاطئ |
| 2026-04-02 | `ai_assistant_page.dart` — إصلاح `_pickAttachment()` المعرّفة لكن غير مُستدعاة: إضافة `onPickAttachment`/`onClearAttachment`/`attachmentName`/`attachmentBytes`/`attachmentMime` لـ `_InputBar`؛ إضافة زر مشبك قبل حقل النص؛ معاينة المرفق فوق الحقل (صورة مصغّرة أو أيقونة ملف + زر X للإلغاء)؛ `app_localizations.dart` — إضافة `attachFile` (en+ar)؛ `flutter build apk --release` — APK (59.3 MB) | إصلاح: زر رفع الملفات كان غير موصول — `_pickAttachment` كانت تُعرَّف لكن لا شيء يستدعيها |
| 2026-04-01 | `ai_assistant_page.dart` — إضافة ميزة رفع الملفات والصور: `_attachmentBytes/Name/Mime` في state + `_pickAttachment()` (FilePicker.any) + `_mimeFromExt()` + `_isImage()`؛ الصور تُرسل كـ base64 لـ Claude (type:image/source:base64) وChatGPT (type:image_url/data:mime;base64)؛ الملفات غير الصور تُرسل كنص `[Attached file: name]`؛ `_runClaudeLoop` يقبل `claudeUserContent` اختيارياً؛ `_InputBar` يعرض زر مشبك + معاينة صورة/ملف فوق حقل النص مع زر X للإلغاء؛ `_MessageBubble` يعرض الصورة/اسم الملف في الفقاعة؛ `app_localizations.dart` — `attachFile` + `removeAttachment`؛ `pubspec.yaml` — `1.0.45+45`؛ APK (59.3 MB) | المستخدم يريد إرفاق صورة أو ملف مع رسالته للذكاء الاصطناعي |
| 2026-04-01 | `ai_assistant_page.dart` — إعادة كتابة RULE 4 "Fast Document Creation Protocol": حذف validate_only كخطوة إلزامية (جولة مضيعة)؛ حظر مطلق لإدراج `reports_to/leave_policy/salary_mode/holiday_list` بدون طلب صريح من المستخدم؛ تسريع: STEP 1 يُلزم بتشغيل get_doctype_info + get_list معاً في batch واحد متوازٍ؛ إضافة جدول ترجمة ثابت (ذكر→Male, اليوم→YYYY-MM-DD) بدون استدعاء get_list عند الوضوح؛ حد أقصى 2 retries؛ تقرير النتيجة بسطر واحد؛ `pubspec.yaml` — `1.0.44+44`؛ APK (59.3 MB) | `reports_to` كان يُدرج دائماً فيفشل بـ "cannot report to himself"؛ والأداء كان بطيئاً بسبب الاستدعاءات التسلسلية |
| 2026-04-01 | `ai_assistant_page.dart` — إعادة كتابة RULE 4 مرة ثانية: حظر مطلق لعرض الخيارات (1/2/3) أثناء العمليات، إضافة STEP 1 "TRANSLATE USER INPUT" يُلزم AI بترجمة كل قيمة عربية/مترجمة إلى المفتاح الإنجليزي عبر get_list قبل أي عملية (ذكر→Male, اليوم→YYYY-MM-DD...)، تبسيط PHASE 2/3/4 مع حل reports_to كأول ما يُحذف عند general_error، STEP 5: تقرير النتيجة فقط بجملة واحدة؛ `pubspec.yaml` — `1.0.43+43`؛ `flutter build apk --release` — APK (59.3 MB) | AI كان يزال يعرض خيارات بدل التنفيذ ولا يترجم "ذكر" تلقائياً إلى "Male" |
| 2026-04-01 | `ai_assistant_page.dart` — إعادة كتابة RULE 4 كـ "Smart Document Creation Protocol" بـ 3 مراحل: (1) DISCOVER: `get_doctype_info` + `get_list` لكل Link field لجلب القيم الصحيحة، (2) VALIDATE: `create_document(validate_only=true)` لكشف الخطأ الحقيقي بدون إنشاء الوثيقة → تصحيح → validate مجدداً حتى النجاح، (3) CREATE: `create_document(validate_only=false)` بالـ payload المتحقق منه؛ قواعد خاصة: gender من `get_list("Gender")`، dates بصيغة YYYY-MM-DD، حظر القيم المترجمة في Link/Select fields؛ `pubspec.yaml` — `1.0.42+42`؛ `flutter build apk --release` — APK (59.3 MB) | إصلاح جذري: `general_error` مع `"error":""` كان يوقف AI لأن FAC لا يُعيد نص الخطأ — validate_only=true يكشف الخطأ الحقيقي |
| 2026-04-01 | `ai_assistant_page.dart` — إضافة `_isDnsError()` يكتشف `Failed host lookup / No address associated / errno=7/101/111`؛ تعديل `_isRetryableError()` لاستثناء DNS (retry لا يفيد)؛ إضافة `_friendlyError()` يحوّل أخطاء الشبكة الخام إلى رسائل عربية واضحة: DNS → "لا يوجد اتصال بالإنترنت..."، Timeout → "انتهت مهلة الاتصال..."؛ `_withRetry` يُمرر الخطأ عبر `_friendlyError` في جميع الحالات؛ `pubspec.yaml` — `1.0.41+41`؛ `flutter build apk --release` — APK (59.3 MB) | إصلاح: `ClientException with SocketException: Failed host lookup 'api.openai.com'` كانت تظهر خاماً للمستخدم |
| 2026-04-01 | `ai_assistant_page.dart` — تقوية RULE 2: إضافة "اكمل/استمر/تفضل/نفذ" لقائمة كلمات الاستمرار، حظر صريح لسؤال "What task do you mean?" ← يعود دائماً للمهمة الأخيرة؛ إعادة كتابة RULE 4 بحالتَين: (A) error فارغ/general_error → استدعاء `get_doctype_info` أولاً لمعرفة الحقول الإلزامية ثم إعادة المحاولة مع جميع الحقول، (B) error واضح → إصلاح الحقل المحدد فقط؛ رفع loop limit من 10 إلى 15 لكلا المزودَين + تحديث nudge threshold من `< 9` إلى `< 14`؛ `pubspec.yaml` — `1.0.40+40`؛ `flutter build apk --release` — APK (59.3 MB) | إصلاح: (1) AI يسأل "أي مهمة؟" عند "استمر" بدل التنفيذ، (2) error فارغ `"error":""` كان يوقف AI بدون retry، (3) "No response received" بعد عمليات متعددة الخطوات |
| 2026-04-01 | `settings_page.dart` — إعادة كتابة `_exportSettings()`: بدل حفظ في مسار مخفي → كتابة JSON مُنسَّق في `getTemporaryDirectory()` ثم `SharePlus.instance.share(XFile)` يفتح share sheet (WhatsApp / Drive / Email / حفظ...)؛ إعادة كتابة `_importSettings()`: تغيير `FileType.custom` إلى `FileType.any` (لقبول الملفات من Drive/WhatsApp بدون MIME صحيح)، إضافة تحقق أن الملف JSON صالح وأنه يحتوي مفتاح ERPNext واحد على الأقل، تصفية المفاتيح الغريبة قبل الحفظ، رسالة نجاح تُظهر عدد الإعدادات المستوردة؛ `pubspec.yaml` — `1.0.39+39`؛ `flutter build apk --release` — APK (59.3 MB) | التصدير كان يحفظ في مسار مخفي لا يصله المستخدم؛ الاستيراد كان يرفض ملفات Drive/WhatsApp بسبب MIME غير صحيح |
| 2026-04-01 | `ai_assistant_page.dart` — إضافة `_withRetry<T>()` + `_isRetryableError()`: إعادة محاولة تلقائية مرة واحدة (بعد 2 ثانية) عند `ClientException: Software caused connection abort` / `connection reset` / `broken pipe` / `TimeoutException` / `connection closed`؛ تطبيق `_withRetry` على `_callChatGPT` + `_callClaude` + `_mcpRequest`؛ `pubspec.yaml` — `1.0.38+38`؛ `flutter build apk --release` — APK (59.3 MB) | إصلاح: Android يقطع الاتصال بـ OpenAI/Claude في منتصف الطلبات الطويلة فيظهر "Software caused connection abort" |
| 2026-04-01 | `test/widget_test.dart` — تحديث اسم الحزمة من `fikra_app` إلى `sadid_ai`؛ تصحيح قيم `AppColors` لتطابق القيم الفعلية (blue-500 + slate palette) بدلاً من القيم القديمة؛ توسيع اختبار AppColors ليشمل 7 ثوابت | إصلاح فشل الاختبارات بعد إعادة التسمية وإعادة التصميم |
| 2026-04-01 | `ai_assistant_page.dart` — إضافة زر "محادثة جديدة" (أيقونة `add_comment_outlined`) في AppBar قبل زر السجل؛ `_newChat()`: dialog تأكيد ثنائي اللغة ثم مسح الرسائل والتاريخ وإعادة تعيين `_sessionNote = null` (المحادثة الحالية محفوظة، الجلسة الجديدة تبدأ Note منفصلة)؛ `app_localizations.dart` — إضافة `newChatConfirm`؛ `pubspec.yaml` — `1.0.37+37`؛ `flutter build apk --release` — APK (59.3 MB) | المستخدم يريد بدء محادثة جديدة بضغطة واحدة دون فقدان المحادثة الحالية |
| 2026-04-01 | `settings_page.dart` — إضافة `buildLogoWidget()` function عامة (File image → fallback asset)؛ إضافة قسم "شعار التطبيق" في Settings: معاينة الشعار الحالي + زر "اختر شعاراً" (FilePicker image) + زر "إزالة الشعار المخصص"؛ صورة مختارة تُنسخ إلى `getApplicationDocumentsDirectory()/custom_logo.png`، المسار يُحفظ في `custom_logo_path` بـ SharedPreferences؛ `login_page.dart` — تحميل `custom_logo_path` في `_checkCredentials()` + استخدام `buildLogoWidget()`؛ `main.dart` — تحويل `HomePage` من StatelessWidget إلى StatefulWidget مع `_loadLogoPath()` + تحديث الـ logo عند العودة من Settings؛ `pubspec.yaml` — `1.0.36+36`؛ `flutter build apk --release` — APK (59.3 MB) | المستخدم يريد رفع شعاره الخاص بدلاً من KCSC_Logo.png |
| 2026-04-03 | `ai_assistant_page.dart` — إضافة قسم **HR ONBOARDING AGENT** في system prompt: workflow كامل من 12 خطوة (STEP 0→12) يغطي دورة حياة الموظف من التوظيف حتى الإنهاء (Recruitment → Job Offer → Employee → Onboarding → Tasks → User Account → HR Config → Documents → Finalization)؛ state tracking داخلي (employee/job_applicant/job_offer/onboarding_record/completed_steps)؛ FAC-first لكل عملية؛ قواعد: لا تتخطى خطوة صامتاً، "استمر" يستأنف من آخر نقطة | دعم workflow استقبال الموظف الجديد بشكل منظم وكامل |
| 2026-04-03 | `ai_assistant_page.dart` — إصلاح ربط المرفقات بملف الموظف: (1) توسيع RULE 0.5 بخطوتَين إلزاميتَين بعد إنشاء أي مستند — STEP A: `update_document({image: file_url})` لحقل الصورة، STEP B: `create_document(File, {attached_to_doctype, attached_to_name, file_url, is_private:1})` لربط الملف بتاب Attachments؛ (2) تحديث `fileUrlContext` المُرسَل للـ AI ليشمل تعليمات STEP A/B الصريحة مع placeholder للـ DOCTYPE/DOCNAME؛ (3) إضافة `_linkFileToDocument()` utility في Flutter كـ fallback يُنشئ `File` record عبر `ApiService.post('/api/resource/File')` مع `attached_to_doctype/name`؛ `pubspec.yaml` — `1.0.54+54`؛ APK (60.0 MB) | الملفات المرفوعة كانت "يتيمة" في `/files/` ولا تظهر في تاب Attachments للموظف لأن Frappe يفصل بين رفع الملف وربطه بمستند |
| 2026-04-06 | `ai_assistant_page.dart` + `app_localizations.dart` — **public/private للملفات + إصلاح "من المحادثة"**: (1) إضافة `isPrivate` + `fromHistory` لـ `_Attachment`؛ (2) `_showImagePreview` → StatefulBuilder مع toggle عام/خاص (افتراضي: عام) قبل الإرسال؛ (3) `_showConversationImagesSheet` → لا تحميل bytes، فقط `fromHistory: true` مع erpUrl — لا إعادة رفع ولا إعادة إرسال base64؛ (4) `_sendMessage` STEP 1/2: تجاهل `fromHistory` في `_ensureBytes` وبناء base64؛ (5) `_uploadAttachmentsToErpNext`: تجاهل `fromHistory` + استخدام `a.isPrivate`؛ (6) System prompt RULE 0.5: AI يسأل عن عام/خاص قبل إنشاء File record، يستخدم is_private=0 افتراضياً عند "اعمل الازم"؛ `pubspec.yaml` — `1.0.60+60`؛ APK (60.6 MB) | الملف الخاص يسبب "Insufficient read permissions" عند ربطه بالموظف؛ "من المحادثة" كانت تُعيد تحميل ورفع الصورة كاملة دون داعٍ |
| 2026-04-06 | `ai_assistant_page.dart` — **تغيير نموذج رفع الملفات**: التطبيق يرفع الملف إلى ERPNext كـ binary (ضرورة تقنية — FAC لا يدعم رفع binary) ويُبلّغ AI بـ file_url فقط؛ AI هو من يقرر ربط الملف بالمستند عبر FAC بناءً على طلب المستخدم؛ حذف `_processFileLinkTags` + `_linkFileToDocument` من جانب التطبيق؛ تحديث RULE 0.5 في system prompt — لا ربط تلقائي، AI ينتظر طلب المستخدم أو "اعمل الازم" | المستخدم يريد AI هو من يتحكم في رفع الملف وربطه بدلاً من التطبيق |
| 2026-04-06 | `ai_assistant_page.dart` — **إصلاح جذري لرفع الصور**: إعادة ترتيب `_sendMessage` إلى 5 خطوات واضحة: (1) `_ensureBytes` لضمان وجود البايتات، (2) بناء `claudeImageBlocks`/`openAiImageBlocks` بـ base64 **قبل** أي رفع، (3) `_uploadAttachmentsToErpNext` لرفع الملفات والحصول على `erpUrl`، (4) بناء `fileUrlContext` مع الـ URLs المؤكدة، (5) دمج المحتوى النهائي مع الصور والنص؛ نقل `_freeUploadedBytes()` من داخل `_uploadAttachmentsToErpNext` إلى `finally` block في `_sendMessage` — الذاكرة تُحرَّر **بعد** انتهاء الـ AI؛ `pubspec.yaml` — `1.0.58+58`؛ APK (60.3 MB) | السبب الجذري لـ "لا أستطيع رفع ملفات من جهازك": `_freeUploadedBytes` كانت تُستدعى داخل `_uploadAttachmentsToErpNext` مما يُفرغ البايتات قبل بناء base64 → AI يرى `bytes.isEmpty` فيرفض إرسال الصورة |
| 2026-04-06 | `ai_assistant_page.dart` + `app_localizations.dart` — **زر Stop لإيقاف الـ AI**: إضافة `_isCancelled` flag + `_cancelAI()` method؛ فحص `_isCancelled` في بداية كل loop iteration لـ Claude وChatGPT → توقف فوري بين tool calls؛ زر الإرسال يتحول لزر Stop أحمر (`stop_rounded`) أثناء المعالجة، يعود لزر الإرسال عند الانتهاء؛ استجابة "تم الإيقاف." تُضاف للمحادثة إن كان هناك رد جزئي، وإلا تُلغى بصمت؛ `pubspec.yaml` — `1.0.57+57`؛ APK (60.3 MB) | المستخدم يريد إيقاف التحليل الطويل وتغيير طلبه |
| 2026-04-06 | `ai_assistant_page.dart` — (1) **حفظ الرسالة فوراً**: `_autoSave()` يُستدعى مباشرة بعد إضافة رسالة المستخدم للـ UI (قبل انتظار رد الـ AI) → الرسالة محفوظة حتى لو أُغلق التطبيق؛ (2) **تنظيف الذاكرة من السياق القديم**: إضافة `_stripOldImages()` static helper يُبدّل محتوى الصور (base64) في رسائل التاريخ القديمة بمرجع نصي بسيط → يمنع تلوث السياق بين المواضيع ويحرر الذاكرة؛ (3) **`fileUrlContext` في مقدمة الرسالة**: نُقل من نهاية الرسالة إلى بدايتها بتنسيق ⚠️ واضح — AI لا يستطيع تجاهله؛ حالة فشل الرفع تُبلَّغ صراحةً بدلاً من الصمت؛ (4) **Onboarding → Employee Link**: توثيق صريح لحقلَي `employee` (Link=HR-EMP-XXXXX) و`employee_name` (نص) وكلاهما إلزامي؛ فحص السجلات الموجودة قبل الإنشاء (draft/submitted)؛ (5) **Loop limit 15→20** + nudge threshold 14→19 لكلا Claude وChatGPT؛ (6) حذف `sadid_logo.png` الفاسدة (JPEG مُسمّاة PNG) من `android/res/mipmap-*` — كانت تمنع بناء الـ APK؛ `pubspec.yaml` — `1.0.56+56`؛ APK (60.3 MB) | إصلاح: رسائل تضيع عند إغلاق التطبيق + تلوث السياق بالصور القديمة + AI يسأل عن file_url رغم وجوده + Onboarding لا يربط بالموظف + "No response received" للعمليات الطويلة |
| 2026-04-06 | `ai_assistant_page.dart` — **إصلاح جذري لرفع الصور وعرضها**: (1) الخطأ الجذري كان cookie مُضاعف `sid=sid=VALUE` — ‏`erpnext_session_cookie` مخزّن كـ `'sid=VALUE'` لكن الكود كان يُضيف `'sid='` مجدداً في كل مكان؛ (2) `_uploadAttachmentsToErpNext`: استبدال الـ manual cookie بـ `getAiAuthHeaders()` يدعم كلا المصادقة (token/session) مع CSRF فقط عند session auth؛ (3) `_ensureBytes`/`_buildImageTile`/`_showFullImage`/`_MyFilesSheet`/`_ConversationImagesSheet`: إزالة prefix `'sid='` الزائد — cookie يُستخدم مباشرة من SharedPreferences؛ (4) إضافة `errorBuilder` لـ `Image.network` في `_buildImageTile`؛ `pubspec.yaml` — `1.0.59+59`؛ APK (60.5 MB) | الصور لم ترفع لـ ERPNext (FAILED) وتختفي من المحادثة بسبب `sid=sid=VALUE` الذي يرفضه الخادم |
| 2026-04-07 | `ai_assistant_page.dart` + `pubspec.yaml` — **إصلاح استخراج النصوص العربية من الملفات**: (1) إضافة `archive: ^3.4.9`؛ (2) إعادة كتابة `_extractFileText` كلياً: DOCX/ODT يستخدم `ZipDecoder` + `utf8.decode` لاستخراج `<w:t>` من `word/document.xml`، XLSX يستخرج `xl/sharedStrings.xml`، PPTX يستخرج `ppt/slides/*.xml`؛ (3) PDF: استخراج نصوص BT/ET مع فحص مقروئية؛ (4) إعادة كتابة `_mimeFromExt`: تغطية شاملة لـ doc/xls/ppt/odt/ods/odp/heic/csv/zip وغيرها — لم تكن تُرجع سوى `application/octet-stream` للأنواع غير المعروفة مما يتلف الملف عند الرفع؛ `pubspec.yaml` — `1.0.61+61`؛ APK (60.6 MB) | الكود القديم استخدم `latin1.decode` على ZIP ثم regex → النص العربي (UTF-8 داخل XML) يظهر هراء؛ أنواع doc/xls/ppt كانت ترفع بـ octet-stream فيتلف الملف |
| 2026-04-06 | `pubspec.yaml` + `flutter_launcher_icons` — إضافة `flutter_launcher_icons: ^0.14.3` وتهيئة icon من `images/sadid-logo.png` مع خلفية `#0F172A`؛ تشغيل `dart run flutter_launcher_icons` لتوليد جميع أحجام mipmap تلقائياً | تغيير أيقونة التطبيق على Android إلى لوجو Sadid (لاحقاً استُبدل بـ msiam_erp.jpeg) |
| 2026-04-09 | `ai_assistant_page.dart` — **(1) HR Identity في system prompt**: إضافة قسم IDENTITY في أعلى الـ prompt يُعرّف المساعد بأنه "Sadid HR AI Agent" مع ردود جاهزة بالعربي/الإنجليزي على أسئلة "من أنت؟"؛ **(2) HR Quick Actions**: استبدال `_EmptyState` بواجهة HR متخصصة تعرض 6 أزرار سريعة (موظف جديد / رواتب / إجازات / تقييم / بحث / تقارير) تُرسل الرسالة مباشرة دون الحاجة للكتابة؛ **(3) Session Context Restore**: `_persistHistory()` يحفظ آخر 10 رسائل في SharedPreferences + `_loadPersistedHistory()` يستعيدها عند فتح التطبيق دون أي HTTP call — AI يتذكر سياق المحادثة السابقة؛ **(4) Session Isolation المحسّن**: إضافة `_isCancelled = true` في `_clearChat` + `_newChat` + `_openHistory` لإيقاف أي AI loop نشط فور تبديل المحادثة؛ **(5) overrideText في `_sendMessage`**: قبول prompt مباشر بدون كتابة في حقل النص — يُستخدم من HR Quick Actions؛ **(6) PDF RTL hint**: تعليمة في system prompt لإعادة ترتيب الأحرف العربية المعكوسة من PDF؛ `app_localizations.dart` — 9 مفاتيح جديدة للـ HR UI؛ `pubspec.yaml` — `1.0.62+62`؛ APK (60.6 MB) | HR Agent متخصص + ذاكرة بين الجلسات + عزل محادثات محسّن + اختصارات سريعة |
| 2026-04-09 | `ai_assistant_page.dart` — **(Task 11) رسالة ترحيب احترافية**: إضافة `_buildWelcomeMessage()` تبني رسالة ترحيب حسب الوقت (صباح/مساء) والموديول النشط (HR أو غيره)؛ `_injectWelcomeMessage()` تُظهر مؤشر التحميل 800ms ثم تضيف الرسالة للـ UI بدون إضافتها لـ `_claudeHistory` أو `_openAiHistory` (توفير tokens)؛ استدعاء في 3 أماكن: `_loadConfig()` (بداية التطبيق) + `_newChat()` (محادثة جديدة) + `_activateModuleAgent()` (تغيير الموديول)؛ `pubspec.yaml` — `1.0.63+63`؛ APK (60.7 MB) | المستخدم لا يبدأ بشاشة فارغة — الـ AI يرحب ويعرّف بنفسه فوراً |
| 2026-04-09 | `ai_assistant_page.dart` + `app_localizations.dart` — **(Task 9) إصلاح خطأ `workflow_state` في Leave Application**: إضافة قسم `HR MODULE — CRITICAL FIELD RULES` في system prompt يحظر `workflow_state` صراحةً من: Leave Application / Salary Slip / Attendance / Employee Checkin / Leave Allocation / Leave Encashment؛ الفلتر الصحيح للإجازات المعلقة: `[["docstatus","=",0],["status","=","Open"]]`؛ فلتر Salary Slip عبر `docstatus` فقط؛ إصلاح KPI في MODULE EXPERTISE للـ Leave Application؛ تحديث prompt زر "طلبات الإجازات" ليتضمن الفلتر الصحيح صراحةً — **(Task 10) نظام Module Specialization**: إضافة `_activeModule` + `_activeModuleLabel` في state + SharedPreferences (`active_ai_module` / `active_ai_module_label`)؛ `_showModuleOptions(label)` — bottom sheet بخيارَين: "اسأل عن الموديول" (استعلام مباشر) أو "تفعيل وكيل الموديول" (تغيير سياق الـ AI كاملاً)؛ `_activateModuleAgent()` — يمسح المحادثة، يحفظ الاختيار في SharedPreferences، يُظهر Snackbar تأكيد؛ `_buildSystemPrompt()` ديناميكي: IDENTITY يتغير بحسب الموديول النشط؛ `_EmptyState` يقبل `activeModule`/`activeModuleLabel`: إذا HR → HR Quick Actions المعتادة، إذا غير HR → 3 chips عامة (داشبورد/تقارير/ملخص) + زر "العودة لـ HR Agent"؛ `_ModuleOptionTile` widget جديد؛ حذف فلتر `public==1` من `_loadErpModules()` — Frappe يُصفّي بالصلاحيات؛ empty state مع أيقونة قفل عند عدم وجود موديولز؛ 13 مفتاح ترجمة جديد؛ `pubspec.yaml` — `1.0.63+63`؛ APK (60.7 MB) | إصلاح DB column error + تخصيص الـ AI لأي موديول من النظام |
| 2026-04-09 | `ai_assistant_page.dart` — **(1) زر موديولز ERPNext في Empty State**: `_erpModules` + `_modulesLoaded` في الـ state، `_loadErpModules()` يجلب `get_workspace_sidebar_items` في الخلفية عند `_loadConfig()`؛ **(2) `_showModulesSheet()`**: Bottom Sheet قابل للسحب (DraggableScrollableSheet) يعرض ListView للموديولز مع تمييز HR بلون وأيقونة مختلفة؛ **(3) `_modulePrompt(label)`**: دالة ذكية تُولّد prompt مخصص لكل موديول (HR/محاسبة/مبيعات/مشتريات/مخزون/تصنيع/مشاريع/أصول/جودة) يطلب KPIs حقيقية عبر FAC — لا تخمين؛ **(4) MODULE EXPERTISE في system prompt**: قسم جديد يُعرّف FAC queries المطلوبة لكل موديول مع أولوية HR؛ `app_localizations.dart` — إضافة `erpModules` + `browseModules`؛ `pubspec.yaml` — `1.0.62+62`؛ APK (60.6 MB) | التنقل السريع بين موديولز ERPNext مع prompts ذكية تجلب KPIs حقيقية عبر FAC |
| 2026-04-09 | `ai_assistant_page.dart` — **إصلاح اختفاء قائمة الموديولز**: (1) إضافة زر `Icons.apps_rounded` في AppBar (دائماً مرئي) يستدعي `_showModulesSheet()` — الزر يظهر بغض النظر عن حالة `_messages`؛ (2) إضافة شارة الموديول النشط `⚡ _activeModuleLabel` تحت عنوان AppBar — يُظهر الوكيل الحالي للمستخدم؛ (3) إصلاح شرط أزرار "محادثة جديدة" و"مسح" من `_messages.isEmpty` إلى `_messages.any((m) => m.role == 'user')` — لا تُعطَّل بسبب رسالة الترحيب المُحقونة؛ `pubspec.yaml` — `1.0.64+64`؛ APK (60.7 MB) | الموديولز كانت تختفي لأن `_injectWelcomeMessage()` تجعل `_messages.isEmpty = false` فيُخفي `_EmptyState` الذي يحتوي زر الموديولز — الحل: نقل الزر للـ AppBar |
| 2026-05-04 | `ai_assistant_page.dart` — **(1) تغيير الاسم**: "Sadid HR/Module AI Agent" → "KCSC ERP AI Agent" في `_buildWelcomeMessage()` + `_buildSystemPrompt()` + `_EmptyState`؛ **(2) system prompt**: المشتريات أولوية قصوى في MODULE EXPERTISE (نُقلت للمقدمة + تفاصيل أوسع)؛ **(3) `_EmptyState` جديد**: استبدال أزرار HR الخاصة بـ Grid 2×3 من `_ModuleCard` يغطي 6 موديولات (مشتريات/محاسبة/HR/مخزون/تصنيع/مبيعات) مع ألوان مميزة وبطاقات احترافية؛ إضافة `_ModuleInfo` data class + `_ModuleCard` widget؛ حذف `_HrActionChip` ← `dashboards_page.dart` + `dashboard_detail_page.dart` — إضافة `Timer` auto-refresh كل 5 دقائق (silent في الخلفية) + عرض "Updated HH:MM · auto every 5 min" في AppBar + زر refresh يتحول لـ spinner أثناء التحميل | تحويل المساعد من متخصص HR إلى وكيل ERP شامل + تحديث تلقائي للداشبوردات |
| 2026-05-04 | `ai_assistant_page.dart` — **أزرار الموديولات أسفل رسالة الترحيب**: إضافة `_showModuleButtons` flag (true عند الترحيب، false عند أول رسالة مستخدم)؛ تعديل ListView.builder ليُدرج `_InlineModuleGrid` كـ rawIndex==1 بعد فقاعة الترحيب مباشرة؛ إضافة `_InlineModuleGrid` widget يعرض نفس شبكة 6 بطاقات `_ModuleCard` بدون header؛ reset في `_clearChat` + `_newChat` + `_injectWelcomeMessage`؛ `_openHistory` يضبط false لأن المحادثات المُستعادة لا تحتاج الأزرار | المستخدم يرى أزرار الموديولات تحت رسالة الترحيب ويمكنه اختيار موديول، تختفي الأزرار بعد أول رسالة يرسلها |
| 2026-05-04 | `ai_assistant_page.dart` — **قواعد run_python_code الشاملة في system prompt**: (1) Decision Rule: استخدم `get_list` FAC مباشرة للاستعلامات البسيطة — لا `run_python_code` إلا للحسابات المعقدة؛ (2) داخل sandbox: `frappe.get_list()` / `frappe.db.sql()` فقط — `tools.get_documents()` محظور؛ (3) قائمة الكلمات المحجوبة في أسماء المتغيرات: `requests`/`socket`/`subprocess`/`os.system` مع بدائل (req / conn / proc) — كلمة "requests" في اسم متغير تُطلق Security block فورياً | إصلاح: `tools.get_documents()` غير موجود في sandbox؛ و`material_requests_pending_count` كانت تُطلق `Security: Network access not allowed` |
| 2026-05-04 | `settings_page.dart` — `buildLogoWidget()`: تأكيد `images/KCSC_Logo.png` كشعار افتراضي؛ إضافة `fit: BoxFit.contain` لكلا حالتَي File و Asset؛ `pubspec.yaml` + `flutter_launcher_icons` — تأكيد `images/KCSC_Logo.png` كأيقونة التطبيق مع خلفية `#0F172A` | توحيد الهوية البصرية للتطبيق بشعار KCSC الرسمي |
| 2026-05-04 | **إزالة كلمة "Sadid" من كامل التطبيق**: `main.dart` — `title: 'Sadid App'` → `'KCSC AI'`؛ `app_localizations.dart` — `appTitle` EN/AR → `'KCSC AI'`؛ `welcome` EN → `'Welcome to KCSC AI'`، AR → `'مرحباً بك في KCSC AI'`؛ `settings_page.dart` — subject بريد النسخ الاحتياطي + رسالة خطأ الاستيراد → `'KCSC AI'`؛ `CLAUDE.md` — تحديث العنوان والإصدار | المستخدم طلب إزالة كلمة "Sadid" بالكامل واستبدالها بـ "KCSC AI" في كل واجهات التطبيق |
| 2026-04-05 | `ai_assistant_page.dart` — (1) **عزل المحادثات**: إضافة `_sessionId` يُزاد عند تغيير المحادثة؛ `_sendMessage` يحفظ `mySession` ويتحقق منه قبل كتابة الرد → رد الـ agent لا يصل لمحادثة مختلفة؛ (2) **إلغاء التسجيل الصوتي**: إضافة `_cancelRecord()` + زر إلغاء أحمر يظهر أثناء التسجيل بدل زر المرفقات؛ `app_localizations.dart` — إضافة `cancelRecording`؛ (3) **تحرير الذاكرة**: إضافة `_freeUploadedBytes()` تحذف البايتات من المرفقات المرفوعة لـ ERPNext (erpUrl موجود) → استهلاك ذاكرة أقل؛ (4) **ربط الصور بالمستندات**: إضافة STEP C إلى RULE 0.5 — AI يُدرج `<file_link doctype="X" docname="Y"/>` في الرد؛ إضافة `_processFileLinkTags()` يقرأ هذه التاغات ويستدعي `_linkFileToDocument` تلقائياً كشبكة أمان؛ (5) **مهام Onboarding Template**: تحديث STEP 4 — استخدام `get_document` (لا `get_list`) لعرض activities child table؛ STEP 5 — فحص project field بعد submit، عرض Tasks كجدول؛ STEP 6 — تحذير من السجلات القديمة المتعارضة؛ `pubspec.yaml` — `1.0.55+55`؛ APK (60.3 MB) | إصلاح 5 مشاكل: رفع الصور، إلغاء التسجيل، تسرب الذاكرة، تلوث المحادثات، مهام Onboarding |
| 2026-05-05 | **نظام الثيم الثنائي (Light/Dark) الشامل**: `app_colors.dart` — إعادة كتابة `AppColors` كـ instance مع `light`/`dark` static + `AppColors.of(context)` factory؛ `app_theme.dart` — ملف جديد يُعرّف `AppTheme.light` و `AppTheme.dark` (Material 3)؛ `main.dart` — `themeMode`/`darkTheme` + تبديل افتراضي إلى Light/English؛ `settings_page.dart` — زر تبديل light/dark/system؛ `widget_test.dart` — إصلاح من static إلى instance access؛ تطبيق `AppColors.of(context)` على جميع الصفحات الـ 12؛ `dashboards_page.dart` + `dashboard_detail_page.dart` — إصلاح ألوان كاملة للـ CustomPainter (تمرير gridColor/labelColor/textColor) + ترجمة جميع نصوص الواجهة عبر `AppLocalizations`؛ `app_localizations.dart` — إضافة `updatedAtLine`/`timespanLabel`/`timegrainLabel` وغيرها؛ `flutter build apk --release` — APK (60.3 MB) | دعم الوضعَين الفاتح والغامق بشكل كامل في جميع الصفحات |
| 2026-05-05 | **توحيد هوية التطبيق بشعار KCSC_Logo.png**: حذف الصور القديمة (`msiam_erp.jpeg`، `msiam_erp1.jpeg`، `sadid-logo.png`) من `images/`؛ `pubspec.yaml` `flutter_launcher_icons` — `image_path` + `adaptive_icon_foreground` تشيران لـ `images/KCSC_Logo.png`؛ تشغيل `dart run flutter_launcher_icons` لإعادة توليد جميع أحجام mipmap؛ `settings_page.dart` `buildLogoWidget()` — الشعار الافتراضي `images/KCSC_Logo.png` مع `fit: BoxFit.contain`؛ تحديث `CLAUDE.md` شامل (هيكل الملفات + اعتماديات + ميزات + مفاتيح SharedPreferences + المشاكل المعروفة)؛ `flutter build apk --release` — APK (60.2 MB) | توحيد الهوية البصرية للتطبيق بشعار KCSC الرسمي الوحيد وتحديث التوثيق |
| 2026-05-05 | `ai_assistant_page.dart` — **خط Cairo في فقاعات المحادثة**: `_MessageBubble.build()` يكتشف اللغة عبر `AppLocalizations.of(context).isArabic` ويُطبّق `fontFamily: 'Cairo'` على label المساعد ونص الرسالة (عبر `DefaultTextStyle.merge`) — عند الإنجليزية يبقى الخط الافتراضي؛ `pubspec.yaml` — إضافة `family: Cairo` مع ملفات `fonts/Cairo-Regular/SemiBold/Bold.ttf` (offline، لا internet) | دعم العربية بخط Cairo في فقاعات الدردشة بدون تغيير باقي الواجهة |
| 2026-05-05 | `pubspec.yaml` — إضافة `family: Inter` مع ملفات `fonts/Inter-Regular/SemiBold/Bold.ttf`؛ `ai_assistant_page.dart` — **(1) حذف زر apps_rounded** من AppBar + حذف `_showModulesSheet()` غير المُستخدمة + حذف `_erpModules`/`_modulesLoaded` الـ dead state؛ **(2) إصلاح شارة الموديول**: حذف `Flexible`+`overflow:ellipsis` — اسم الموديول الكامل ("Human Resources") يظهر بلا قطع؛ **(3) كشف الموديول تلقائياً**: إضافة `_detectModuleFromText()` يحلّل رد الـ AI بكلمات مفتاحية عربية/إنجليزية لـ 6 موديولات ويُحدّث `_activeModule`/`_activeModuleLabel` ويحفظ في SharedPreferences — يُستدعى بعد كل رد؛ **(4) `isWelcome` على `_Message`**: حقل جديد يُعلّم رسالة الترحيب؛ **(5) رسالة ترحيب ثنائية اللغة**: `_buildWelcomeMessage()` يُنتج عربياً أو إنجليزياً بحسب `isArabic`؛ **(6) فقاعة ترحيب احترافية**: `_buildWelcomeBubble()` — عرض 92%، حدود زرقاء، شريط header بـ "KCSC ERP AI Agent" + أيقونة، نص بـ Inter (EN) أو Cairo (AR) بحجم 14px/1.55، يتكيف مع Light/Dark؛ `flutter build apk --release` — APK (61.1 MB) | واجهة مساعد أكثر احترافية: خط مناسب لكل لغة + شارة موديول واضحة + كشف تلقائي للموديول من السياق |
| 2026-05-06 | `app_localizations.dart` — إضافة 9 مفاتيح ترجمة جديدة: `savePdf`/`saveExcel`/`sendByEmail`/`sendEmailWithPdf`/`emailAddress`/`emailSubject`/`dataReport`/`send`/`chooseLogo`؛ `message_renderer.dart` — إضافة import `app_localizations.dart` + استبدال النصوص المُضمَّنة بـ `AppLocalizations.of(ctx)` في: أزرار "حفظ PDF" و"حفظ Excel" و"إرسال بالبريد" + كامل محتوى `_showEmailDialog` (عنوان + حقول + أزرار)؛ `settings_page.dart` — استبدال `Text('اختر شعاراً')` بـ `AppLocalizations.of(context).chooseLogo`؛ `pubspec.yaml` — `1.0.66+66` | تطبيق قاعدة §3 — لا نصوص مُضمَّنة في الـ widgets؛ جميع النصوص تتبدّل تلقائياً بحسب لغة التطبيق (EN/AR) |
| 2026-05-06 | **بناء Web Release** — `flutter build web --release --base-href /kcsc-ai/`؛ النشر على `https://poc.kcsc.com.jo/kcsc-ai/` عبر Nginx على خادم ERPNext؛ إضافة location block في `/etc/nginx/conf.d/frappe-bench.conf` مع `alias` + `try_files` + `Cache-Control: no-cache` | نشر التطبيق كـ PWA على الخادم بدون تثبيت Flutter على الجهاز المستهدف |
| 2026-05-06 | **إصلاح الميكروفون على Web** — `ai_assistant_page.dart`: إضافة `import 'package:flutter/foundation.dart' show kIsWeb'`؛ (1) `cancelRecord()`: guard `File.delete` بـ `!kIsWeb`؛ (2) `toggleRecord()`: على Web → `encoder: AudioEncoder.opus` + `path: ''` + try/catch يعرض رسالة الخطأ (بدون `hasPermission()` لأن المتصفح يُظهر الإذن عند `start()`)؛ على Mobile → يبقى `aacLc` + `getTemporaryDirectory()`؛ (3) `transcribeAndSend()`: على Web → `http.get(blobUrl)` لجلب البايتات + `filename: 'audio.webm'`؛ على Mobile → `File(path).readAsBytes()` + `filename: 'audio.m4a'`؛ guard `File.delete` في `finally` بـ `!kIsWeb` | الميكروفون لم يعمل على Web بسبب: `getTemporaryDirectory()` + `File` + `aacLc` كلها غير مدعومة على المتصفح |
| 2026-05-06 | **هوية التطبيق على Web** — `web/index.html`: `<title>` + `apple-mobile-web-app-title` → "KCSC AI"؛ `web/manifest.json`: `name`/`short_name` → "KCSC AI"، `background_color` → `#0F172A`، `theme_color` → `#3B82F6`، `description` → "KCSC ERP AI Assistant"؛ **أيقونات Web**: تصغير `images/KCSC_Logo.png` عبر PowerShell+.NET → `web/favicon.png` (32px) + `web/icons/Icon-192.png` + `web/icons/Icon-512.png` + `web/icons/Icon-maskable-192.png` + `web/icons/Icon-maskable-512.png` | إزالة "fikra_app" من كل واجهات الويب واستبدالها بهوية KCSC AI |
| 2026-05-06 | **`userBubble` color** — `app_colors.dart`: إضافة حقل `userBubble: Color(0xFF60A5FA)` (blue-400) لكلا الثيمَين Light و Dark؛ `ai_assistant_page.dart` `_MessageBubble`: تغيير `color: isUser ? c.primary : c.surface` → `color: isUser ? c.userBubble : c.surface` | فقاعة رسالة المستخدم كانت blue-500 (غامقة)؛ المستخدم طلب أزرق فاتح — blue-400 مرئي مع النص الأبيض |
| 2026-05-06 | `flutter build apk --release` — APK (61.1 MB) + `flutter build web --release --base-href /kcsc-ai/` — Web (40 MB) | بناء متوازٍ للمنصتَين بعد تحديثات الألوان والأيقونات |
| 2026-05-06 | **إصلاح Web: Auth + File Export** — `api_service.dart`: إضافة `kIsWeb` guard في `getAuthHeaders()` — يستدعي `getAiAuthHeaders()` (Token auth) على Web لأن المتصفح يحجب Cookie headers يدوياً → يصلح CSRFTokenError + 403 على جميع API calls؛ `message_renderer.dart` + `web_download.dart` (3 ملفات): تطبيق `kIsWeb` guard في `_savePdfToDevice`/`_saveCsvToDevice`/`_shareAsCsv` → يستدعي `downloadBytesInBrowser()` (Blob URL) بدلاً من `getExternalStorageDirectory()` + `File` + `SharePlus` (كلها غير مدعومة على Web)؛ إصلاح `web_download_web.dart`: `Uint8List.fromList(bytes).toJS` بدلاً من `bytes.toJS` (List<int> لا يدعم .toJS)؛ `pubspec.yaml` — `web: ^1.1.0`؛ APK (61.1 MB) + Web build ✅ | المساعد الذكي + حفظ PDF/Excel يعملان الآن على Web بدون أخطاء CSRF أو filesystem |
| 2026-05-06 | **إصلاح جداول HTML + تحسينات الويب** — (1) `ai_assistant_page.dart`: إزالة `DefaultTextStyle.merge(fontFamily: Cairo)` من حول `MessageRenderer` — كان يُسبّب اختفاء `DataTable` بسبب تضارب في قياس الأعمدة؛ بدلاً من ذلك تُمرَّر `fontFamily` كمعامل لـ `MessageRenderer` وتُطبَّق فقط على `SelectableText` (النص العادي) لا على الجداول أو الرسوم؛ (2) `message_renderer.dart`: إضافة `fontFamily` parameter لـ `MessageRenderer`؛ تخفيف شرط اكتشاف الجداول في `_splitTextTable` و `_HtmlTable._parse()` — لم يعد يشترط وجود `|` في نهاية السطر (يكفي `startsWith('|') && indexOf('|',1)!=-1`)؛ إصلاح `_sharePdf` على Web → `downloadBytesInBrowser` بدل print dialog؛ إصلاح `_openEmail` على Web → `launchUrl` مباشرة بدون `canLaunchUrl` (يرجع false على الويب لـ mailto: رغم دعم المتصفح له)؛ APK (61.1 MB) + Web ✅ | الجداول تعود للظهور كـ DataTable احترافي؛ PDF يُحمَّل مباشرة في المتصفح؛ الإيميل يفتح Outlook على الويب |
| 2026-05-07 | `message_renderer.dart` — **إرسال بريد مباشر على Web بدون dialog**: (1) إضافة دالة `sendEmailWebDirectly()` على مستوى الملف (top-level) — تبني `mailto:` URI وتطلقه فوراً عبر `launchUrl(mode: externalApplication)` بدون أي AlertDialog؛ تتجاوز `canLaunchUrl` (يرجع false على الويب دائماً لـ mailto:)؛ تحاول body كامل → مقطوع → subject فقط عند طول URI مفرط؛ Snackbar بالعربي عند الفشل؛ (2) زر "إرسال بالبريد" في `_HtmlTableState.build()`: تفرّع بحسب `kIsWeb` — **Web** يستدعي `sendEmailWebDirectly()` مباشرةً (بدون dialog)، **Mobile** يبقى على `_showEmailDialog()` كما هو؛ body الجدول يُمرَّر بصيغة tab-separated | المستخدم يريد ضغطة واحدة تفتح Outlook مباشرةً على الويب بدون نوافذ Flutter إضافية؛ إعداد Windows المطلوب: Settings → Apps → Default apps → Email → Outlook |
| 2026-05-07 | `message_renderer.dart` — **إرسال بريد احترافي على Web مع PDF تلقائي**: إضافة `_sendEmailWithPdfDownloadWeb()` في `_HtmlTableState` — عند الضغط على "إرسال بالبريد" على Web: (1) يُولّد PDF من بيانات الجدول ويُنزّله تلقائياً في مجلد Downloads؛ (2) يفتح Outlook compose بـ Subject جاهز وBody احترافي ثنائي اللغة يُوجّه المستخدم لإرفاق الملف؛ (3) Snackbar يظهر لـ 8 ثوانٍ يُذكّر بالإرفاق؛ Mobile يبقى على `_showEmailDialog()` — سبب الحل: `mailto:` لا يدعم إرفاق ملفات (قيد أمني في المتصفح) فالحل هو تنزيل PDF + فتح compose في آنٍ واحد | المستخدم يريد ملف مرفق تلقائياً؛ الإرفاق المباشر عبر mailto: مستحيل تقنياً من المتصفح |
| 2026-05-07 | `message_renderer.dart` — **إصلاح جذري لتعبئة Subject/Body في Outlook + إعادة تسمية**: (1) إعادة تسمية `sendEmailWebDirectly` → `sendEmailUsingActiveOutlookProfile`؛ (2) إصلاح bug الـ encoding: `Uri(queryParameters:{})` في Dart يستخدم `+` للمسافات (form-encoding) بينما `mailto:` يتطلب `%20` (RFC 6068) — Outlook Classic يرفض `+` فيظهر الـ compose فارغاً؛ الحل: بناء URI يدوياً بـ `Uri.encodeComponent()`؛ (3) حساب حد الـ body بناءً على الطول **المُشفَّر** لا الخام — النص العربي يتوسع 6× عند encoding فكان يتجاوز حد 2048 حرف للمتصفح بصمت؛ حد جديد: 1400 حرف مشفَّر (≈280 حرف عربي خام)؛ (4) تطبيق نفس الإصلاح على `_EmailButton._openEmail()` — كان يعاني من نفس bug الـ `+` encoding؛ **إعداد Windows الإلزامي**: Settings → Apps → Default Apps → Email → "Microsoft Outlook" (Classic) لا "New Outlook" — بدونه يفتح شاشة Welcome بدل Compose | Outlook Classic يعرض نافذة Compose فارغة لأن `+` بدل `%20` يجعله يتجاهل الـ query parameters |
| 2026-05-07 | **دعم Workflow الديناميكي — المرحلة 1 (البنية الأساسية)**: إضافة `lib/workflow_service.dart` — Singleton مع كاش per-doctype يغطي 3 عمليات: `getWorkflowForDocType` (GET /api/resource/Workflow)، `getTransitions` (POST frappe.model.workflow.get_transitions)، `applyWorkflow` (POST frappe.model.workflow.apply_workflow)؛ نماذج البيانات: `WorkflowInfo` + `WorkflowTransition`؛ إضافة `lib/document_viewer_page.dart` (~960 سطر) — عارض مستندات read-only: `_smartFields()` (يتخطى حقول النظام، حد 12 حقلاً)، `workflowStateColor()` و`_actionColor()` للتلوين الديناميكي، `_ActionBar` يعرض أزرار الانتقالات إذا وُجد workflow أو أزرار docstatus كـ fallback، `_executeAction()` يؤكد ثم يُطبّق ويُحدّث؛ إضافة `lib/pending_approvals_page.dart` (~280 سطر) — قائمة Workflow Action للمستخدم الحالي مع بطاقات ملونة + pull-to-refresh + تنقل لـ DocumentViewerPage | دعم كامل لـ workflow ديناميكي لأي DocType في ERPNext بدون hardcoding |
| 2026-05-07 | **دعم Workflow — المرحلة 2 (التوصيل)**: `app_localizations.dart` — إضافة 18+ مفتاح ترجمة (wfDocumentDetails/wfWorkflowState/wfConfirmAction...) مع parameterized methods؛ `main.dart` — إضافة مسارَين: `/document-viewer` (مع args doctype/docname) + `/pending-approvals`؛ `app_drawer.dart` — إضافة `DrawerSection.pendingApprovals` + أيقونة `approval_rounded` فوق قسم AI؛ `report_view_page.dart` — جلب `ref_doctype` من بيانات التقرير + `DataRow.onSelectChanged` يفتح `DocumentViewerPage` عند وجود عمود `name`؛ `message_renderer.dart` — تحليل `<open_document doctype="X" docname="Y"/>` + `_OpenDocumentButton` widget + `onOpenDocument` callback؛ `ai_assistant_page.dart` — RULE 5 في system prompt + `_openDocument()` method + تمرير callback لـ `_MessageBubble` | ربط عارض المستندات بجميع مداخل التطبيق: Drawer + تقارير + AI Chat |
| 2026-05-07 | `flutter build web --release --base-href /kcsc-ai/` — Web ✅ (55.8s) — ملاحظة: تشغيل عبر PowerShell لا Git Bash (Git Bash يحوّل `/kcsc-ai/` إلى مسار Windows) | بناء Web بعد إضافة Workflow pages |
| 2026-05-07 | `flutter build apk --release` — APK (62.8 MB) | بناء Android بعد إضافة Workflow pages |
| 2026-05-08 | **إعادة بناء `pending_approvals_page.dart` كاملة — إصلاح 417 + pagination + lazy load + skeleton**: (1) **إصلاح جذري للخطأ 417**: `GET /api/resource/Workflow Action` يُعيد 417 لأن Frappe يرفض `get_list` على هذا الـ system doctype عبر REST endpoint مباشرة؛ الحل: استبدال بـ `ApiService.postForm('/api/method/frappe.client.get_list', {...})` مع `filters`/`fields` كـ JSON strings — نفس المسار الذي تستخدمه Frappe Desk؛ (2) **Pagination**: 20 عنصر لكل صفحة عبر `limit_start`/`limit_page_length`؛ (3) **Lazy loading**: `ScrollController` يُطلق `_fetchPage(reset: false)` عند الاقتراب من النهاية بـ 200px؛ (4) **Skeleton loading**: 6 بطاقات `_SkeletonCard` مع `_Box` placeholders تظهر أثناء أول تحميل بدلاً من CircularProgressIndicator؛ (5) **Filter chips**: `_FilterChipRow` تظهر تلقائياً عند وجود أكثر من doctype واحد — "كل الأنواع" + DocType chips + `AnimatedContainer` للتبديل؛ (6) **Count badge**: `_CountBadge` برتقالي في AppBar يُظهر عدد العناصر المحملة؛ (7) **`_ErrorView`** منفصل عن `_EmptyView` — `_ErrorView` فقط عند `_items.isEmpty`؛ (8) `app_localizations.dart` — إضافة `wfAllTypes` (en: "All Types" / ar: "كل الأنواع") + getter | الخطأ 417 كان يمنع تحميل الموافقات المعلقة على جميع الأجهزة؛ إعادة البناء أضافت pagination + lazy load + UX محسّن |
| 2026-05-08 | `flutter build web --release --base-href /kcsc-ai/` — Web ✅ (59.8s) + `flutter build apk --release` — APK (62.8 MB) | بناء متوازٍ بعد إعادة بناء pending_approvals_page |
| 2026-05-08 | `flutter build apk --release` — APK (62.8 MB) + `flutter build web --release --base-href /kcsc-ai/` — Web ✅ | بناء بعد إعادة بناء pending_approvals_page الثانية |
| 2026-05-08 | **Real-time Workflow Updates — Socket.IO + Polling fallback**: (1) **`lib/realtime_workflow_service.dart`** — Singleton جديد: يتصل بـ Frappe Socket.IO (`socket_io_client ^2.0.3`)، يُصادق بـ `emit('login', {sid})` للانضمام لـ room المستخدم، يستمع لحدث `workflow_update`، يُراقب debounce 200ms لدمج الأحداث المتتالية، fallback تلقائي لـ polling كل 15 ثانية عند فشل الـ socket أو استخدام Token auth، `broadcastLocal()` للتحديث الفوري قبل وصول الـ socket event؛ (2) **`document_viewer_page.dart`** — بعد `_executeAction()` نجاح: `RealtimeWorkflowService().broadcastLocal({doctype, docname, new_state, action})`؛ (3) **`pending_approvals_page.dart`** — subscribe في `initState` + `_onWorkflowEvent`: إزالة العنصر فوراً عند حدث نقطي أو reload عند حدث poll؛ (4) **`app_drawer.dart`** — subscribe + `_BadgeChip` برتقالي يعرض عدد الموافقات المعلقة بجانب "الموافقات المعلقة"؛ (5) **`ai_assistant_page.dart`** — subscribe + `_onWorkflowEvent` يُضيف رسالة تأكيد للمحادثة إذا كان المستند فُتح من الـ chat؛ (6) **`login_page.dart`** + `_loadConfig()` — `RealtimeWorkflowService().initialize()` بعد تسجيل الدخول؛ (7) **`FAC_REALTIME_SETUP.md`** — تعليمات backend: `hooks.py` + `api.py` لـ `frappe.publish_realtime`؛ `pubspec.yaml` — `socket_io_client: ^2.0.3`، `1.0.67+67` | الموافقات تُزال فوراً بعد التنفيذ دون تحديث يدوي — Mobile + Web |
| 2026-05-08 | **`pending_approvals_page.dart` — إعادة بناء ثانية: إصلاح DataError + بحث + تجميع**: (1) **إصلاح `frappe.exceptions.DataError`**: حذف حقل `action` كلياً من `fields` array وكلاسس `_PendingItem` — يُسبّب `Field not permitted in query: action` على بعض إصدارات Frappe؛ حذف `_ActionPill` widget الذي كان يعتمد عليه؛ (2) **بحث**: `_SearchBar` widget مع تأخير `Timer(400ms)` → `['reference_name', 'like', '%query%']` server-side filter؛ زر مسح يظهر عند وجود نص؛ (3) **تجميع**: getter محسوب `_displayItems` يُنتج `List<Object>` يمزج `_GroupHeader` + `_PendingItem` — التجميع يعمل فقط عندما `_filterDoctype.isEmpty && _searchQuery.isEmpty`؛ `SliverList.builder` يتحقق من النوع (`item is _GroupHeader`) قبل البناء؛ `_GroupHeaderWidget` يعرض اسم DocType بخط ثقيل + شارة بالعدد | `action` field كان يُسبّب DataError على Frappe وجعل الصفحة غير قابلة للاستخدام؛ البحث والتجميع يُحسّنان التنقل في قوائم الموافقات الكبيرة |
| 2026-05-08 | `flutter build apk --release` — APK (63.6 MB) + `flutter build web --release --base-href /kcsc-ai/` — Web ✅ | بناء بعد إضافة Real-time Workflow Service |
| 2026-05-08 | **إصلاح مطابقة هوية المستخدم في الموافقات**: `api_service.dart` — إضافة `_keyUserEmail` + جلب `frappe.auth.get_logged_user` بعد تسجيل الدخول وحفظ البريد الإلكتروني كـ `erpnext_user_email`؛ إضافة `getLoggedUserId()` static method تُعيد `user_email` أولاً ثم `username` كـ fallback؛ `realtime_workflow_service.dart` + `pending_approvals_page.dart` — استبدال `prefs.getString('erpnext_username')` بـ `ApiService.getLoggedUserId()` — `Workflow Action.user` يخزن البريد الإلكتروني وليس اسم المستخدم القصير | الفلتر `['user','=',username]` كان يفشل عندما يُدخل المستخدم اسماً قصيراً بدلاً من بريده الإلكتروني |
| 2026-05-08 | **إشعارات خلفية عند وصول موافقات جديدة**: `pubspec.yaml` — إضافة `flutter_local_notifications: ^18.0.1` + `workmanager: ^0.9.0`؛ `android/app/build.gradle.kts` — تفعيل `isCoreLibraryDesugaringEnabled = true` + تبعية `desugar_jdk_libs:2.1.4`؛ `AndroidManifest.xml` — إضافة `RECEIVE_BOOT_COMPLETED` + `WAKE_LOCK` + `POST_NOTIFICATIONS`؛ **`lib/background_service.dart`** (ملف جديد) — `callbackDispatcher` يُشغَّل بـ WorkManager كل 15 دقيقة: يجلب عدد الموافقات المعلقة عبر `frappe.client.get_list`، يقارن بالعدد المحفوظ في SharedPreferences، يُطلق إشعاراً محلياً (Android) عند زيادة العدد؛ `initBackgroundService()` + `stopBackgroundService()` + `showApprovalNotification()` + `getInitialNotificationRoute()`؛ `main.dart` — `main()` async + `WidgetsFlutterBinding.ensureInitialized()` + `navigatorKey` + استدعاء `initBackgroundService()` + معالجة route عند الإطلاق من إشعار؛ `pubspec.yaml` — `1.0.68+68` | إشعار فوري على Android عند وصول طلب موافقة جديد حتى عند إغلاق التطبيق |
| 2026-05-08 | `flutter build apk --release` — APK (64.0 MB) + `flutter build web --release --base-href /kcsc-ai/` — Web ✅ | بناء بعد إضافة إشعارات خلفية |
| 2026-05-09 | **إعادة بناء شاملة: PendingApprovalsPage + FacPendingResult models**: (1) **`lib/fac_mcp_service.dart`** — إضافة 3 models: `FacWorkflowAction(action,nextState)` + `FacPendingDoc(doctype,documentName,workflowState,creation,permittedRoles,availableActions)` + `FacPendingResult(success,totalPending,doctypesWithPending,pendingApprovals,message)` مع `fromJson()` يتعامل مع التنسيق الحقيقي `pending_approvals:{"Sales Invoice":[{document_name:...}]}`؛ إعادة كتابة `getPendingApprovals()` لتُعيد `FacPendingResult?` بدل `List<PendingDoc>?`؛ debug logging في كل خطوة بـ `[FAC]` prefix؛ (2) **`lib/pending_approvals_page.dart`** — إعادة بناء كاملة: يستدعي `FacMcpService().getPendingApprovals()` مباشرة بدون WorkflowRepository؛ state: `FacPendingResult? _facResult` + fallback SOURCE A (`List<_FbDoc>`)؛ `_displayGroups` يُولّد `Map<doctype, List<_DisplayDoc>>` مباشرة من FAC response؛ `_buildGroupedCards()` يُولّد group header + cards مع أزرار workflow actions من FAC؛ `_executeAction()` يحاول FAC runWorkflow ثم safeApplyWorkflow؛ auto-refresh 30s + realtime events + manual Refresh + pull-to-refresh؛ `_FallbackBanner` عند استخدام SOURCE A؛ (3) **`lib/workflow_repository.dart`** — تحديث استدعاء `getPendingApprovals()` بدون filterDoctype (يُحوّل `FacPendingResult.allDocs` إلى `List<PendingDoc>`)؛ `pubspec.yaml` — `1.0.75+75` | البيانات من FAC كانت تُعاد صحيحة لكن لا تُعرض — السبب: WorkflowRepository كطبقة وسيطة أضافت تعقيداً أدى لعدم التحديث الصحيح؛ الحل: استدعاء مباشر + models صريحة + rendering مباشر من FAC response |
| 2026-05-09 | **إصلاح جذري لـ parsing استجابة get_pending_approvals**: `lib/fac_mcp_service.dart` — `_parsePendingApprovals()` أُعيدت كتابتها لدعم التنسيق الحقيقي لـ FAC: `{"success":true, "pending_approvals": {"Sales Invoice": [{"document_name":"ACC-SINV-...", "workflow_state":"Pending", ...}]}}` — الكود القديم كان يبحث عن `raw['data']`/`raw['approvals']`/`raw['message']` كـ List فلا يجد شيئاً؛ الإصلاح: (1) Format-1: يقرأ `raw['pending_approvals']` كـ Map ويستخرج key=doctype, value=List، يقرأ `document_name` (وليس `name`/`reference_name`/`docname`)؛ (2) Format-2 fallback: قائمة مسطحة تحت `data`/`approvals`/`result`؛ (3) Format-3 fallback: قائمة مباشرة؛ إضافة `_parseFlatList()` مشتركة؛ debug logging لكل format يُظهر عدد المستندات المُستخرجة؛ `pubspec.yaml` — `1.0.74+74` | كل الـ 7 فواتير تظهر الآن — `raw['message']` كان String وليس List فيُعيد `null as List` → `[]` → صفر نتائج |
| 2026-05-09 | **Auto-refresh + Realtime Notifications**: (1) **`lib/web_notification.dart`** (جديد) + **`lib/web_notification_web.dart`** + **`lib/web_notification_stub.dart`** — conditional export: Browser Notification API على Web عبر `dart:js_interop`+`package:web`، stub فارغ على Mobile؛ `requestWebNotificationPermission()` + `showWebNotification(title, body, tag)`؛ (2) **`lib/realtime_workflow_service.dart`** — تقليل polling من 15s إلى 10s؛ إضافة `_lastKnownCount` لتتبع التغييرات دون إشعار عند أول تشغيل؛ `_dispatchNotifications()` يُطلق عند زيادة العدد: SnackBar داخل التطبيق (via `workflowNavigatorKey`) + Android Push عبر `showApprovalNotification()` + Web Browser Notification؛ `workflowNavigatorKey` عام مُعرَّف هنا (نُقل من main.dart)؛ debug logging: poll results، count changes، notification dispatch؛ (3) **`lib/pending_approvals_page.dart`** — إضافة `_autoRefreshTimer` — Timer.periodic كل 30s عند فتح الشاشة يستدعي `invalidateA()` + `_fetchPage(reset:true)` — يُلغى في `dispose()`؛ (4) **`lib/main.dart`** — استيراد `workflowNavigatorKey` من realtime_workflow_service بدل تعريف مفتاح منفصل؛ `pubspec.yaml` — `1.0.73+73` | الموافقات تُحدَّث تلقائياً كل 30s (في الشاشة) + 10s (badge في الـ Drawer) + عند كل workflow event + SnackBar + Push + Web Browser Notification عند وصول موافقات جديدة |
| 2026-05-09 | **FAC MCP كمصدر أساسي للموافقات + إصلاح تنفيذ workflow**: (1) **`lib/fac_mcp_service.dart`** (جديد) — FAC MCP Direct Client بدون AI: JSON-RPC 2.0 مع auto-login، `tools/list` → اكتشاف الأدوات، `getPendingApprovals()` يستدعي `"Get Pending Approvals"` FAC tool مباشرة + debug logging لكل استجابة، `runWorkflow(doc, action)` يكتشف أداة workflow تلقائياً بأسماء متعددة (run_workflow/apply_workflow/execute_workflow)، `_parsePendingApprovals()` يدعم أشكال استجابة متعددة (data/approvals/message/result)، `WorkflowSource.facTool` enum جديد؛ (2) **`lib/workflow_models.dart`** — إضافة `facTool` لـ `WorkflowSource` enum؛ (3) **`lib/workflow_repository.dart`** — SOURCE 0 (FAC PRIMARY) → SOURCE A (Workflow Action fallback) → SOURCE B (Dynamic scan supplement): كاش 30s لـ FAC، `_facAvailable` flag يُعطّل FAC عند غيابه، merge بأولوية SOURCE 0 > A > B، debug logging كامل لكل مرحلة؛ (4) **`lib/document_viewer_page.dart`** — `_executeAction` يحاول FAC `runWorkflow` أولاً ثم `safeApplyWorkflow` كـ fallback؛ (5) **`lib/pending_approvals_page.dart`** — source badges: FAC=أخضر (FAC)، Dynamic=برتقالي (SCAN)، `_SourceBadge` widget جديد، لون الحدود حسب المصدر؛ `pubspec.yaml` — `1.0.70+70` | FAC "Get Pending Approvals" المصدر الرئيسي — يضمن ظهور كل المستندات التي يملك المستخدم صلاحية الموافقة عليها بدقة |
| 2026-05-09 | **إصلاح Refresh + تشخيص Pending Approvals**: `lib/pending_approvals_page.dart` — إعادة كتابة كاملة: (1) `_manualRefresh()` دالة مستقلة تستدعي `FacMcpService().reset()` (إعادة تهيئة جلسة MCP من الصفر) + `_repo.invalidate()` قبل كل refresh يدوي؛ (2) زر Refresh يتحول لـ `CircularProgressIndicator` (20px, strokeWidth=2) أثناء التحميل عبر `_refreshing` flag — يختفي تلقائياً عند انتهاء الـ fetch؛ (3) `_fetchPage` يقبل `source` parameter لتتبع مصدر كل استدعاء في الـ logs؛ (4) debug logging شامل: user ID، عدد docs من كل source، أسماء المستندات والحالات، تحذير عند صفر نتائج؛ (5) `_EmptyView` تعرض `(user@email.com)` تشخيصياً + زر Refresh؛ (6) `_openItem()` يستدعي `FacMcpService().reset()` + `invalidate()` عند العودة من DocumentViewer؛ (7) `RefreshIndicator` (pull-to-refresh) يستدعي `_manualRefresh()`؛ `pubspec.yaml` — `1.0.72+72` | الشاشة كانت تعرض صفر نتائج بدون أي تشخيص — السبب: FAC يفشل صامتاً ثم SOURCE A تعيد فارغة، الآن كل فشل مُسجَّل + الـ session يُعاد تهيئته عند Refresh |
| 2026-05-09 | **إصلاح جذري: اسم أداة FAC خاطئ كان السبب الرئيسي لاختفاء الموافقات**: (1) **`lib/fac_mcp_service.dart`** — تغيير `_kToolPendingApprovals` من `'Get Pending Approvals'` (بحروف كبيرة ومسافات) إلى `'get_pending_approvals'` (الاسم الحرفي الصحيح من tools/list)؛ إضافة أسماء جميع الأدوات المؤكدة: `run_workflow`, `get_document`, `fetch`, `search`, `search_doctype`؛ استبدال `.contains().toLowerCase()` بـ `_findTool()` بمطابقة حرفية كاملة (exact match) — لأن `"get pending approvals" ≠ "get_pending_approvals"` حتى بعد toLowerCase()؛ إضافة `getDocument()`/`fetch()`/`search()`/`searchDoctype()` methods؛ تصدير `kToolPendingApprovals` و `kToolRunWorkflow` كـ public constants؛ debug logging محسَّن يُظهر الأدوات المتاحة عند عدم الإيجاد؛ (2) **`lib/workflow_repository.dart`** — `invalidate()` و `invalidateA()` يُعيدان `_facAvailable = true` — كان يبقى `false` إلى الأبد بعد أول فشل فيمنع أي إعادة محاولة؛ debug logging يُظهر اسم الأداة المطلوبة + الأدوات المتاحة عند الفشل؛ (3) **`lib/CLAUDE.md`** — إضافة تحذير حرج عن حساسية أسماء الأدوات + الأسماء المؤكدة؛ `pubspec.yaml` — `1.0.71+71` | `_facAvailable=false` كان يُضبط فوراً بسبب عدم إيجاد "Get Pending Approvals" (بحروف كبيرة) فيسقط لـ SOURCE A الذي قد لا يحتوي Workflow Action records — الـ 4 فواتير تظهر الآن |
| 2026-05-09 | **تحديث CLAUDE.md شامل**: تحديث §1 (الإصدار 1.0.70+70)، §2 (وصف دقيق لجميع الملفات الجديدة)، §3.2 (تدفق البيانات يشمل WorkflowRepository + FacMcpService + Singleton services)، §4.2 (إضافة FAC MCP endpoints: tools/list, tools/call, has_permission, "Get Pending Approvals")، §7.6 (توثيق شامل: WorkflowSource enum، FacMcpService API، FacValidator، WorkflowRepository SOURCE 0/A/B، WorkflowService مع safeApplyWorkflow، DocumentViewerPage بـ FAC runWorkflow، PendingApprovalsPage بـ source badges، RealtimeWorkflowService)، §11 (pattern استدعاء FAC)، §12 (قاعدتان جديدتان: FAC أولاً + WorkflowRepository للموافقات)، §13 (تحديث: مشاكل محلولة + مشاكل جديدة) | توثيق كامل لجميع التغييرات التقنية المُنجزة |
| 2026-05-09 | **إعادة كتابة `pending_approvals_page.dart` — HTTP مباشر بدون طبقات وسيطة**: حذف جميع الاعتماديات على `WorkflowRepository`/`FacMcpService` من الصفحة؛ `_fetchFromFac()` تستدعي MCP مباشرة عبر `http.post`: (1) `initialize` للجلسة، (2) `tools/call` بـ `get_pending_approvals`، (3) فك التغليف المتداخل `outer['message'] → rpc → content[0].text → jsonDecode`، (4) تحليل `response['pending_approvals']` كـ `Map<String, List>` باستخدام `document_name` field؛ `_fetchFallback()` — استعلام `frappe.client.get_list(Workflow Action)` كـ fallback صريح؛ `_executeAction()` يحاول `run_workflow` عبر HTTP ثم `safeApplyWorkflow` fallback؛ auto-refresh كل 30s + realtime listener + pull-to-refresh؛ state مبسّط: `Map<String, List<_Doc>> _data` + `bool _usingFallback`؛ `pubspec.yaml` — `1.0.76+76`؛ APK (64.2 MB) + Web ✅ | البيانات كانت تُعاد صحيحة من FAC لكن الطبقات الوسيطة (WorkflowRepository → FacMcpService) أضافت تعقيداً أدى لعدم تحديث الـ UI — الحل: استدعاء HTTP مباشر بنفس نمط الـ mock الذي يعمل |
| 2026-05-09 | `flutter build apk --release` — APK (64.2 MB) + `flutter build web --release --base-href /kcsc-ai/` — Web ✅ | بناء بعد إصلاح FAC auth headers |
| 2026-05-09 | **إعادة بناء شاملة ونهائية لـ `pending_approvals_page.dart` — إصلاح جذري للعرض + parser عالمي + skeleton + filter دائم**: (1) **`_mcpPost()`** top-level helper — `ApiService.getAiAuthHeaders()` + `ApiService.getErpNextUrl()` + re-login تلقائي + status code handling كامل؛ (2) **`_extractPa(rpc)`** — parser عالمي يدعم 6 أشكال استجابة FAC بالأولوية (content[0].text → message string → message Map → direct root → structuredContent → nested data)؛ (3) **`_Item` model** — flat list builder يفصل بين header/doc/spacer لـ `ListView.builder` المُحسَّن؛ (4) **Skeleton cards** — `_SkeletonCard` مع `AnimationController` pulsing بدل CircularProgressIndicator؛ (5) **Filter chips دائماً مرئية** حتى مع doctype واحد؛ (6) **Card borders** بـ `c.surfaceHigh` لضمان الرؤية في light/dark mode — لا white-on-white؛ (7) **`_busy` flag** يمنع تداخل `_load()` المتزامن؛ (8) **Debug logging شامل** في كل مرحلة؛ APK (64.3 MB) + Web ✅ | الشاشة لا تُظهر بيانات رغم صحة الـ parsing — تم الإصلاح الشامل بإعادة بناء كاملة مع parser عالمي يغطي كل أشكال FAC |
| 2026-05-09 | **إصلاح جذري: FAC auth headers خاطئة كانت تُسقط كل اتصال MCP**: `pending_approvals_page.dart` — استبدال `_authHeaders()` المخصصة (كانت تُعيد headers مختلفة عن بقية التطبيق) بـ `_mcpPost()` helper جديدة على مستوى الملف تستخدم `ApiService.getAiAuthHeaders()` + `ApiService.getErpNextUrl()` — نفس pattern دقيق كـ `_mcpRequest()` في `ai_assistant_page.dart`؛ `_mcpPost()` تتحقق من كل status codes: 401/403 → re-login تلقائي، 404 → رسالة واضحة، 417 → Frappe error، غير 200 → throw؛ تكتشف `exc_type`/`_server_messages` في الـ outer Frappe response قبل parse؛ `_fetchFromFac()` + `_runWorkflowFac()` مُعادَتا كتابتهما بالكامل لاستخدام `_mcpPost()`؛ `_facEndpoint()` helper تقرأ `ai_endpoint` من SharedPreferences مع default `frappe_assistant_core.api.fac_endpoint.handle_mcp`؛ حذف `_mcpId` من الـ state وتعويضه بـ `_globalMcpId` على مستوى الملف؛ APK (64.2 MB) ✅ | الـ FAC كانت تفشل بصمت لأن `_authHeaders()` المحلية تُنتج headers مختلفة عن `getAiAuthHeaders()` (مثل: Cookie format، Accept header، CSRF handling) — السبب: كل MCP call كان يُعيد HTTP 401/403 فتنكسر silently وتسقط لـ fallback فارغ |
| 2026-05-09 | **إعادة كتابة شاملة نهائية لـ `pending_approvals_page.dart` — UI احترافي بـ AppColors**: (1) **هيكل مطابق للـ mock الذي يعمل**: `Map<String, List<_Doc>> _data` state مبسّط، `_Doc(name, state, creation, actions)` + `_Action(action, nextState)`؛ (2) **FAC HTTP مباشر**: `_fetchFromFac()` — initialize → `tools/call get_pending_approvals` → فك التغليف المتداخل `outer['message'] → rpc → content[0].text → jsonDecode` → تحليل `pending_approvals` Map بـ `document_name` field؛ (3) **Fallback**: `ApiService.postForm(frappe.client.get_list, Workflow Action)` — بدون `action` field؛ (4) **Execute action**: dialog تأكيد → `run_workflow` HTTP مباشر → `WorkflowService().safeApplyWorkflow` fallback؛ (5) **AppColors كاملة** light/dark: خلفية `c.background`، AppBar `c.primary`، بطاقات `c.surface`، نص `c.textPrimary/Secondary`؛ ألوان الأزرار: Approve=`AppColors.success` أخضر، Reject=`AppColors.error` أحمر، غيره=`AppColors.warning` برتقالي؛ (6) **بحث + filter chips**: TextField debounce 300ms + `_ChipButton` animated لكل DocType؛ (7) **Group headers**: container `c.primary` يعرض DocType + عدد؛ (8) **Count badge** برتقالي في AppBar؛ (9) Auto-refresh 30s + `RealtimeWorkflowService` listener + pull-to-refresh + card tap → `/document-viewer`؛ `pubspec.yaml` — `1.0.76+76`؛ APK (64.2 MB) + Web ✅ | الشاشة لم تُظهر بيانات رغم صحة الـ parsing — السبب الجذري: الهيكل القديم المعقد؛ الحل: إعادة كتابة من الصفر مطابقةً للـ mock الذي يعمل بدون أي طبقات وسيطة |
| 2026-05-09 | `flutter build apk --release` — APK (64.3 MB) + `flutter build web --release --base-href /kcsc-ai/` — Web ✅ | بناء بعد إصلاح CSRF + إظهار خطأ FAC |
| 2026-05-09 | **إصلاح `_mcpPost` — CSRF Token + رسالة الخطأ المرئية**: (1) `pending_approvals_page.dart` — `_mcpPost()`: إضافة `X-Frappe-CSRF-Token` عند session auth (بدونه Frappe يرفض POST) — نفس ما يفعله `ApiService.post()` وكان ناقصاً من `getAiAuthHeaders()`؛ trim trailing slash من URL (`replaceAll(RegExp(r'/+$'), '')`؛ إضافة log كامل للـ URL والـ response body أول 300 حرف؛ (2) إضافة `_facError` field في state — يحفظ رسالة الاستثناء الحقيقية؛ (3) `_fallbackBanner()` يعرض نص الخطأ الفعلي أسفل "Fallback mode" مع `maxLines: 3` — يُمكّن التشخيص المباشر من الشاشة؛ APK (64.3 MB) ✅ + Web ✅ | session auth POST requests كانت تُرفض بـ 403 لغياب CSRF header؛ الخطأ كان صامتاً في debug logs فقط — الآن يظهر مباشرة على الشاشة للتشخيص |
| 2026-05-10 | **PART 10 — FAC Tools, Skills & User Permissions — بنية إنتاجية شاملة**: **(1) `lib/fac_mcp_service.dart`** — إضافة `FacDiagnostics` singleton (يُتابع: toolName, skillUsed, responseType, parserMode, authMode, activeUserId, source0/A/B counts, permissionFiltered, deniedDoctypes, deniedActions, skippedDoctypes, hiddenDocumentsCount, facAvailable, lastError)؛ إضافة `_extractFacContent()` يدعم 8 صيغ FAC: content[0].text / skill_result / tool_result / workflow_documents / structuredContent / payload / data / direct؛ إضافة retry logic في `_mcpRequest` (max 2 retries, exponential backoff 2s/4s، لا retry عند 401/403/permission denied)؛ `_mcpRequestOnce` يُضيف CSRF token عند session auth (كان مفقوداً)؛ `getPendingApprovals` يحدّث diagnostics تلقائياً (authMode, userId, source0Count, lastSuccessTime)؛ **(2) `lib/fac_validator.dart`** — `canAccessDocType` يُسجّل الـ doctypes المرفوضة في `FacDiagnostics().deniedDoctypes`؛ `validateBeforeApply` يُسجّل الـ actions المرفوضة في `FacDiagnostics().deniedActions`؛ **(3) `lib/workflow_repository.dart`** — SOURCE 0 يحدّث `source0Count`، SOURCE A يحدّث `sourceACount`، SOURCE B يحدّث `sourceBCount` و`skippedDoctypes`؛ **(4) `lib/pending_approvals_page.dart`** — `_findPa` يدعم skill_result / tool_result / workflow_documents / payload بالإضافة للصيغ السابقة؛ إضافة `_convertWorkflowDocuments()` يُحوّل workflow_documents إلى pending_approvals format؛ زر `bug_report_outlined` في AppBar يفتح `_showDebugPanel()` — bottom sheet قابل للسحب يعرض كل `FacDiagnostics().toMap()` مع تلوين القيم الحرجة (denied/skipped/hidden) بالبرتقالي؛ زر "Details" في fallback banner يفتح نفس الـ debug panel؛ `_fetchFac` يحدّث `FacDiagnostics` عند النجاح والفشل | بنية إنتاجية آمنة: صلاحيات ERPNext محترمة بالكامل، FAC يُطبّق permissions server-side، logging شامل لكل حالة رفض/تجاوز/خطأ، debug panel مدمج للتشخيص الفوري بدون أدوات خارجية |
| 2026-05-11 | **إصلاح جذري: docstatus=1 خاطئ في Reverse Workflow + إعادة بناء Approved page**: **(1) الخطأ الجذري**: `pending_approvals_page.dart` — `_executeAction()` كان يستدعي `FacMcpService().submitDocument()` بعد كل workflow action (حتى reverse actions مثل Review→Pending) فيُحوّل `docstatus` إلى 1 بشكل غلط؛ **الإصلاح**: حذف كتلة `submitDocument()` بالكامل — ERPNext workflow engine وحده يتحكم في docstatus؛ **(2) منطق التحريك الذكي بعد run_workflow**: بعد كل إجراء → fetch الـ doc المُحدَّث من الخادم → قراءة `docstatus` + `workflow_state` الفعليَّين → `docstatus=1`: `_removeDoc` + broadcast للـ Approved→ `docstatus=0`: `_removeDoc` optimistically + reload (قد يعود للـ Pending) → `docstatus=2`: `_removeDoc` فقط؛ debug logging شامل (`[WF] Action/Before/After docstatus/state`)؛ **(3) إعادة بناء `approved_page._fetchApproved()`**: تغيير مصدر البيانات من `Workflow Action (Completed)` إلى **active workflows → docstatus=1 server-side filter**: GET `/api/resource/Workflow?is_active=1` → لكل doctype: `frappe.client.get_list(dt, [['docstatus','=',1], ['modified','>=',cutoff]])` بالتوازي (`Future.wait`) — يستخدم `modified` بدل `creation` لاكتشاف المستندات المُقدَّمة حديثاً أياً كان تاريخ إنشائها؛ يحترم صلاحيات ERPNext تلقائياً؛ debug log لكل مستند: doctype/docname/state/docstatus/visible=true؛ **(4) حذف `_batchCheckDocstatus` من `approved_page.dart`**: الفلتر الآن server-side في الاستعلام نفسه؛ **(5) `_cancelDoc()` في Approved**: إضافة `RealtimeWorkflowService().broadcastLocal({doctype, docname, action:'Cancel', docstatus:2})` بعد نجاح الإلغاء → Pending page تُحدَّث لو أن ERPNext engine أعاد المستند للـ Draft؛ APK (64.4 MB) + Web ✅ | الضمان: Review→Pending لا يُنتج docstatus=1، Approved يعرض حصراً مستندات مُقدَّمة فعلاً |
| 2026-05-11 | **فصل صارم docstatus=0/1 بين Pending وApproved + cross-page realtime sync**: **(1) `_batchCheckDocstatus(groups, targetDocstatus)` — دالة مشتركة في كلا الملفَين**: تستعلم `frappe.client.get_list(doctype, [['name','in',[...]], ['docstatus','=',N]])` مرة واحدة لكل doctype (parallel `Future.wait`) بدلاً من call لكل مستند — توفير ضخم في عدد الطلبات؛ على خطأ API: safe fallback = show all (لا تُفرغ القائمة بسبب خطأ صلاحيات)؛ **(2) `pending_approvals_page.dart`**: (a) بعد `_fetchFac()` تحليل FAC response → batch-check `docstatus=0` → يُزيل أي مستند `docstatus=1` قد يتسرّب من FAC؛ (b) بعد `_fetchFallback()` → نفس الفلتر على مستندات Workflow Action (Open)؛ (c) في `_executeAction()` بعد نجاح run_workflow → `RealtimeWorkflowService().broadcastLocal({doctype, docname, action, new_state})` → يُطلق refresh تلقائي في Approved page؛ **(3) `approved_page.dart`**: (a) إضافة `import 'realtime_workflow_service.dart'`؛ (b) إضافة `late WorkflowEventCallback _rtCb` + subscribe في `initState` + unsubscribe في `dispose` → الصفحة تُحدَّث تلقائياً عند أي workflow event من أي مكان في التطبيق؛ (c) بعد `_fetchApproved()` تجميع Workflow Actions (Completed) → batch-check `docstatus=1` → يُزيل أي مستند لم يُقدَّم بعد من قائمة المعتمدة؛ APK (64.4 MB) + Web ✅ | الضمان التقني: Pending يعرض حصراً `docstatus=0`، Approved يعرض حصراً `docstatus=1`، المستند ينتقل تلقائياً بين الصفحتَين فور تنفيذ الإجراء |
| 2026-05-10 | **صفحة المعتمدة (Approved Approvals) — ملف جديد + cancel_document FAC**: **(1) `lib/approved_page.dart`** (جديد، ~480 سطر) — صفحة المستندات المعتمدة: تجلب `Workflow Action` بـ `[status=Completed, user=me, creation>=last_N_days]` + تجميع بـ `reference_doctype` + dedup لأحدث إدخال لكل مستند؛ Chips تاريخ (آخر 7/30/90 يوم) + filter chips بـ doctype + بحث debounce 300ms؛ كل بطاقة: اسم المستند + state badge أخضر + تاريخ + زر Cancel عبر FAC؛ Cancel: `FacMcpService().cancelDocument()` أولاً → `frappe.client.cancel` كـ fallback → إزالة فورية من القائمة؛ skeleton loading + pull-to-refresh؛ لون AppBar = `AppColors.success` (أخضر) للتمييز عن Pending؛ **(2) `lib/fac_mcp_service.dart`** — إضافة `cancelDocument(String doctype, String name)`: تستدعي FAC `cancel_document` مع `{doctype, name}`، تتحقق من `result.success`، ترفع الخطأ الحقيقي، تُعيد `null` إذا الأداة غير موجودة؛ **(3) `lib/app_drawer.dart`** — إضافة `DrawerSection.approvedApprovals` في enum + حالة في switch + `_NavItem` بأيقونة `check_circle_outline_rounded` تحت Pending Approvals مباشرة؛ **(4) `lib/main.dart`** — إضافة route `/approved-approvals` + import؛ **(5) `lib/app_localizations.dart`** — 9 مفاتيح جديدة: `wfApprovedApprovals`/`wfNoApproved`/`wfApprovedOn`/`wfCancelConfirmTitle`/`wfLast7`/`wfLast30`/`wfLast90`؛ APK (64.3 MB) + Web ✅ | صفحة منفصلة للمستندات المعتمدة مع إمكانية الإلغاء عبر FAC — تُكمّل دورة حياة الـ Workflow |
| 2026-05-10 | **إضافة `submit_document` FAC tool في 3 ملفات**: **(1) `lib/fac_mcp_service.dart`** — إضافة `submitDocument(String doctype, String name)` method: تستدعي أداة FAC `submit_document` مع `{doctype, name}`، تتحقق من `result.success`، ترفع الخطأ الحقيقي عند الفشل، تُسجّل في `FacDiagnostics.lastSuccessTime`؛ تُعيد `null` إذا كانت الأداة غير موجودة على الخادم (caller يرجع للـ fallback)؛ **(2) `lib/pending_approvals_page.dart` — `_executeAction()`**: بعد نجاح `run_workflow` أو `safeApplyWorkflow`: يستدعي `FacMcpService().submitDocument(dt, dn)` تلقائياً — non-fatal (لا يوقف الـ UX إذا فشل)؛ الهدف: تحويل docstatus من 0 إلى 1 في نفس خطوة الموافقة؛ إصلاح warning `_lastOpenedDoctype` (حذف الحقل غير المستخدم وجميع إسناداته)؛ **(3) `lib/document_viewer_page.dart` — `_handleSubmit()`**: استبدال `ApiService.post('frappe.client.submit')` بـ `FacMcpService().submitDocument(doctype, name)` — يُراجَع على `isError` ويُعيد الخطأ الحقيقي؛ fallback لـ `frappe.client.submit` فقط إذا لم تكن أداة FAC موجودة؛ **(4) `lib/ai_assistant_page.dart`** — إضافة قسم `DOCUMENT SUBMISSION — submit_document` في system prompt: الخطوات الإلزامية (verify docstatus→0 ثم submit ثم تأكيد)، قائمة الكلمات المفتاحية العربية/الإنجليزية التي تُفعّل الـ submit، حظر صريح لـ `frappe.client.submit`، حذف `_lastOpenedDoctype` (unused field كان يُسبّب warning)؛ APK (64.2 MB) + Web ✅ | تطبيق مبدأ "FAC أولاً" على عملية الـ Submit في جميع مداخل التطبيق |
| 2026-05-10 | **إصلاح run_workflow + إزالة فورية بعد الإجراء**: **(1) `lib/fac_mcp_service.dart` — `runWorkflow()`**: تغيير `'docname': doc['name']` → `'name': doc['name']` في arguments لأداة FAC — كان يُسبّب `ValidationError: Missing required field: name` في كل محاولة Approve/Reject (FAC يتوقع `name` وليس `docname`)؛ **(2) `lib/pending_approvals_page.dart` — `_executeAction()`**: نفس الإصلاح في الاستدعاء المباشر عبر `_mcpPost`؛ إضافة فحص `result.isError == true` بعد `run_workflow` لرفع الخطأ الحقيقي؛ بعد النجاح: `setState` يُزيل المستند فوراً من `_data[dt]` بدلاً من انتظار reload — يظهر التأثير لحظياً للمستخدم؛ رسالة SnackBar تتضمن اسم المستند للوضوح؛ **(3) `_openDoc()`**: بعد العودة من `DocumentViewerPage` → يستدعي `_removeIfActioned(dt, dn)` الذي يجلب `docstatus` من الخادم — إذا `docstatus != 0` (Submitted/Cancelled) يُزيل المستند فوراً من القائمة؛ **(4) `_removeIfActioned()` + `_removeDoc()`** — دوال جديدة: الأولى تتحقق من docstatus عبر HTTP، الثانية تُعدّل `_data` في `setState` وتحذف الـ doctype كاملاً إذا أصبحت قائمته فارغة؛ APK (64.2 MB) + Web ✅ | المشكلة: `run_workflow` كان يُرسل `docname` فيرفضه FAC بـ ValidationError؛ والمستند كان يبقى في القائمة بعد الإجراء حتى يكتمل الـ reload البطيء |
| 2026-05-10 | **إصلاح جذري: FAC v2.0.0 double-wrap + خطوط Cairo/Inter**: **(1) `lib/pending_approvals_page.dart` — `_findPa()`**: إضافة فحص مستوى `result` — السبب الجذري لظهور "No pending_approvals found": FAC v2.0.0 يُغلّف البيانات بـ double-wrap `{"success": true, "result": {"success": true, "pending_approvals": {...}}}` فكان `_findPa` يبحث في المستوى الأول (success/result) ولا يجد `pending_approvals`؛ الإصلاح: إضافة `if (m.containsKey('result') && m['result'] is Map) { final r = _findPa(m['result']); if (r != null) return r; }` — الآن يُكمل البحث تلقائياً داخل أي مستوى `result`؛ **(2) ملفات الخطوط `fonts/*.ttf`**: استبدال 6 ملفات فارغة (0A 0A 0A 0A = newlines، غير صالحة) بملفات TTF حقيقية محمّلة من Google Fonts CDN: Cairo (Regular/SemiBold/Bold) + Inter (Regular/SemiBold/Bold) — كانت تُسبّب أخطاء "Failed to load font" على الويب؛ APK (64.2 MB) + Web ✅ | السبب: اللوج أظهر `"text": "{\"success\": true, \"result\": {\"pending_approvals\": {...}}}"` — البيانات موجودة لكن `_findPa` لا يُدرك أنها بحاجة لخطوة nesting إضافية عبر `result` key |
| 2026-05-10 | **إصلاح FAC parser + diagnostics شاملة**: **(1) `lib/fac_mcp_service.dart` — `FacDiagnostics`**: إضافة حقلَي `lastRawFacText` (أول 600 حرف من content[0].text — للتشخيص الفوري) + `facToolStatus` ('OK' \| 'isError=true' \| 'no_content')؛ إضافتهما في `toMap()` لعرضهما في debug panel؛ تحديث `resetSession()` لمسحهما؛ **(2) `lib/pending_approvals_page.dart` — `_fetchFac()`**: قبل أي MCP call → تحديث `FacDiagnostics.authMode` (token/session) + `FacDiagnostics.activeUserId` + `FacDiagnostics.toolName` من `ApiService.getAiAuthHeaders()` + `ApiService.getLoggedUserId()`؛ بعد `tools/call` → استخراج `result.content[0].text`، حفظ أول 600 حرف في `FacDiagnostics.lastRawFacText`، كشف `result.isError == true` وإخراج رسالة الخطأ الحقيقية (بدلاً من "No pending_approvals found") وعرضها في `_facError`؛ رسالة `lastError` الآن تتضمن preview من الـ raw response لتشخيص هيكل الاستجابة؛ **(3) `_findPa()`**: معالجة `pending_approvals` كـ JSON string (try jsonDecode قبل فحص is Map)؛ `skill_result`/`tool_result`/`payload`/`data` wrappers لا تُوقف البحث عند أول فشل (تستمر للـ fallback)؛ إضافة فحص `data` wrapper مباشرة؛ **(4) `_extractPa()`**: CASE 1 يُجرّب **كل** content items (ليس فقط `[0]`)؛ CASE 1b جديد — يبحث في `result` مباشرة إذا لم يوجد content wrapper (FAC يُرجع البيانات مباشرة بدون MCP envelope)؛ تحسين debug logging بـ CASE name في كل تفرّع؛ APK (64.3 MB) + Web ✅ | المشكلة: `auth_mode: —` و`user_id: —` في debug panel لأن `_fetchFac` يتجاوز `FacMcpService`؛ و`isError: true` من FAC كان يُعالَج كـ "No pending_approvals" بدلاً من عرض الخطأ الحقيقي؛ والـ parser لم يُجرّب كل content items ولا مستوى result المباشر |
| 2026-05-11 | **OCR Workflow Engine — نظام معالجة ذكي للمستندات**: إضافة 3 ملفات جديدة: **(1) `lib/ocr_models.dart`** — كامل نماذج البيانات: `OcrDocumentType` enum (purchaseInvoice/salesInvoice/paymentReceipt/deliveryNote/quotation/expense/unknown مع icon+erpNextDoctype)، `OcrIntent` enum (8 أنواع نوايا)، `OcrInput` (مع factory من visual analysis أو FAC skill)، `OcrEntities` (استخراج كيانات مع `toErpNextData()`)، `OcrFacMapping`، `OcrErpNextAction`، `OcrWorkflowResult` (status/canExecute/buildExecutionPrompt)؛ **(2) `lib/ocr_workflow_engine.dart`** — المحرك الذكي: system prompt محكم بـ 5 مهام (classification + entity extraction + intent detection + FAC mapping + ERPNext mapping)، يدعم Claude (مع prompt caching) + ChatGPT fallback، confidence gating (finalConf = average input+engine)، JSON parser مع markdown strip، `processOcrResult()` + `processText()` APIs؛ **(3) `lib/ai_assistant_page.dart`** — Integration: `_maybeRunOcrWorkflow()` يُشغَّل تلقائياً بعد أي رد AI يحتوي على صورة + كلمات مفتاحية (scan/invoice/فاتورة/استخرج...)، `_formatOcrResult()` يُنتج Markdown ثنائي اللغة EN/AR مع جدول entities + جدول FAC action + نصيحة execution، `_isOcrTrigger()` static keyword detector؛ APK (64.6 MB) + Web ✅ | المحرك يُحوّل النص المستخرج بصرياً إلى JSON بنيوي محدد لـ ERPNext — deterministic/auditable/production-grade |
| 2026-05-11 | **إصلاح pipeline OCR الكامل في `ai_assistant_page.dart`**: **(1) تشخيص جذري للسبب الرئيسي**: `fileUrlContext` كانت تقول `"uploaded to ERPNext server"` لكن RULE 0.5 يُخبر الـ AI أن يبحث عن `"is saved on ERPNext server"` — عدم تطابق الصياغة جعل الـ AI لا يتعرف على الـ file_url؛ **(2) إصلاح `fileUrlContext`**: استعادة الجملة الحرفية `"is saved on ERPNext server"` + إضافة MIME و Size؛ **(3) إصلاح `_facRoutingHint`**: تحويل التعليمات من "إلزامية" إلى "اقتراح" — بدلاً من "execute BOTH steps automatically" → "choose based on image content"; `fetch_barcode` لم يعد إلزامياً على كل صورة؛ **(4) إضافة logging شامل في `_uploadAttachmentsToErpNext`**: `[OCR] [A/B/C]` prefix لكل خطوة — File info + HTTP status + Response body + file_url result + Frappe error detection؛ **(5) إضافة logging في `_ensureBytes`**: تتبع download من ERPNext عند استعادة الـ bytes؛ **(6) إضافة logging في `fileUrlContext`**: `debugPrint('[OCR] ✅/⚠️/❌ ...'` للتشخيص الفوري؛ **(7) تحديث RULE 0.5**: إضافة قسم "OCR / TEXT EXTRACTION" بـ decision tree كامل — متى تستخدم `extract-file-content-usage` vs base64 visual vs `fetch_barcode`؛ fallback chain صريح عند فشل FAC OCR → يرجع للـ base64 visual؛ APK (64.5 MB) + Web ✅ | الأسباب الجذرية: (1) format mismatch في fileUrlContext كسر parsing الـ AI للـ file_url؛ (2) `_facRoutingHint` للصور كان يُجبر `fetch_barcode` على كل صورة مما يُربك flow التحليل البصري الطبيعي |
| 2026-05-11 | **FAC Routing Engine + Barcode/OCR integration في `ai_assistant_page.dart`**: **(1) System Prompt — قسم `FAC ROUTING ENGINE`** جديد شامل: catalog كامل لـ 20 FAC Tool + 18 FAC Skill بأسماء حرفية دقيقة، 8 routing rules مرقّمة (barcode pipeline → document search → reports → file extraction → schema → workflow → vector search → python code) مع بروتوكول كامل لكل نوع؛ **(2) Barcode Pipeline الإلزامي**: عند وجود image file_url في السياق → AI يُشغّل `fetch_barcode(file_url)` فوراً بدون انتظار تأكيد المستخدم → `get_document("Item")` → Bin stock query؛ **(3) `_facRoutingHint(name, mime)`** — helper جديد يُنتج تعليمات routing حسب نوع الملف: صورة → `extract-file-content-usage` + `fetch_barcode`، PDF → `extract-file-content-usage`، Excel/CSV → `extract-file-content-usage` + `analyze_business_data`، DOCX → `extract-file-content-usage`؛ **(4) `fileUrlContext` مُحسَّن**: يتضمن MIME type + `_facRoutingHint()` لكل مرفق مرفوع — AI يعرف بدقة أي pipeline يُشغّل لكل ملف؛ APK (64.5 MB) + Web ✅ | AI يعرف الآن جميع أدوات ومهارات FAC المتاحة ويُوجَّه تلقائياً لاستخدام الأداة الصحيحة حسب نوع الطلب والملف — ممنوع منعاً باتاً أي وصول مباشر خارج طبقة FAC |
| 2026-05-11 | **كاميرا حقيقية على Flutter Web — `lib/web_camera*.dart`**: إضافة 3 ملفات جديدة بنفس نمط conditional export للمشروع: `web_camera.dart` (conditional export)، `web_camera_stub.dart` (no-op على mobile)، `web_camera_web.dart` (تنفيذ كامل عبر WebRTC)؛ **`showWebCameraOverlay()`** يعيد `(List<int>? bytes, bool shouldFallback)`: `(bytes, false)` = التقاط ناجح، `(null, false)` = المستخدم ألغى، `(null, true)` = الكاميرا غير متاحة → افتح FilePicker؛ **التنفيذ**: (1) فحص `isSecureContext` (HTTPS مطلوب)، (2) `getUserMedia({video: true})` عبر `package:web`، (3) `<video>` live preview في overlay كامل الشاشة بـ CSS مطابق لثيم التطبيق، (4) زر Capture → `canvas.toDataURL('image/jpeg')` → base64 decode → JPEG bytes، (5) زر Cancel → `(null, false)` بلا fallback، (6) معالجة أخطاء: NotAllowedError / NotFoundError / NotReadableError → رسالة واضحة + `(null, true)`؛ **`ai_assistant_page.dart`**: استبدال FilePicker الـ fallback بـ `showWebCameraOverlay()` — camera حقيقية أولاً، FilePicker fallback فقط عند `shouldFallback==true`؛ APK (64.4 MB) + Web ✅ | الكاميرا الحقيقية تعمل الآن على Chrome/Edge Desktop + Android Web — لا يفتح file browser بعد الآن عند الضغط على Camera |
| 2026-05-11 | **إصلاح keyboard + camera على Web في `ai_assistant_page.dart`**: **(1) `resizeToAvoidBottomInset: false`** — إضافة للـ Scaffold: بدونه كان Flutter يُصغّر الـ body عند فتح الكيبورد + `_InputBar` تُضيف `viewInsets.bottom` يدوياً → double-counting → مساحة الرسائل تصبح أقل من 100px! الحل: الـ body يبقى بنفس الارتفاع، و`_InputBar` تتحكم بالمسافة عبر `viewInsets.bottom + 12`؛ **(2) Camera على Web → FilePicker fallback**: `ImagePicker.camera` يستخدم `<input capture>` الذي لا يعمل بشكل موثوق على المتصفحات الـ desktop → على Web يتحول الاختيار تلقائياً لـ `FilePicker.platform.pickFiles(type: FileType.image)` — يعمل على Chrome/Edge/Android Web؛ APK (64.4 MB) + Web ✅ | الأعراض: (1) الرسائل تختفي ويتقلص الشات عند فتح الكيبورد على mobile؛ (2) Camera crash على Flutter Web (desktop browsers لا تدعم capture) |
| 2026-05-11 | **تحسين workflow في `ai_assistant_page.dart` — production-ready**: **(1) `_lastOpenedDoctype`** — إعادة إضافة الحقل واستخدامه: يُضبط في `_openDocument()` ويُستخدم في `_onWorkflowEvent()` للمطابقة الدقيقة (doctype + docname معاً بدل docname فقط) — يمنع false positives من مستندات بنفس الاسم في doctypes مختلفة؛ **(2) `_openDocument()` → async**: تحويلها لـ `Future<void>` + `await Navigator.pushNamed` → عند عودة المستخدم من الـ viewer بدون إجراء، تُمسح التتبع تلقائياً (`_lastOpenedDocname = null`)؛ **(3) `_onWorkflowEvent()` — docstatus-aware messages**: بدلاً من رسالة واحدة، ثلاث رسائل حسب النتيجة: `docstatus=2` → "🚫 تم الإلغاء"، `docstatus=1` → "✅ تم التقديم/الاعتماد"، `docstatus=0` → رسالة التأكيد المعتادة (`wfChatConfirmation`)؛ تحقق من doctype مطابقة؛ debug logging `[AI-WF]`؛ **(4) System prompt RULE 5** — إعادة كتابة شاملة: 4 خطوات إلزامية (DISCOVER→VALIDATE→EXECUTE→CONFIRM)، قواعد cancellation، DUPLICATE ACTION PREVENTION، ERROR HANDLING، تحذيرات صريحة لكل حالة (docstatus=2 موجود مسبقاً، docstatus=0 لا يُلغى مباشرة، اسم أداة حساس لحالة الأحرف، NEVER frappe.client.cancel)؛ APK (64.4 MB) + Web ✅ | الهدف: workflow في المساعد الذكي production-ready مع منع التكرار، التحقق من الحالة الفعلية، ورسائل احترافية لكل نتيجة |
| 2026-05-11 | **إصلاح `_executeAction()` في `pending_approvals_page.dart` — cancel/reject ذكي + broadcast docstatus=2**: **(1) `_isCancelAction(String action)`** — helper جديد يكتشف أسماء الإجراءات من نوع cancel/reject/deny/refuse/إلغاء/رفض/reverse؛ **(2) CASE 1 (run_workflow نجح)**: إضافة `[Pending Cancel] Using run_workflow: true` log؛ **(3) Fallback (!done) — cancel-aware logic**: إذا `isCancelLike`: (a) جلب الـ doc الكامل + docstatus، (b) `WorkflowService().getTransitions()` لاكتشاف cancel transitions، (c) إذا وُجد cancel transition → `safeApplyWorkflow`، (d) إذا لم يوجد + `docstatus==1` → direct ERPNext cancel (`has_permission?ptype=cancel` ثم `postForm(frappe.client.cancel, {doctype, name})` بالبارامترات الصحيحة)، (e) إذا لم يوجد + `docstatus==0` → `safeApplyWorkflow` fallback؛ إذا `!isCancelLike`: `safeApplyWorkflow` مباشرة؛ **(4) docstatus=2 branch**: إضافة `RealtimeWorkflowService().broadcastLocal({..., docstatus: 2})` — كان مفقوداً فكانت Approved page لا تُحدَّث عند cancel من Pending؛ **(5) debug logging شامل**: `[Pending Cancel]` prefix في كل خطوة بما فيها Docstatus Before/After، Workflow State After، Available transitions، Has Cancel Permission، API Response؛ APK (64.4 MB) + Web ✅ | المشاكل المُصلحة: (1) لا `broadcastLocal` لـ docstatus=2 → Approved لا تتحدث عند cancel من Pending؛ (2) CASE 2 (direct cancel) لم يكن موجوداً للمستندات المُقدَّمة التي تظهر في Pending بدون workflow cancel transition |
| 2026-05-11 | **إصلاح `_cancelDoc()` في `approved_page.dart` — منطق إلغاء ذكي حسب الـ Workflow**: إعادة كتابة `_cancelDoc()` كاملاً بمنطق ثنائي: **(CASE 1) إذا كان للمستند workflow transition من نوع Cancel/Reject/Deny/Refuse/إلغاء/رفض** → `FacMcpService().runWorkflow(doc, action)` أولاً → fallback `WorkflowService().safeApplyWorkflow()`؛ **(CASE 2) إذا لم يوجد transition من هذا النوع** → (a) Safety check: `docstatus == 1` (فقط المُقدَّمة تُلغى)، (b) Permission check: `frappe.client.has_permission?ptype=cancel`، (c) تنفيذ `ApiService.postForm('/api/method/frappe.client.cancel', {'doctype': dt, 'name': dn})` — البارامترات الصحيحة (وليس `{'doc': jsonEncode(docMap)}` الخاطئ)؛ إضافة `import 'workflow_service.dart'` + debug logging شامل لكل خطوة؛ APK (64.4 MB) + Web ✅ | **الأخطاء الجذرية المُصلحة**: (1) `cancel_document` FAC tool غير موجودة على هذا الخادم — حُذفت كلياً؛ (2) `frappe.client.cancel` كانت تُستدعى بـ `{'doc': jsonEncode(full_doc)}` بدلاً من `{'doctype': dt, 'name': dn}` — سبّبت 500 INTERNAL SERVER ERROR؛ القاعدة: **لا استخدام لـ `cancel_document` FAC** في أي مكان |
| 2026-05-16 | **i18n بطاقة الترحيب + SnackBars في `ai_assistant_page.dart`**: **(1) `app_localizations.dart`** — إضافة 14 مفتاح/دالة: `greetingMorning`/`greetingAfternoon`/`greetingEvening`/`greeting()`/`agentName`/`assistantIntro`/`assistantModulesTitle`/`assistantModules`/`assistantHelpQuestion`/`micPermissionDenied`/`micError(e)`/`whisperError(e)`/`voiceGenericError(e)`/`emailSendFailed(e)`؛ **(2) `ai_assistant_page.dart`** — `_buildWelcomeMessage()` مُعاد كتابتها لاستخدام 5 مفاتيح l10n بدلاً من 12 نص مشفر؛ `_buildWelcomeBubble()` يستخدم `l.agentName` بدلاً من نص ثنائي مشفر؛ dialog buttons (`إلغاء`/`حفظ`) → `l10n.cancel`/`l10n.save`؛ 4 SnackBars للميكروفون/Whisper/البريد → مفاتيح l10n؛ `flutter analyze` → 0 issues | refactoring: صفر نصوص مشفرة في منطقة الترحيب والأخطاء الصوتية |
| 2026-05-16 | **i18n شامل لـ `settings_page.dart` + بنية `lib/core/localization/`**: **(1) `app_localizations.dart`** — إضافة 19 مفتاح/دالة: `appLogoSection`/`removeLogo`/`logoUpdated`/`noImageContent`/`exportTooltip`/`importTooltip`/`backupSubject`/`noFileContent`/`notSettingsFile`/`notKcscSettings`/`exportFailed(e)`/`importSuccess(n)`/`importFailed(e)`/`providerClaudeOnly`/.../`providerDesc(p)`/`chatGptInfo`/`apiTokenOptional`؛ **(2) `settings_page.dart`** — استبدال جميع النصوص المشفرة بـ `l.xxx` — شامل: AppBar tooltips، section headers، validators، provider labels، info texts، SnackBars، dialogs؛ `final l = AppLocalizations.of(context)` في `build()` وكل method؛ حل `use_build_context_synchronously` بالتقاط `l` قبل الـ awaits؛ **(3) `lib/core/localization/`** — ملفا re-export: `app_localizations.dart` + `locale_provider.dart`؛ `flutter analyze` → 0 issues | تطبيق قاعدة §3: صفر نصوص مُضمَّنة في settings_page + بنية مجلدات مرجعية |
| 2026-05-16 | `app_drawer.dart` — **إخفاء رابط لوحات المعلومات (Dashboards) من القائمة الجانبية**: تحويل `_NavItem` الخاص بـ Dashboards إلى تعليق مع رسالة `// re-enable by un-commenting`؛ الإبقاء على: import، enum value، حالة `_go(DrawerSection.dashboards)` كاملة — يمكن إعادة التفعيل بسطر واحد؛ `flutter analyze` → 0 issues؛ APK + Web ✅ | طلب المستخدم: إخفاء الداشبورد مؤقتاً مع الحفاظ على الملفات والمسارات |
| 2026-05-16 | **إصلاح تحذيرات المحلل في `dashboard_detail_page.dart` + بناء APK/Web**: (1) 2 تعليقات doc comment تحتوي على `<` عالجها المحلل كـ HTML — استبدلت بـ `[Map<String,dynamic>]` و`[List<dynamic>]`؛ (2) `use_build_context_synchronously` عند line 624 — استُخرجت السلسلة النصية قبل `await` في متغير محلي `errMsg` بدلاً من الاستدعاء المباشر لـ `AppLocalizations.of(context)` داخل `throw`؛ (3) `unused_local_variable` عند line 1265 — حُذفت `final c = widget.c;` من `_BarChartCardState.build()` إذ لم تُستخدم `c` في الـ bar chart (يستخدم `_pal()` المستقلة)؛ (4) `curly_braces_in_flow_control_structures` في سطرَين — أُضيفت `{ }` حول `return SizedBox.shrink()` في `getTitlesWidget` الـ bar وline chart؛ `flutter analyze lib/dashboard_detail_page.dart` → **0 issues**؛ APK (64.7 MB) ✅ + Web ✅ | تنظيف الديون التقنية وإزالة جميع تحذيرات المحلل |
| 2026-05-21 | **واجهة دردشة n8n webhook كاملة — ملفَين جديدَين + تحديثات عدة**: **(1) `lib/n8n_chat_service.dart`** (جديد) — `N8nWebhookChatService`: `sendMessage({message, sessionId, language})` يُرسل JSON-POST لـ `https://n8n.kcsc.com.jo/webhook/.../chat` مع retry ×2 + exponential backoff (1s/2s)؛ `_parse()` يدعم 5 أشكال للرد (`output|text|message|response|answer`)؛ `loadOrCreateSession()` / `resetSession()` عبر `Random.secure()` → `kcsc_{ms}_{12chars}` في `n8n_webhook_session_id`؛ **(2) `lib/n8n_webhook_chat_page.dart`** (جديد) — واجهة WhatsApp/ChatGPT: فقاعات يمين (user=`c.userBubble`) + يسار (bot=`c.surface`+border)؛ `TweenAnimationBuilder<double>` per message (fade-in + slide ±28px، 380ms، `ValueKey` يمنع إعادة التشغيل)؛ `_TypingBubble` + `_TypingDots` (3 نقاط، phase offset 0.22، scale+opacity)؛ `_EmptyState` مع 3 `_SuggestionChip` suggestion chips جاهزة؛ `_detectDir()` RTL تلقائي؛ Long-press copy؛ New Chat مع dialog تأكيد؛ **(3) `app_localizations.dart`** — 12 مفتاح جديد: `n8nChatTitle`..`n8nSuggestion3`؛ **(4) `app_drawer.dart`** — `DrawerSection.n8nWebhookChat` جديد + `_NavItem(support_agent_rounded)` + case في switch؛ **(5) `main.dart`** — import + route `/n8n-webhook-chat`؛ `flutter analyze` → **0 issues**؛ APK (65.1 MB) ✅ + Web ✅ | تطبيق الطلب: واجهة دردشة مستقلة تتصل بـ n8n webhook مع أنيميشن كامل وRTL وsession management |
| 2026-05-22 | **n8n Webhook URL من الإعدادات + شاشة إعداد**: **(1) `lib/n8n_chat_service.dart`** — إضافة `getWebhookUrl()` static يقرأ `n8n_chat_url` من SharedPreferences؛ `sendMessage()` يقرأ الـ URL تلقائياً قبل كل إرسال ويرمي `Exception('n8n_not_configured')` إذا كان فارغاً — لا URL مشفَّر في الكود؛ **(2) `lib/n8n_webhook_chat_page.dart`** — `_initSession()` تتحقق من الـ URL عند فتح الصفحة وتضبط `_urlConfigured`؛ إضافة `_NotConfiguredBanner` widget يظهر عند غياب الـ URL: أيقونة warning + رسالة AR/EN + زر "فتح الإعدادات" ينتقل لـ `/settings`؛ `flutter analyze` → **0 issues**؛ APK (64.8 MB) ✅ + Web ✅ | الـ URL الآن يُقرأ من Settings — لا hardcoded URLs في الكود |
| 2026-05-22 | **إعادة بناء n8n Chat Module — اتصال مباشر + Chat Page من صفر**: **(1) `lib/n8n_chat_service.dart`** — إعادة كتابة كاملة: اتصال مباشر `http.post` لـ n8n webhook بدون أي dependency على `ApiService` أو ERPNext — `N8nWebhookChatService` singleton (`const instance`) يستقبل `message/session_id/language`، retry ×2 مع backoff (2s/4s)، timeout 15s، parser يدعم 5 أشكال رد؛ `loadOrCreateSession()` / `resetSession()` — session ID في `n8n_session_id` بـ SharedPreferences مستقل عن بقية الـ app؛ صفر dependency على `ApiService`؛ **(2) `lib/n8n_webhook_chat_page.dart`** — إعادة بناء كاملة من صفر: `_Message` model (user/bot/isError)، فقاعات user (يمين، `c.userBubble`) + bot (يسار، `c.surface`+border)، RTL تلقائي بفحص أول code-point، `_TypingIndicator` مع `_AnimatedDots` (3 نقاط، phase offset 0.33، AnimationController 1.2s)، `_InputBar` مع multi-line TextField + CircleBorder send button، `_EmptyState` مع 3 suggestion chips، retry button على error messages، long-press copy، new chat مع dialog تأكيد، auto-scroll `animateTo(maxScrollExtent, 300ms)`؛ `flutter analyze` → **0 issues**؛ APK (64.8 MB) ✅ + Web ✅ | n8n Chat معزول تماماً: لا ERPNext، لا ApiService، لا shared state — Flutter يتصل مباشرة بـ n8n بعد تفعيل CORS headers على nginx الخاص بـ n8n.kcsc.com.jo |
| 2026-05-22 | **إصلاح CORS + معمارية proxy لـ n8n Chat**: **(1) `lib/n8n_chat_page.dart`** — إعادة كتابة كاملة من 1985 سطر → 105 سطر: حُذف كل كود مراقبة n8n (`_N8nApi`/`_Workflow`/`_Execution`/`_Stats`/`_StatsGrid`/`_WorkflowCard`/`_ExecutionPanel`/`_SetupBanner`/polling timers) — السبب الجذري لـ CORS errors؛ الصفحة الآن `StatelessWidget` ثابتة بدون أي HTTP calls تعرض زر انتقال لـ `/n8n-webhook-chat`؛ **(2) `lib/n8n_chat_service.dart`** — استبدال `http.post` المباشر لـ `https://n8n.kcsc.com.jo/webhook/.../chat` بـ `ApiService.postForm('/api/method/kcsc_erp.api.n8n_proxy.chat')` — الاتصال الآن عبر ERPNext كـ proxy فيختفي CORS تلقائياً؛ **(3) `kcsc_erp/kcsc_erp/api/n8n_proxy.py`** (ملف جديد) — method مُسجَّل بـ `@frappe.whitelist()` يستقبل `message/session_id/language` ويُحوّلها لـ n8n server-side مع: retry ×3 عند Timeout/ConnectionError، حماية من 4xx، `frappe.log_error` لكل نوع خطأ، parser يدعم 5 أشكال رد من n8n؛ **(4) `lib/app_theme.dart`** — إضافة `fontFamily: 'Cairo'` لكلا ثيمَي light وdark → يحل "Could not find a set of Noto fonts" على Flutter Web؛ `flutter analyze` → **0 issues**؛ APK (64.8 MB) ✅ + Web ✅ | CORS errors مُزالة بالكامل: Flutter → ERPNext (same-origin) → n8n (server-side) |
| 2026-05-21 | **إعادة بناء شاملة لـ `n8n_chat_page.dart` — Workflow Automation Dashboard**: تحويل الصفحة من chat page بسيطة إلى لوحة تحكم n8n كاملة تستهلك n8n REST API v1؛ **(1) `_N8nApi` service class**: `GET /api/v1/workflows`، `GET /api/v1/executions`، `POST /api/v1/workflows/{id}/execute`، activate/deactivate؛ مصادقة بـ `X-N8N-API-KEY` header؛ **(2) `_SetupBanner`**: يظهر عند غياب `n8n_api_key` — إدخال المفتاح inline مع visibility toggle، يُحفظ في `SharedPreferences('n8n_api_key')`، base URL يُستخرج تلقائياً من `n8n_chat_url`؛ **(3) `_StatsGrid`**: 4 بطاقات إحصائية (Total/Active/Failed/Running) — skeleton loading، 4 أعمدة ≥380px أو 2×2 ؛ **(4) `_WorkflowCard`**: اسم + active toggle (يُفعّل/يوقف workflow) + last execution badge + success rate bar مُلوَّن (green/yellow/red) + 3 أزرار (Open in browser / Execute / View logs)؛ **(5) `_ExecutionPanel`**: سجل التنفيذات — sidebar دائم على ≥768px، `DraggableScrollableSheet` على موبايل؛ **(6) Responsive layout**: `< 768px` قائمة عمودية + bottom sheet، `≥ 768px` → `Row` (flex:5 + SizedBox(340))؛ **(7) `_SkeletonCard`** pulsing animation؛ **(8) `_EmptyView` / `_ErrorView`** مع retry؛ **(9) بحث inline في AppBar** + `RotationTransition` على زر Refresh؛ الكلاس `N8nChatPage` محفوظ للتوافق مع مسار `/n8n-chat`؛ `flutter analyze lib/n8n_chat_page.dart` → **0 issues**؛ APK (64.9 MB) ✅ + Web ✅ | تحويل صفحة n8n من chat بسيط إلى لوحة تحكم production-grade لإدارة ومراقبة n8n workflows |
| 2026-05-15 | **إعادة بناء شاملة وتصحيح جذري لـ `dashboard_detail_page.dart`** — تشخيص وإصلاح 7 أسباب جذرية لخلل البيانات: **(1)** `_httpGet()` كانت تبتلع جميع الاستثناءات بـ `catch(_){}` صامتاً → الرسوم فارغة دائماً؛ **(2)** بناء URL كامل → تحليله لاستخراج المسار → تمريره لـ `ApiService.get()` (تشفير مزدوج + مسارات خاطئة)؛ **(3)** لا `_busy` flag → تحميلات متزامنة تكتب فوق بعضها؛ **(4)** لا `_loadToken` → نتائج قديمة تلوّث الـ state الحالي؛ **(5)** مفتاح الكاش لا يشمل `extraFilters` → cache hits خاطئة لفلاتر مختلفة؛ **(6)** حقل `exc` لا يُفحص لكل chart على حدة → أخطاء الصلاحيات صامتة؛ **(7)** Timer لا يفحص `_busy` → يُطلق تحميلاً أثناء تحميل آخر نشط؛ **البنية الجديدة**: `_DashService.fetchChartData()` يبني query string مباشرة `ApiService.get('/api/method/.../get?chart_name=...')` — لا مساعد وسيط؛ `_deepParseChart()` parser عميق يتعامل مع جميع أشكال استجابة FAC/MCP؛ `_busy` + `_loadToken` + `alive()` لحماية الـ state؛ per-chart `_chartLoading`/`_chartErrors`؛ `_SkeletonLoader`/`_ChartError`/`_NoData` widgets منفصلة؛ logging هيكلي `[DASHBOARD][FAC/PARSER/STATE/PERMISSION/DASH_REFRESH]` | الرسوم كانت فارغة دائماً — الأسباب الجذرية موثقة ومُصلحة بالكامل |
| 2026-05-15 | **إعادة بناء صفحتَي Dashboard من الصفر — Enterprise-grade**: **(1) `dashboards_page.dart`** — استبدال `http` بـ `ApiService.get()` (static)؛ إضافة search bar مع clear button؛ Responsive grid (عمودان ≥700px، قائمة على موبايل)؛ `Material + InkWell` بدل `ListTile`؛ حذف `http` import كلياً؛ **(2) `dashboard_detail_page.dart`** (إعادة كتابة كاملة ~1650 سطر): طبقة `_DashService` — FAC أولاً (FacMcpService) ثم ERPNext API fallback تلقائياً + كاش 5 دقائق في الذاكرة؛ `fl_chart` لجميع الرسوم (Bar/Line/Pie/Donut) تحل محل Custom Painters — أنيمشن + tooltip + تفاعل؛ `_KpiCard` للقيم الفردية (Count/Sum/Average)؛ `_PendingWidget` يعرض عدد الموافقات المعلقة (FAC → ERPNext fallback) مع رابط لـ `/pending-approvals`؛ Responsive layout: < 768px → mobile vertical scroll + bottom sheet filters، ≥ 768px → sidebar فلاتر قابل للطي + grid (2 أو 3 أعمدة حسب الاتساع)؛ Company filter dropdown محمّل من ERPNext؛ `_DataTableCard` مع expand/collapse؛ per-chart filters sheet محفوظة؛ `iconTheme + systemOverlayStyle + elevation` في AppBar؛ **(3) `app_localizations.dart`** — إضافة 4 مفاتيح: `dashSearchHint`/`dashCompany`/`dashViewAll`/`dashNoPermission` | إعادة بناء كاملة: الصفحة كانت تستخدم `http` مباشرة بدون FAC وبدون fl_chart — الجديدة enterprise-grade مع responsive + FAC + fl_chart |
| 2026-05-15 | **تحسين AppBar احترافي في `pending_approvals_page.dart` و `approved_page.dart`**: **(1) إصلاح جذري لسهم الرجوع**: `iconTheme: const IconThemeData(color: Colors.white)` يتجاوز `appBarTheme.iconTheme(color: textSecondary)` الغامق المُعرَّف عالمياً في `app_theme.dart` — السهم أبيض في كلا الوضعَين Light وDark لأن خلفية AppBar ملوّنة دائماً؛ **(2) `systemOverlayStyle: SystemUiOverlayStyle.light`** + `import 'package:flutter/services.dart' show SystemUiOverlayStyle` — أيقونات شريط الحالة (وقت/بطارية/إشارة) تصبح بيضاء فوق AppBar الملوّن؛ **(3) `elevation: 3` + `shadowColor`** — ظل خفيف يعطي عمقاً بصرياً ويفصل AppBar عن المحتوى؛ **(4) Title Column ثنائي السطر**: عنوان رئيسي (fontSize:17/w700/letterSpacing:0.2) + subtitle أبيض شفاف 75% يعرض في Pending "X بند في الانتظار" / "X pending" وفي Approved "آخر N يوم" / "Last N days"؛ **(5) `titleSpacing: 0` + padding 4px + `SizedBox(4)` trailing** — توازن بصري RTL/LTR | سهم الرجوع كان يظهر داكناً بسبب `iconTheme` العالمي في `app_theme.dart` الذي يتجاوز `foregroundColor` المحلي |
| 2026-05-15 | **i18n شامل لـ `pending_approvals_page.dart` و `approved_page.dart`**: `app_localizations.dart` — إضافة 3 مفاتيح ثابتة (`wfSearchHint`/`wfFallbackMode`/`wfFallbackDetails`) + 5 دوال معاملة (`wfLocalizeAction` بخريطة 28 إجراء: Approve→موافقة، Reject→رفض، Submit→تقديم، Cancel→إلغاء...؛ `wfLastNDays(n)`؛ `wfExecutingMsg`؛ `wfActionDoneMsg`؛ `wfActionCancelledMsg`)؛ `pending_approvals_page.dart` — 9 تغييرات: عنوان dialog، زر تأكيد، 3 SnackBars، hint البحث، لافتة Fallback، زر Details، `_ActBtn.build()` يستدعي `wfLocalizeAction(label)`، `_RefreshBtn` يستخدم `l.wfRefreshApprovals`؛ `approved_page.dart` — 2 تغييرات: hint البحث + نص "آخر N يوم/Last N days"؛ لوحة FAC Diagnostics (developer tool) تبقى بالإنجليزي | كل عناصر الصفحتَين تعرض بالعربية عند اختيار AR وبالإنجليزية عند اختيار EN — صفر نصوص مُضمَّنة في الـ widgets |
| 2026-05-15 | `ai_assistant_page.dart` — **إخفاء بطاقات الموديولات الستة من شاشة الترحيب**: حذف `_ModuleInfo` class + `_ModuleCard` class + `_EmptyState._modules` list (Purchasing/Accounting/Human Resources/Inventory/Manufacturing/Sales)؛ إزالة قسم "ابدأ بموديول" + GridView + Divider من `_EmptyState.build()` — شاشة الترحيب تعرض رسالة الترحيب فقط؛ `_InlineModuleGrid.build()` → `SizedBox.shrink()` بدون أي عناصر أسفل رسالة الترحيب؛ صفر تغيير في system prompt أو منطق module detection أو أي جزء آخر من الصفحة | طلب المستخدم: إخفاء الموديولات من الـ UI فقط مع الحفاظ على كامل المنطق |
| 2026-05-12 | `ai_assistant_page.dart` — **إصلاح OCR بدون تعديل السيرفر — Native Vision للصور**: تشخيص جذري لخطأ PaddleOCR: `extract_file_content` FAC tool تُشغّل الـ subprocess بـ `sys.executable` (Frappe Python 3.14) الذي يملك `paddleocr 3.5.0` بلا `paddlepaddle`؛ بينما البيئة الصحيحة `/opt/ocr-service/venv` (Python 3.10 + paddlepaddle 3.0.0) لا تُستدعى أبداً؛ **الحل داخل التطبيق (بدون أي تعديل على السيرفر):** تحديث 3 أقسام في system prompt: (1) RULE 0.5 — استبدال "use extract-file-content-usage for images" بـ "PRIMARY: use native vision on base64 directly"; (2) FAC ROUTING ENGINE ④ — الصور → native vision، PDF/Excel/DOCX → extract-file-content-usage كما هو؛ (3) `_facRoutingHint()` — تغيير hint الصور من "extract-file-content-usage for deep OCR" إلى "use YOUR NATIVE VISION (no FAC OCR needed)"؛ المبرر: Claude يستقبل الصورة كـ base64 في نفس الرسالة — لديه رؤية بصرية كاملة بدون أي أداة خارجية، أسرع وأدق للفواتير العربية؛ APK (64.6 MB) + Web ✅ | خطأ "Engine paddle_static unavailable" عند OCR أي صورة — الحل: Claude يقرأ الصورة بنفسه مباشرة |
| 2026-06-23 | **تصفير الإصدار**: `pubspec.yaml` — `version: 1.0.78+78` → `version: 1.0.0+1`؛ `build.gradle.kts` يقرأ الإصدار تلقائياً من pubspec | إعادة البداية بإصدار جديد بعد إعادة التسمية |
| 2026-06-23 | **إعادة تسمية التطبيق إلى "Kashef (كاشف)"**: تغيير "Faheem"/"فهيم" → "Kashef"/"كاشف" في: `app_localizations.dart` (6 مفاتيح)، `main.dart`، `ai_assistant_page.dart`، `background_service.dart`، `realtime_workflow_service.dart`، `AndroidManifest.xml`، `web/manifest.json`، `web/index.html` | طلب المستخدم |
| 2026-06-27 | **اسم ملف التصدير الديناميكي**: `settings_page.dart` — إضافة `_backupFileName()` تولّد اسم ملف بالتنسيق `Kashef_backup_YYYY-MM-DD_HH-mm-ss.json` بدون حزمة إضافية (padding يدوي)؛ استبدال `'kcsc_ai_backup.json'` الثابت في كلا المسارَين (Web + Mobile) | الاسم الثابت لا يُميّز بين النسخ الاحتياطية المتعددة |
| 2026-06-27 | **إصلاح تصدير الإعدادات على Flutter Web**: `settings_page.dart` — `_exportSettings()`: إضافة `kIsWeb` branch — على Web: `downloadBytesInBrowser(utf8.encode(jsonStr), 'kcsc_ai_backup.json', 'application/json')` يُنزِّل الملف مباشرة في المتصفح بدون `getTemporaryDirectory`/`File`/`SharePlus` (كلها غير مدعومة على Web)؛ على Mobile/Desktop: يبقى السلوك القديم (temp file + SharePlus share sheet) بدون أي تغيير؛ `app_localizations.dart` — إضافة مفتاح `exportSuccess` (EN/AR) للـ SnackBar عند النجاح على Web؛ APK (64.9 MB) ✅ + Web ✅ | `MissingPluginException: getTemporaryDirectory` كانت تُوقف التصدير بالكامل على الويب |
| 2026-06-27 | **إصلاح خطأ لغة التفريغ الصوتي**: `ai_assistant_page.dart` — `transcribeAndSend()`: تغيير نموذج Whisper من `whisper-1` إلى `gpt-4o-transcribe` (كشف لغة أدق — يمنع تفريغ الإنجليزية كعربية)؛ تغيير `response_format` من `verbose_json` إلى `json` (gpt-4o-transcribe لا يدعم verbose_json)؛ `json['language']` غائب في الرد → `languageHint = null` → لا يُضاف prefix إجباري للغة → RULE 0 في system prompt يكتشف اللغة من النص مباشرة ويرد بها | إصلاح: رسائل صوتية إنجليزية كانت تُفرَّغ كعربية بسبب ضعف كشف اللغة في whisper-1؛ APK (64.9 MB) + Web ✅ |
| 2026-06-23 | **تغيير شعار التطبيق إلى Kashef**: نسخ `assets/images/kashef logo.jpeg` → `images/kashef_logo.jpeg`؛ `pubspec.yaml` — `flutter_launcher_icons` يُحدَّث لـ `kashef_logo.jpeg` (خلفية `#FFFFFF`)؛ `settings_page.dart` — `buildLogoWidget()` fallback → `images/kashef_logo.jpeg`؛ توليد أيقونات Android عبر `dart run flutter_launcher_icons`؛ توليد أيقونات Web (favicon 32px + PWA 192/512 + maskable) عبر PowerShell System.Drawing | طلب المستخدم: هوية بصرية جديدة بشعار أيقونة العين الزرقاء |
| 2026-06-10 | **إعادة تسمية التطبيق إلى "Faheem (فهيم)" + تغيير الشعار**: **(1) اسم التطبيق** — تغيير "KCSC AI" → "Faheem" / "فهيم" في: `app_localizations.dart` (`appTitle`/`welcome`/`backupSubject`/`notKcscSettings`/`agentName`/`assistantIntro`)، `main.dart` (title)، `background_service.dart` (عنوان الإشعار)، `realtime_workflow_service.dart` (عنوان SnackBar/إشعار)، `ai_assistant_page.dart` (`agentName` + `agentDescAr/En` + empty state)، `web/manifest.json` (name/short_name/description)، `web/index.html` (title + apple-mobile-web-app-title)، `AndroidManifest.xml` (android:label)؛ **(2) الشعار** — تغيير من `images/KCSC_Logo.png` إلى `images/faheem_logo.png` في: `pubspec.yaml` (flutter_launcher_icons — خلفية `#FFFFFF` بدل `#0F172A`)، `settings_page.dart` (`buildLogoWidget()` fallback)؛ توليد أيقونات Android تلقائياً عبر `dart run flutter_launcher_icons`؛ توليد أيقونات Web (favicon 32px + PWA 192/512 + maskable) عبر PowerShell System.Drawing؛ **(3) Web URL** — تغيير base-href من `/kcsc-ai/` إلى `/faheem/`؛ `flutter build web --release --base-href /faheem/` عبر PowerShell (Git Bash يُحوّل المسار خطأً) | طلب المستخدم: إعادة تسمية التطبيق والمساعد الذكي باسم "فهيم" مع هوية بصرية جديدة |
| 2026-05-09 | **نظام Workflow الديناميكي — إعادة بناء شاملة (9 خطوات)**: (1) **`lib/workflow_models.dart`** (جديد) — `PendingDoc` + `WorkflowSource` enum (workflowAction/dynamicScan)؛ (2) **`lib/fac_validator.dart`** (جديد) — FAC Permission layer: `hasReadPermission` (frappe.client.has_permission) + `getValidatedTransitions` + `validateBeforeApply` (pre-execution FAC gate) + `canAccessDocType`؛ (3) **`lib/workflow_repository.dart`** (جديد) — طبقة البيانات المركزية تجمع SOURCE A (Workflow Action records) + SOURCE B (Dynamic scan لكل DocType نشط عليه workflow بـ limit=30 + get_transitions للتحقق) — كاش 30s/60s — dedup بـ doctype::docname — SOURCE A أولوية؛ (4) **`lib/workflow_service.dart`** — إضافة `safeApplyWorkflow()` يستدعي `FacValidator.validateBeforeApply()` قبل `applyWorkflow()` — يمنع 417 EXPECTATION FAILED؛ (5) **`lib/pending_approvals_page.dart`** — إعادة بناء كاملة: يستخدم `WorkflowRepository` بدل API مباشر، source badge للعناصر من Dynamic Scan، `_DynamicScanBanner` عند وجود عناصر مكتشفة، invalidate + refresh بعد كل workflow action؛ (6) **`lib/realtime_workflow_service.dart`** — `_loadPendingCount` يستخدم `WorkflowRepository.fetchCount()` (SOURCE A+B) + fallback للـ API المباشر، `broadcastLocal` يستدعي `WorkflowRepository().invalidate()`؛ (7) **`lib/document_viewer_page.dart`** — استبدال `applyWorkflow` بـ `safeApplyWorkflow` لكل أزرار الـ transitions؛ (8) **`lib/app_localizations.dart`** — 6 مفاتيح جديدة: `wfSourceDynamic`/`wfDynamicScanNotice`/`wfFacDenied`/`wfStateChanged`/`wfValidating`/`wfNoTransitions`؛ `pubspec.yaml` — `1.0.69+69` | إصلاح جذري شامل: Draft invoices تظهر الآن، مستندات بدون Workflow Action تُكتشف، FAC يتحقق قبل كل إجراء، 417 errors ممنوعة |
