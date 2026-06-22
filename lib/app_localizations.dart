import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// AppLocalizations — supports English ('en') and Arabic ('ar')
// ---------------------------------------------------------------------------
class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const delegate = _AppLocalizationsDelegate();

  String get languageCode => locale.languageCode;
  bool get isArabic => locale.languageCode == 'ar';

  // ── Strings map ────────────────────────────────────────────────────────────
  static const Map<String, Map<String, String>> _s = {
    // ── General ──────────────────────────────────────────────────────────────
    'appTitle':           {'en': 'Kashef',               'ar': 'كاشف'},
    'settings':           {'en': 'Settings',           'ar': 'الإعدادات'},
    'retry':              {'en': 'Retry',               'ar': 'إعادة المحاولة'},
    'cancel':             {'en': 'Cancel',              'ar': 'إلغاء'},
    'refresh':            {'en': 'Refresh',             'ar': 'تحديث'},
    'logout':             {'en': 'Logout',              'ar': 'تسجيل الخروج'},
    'save':               {'en': 'Save',                'ar': 'حفظ'},
    'clear':              {'en': 'Clear',               'ar': 'مسح'},
    'apply':              {'en': 'Apply',               'ar': 'تطبيق'},
    'search':             {'en': 'Search…',             'ar': 'بحث…'},
    'noResults':          {'en': 'No results',          'ar': 'لا توجد نتائج'},
    'copied':             {'en': 'Copied',              'ar': 'تم النسخ'},
    'default_':           {'en': 'Default',             'ar': 'افتراضي'},

    // ── Home ─────────────────────────────────────────────────────────────────
    'welcome':            {'en': 'Welcome to Kashef',    'ar': 'مرحباً بك في كاشف'},
    'tapToContinue':      {'en': 'Tap the button below to continue', 'ar': 'اضغط على الزر للمتابعة'},
    'login':              {'en': 'Login',               'ar': 'تسجيل الدخول'},

    // ── Login ────────────────────────────────────────────────────────────────
    'signIn':             {'en': 'Sign in to ERPNext',  'ar': 'تسجيل الدخول إلى ERPNext'},
    'noCredentials':      {'en': 'No credentials configured yet. Tap Settings to set up your ERPNext URL, username, and password.',
                           'ar': 'لم يتم ضبط بيانات الاتصال بعد. اضغط على الإعدادات لإدخال رابط ERPNext واسم المستخدم وكلمة المرور.'},
    'configureSettings':  {'en': 'Configure Connection in Settings', 'ar': 'إعداد الاتصال من الإعدادات'},
    'loginSuccessful':    {'en': 'Login successful',    'ar': 'تم تسجيل الدخول بنجاح'},

    // ── Modules ──────────────────────────────────────────────────────────────
    'modules':            {'en': 'Modules',             'ar': 'الوحدات'},
    'aiAssistant':        {'en': 'AI Assistant',        'ar': 'المساعد الذكي'},
    'dashboards':         {'en': 'Dashboards',          'ar': 'لوحات البيانات'},
    'noModules':          {'en': 'No modules found.',   'ar': 'لا توجد وحدات.'},
    'moduleBlocked':      {'en': 'This module has been blocked for your account by the administrator.',
                           'ar': 'تم حظر هذه الوحدة لحسابك من قِبل المسؤول.'},
    'fullAccess':         {'en': 'You have full access permission to this module.',
                           'ar': 'لديك صلاحية وصول كاملة لهذه الوحدة.'},

    // ── Company ──────────────────────────────────────────────────────────────
    'company':            {'en': 'Company',             'ar': 'الشركة'},
    'selectedCompany':    {'en': 'Selected Company',    'ar': 'الشركة المختارة'},
    'notConfigured':      {'en': 'Not configured — go to Settings', 'ar': 'غير مُعدَّد — اذهب إلى الإعدادات'},
    'companyInSettings':  {'en': 'Company is set in Settings and cannot be changed here.',
                           'ar': 'الشركة مُحددة في الإعدادات ولا يمكن تغييرها هنا.'},
    'continueToModules':  {'en': 'Continue to Modules', 'ar': 'المتابعة إلى الوحدات'},
    'changeCompany':      {'en': 'Change company in Settings', 'ar': 'تغيير الشركة من الإعدادات'},
    'noCompany':          {'en': 'No company configured. Please set a company name in Settings.',
                           'ar': 'لم يتم تحديد شركة. يرجى تحديد اسم الشركة في الإعدادات.'},

    // ── Settings ─────────────────────────────────────────────────────────────
    'clearAllSettings':   {'en': 'Clear all settings',  'ar': 'مسح جميع الإعدادات'},
    'erpnextConnection':  {'en': 'ERPNext Connection',   'ar': 'اتصال ERPNext'},
    'erpnextUrl':         {'en': 'ERPNext URL',          'ar': 'رابط ERPNext'},
    'urlHint':            {'en': 'https://your-site.erpnext.com', 'ar': 'https://your-site.erpnext.com'},
    'username':           {'en': 'Username',             'ar': 'اسم المستخدم'},
    'usernameHint':       {'en': 'admin or user@example.com', 'ar': 'admin أو user@example.com'},
    'password':           {'en': 'Password',             'ar': 'كلمة المرور'},
    'apiTokenSection':    {'en': 'ERPNext API Token (Optional)', 'ar': 'رمز API لـ ERPNext (اختياري)'},
    'apiTokenInfo':       {'en': 'If you enter API Key and API Secret, they will be used instead of password.\nGenerate them from: ERPNext ← My Settings ← API Access.',
                           'ar': 'إذا أدخلت API Key و API Secret فسيُستخدمان بدلاً من كلمة المرور.\nيمكن توليدهما من: ERPNext ← My Settings ← API Access.'},
    'apiKey':             {'en': 'API Key',              'ar': 'مفتاح API'},
    'apiSecret':          {'en': 'API Secret',           'ar': 'سر API'},
    'companyName':        {'en': 'Company Name',         'ar': 'اسم الشركة'},
    'companyHint':        {'en': 'My Company LLC',       'ar': 'شركتي المحدودة'},
    'aiSection':          {'en': 'AI Assistant — Frappe Assistant Core', 'ar': 'المساعد الذكي — Frappe Assistant Core'},
    'aiInfo':             {'en': 'Frappe Assistant Core must be installed on the server.\nClaude API Key is used to connect to Claude directly from the app.',
                           'ar': 'يجب تثبيت Frappe Assistant Core على الخادم.\nيُستخدم Claude API Key للاتصال بـ Claude مباشرة من التطبيق.'},
    'claudeApiKey':       {'en': 'Claude API Key',       'ar': 'مفتاح Claude API'},
    'mcpEndpoint':        {'en': 'MCP Endpoint',         'ar': 'نقطة اتصال MCP'},
    'resetToDefault':     {'en': 'Reset to default',     'ar': 'إعادة تعيين إلى الافتراضي'},
    'saving':             {'en': 'Saving…',              'ar': 'جاري الحفظ…'},
    'saved':              {'en': 'Saved',                'ar': 'تم الحفظ'},
    'saveSettings':       {'en': 'Save Settings',        'ar': 'حفظ الإعدادات'},
    'backToLogin':        {'en': 'Back to Login',        'ar': 'العودة لتسجيل الدخول'},
    'urlRequired':        {'en': 'URL is required',      'ar': 'الرابط مطلوب'},
    'validUrl':           {'en': 'Enter a valid URL starting with https://', 'ar': 'أدخل رابطاً صحيحاً يبدأ بـ https://'},
    'usernameRequired':   {'en': 'Username is required', 'ar': 'اسم المستخدم مطلوب'},
    'passwordRequired':   {'en': 'Password is required', 'ar': 'كلمة المرور مطلوبة'},
    'companyRequired':    {'en': 'Company is required',  'ar': 'اسم الشركة مطلوب'},
    'clearSettingsTitle': {'en': 'Clear Settings',       'ar': 'مسح الإعدادات'},
    'clearSettingsConfirm':{'en': 'This will remove all saved credentials. Continue?',
                            'ar': 'سيتم حذف جميع البيانات المحفوظة. هل تريد المتابعة؟'},
    'settingsCleared':    {'en': 'Settings cleared',     'ar': 'تم مسح الإعدادات'},

    // ── Settings — logo ──────────────────────────────────────────────────────
    'appLogoSection':     {'en': 'App Logo',             'ar': 'شعار التطبيق'},
    'removeLogo':         {'en': 'Remove Custom Logo',   'ar': 'إزالة الشعار المخصص'},
    'logoUpdated':        {'en': 'Logo updated',         'ar': 'تم تحديث الشعار'},
    'noImageContent':     {'en': 'No image content found', 'ar': 'لم يُعثر على محتوى الصورة'},

    // ── Settings — export/import ──────────────────────────────────────────────
    'exportTooltip':      {'en': 'Export Settings (Backup)', 'ar': 'تصدير الإعدادات (نسخ احتياطي)'},
    'importTooltip':      {'en': 'Import Settings',      'ar': 'استيراد الإعدادات'},
    'backupSubject':      {'en': 'Kashef — Settings Backup', 'ar': 'كاشف — إعدادات النسخ الاحتياطي'},
    'noFileContent':      {'en': 'No file content found.', 'ar': 'لم يُعثر على محتوى الملف.'},
    'notSettingsFile':    {'en': 'The file is not a valid settings file.', 'ar': 'الملف ليس ملف إعدادات صالحاً.'},
    'notKcscSettings':    {'en': 'File does not appear to be a Kashef settings file.', 'ar': 'الملف لا يبدو ملف إعدادات كاشف.'},

    // ── Settings — AI provider labels ─────────────────────────────────────────
    'providerClaudeOnly':   {'en': 'Claude Only',        'ar': 'Claude فقط'},
    'providerChatGptOnly':  {'en': 'ChatGPT Only',       'ar': 'ChatGPT فقط'},
    'providerClaudeFirst':  {'en': 'Claude First',       'ar': 'Claude أولاً'},
    'providerChatGptFirst': {'en': 'ChatGPT First',      'ar': 'ChatGPT أولاً'},
    'providerDescClaude':   {'en': 'Claude only — no fallback', 'ar': 'Claude فقط — بدون fallback'},
    'providerDescChatGpt':  {'en': 'ChatGPT only — no fallback', 'ar': 'ChatGPT فقط — بدون fallback'},
    'providerDescClaudeFirst': {'en': 'Claude first → falls back to ChatGPT automatically', 'ar': 'Claude أولاً ← عند الفشل ينتقل لـ ChatGPT تلقائياً'},
    'providerDescChatGptFirst':{'en': 'ChatGPT first → falls back to Claude automatically', 'ar': 'ChatGPT أولاً ← عند الفشل ينتقل لـ Claude تلقائياً'},
    'chatGptInfo':          {'en': 'ChatGPT is used via OpenAI API.\nRequires an OpenAI API Key with access to GPT-4 models.',
                             'ar': 'يُستخدم ChatGPT عبر OpenAI API.\nيتطلب مفتاح OpenAI API Key مع صلاحية الوصول إلى نماذج GPT-4.'},

    // ── Settings — misc ───────────────────────────────────────────────────────
    'apiTokenOptional':   {'en': 'ERPNext API Token (Optional)', 'ar': 'رمز API لـ ERPNext (اختياري)'},

    'language':           {'en': 'Language',             'ar': 'اللغة'},
    'english':            {'en': 'English',              'ar': 'الإنجليزية'},
    'arabic':             {'en': 'Arabic',               'ar': 'العربية'},
    'themeMode':          {'en': 'Theme',                'ar': 'المظهر'},
    'lightMode':          {'en': 'Light',                'ar': 'فاتح'},
    'darkMode':           {'en': 'Dark',                 'ar': 'داكن'},
    'systemMode':         {'en': 'System',               'ar': 'تلقائي'},

    // ── Accounting Dashboard ──────────────────────────────────────────────────
    'accountingDashboard':{'en': 'Accounting Dashboard', 'ar': 'لوحة المحاسبة'},
    'failedLoadDashboard':{'en': 'Failed to load dashboard data', 'ar': 'فشل تحميل بيانات لوحة التحكم'},
    'quickStats':         {'en': 'Quick Stats',          'ar': 'إحصائيات سريعة'},
    'companies':          {'en': 'Companies',            'ar': 'الشركات'},
    'active':             {'en': 'Active',               'ar': 'نشط'},
    'accountingModules':  {'en': 'Accounting Modules',   'ar': 'وحدات المحاسبة'},
    'chartOfAccounts':    {'en': 'Chart of Accounts',    'ar': 'دليل الحسابات'},
    'journalEntries':     {'en': 'Journal Entries',      'ar': 'القيود اليومية'},
    'generalLedger':      {'en': 'General Ledger',       'ar': 'دفتر الأستاذ'},
    'trialBalance':       {'en': 'Trial Balance',        'ar': 'ميزان المراجعة'},
    'financialReports':   {'en': 'Financial Reports',    'ar': 'التقارير المالية'},
    'bankReconciliation': {'en': 'Bank Reconciliation',  'ar': 'مطابقة البنك'},

    // ── Dashboards ────────────────────────────────────────────────────────────
    'noDashboards':       {'en': 'No dashboards found',  'ar': 'لا توجد لوحات بيانات'},
    'dashSearchHint':     {'en': 'Search dashboards…',   'ar': 'بحث في اللوحات…'},
    'dashCompany':        {'en': 'Company',               'ar': 'الشركة'},
    'dashViewAll':        {'en': 'View all',              'ar': 'عرض الكل'},
    'dashNoPermission':   {'en': 'No permission',         'ar': 'لا صلاحية'},

    // ── Dashboard Detail ──────────────────────────────────────────────────────
    'updatedAt':          {'en': 'Updated',              'ar': 'تم التحديث'},
    'autoEvery5Min':      {'en': 'auto every 5 min',     'ar': 'تلقائي كل 5 دقائق'},
    'dateRangeShort':     {'en': 'Date Range',           'ar': 'نطاق التاريخ'},
    'changeFilters':      {'en': 'Change Filters',       'ar': 'تغيير الفلاتر'},
    'noCharts':           {'en': 'No charts in this dashboard', 'ar': 'لا توجد مخططات في هذه اللوحة'},
    'noData':             {'en': 'No data',              'ar': 'لا توجد بيانات'},
    'period':             {'en': 'Period',               'ar': 'الفترة'},
    'value':              {'en': 'Value',                'ar': 'القيمة'},
    'showLess':           {'en': 'Show less ▲',          'ar': 'عرض أقل ▲'},
    'filterMode':         {'en': 'FILTER MODE',          'ar': 'نمط الفلتر'},
    'timespan':           {'en': 'TIMESPAN',             'ar': 'الفترة الزمنية'},
    'dateRange':          {'en': 'DATE RANGE',           'ar': 'نطاق التاريخ'},
    'from':               {'en': 'From',                 'ar': 'من'},
    'to':                 {'en': 'To',                   'ar': 'إلى'},
    'timegrain':          {'en': 'TIMEGRAIN',            'ar': 'دقة الوقت'},
    'relative':           {'en': 'Relative',             'ar': 'نسبي'},
    'selectDate':         {'en': 'Select date',          'ar': 'اختر تاريخاً'},
    'lastWeek':           {'en': 'Last Week',            'ar': 'الأسبوع الماضي'},
    'lastMonth':          {'en': 'Last Month',           'ar': 'الشهر الماضي'},
    'lastQuarter':        {'en': 'Last Quarter',         'ar': 'الربع الماضي'},
    'lastYear':           {'en': 'Last Year',            'ar': 'السنة الماضية'},
    'daily':              {'en': 'Daily',                'ar': 'يومي'},
    'weekly':             {'en': 'Weekly',               'ar': 'أسبوعي'},
    'monthly':            {'en': 'Monthly',              'ar': 'شهري'},
    'quarterly':          {'en': 'Quarterly',            'ar': 'ربع سنوي'},
    'yearly':             {'en': 'Yearly',               'ar': 'سنوي'},

    // ── AI Assistant ─────────────────────────────────────────────────────────
    'clearChat':          {'en': 'Clear chat',           'ar': 'مسح المحادثة'},
    'addClaudeKey':       {'en': 'Add Claude API Key in Settings to enable AI',
                           'ar': 'أضف Claude API Key في الإعدادات لتفعيل الذكاء الاصطناعي'},
    'errorOccurred':      {'en': 'An error occurred',    'ar': 'حدث خطأ'},
    'copyError':          {'en': 'Copy Error',           'ar': 'نسخ الخطأ'},
    'errorCopied':        {'en': 'Error copied',         'ar': 'تم نسخ الخطأ'},
    'thinking':           {'en': 'Thinking…',            'ar': 'جاري التفكير…'},
    'transcribing':       {'en': 'Transcribing…',           'ar': 'جاري التحويل الصوتي…'},
    'whisperKeyMissing':  {'en': 'Add OpenAI API Key in Settings to enable voice recognition',
                           'ar': 'أضف OpenAI API Key في الإعدادات لتفعيل التعرف الصوتي'},
    'attachFile':         {'en': 'Attach file or image',   'ar': 'إرفاق ملف أو صورة'},
    'cancelRecording':    {'en': 'Cancel recording',       'ar': 'إلغاء التسجيل'},
    'stopping':           {'en': 'Stopping…',              'ar': 'جارٍ الإيقاف…'},
    'stoppedByUser':      {'en': 'Stopped.',               'ar': 'تم الإيقاف.'},
    'stopGeneration':     {'en': 'Stop',                   'ar': 'إيقاف'},
    'camera':             {'en': 'Camera',                 'ar': 'الكاميرا'},
    'gallery':            {'en': 'Gallery',                'ar': 'معرض الصور'},
    'document':           {'en': 'Document',               'ar': 'ملف / وثيقة'},
    'addCaption':         {'en': 'Add a caption…',         'ar': 'أضف تعليقاً…'},
    'myFilesInSystem':    {'en': 'My files in ERPNext',    'ar': 'ملفاتي في النظام'},
    'browseAndSearch':    {'en': 'Browse & search',        'ar': 'تصفح وبحث'},
    'fromConversation':   {'en': 'From conversation',      'ar': 'من المحادثة'},
    'useExistingImages':  {'en': 'Use existing images',    'ar': 'استخدام صور موجودة'},
    'searchFiles':        {'en': 'Search files…',          'ar': 'ابحث عن ملف…'},
    'noFilesFound':       {'en': 'No files found',         'ar': 'لا توجد ملفات'},
    'noImagesInChat':     {'en': 'No images in conversation', 'ar': 'لا توجد صور في المحادثة'},
    'fileVisibility':     {'en': 'File visibility',          'ar': 'خصوصية الملف'},
    'filePublic':         {'en': 'Public',                   'ar': 'عام'},
    'filePrivate':        {'en': 'Private',                  'ar': 'خاص'},
    'filePublicHint':     {'en': 'Accessible to all users',  'ar': 'يمكن لجميع المستخدمين الوصول إليه'},
    'filePrivateHint':    {'en': 'Only you can access it',   'ar': 'أنت فقط تستطيع الوصول إليه'},
    'addSelected':        {'en': 'Add selected',           'ar': 'إضافة المختار'},
    'loadingFiles':       {'en': 'Loading files…',         'ar': 'جاري تحميل الملفات…'},
    'uploadingFiles':     {'en': 'Uploading files…',       'ar': 'جاري رفع الملفات…'},
    'connectingServer':   {'en': 'Connecting to server…',  'ar': 'جاري الاتصال بالسيرفر…'},
    'loadingTools':       {'en': 'Loading tools from ERPNext…', 'ar': 'جاري تحميل الأدوات من ERPNext…'},
    'processingResults':  {'en': 'Processing results…',   'ar': 'جاري معالجة النتائج…'},
    'savingChart':        {'en': 'Saving chart…',         'ar': 'جاري حفظ الرسم البياني…'},
    'noReplyReceived':    {'en': 'No response received.',  'ar': 'لم يتم الحصول على رد.'},
    'tryingProvider':     {'en': 'Trying {p}…',            'ar': 'جاري المحاولة مع {p}…'},
    'fallbackToProvider': {'en': 'Switching to {p}…',      'ar': 'التحويل إلى {p}…'},
    'saveChart':          {'en': 'Save Chart',             'ar': 'حفظ الرسم البياني'},
    'chartName':          {'en': 'Name',                   'ar': 'الاسم'},
    'chartType':          {'en': 'Type',                   'ar': 'النوع'},
    'chartCategories':    {'en': 'Categories',             'ar': 'الفئات'},
    'chartWillCreate':    {'en': 'A Dashboard Chart will be created in ERPNext.', 'ar': 'سيتم إنشاء Dashboard Chart في ERPNext.'},
    'chartFromAssistant': {'en': 'Chart from AI Assistant', 'ar': 'مخطط من المساعد الذكي'},
    'listening':          {'en': 'Listening…',           'ar': 'جاري الاستماع…'},
    'listeningWillSend':  {'en': 'Listening — will send automatically…', 'ar': 'جاري الاستماع — سيُرسل تلقائياً…'},
    'tapMicToSend':         {'en': 'Tap to speak — sends automatically when done', 'ar': 'اضغط للتحدث — يُرسل تلقائياً عند الانتهاء'},
    'tapToStopListening':   {'en': 'Tap to stop listening',  'ar': 'اضغط لإيقاف الاستماع'},
    'selectVoiceLanguage':  {'en': 'Select voice language',  'ar': 'اختر لغة الصوت'},
    'typeQuestion':       {'en': 'Type your question here…', 'ar': 'اكتب سؤالك هنا…'},
    'q1':                 {'en': 'What are the pending invoices?',      'ar': 'ما هي الفواتير المعلقة؟'},
    'q2':                 {'en': 'Show me the inventory report',        'ar': 'أظهر لي تقرير المخزون'},
    'q3':                 {'en': 'What are the company profits this month?', 'ar': 'ما هي أرباح الشركة هذا الشهر؟'},
    'q4':                 {'en': 'List of debtor customers',            'ar': 'قائمة العملاء المديونين'},

    // ── Welcome card ──────────────────────────────────────────────────────────
    'greetingMorning':    {'en': 'Good morning 🌅',         'ar': 'صباح الخير 🌅'},
    'greetingAfternoon':  {'en': 'Good afternoon 🌞',       'ar': 'مساء الخير 🌞'},
    'greetingEvening':    {'en': 'Good evening 🌙',         'ar': 'مساء النور 🌙'},
    'agentName':          {'en': 'Kashef',                  'ar': 'كاشف'},
    'assistantIntro':     {'en': 'I\'m **Kashef** — your intelligent assistant for ERPNext.',
                           'ar': 'أنا **كاشف** — مساعدك الذكي المتكامل لنظام ERPNext.'},
    'assistantModulesTitle':{'en': 'I cover all system modules:', 'ar': 'أغطي جميع موديولات النظام:'},
    'assistantModules':   {'en': '🛒 Purchasing · 💰 Accounting · 👥 Human Resources\n📦 Inventory · 🏭 Manufacturing · 📊 Sales',
                           'ar': '🛒 المشتريات · 💰 المحاسبة · 👥 الموارد البشرية\n📦 المخزون · 🏭 التصنيع · 📊 المبيعات'},
    'assistantHelpQuestion':{'en': 'How can I help you today?', 'ar': 'تفضّل، بماذا أستطيع مساعدتك اليوم؟'},

    // ── Voice / Microphone ────────────────────────────────────────────────────
    'micPermissionDenied':{'en': 'Microphone permission denied', 'ar': 'تم رفض صلاحية الميكروفون'},

    // ── Email ─────────────────────────────────────────────────────────────────
    'emailSendFailed':    {'en': 'Failed to send email',    'ar': 'فشل إرسال البريد'},

    // ── HR Quick Actions ───────────────────────────────────────────────────────
    'hrAgentTitle':       {'en': 'HR AI Agent',                        'ar': 'HR AI Agent'},
    'hrAgentSubtitle':    {'en': 'Your Smart HR Assistant',            'ar': 'مساعدك الذكي للموارد البشرية'},
    'quickActions':       {'en': 'Quick Actions',                      'ar': 'إجراءات سريعة'},
    'hrAddEmployee':      {'en': 'Add New Employee',                   'ar': 'إضافة موظف جديد'},
    'hrPayroll':          {'en': 'Current Payroll',                    'ar': 'كشف الرواتب'},
    'hrLeaveRequests':    {'en': 'Leave Requests',                     'ar': 'طلبات الإجازات'},
    'hrAppraisal':        {'en': 'Performance Appraisal',              'ar': 'تقييم الأداء'},
    'hrSearchEmployee':   {'en': 'Search Employee',                    'ar': 'بحث عن موظف'},
    'hrReports':          {'en': 'HR Reports',                        'ar': 'تقارير HR'},
    'erpModules':         {'en': 'ERP Modules',                        'ar': 'موديولز النظام'},
    'browseModules':      {'en': 'Browse all available modules',       'ar': 'تصفح جميع موديولز النظام المتاحة'},

    // ── Reports ───────────────────────────────────────────────────────────────
    'noReports':          {'en': 'No accessible reports found for this module.', 'ar': 'لا توجد تقارير متاحة لهذه الوحدة.'},
    'loadingParams':      {'en': 'Loading report parameters…', 'ar': 'جاري تحميل معاملات التقرير…'},
    'runningReport':      {'en': 'Running report…',      'ar': 'جاري تشغيل التقرير…'},
    'backToFilters':      {'en': 'Back to Filters',      'ar': 'العودة إلى الفلاتر'},
    'runReport':          {'en': 'Run Report',           'ar': 'تشغيل التقرير'},
    'selectPlaceholder':  {'en': '-- Select --',         'ar': '-- اختر --'},
    'noDataFilters':      {'en': 'No data found for these filters.', 'ar': 'لا توجد بيانات لهذه الفلاتر.'},
    'isRequired':         {'en': 'is required',          'ar': 'مطلوب'},

    // ── Report filters / errors ───────────────────────────────────────────────
    'missingFiltersAdded':    {'en': 'Missing filters added — review values and retry',       'ar': 'تم إضافة فلاتر مفقودة — راجع القيم ثم أعد التشغيل'},
    'fiscalYearFiltersAdded': {'en': 'Fiscal year filters added — review and retry',          'ar': 'تم إضافة فلاتر السنة المالية — راجع القيم ثم أعد التشغيل'},
    'dateFiltersAdded':       {'en': 'Date fields added — review and retry',                  'ar': 'تم إضافة حقول التاريخ المفقودة — راجع ثم أعد التشغيل'},
    'reportDataError':        {'en': 'Error processing report data — check filters and retry','ar': 'خطأ في معالجة بيانات التقرير — تحقق من قيم الفلاتر وأعد المحاولة'},
    'aiAutoFillTooltip':      {'en': 'Auto-fill with AI',                                     'ar': 'ملء تلقائي بواسطة الذكاء الاصطناعي'},
    'unknownError':           {'en': 'Unknown error',                                         'ar': 'خطأ غير معروف'},
    'refreshFilters':         {'en': 'Refresh Filters',                                       'ar': 'تحديث الفلاتر'},
    'addItem':                {'en': 'Add',                                                   'ar': 'إضافة'},
    'noneSelected':           {'en': 'None selected',                                         'ar': 'لم يتم الاختيار'},
    'filtersCached':          {'en': 'Filters loaded from cache',                             'ar': 'تم تحميل الفلاتر من الذاكرة المؤقتة'},
    'filtersRefreshed':       {'en': 'Filters refreshed from server',                         'ar': 'تم تحديث الفلاتر من الخادم'},
    'aiAnalyzingReport':      {'en': 'AI is analyzing the report',                           'ar': 'الذكاء الاصطناعي يحلل التقرير'},
    'aiConnecting':           {'en': 'Connecting to ERPNext…',                                'ar': 'جاري الاتصال بـ ERPNext…'},
    'aiNoTools':              {'en': 'No MCP tools found',                                    'ar': 'لم يتم العثور على أدوات MCP'},
    'aiProcessing':           {'en': 'Processing results…',                                   'ar': 'جاري معالجة النتائج…'},
    'aiNoResult':             {'en': 'AI returned no valid values',                           'ar': 'لم يُرجع الذكاء الاصطناعي قيماً صالحة'},

    // ── AI Provider ───────────────────────────────────────────────────────────
    'aiProvider':         {'en': 'AI Provider',          'ar': 'مزود الذكاء الاصطناعي'},
    'chatgptModel':       {'en': 'ChatGPT Model',        'ar': 'نموذج ChatGPT'},
    'chatgptApiKey':      {'en': 'ChatGPT API Key (OpenAI)', 'ar': 'مفتاح ChatGPT API (OpenAI)'},
    'addAiKey':           {'en': 'Add an AI API Key in Settings to enable the assistant',
                           'ar': 'أضف مفتاح API للذكاء الاصطناعي في الإعدادات لتفعيل المساعد'},

    // ── Chat History ──────────────────────────────────────────────────────────
    'chatHistory':          {'en': 'Chat History',                     'ar': 'سجل المحادثات'},
    'noSavedChats':         {'en': 'No saved conversations yet',       'ar': 'لا توجد محادثات محفوظة بعد'},
    'conversationSaved':    {'en': 'Saved to ERPNext',                 'ar': 'تم الحفظ في ERPNext'},
    'saveFailed':           {'en': 'Save failed',                      'ar': 'فشل الحفظ'},
    'deleteConversation':   {'en': 'Delete conversation',              'ar': 'حذف المحادثة'},
    'deleteConvConfirm':    {'en': 'Delete this conversation?',        'ar': 'حذف هذه المحادثة؟'},
    'conversationDeleted':  {'en': 'Conversation deleted',             'ar': 'تم حذف المحادثة'},
    'loadSessionConfirm':   {'en': 'Load this conversation? Current chat will be cleared.', 'ar': 'تحميل هذه المحادثة؟ سيتم مسح المحادثة الحالية.'},
    'loadConversation':     {'en': 'Load',                             'ar': 'تحميل'},
    'newChatSession':       {'en': 'New Chat',                         'ar': 'محادثة جديدة'},
    'newChatConfirm':       {'en': 'The current conversation will be saved. Start a new chat?', 'ar': 'ستُحفظ المحادثة الحالية. هل تريد بدء محادثة جديدة؟'},
    'messages':             {'en': 'messages',                         'ar': 'رسالة'},

    // ── Attachment multi-select ───────────────────────────────────────────────
    'multipleSelection': {'en': 'Multiple selection',   'ar': 'اختيار متعدد'},
    'savedToSystem':     {'en': 'Saved to ERPNext',     'ar': 'محفوظ في النظام'},

    // ── Connection errors ─────────────────────────────────────────────────────
    'connectionError':    {'en': 'Connection error',     'ar': 'خطأ في الاتصال'},

    // ── Module Specialization ─────────────────────────────────────────────────
    'noModulesAvailable':    {'en': 'No modules available',                         'ar': 'لا توجد موديولز متاحة'},
    'chooseModuleAction':    {'en': 'What would you like to do?',                   'ar': 'ماذا تريد أن تفعل؟'},
    'askAboutModule':        {'en': 'Ask about this module',                        'ar': 'اسأل عن هذا الموديول'},
    'askAboutModuleSub':     {'en': 'Get live KPIs and data from ERPNext',         'ar': 'احصل على مؤشرات وبيانات مباشرة من النظام'},
    'activateModuleAgent':   {'en': 'Activate Module Agent',                        'ar': 'تفعيل وكيل الموديول'},
    'activateModuleAgentSub':{'en': 'Switch AI to specialize in this module',      'ar': 'تخصيص الذكاء الاصطناعي لهذا الموديول'},
    'moduleAlreadyActive':   {'en': 'Already active',                               'ar': 'نشط بالفعل'},
    'resetToHR':             {'en': 'Reset to HR Agent',                            'ar': 'العودة لـ HR Agent'},
    'moduleActivated':       {'en': 'Agent activated',                              'ar': 'تم تفعيل الوكيل'},
    'activeModuleAgent':     {'en': 'Active Module',                                'ar': 'الموديول النشط'},
    'moduleAskDashboard':    {'en': 'Show Dashboard',                               'ar': 'اعرض الداشبورد'},
    'moduleAskReports':      {'en': 'Show Reports',                                 'ar': 'اعرض التقارير'},
    'moduleAskSummary':      {'en': 'Show Summary',                                 'ar': 'اعرض الملخص'},

    // ── Export Table / Email Dialog ───────────────────────────────────────────
    // ── Workflow / Document Viewer ────────────────────────────────────────────
    'wfDocumentDetails':  {'en': 'DOCUMENT DETAILS',               'ar': 'تفاصيل المستند'},
    'wfWorkflowState':    {'en': 'WORKFLOW STATE',                 'ar': 'حالة سير العمل'},
    'wfNoEditInViewer':   {'en': 'This viewer is read-only. Edit from ERPNext Desk.', 'ar': 'هذا العرض للقراءة فقط. قم بالتعديل من ERPNext.'},
    'wfSubmitDoc':        {'en': 'Submit',                         'ar': 'تقديم'},
    'wfCancelDoc':        {'en': 'Cancel Document',                'ar': 'إلغاء المستند'},
    'wfDraft':            {'en': 'Draft',                          'ar': 'مسودة'},
    'wfSubmitted':        {'en': 'Submitted',                      'ar': 'مُقدَّم'},
    'wfCancelled':        {'en': 'Cancelled',                      'ar': 'ملغي'},
    'wfExecutingAction':  {'en': 'Executing action…',              'ar': 'جاري التنفيذ…'},
    'wfNoActionsAvailable': {'en': 'No actions available for your role', 'ar': 'لا توجد إجراءات متاحة لدورك'},
    'wfChooseAction':     {'en': 'Choose an action',               'ar': 'اختر إجراءً'},
    'wfOpenDocument':     {'en': 'Open Document',                  'ar': 'فتح المستند'},
    'wfPendingApprovals': {'en': 'Pending Approvals',              'ar': 'الموافقات المعلقة'},
    'wfNoPendingApprovals': {'en': 'No pending approvals',         'ar': 'لا توجد موافقات معلقة'},
    'wfApprovedApprovals':  {'en': 'Approved',                    'ar': 'المعتمدة'},
    'wfNoApproved':         {'en': 'No approved documents',        'ar': 'لا توجد مستندات معتمدة'},
    'wfApprovedOn':         {'en': 'Approved',                    'ar': 'اعتُمد'},
    'wfCancelConfirmTitle': {'en': 'Cancel Document',             'ar': 'إلغاء المستند'},
    'wfLast7':              {'en': 'Last 7 days',                 'ar': 'آخر 7 أيام'},
    'wfLast30':             {'en': 'Last 30 days',                'ar': 'آخر 30 يوم'},
    'wfLast90':             {'en': 'Last 90 days',                'ar': 'آخر 90 يوم'},
    'wfPendingForYou':    {'en': 'Awaiting your action',           'ar': 'في انتظار إجراءك'},
    'wfRefreshApprovals': {'en': 'Refresh',                        'ar': 'تحديث'},
    'wfAllTypes':         {'en': 'All Types',                      'ar': 'كل الأنواع'},
    'wfCurrentState':     {'en': 'Current state',                  'ar': 'الحالة الحالية'},
    'wfRequiredAction':   {'en': 'Required action',                'ar': 'الإجراء المطلوب'},
    'wfRealtimeConnected': {'en': 'Real-time sync active',         'ar': 'المزامنة الفورية نشطة'},
    'wfRealtimePolling':  {'en': 'Sync every 15 s',               'ar': 'مزامنة كل 15 ث'},
    'wfSourceDynamic':    {'en': 'SCAN',                           'ar': 'مسح'},
    'wfDynamicScanNotice':{'en': 'Some items were found by scanning workflow-enabled documents directly.',
                           'ar': 'بعض العناصر تم اكتشافها عبر مسح المستندات ذات الـ workflow مباشرةً.'},
    'wfFacDenied':        {'en': 'You do not have permission to perform this action.',
                           'ar': 'ليس لديك صلاحية لتنفيذ هذا الإجراء.'},
    'wfStateChanged':     {'en': 'Document state may have changed. Please refresh.',
                           'ar': 'قد تكون حالة المستند تغيرت. يرجى التحديث.'},
    'wfValidating':       {'en': 'Validating permissions…',        'ar': 'جاري التحقق من الصلاحيات…'},
    'wfNoTransitions':    {'en': 'No workflow actions available for your role on this document.',
                           'ar': 'لا توجد إجراءات workflow متاحة لدورك على هذا المستند.'},
    'wfSearchHint':       {'en': 'Search…',                        'ar': 'بحث…'},
    'wfFallbackMode':     {'en': 'Fallback mode — FAC unavailable', 'ar': 'وضع بديل — FAC غير متاح'},
    'wfFallbackDetails':  {'en': 'Details',                         'ar': 'تفاصيل'},

    'savePdf':           {'en': 'Save PDF',                       'ar': 'حفظ PDF'},
    'saveExcel':         {'en': 'Save Excel',                     'ar': 'حفظ Excel'},
    'sendByEmail':       {'en': 'Send Email',                     'ar': 'إرسال بالبريد'},
    'sendEmailWithPdf':  {'en': 'Send Email with PDF Attachment', 'ar': 'إرسال بالبريد مع مرفق PDF'},
    'emailAddress':      {'en': 'Email Address',                  'ar': 'البريد الإلكتروني'},
    'emailSubject':      {'en': 'Subject',                        'ar': 'الموضوع'},
    'dataReport':        {'en': 'Data Report',                    'ar': 'تقرير البيانات'},
    'send':              {'en': 'Send',                           'ar': 'إرسال'},
    'chooseLogo':        {'en': 'Choose Logo',                    'ar': 'اختر شعاراً'},

    // ── n8n Webhook Chat ──────────────────────────────────────────────────────
    'n8nChatTitle':      {'en': 'n8n Chat Bot',                   'ar': 'روبوت المحادثة n8n'},
    'n8nChatSubtitle':   {'en': 'Online · Powered by n8n',        'ar': 'متصل · مدعوم بـ n8n'},
    'n8nThinking':       {'en': 'n8n is thinking…',               'ar': 'n8n يفكر…'},
    'n8nChatError':      {'en': 'Something went wrong. Try again.','ar': 'حدث خطأ. حاول مجدداً.'},
    'n8nChatErrorBadge': {'en': 'Error',                          'ar': 'خطأ'},
    'n8nChatPlaceholder':{'en': 'Type a message…',                'ar': 'اكتب رسالة…'},
    'n8nChatEmpty':      {'en': 'Start a conversation\nAsk me anything about automation',
                          'ar': 'ابدأ محادثة\nاسألني أي شيء عن الأتمتة'},
    'n8nNewChat':        {'en': 'New Chat',                       'ar': 'محادثة جديدة'},
    'n8nNewChatConfirm': {'en': 'Start a new session? Current chat will be cleared.',
                          'ar': 'بدء جلسة جديدة؟ سيتم مسح المحادثة الحالية.'},
    'n8nSuggestion1':    {'en': 'What workflows are active?',     'ar': 'ما سير الأعمال النشطة؟'},
    'n8nSuggestion2':    {'en': 'Show latest executions',         'ar': 'أظهر آخر التنفيذات'},
    'n8nSuggestion3':    {'en': 'How can you help me?',           'ar': 'كيف يمكنك مساعدتي؟'},
  };

  String _t(String key) =>
      _s[key]?[locale.languageCode] ?? _s[key]?['en'] ?? key;

  // ── Accessors ──────────────────────────────────────────────────────────────
  String get appTitle            => _t('appTitle');
  String get settings            => _t('settings');
  String get retry               => _t('retry');
  String get cancel              => _t('cancel');
  String get refresh             => _t('refresh');
  String get logout              => _t('logout');
  String get save                => _t('save');
  String get clear               => _t('clear');
  String get apply               => _t('apply');
  String get search              => _t('search');
  String get noResults           => _t('noResults');
  String get copied              => _t('copied');
  String get defaultLabel        => _t('default_');

  String get welcome             => _t('welcome');
  String get tapToContinue       => _t('tapToContinue');
  String get login               => _t('login');

  String get signIn              => _t('signIn');
  String get noCredentials       => _t('noCredentials');
  String get configureSettings   => _t('configureSettings');
  String get loginSuccessful     => _t('loginSuccessful');

  String get modules             => _t('modules');
  String get aiAssistant         => _t('aiAssistant');
  String get dashboards          => _t('dashboards');
  String get noModules           => _t('noModules');
  String get moduleBlocked       => _t('moduleBlocked');
  String get fullAccess          => _t('fullAccess');
  String requiredRoles(String roles) =>
      isArabic ? 'تحتاج إلى أحد الأدوار التالية:\n$roles'
               : 'You need one of the following roles:\n$roles';

  String get company             => _t('company');
  String get selectedCompany     => _t('selectedCompany');
  String get notConfigured       => _t('notConfigured');
  String get companyInSettings   => _t('companyInSettings');
  String get continueToModules   => _t('continueToModules');
  String get changeCompany       => _t('changeCompany');
  String get noCompany           => _t('noCompany');

  String get clearAllSettings    => _t('clearAllSettings');
  String get erpnextConnection   => _t('erpnextConnection');
  String get erpnextUrl          => _t('erpnextUrl');
  String get urlHint             => _t('urlHint');
  String get username            => _t('username');
  String get usernameHint        => _t('usernameHint');
  String get password            => _t('password');
  String get apiTokenSection     => _t('apiTokenSection');
  String get apiTokenInfo        => _t('apiTokenInfo');
  String get apiKey              => _t('apiKey');
  String get apiSecret           => _t('apiSecret');
  String get companyName         => _t('companyName');
  String get companyHint         => _t('companyHint');
  String get aiSection           => _t('aiSection');
  String get aiInfo              => _t('aiInfo');
  String get claudeApiKey        => _t('claudeApiKey');
  String get mcpEndpoint         => _t('mcpEndpoint');
  String get resetToDefault      => _t('resetToDefault');
  String get saving              => _t('saving');
  String get saved               => _t('saved');
  String get saveSettings        => _t('saveSettings');
  String get backToLogin         => _t('backToLogin');
  String get urlRequired         => _t('urlRequired');
  String get validUrl            => _t('validUrl');
  String get usernameRequired    => _t('usernameRequired');
  String get passwordRequired    => _t('passwordRequired');
  String get companyRequired     => _t('companyRequired');
  String get clearSettingsTitle  => _t('clearSettingsTitle');
  String get clearSettingsConfirm=> _t('clearSettingsConfirm');
  String get settingsCleared     => _t('settingsCleared');

  // Settings — logo
  String get appLogoSection      => _t('appLogoSection');
  String get removeLogo          => _t('removeLogo');
  String get logoUpdated         => _t('logoUpdated');
  String get noImageContent      => _t('noImageContent');

  // Settings — export/import
  String get exportTooltip       => _t('exportTooltip');
  String get importTooltip       => _t('importTooltip');
  String get backupSubject       => _t('backupSubject');
  String get noFileContent       => _t('noFileContent');
  String get notSettingsFile     => _t('notSettingsFile');
  String get notKcscSettings     => _t('notKcscSettings');
  String exportFailed(String e)  => isArabic ? 'فشل التصدير: $e' : 'Export failed: $e';
  String importSuccess(int n)    => isArabic ? 'تم استيراد $n إعداد بنجاح ✓' : 'Imported $n settings successfully ✓';
  String importFailed(String e)  => isArabic ? 'فشل الاستيراد: $e' : 'Import failed: $e';

  // Settings — AI provider
  String get providerClaudeOnly    => _t('providerClaudeOnly');
  String get providerChatGptOnly   => _t('providerChatGptOnly');
  String get providerClaudeFirst   => _t('providerClaudeFirst');
  String get providerChatGptFirst  => _t('providerChatGptFirst');
  String get providerDescClaude    => _t('providerDescClaude');
  String get providerDescChatGpt   => _t('providerDescChatGpt');
  String get providerDescClaudeFirst  => _t('providerDescClaudeFirst');
  String get providerDescChatGptFirst => _t('providerDescChatGptFirst');
  String get chatGptInfo           => _t('chatGptInfo');
  String get apiTokenOptional      => _t('apiTokenOptional');
  String providerDesc(String provider) {
    switch (provider) {
      case 'claude':       return providerDescClaude;
      case 'chatgpt':      return providerDescChatGpt;
      case 'claude_first': return providerDescClaudeFirst;
      default:             return providerDescChatGptFirst;
    }
  }

  String get language            => _t('language');
  String get english             => _t('english');
  String get arabic              => _t('arabic');
  String get themeMode           => _t('themeMode');
  String get lightMode           => _t('lightMode');
  String get darkMode            => _t('darkMode');
  String get systemMode          => _t('systemMode');

  String get accountingDashboard => _t('accountingDashboard');
  String get failedLoadDashboard => _t('failedLoadDashboard');
  String get quickStats          => _t('quickStats');
  String get companies           => _t('companies');
  String get active              => _t('active');
  String get accountingModules   => _t('accountingModules');
  String get chartOfAccounts     => _t('chartOfAccounts');
  String get journalEntries      => _t('journalEntries');
  String get generalLedger       => _t('generalLedger');
  String get trialBalance        => _t('trialBalance');
  String get financialReports    => _t('financialReports');
  String get bankReconciliation  => _t('bankReconciliation');

  String get noDashboards        => _t('noDashboards');
  String get dashSearchHint      => _t('dashSearchHint');
  String get dashCompany         => _t('dashCompany');
  String get dashViewAll         => _t('dashViewAll');
  String get dashNoPermission    => _t('dashNoPermission');
  String get updatedAt           => _t('updatedAt');
  String get autoEvery5Min       => _t('autoEvery5Min');
  String get dateRangeShort      => _t('dateRangeShort');
  String updatedAtLine(String time) =>
      '${_t('updatedAt')} $time  ·  ${_t('autoEvery5Min')}';
  String timespanLabel(String t) {
    const m = {
      'Last Week': 'lastWeek', 'Last Month': 'lastMonth',
      'Last Quarter': 'lastQuarter', 'Last Year': 'lastYear',
    };
    return m.containsKey(t) ? _t(m[t]!) : t;
  }
  String timegrainLabel(String t) {
    const m = {
      'Daily': 'daily', 'Weekly': 'weekly', 'Monthly': 'monthly',
      'Quarterly': 'quarterly', 'Yearly': 'yearly',
    };
    return m.containsKey(t) ? _t(m[t]!) : t;
  }
  String failedLoadDashboards(int code) =>
      isArabic ? 'فشل تحميل لوحات البيانات ($code)'
               : 'Failed to load dashboards ($code)';
  String dashboardCount(int count, int modules) =>
      isArabic ? '$count لوحة · $modules وحدة'
               : '$count dashboard${count == 1 ? '' : 's'} · $modules module${modules == 1 ? '' : 's'}';

  String get changeFilters       => _t('changeFilters');
  String get noCharts            => _t('noCharts');
  String get noData              => _t('noData');
  String get period              => _t('period');
  String get value               => _t('value');
  String get showLess            => _t('showLess');
  String showAllRows(int n)      =>
      isArabic ? 'عرض كل $n صفوف ▼' : 'Show all $n rows ▼';
  String get filterMode          => _t('filterMode');
  String get timespan            => _t('timespan');
  String get dateRange           => _t('dateRange');
  String get from                => _t('from');
  String get to                  => _t('to');
  String get timegrain           => _t('timegrain');
  String get relative            => _t('relative');
  String get selectDate          => _t('selectDate');
  String get lastWeek            => _t('lastWeek');
  String get lastMonth           => _t('lastMonth');
  String get lastQuarter         => _t('lastQuarter');
  String get lastYear            => _t('lastYear');
  String get daily               => _t('daily');
  String get weekly              => _t('weekly');
  String get monthly             => _t('monthly');
  String get quarterly           => _t('quarterly');
  String get yearly              => _t('yearly');

  String get clearChat           => _t('clearChat');
  String get addClaudeKey        => _t('addClaudeKey');
  String get errorOccurred       => _t('errorOccurred');
  String get copyError           => _t('copyError');
  String get errorCopied         => _t('errorCopied');
  String get thinking            => _t('thinking');
  String get transcribing        => _t('transcribing');
  String get whisperKeyMissing   => _t('whisperKeyMissing');
  String get attachFile          => _t('attachFile');
  String get cancelRecording     => _t('cancelRecording');
  String get stopping            => _t('stopping');
  String get stoppedByUser       => _t('stoppedByUser');
  String get stopGeneration      => _t('stopGeneration');
  String get camera              => _t('camera');
  String get gallery             => _t('gallery');
  String get document            => _t('document');
  String get addCaption          => _t('addCaption');
  String get myFilesInSystem     => _t('myFilesInSystem');
  String get browseAndSearch     => _t('browseAndSearch');
  String get fromConversation    => _t('fromConversation');
  String get useExistingImages   => _t('useExistingImages');
  String get searchFiles         => _t('searchFiles');
  String get noFilesFound        => _t('noFilesFound');
  String get noImagesInChat      => _t('noImagesInChat');
  String get fileVisibility      => _t('fileVisibility');
  String get filePublic          => _t('filePublic');
  String get filePrivate         => _t('filePrivate');
  String get filePublicHint      => _t('filePublicHint');
  String get filePrivateHint     => _t('filePrivateHint');
  String get addSelected         => _t('addSelected');
  String get loadingFiles        => _t('loadingFiles');
  String get uploadingFiles      => _t('uploadingFiles');
  String get connectingServer    => _t('connectingServer');
  String get loadingTools        => _t('loadingTools');
  String get processingResults   => _t('processingResults');
  String get savingChart         => _t('savingChart');
  String get noReplyReceived     => _t('noReplyReceived');
  String tryingProvider(String p)     => _t('tryingProvider').replaceAll('{p}', p);
  String fallbackToProvider(String p) => _t('fallbackToProvider').replaceAll('{p}', p);
  String get saveChart           => _t('saveChart');
  String get chartName           => _t('chartName');
  String get chartType           => _t('chartType');
  String get chartCategories     => _t('chartCategories');
  String get chartWillCreate     => _t('chartWillCreate');
  String get chartFromAssistant  => _t('chartFromAssistant');
  String chartSaved(String title) =>
      isArabic ? '✅ تم حفظ "$title" في لوحة المعلومات'
               : '✅ "$title" saved to dashboard';
  String chartSaveFailed(String err) =>
      isArabic ? '❌ فشل الحفظ: $err' : '❌ Save failed: $err';
  String categoriesCount(int n) =>
      isArabic ? '$n فئة' : '$n categories';
  String toolsLoaded(int count)  =>
      isArabic ? 'تم تحميل $count أداة ✓ — جاري التفكير…'
               : 'Loaded $count tools ✓ — Thinking…';
  String executingTool(String name) =>
      isArabic ? 'جاري تنفيذ: $name…' : 'Running: $name…';
  String get listening           => _t('listening');
  String get listeningWillSend   => _t('listeningWillSend');
  String get tapMicToSend        => _t('tapMicToSend');
  String get tapToStopListening  => _t('tapToStopListening');
  String get selectVoiceLanguage => _t('selectVoiceLanguage');
  String get typeQuestion        => _t('typeQuestion');
  String poweredBy(String model) =>
      isArabic ? 'مدعوم بـ $model\nعبر Frappe Assistant Core MCP'
               : 'Powered by $model\nvia Frappe Assistant Core MCP';
  String get q1                  => _t('q1');
  String get q2                  => _t('q2');
  String get q3                  => _t('q3');
  String get q4                  => _t('q4');

  // Welcome card
  String get greetingMorning         => _t('greetingMorning');
  String get greetingAfternoon       => _t('greetingAfternoon');
  String get greetingEvening         => _t('greetingEvening');
  String get agentName               => _t('agentName');
  String get assistantIntro          => _t('assistantIntro');
  String get assistantModulesTitle   => _t('assistantModulesTitle');
  String get assistantModules        => _t('assistantModules');
  String get assistantHelpQuestion   => _t('assistantHelpQuestion');
  String greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return greetingMorning;
    if (h < 17) return greetingAfternoon;
    return greetingEvening;
  }

  // Voice / microphone
  String get micPermissionDenied     => _t('micPermissionDenied');
  String micError(String e)          => isArabic ? '❌ خطأ في الميكروفون: $e' : '❌ Microphone: $e';
  String whisperError(String e)      => isArabic ? '❌ خطأ في التحويل الصوتي: $e' : '❌ Whisper: $e';
  String voiceGenericError(String e) => '❌ $e';

  // Email
  String emailSendFailed(String e)   => isArabic ? '❌ فشل إرسال البريد: $e' : '❌ Failed to send email: $e';

  String get hrAgentTitle        => _t('hrAgentTitle');
  String get hrAgentSubtitle     => _t('hrAgentSubtitle');
  String get quickActions        => _t('quickActions');
  String get hrAddEmployee       => _t('hrAddEmployee');
  String get hrPayroll           => _t('hrPayroll');
  String get hrLeaveRequests     => _t('hrLeaveRequests');
  String get hrAppraisal         => _t('hrAppraisal');
  String get hrSearchEmployee    => _t('hrSearchEmployee');
  String get hrReports           => _t('hrReports');
  String get erpModules          => _t('erpModules');
  String get browseModules       => _t('browseModules');

  String get noReports           => _t('noReports');
  String failedLoadReports(int code) =>
      isArabic ? 'فشل تحميل التقارير ($code)' : 'Failed to load reports ($code)';
  String reportCount(int count) =>
      isArabic ? '$count تقرير متاح' : '$count accessible report${count == 1 ? '' : 's'}';
  String reportParams(int count) =>
      isArabic ? 'معاملات التقرير ($count حقل)' : 'Report Parameters ($count fields)';
  String rowColCount(int rows, int cols) =>
      isArabic ? '$rows صفوف · $cols أعمدة' : '$rows rows · $cols columns';
  String get loadingParams       => _t('loadingParams');
  String get runningReport       => _t('runningReport');
  String get backToFilters       => _t('backToFilters');
  String get runReport           => _t('runReport');
  String get selectPlaceholder   => _t('selectPlaceholder');
  String get noDataFilters       => _t('noDataFilters');
  String get isRequired          => _t('isRequired');
  String selectField(String label) =>
      isArabic ? 'اختر $label' : 'Select $label';
  String connectionError(String e) =>
      isArabic ? 'خطأ في الاتصال: $e' : 'Connection error: $e';

  String get missingFiltersAdded    => _t('missingFiltersAdded');
  String get fiscalYearFiltersAdded => _t('fiscalYearFiltersAdded');
  String get dateFiltersAdded       => _t('dateFiltersAdded');
  String get reportDataError        => _t('reportDataError');
  String get aiAutoFillTooltip      => _t('aiAutoFillTooltip');
  String get unknownError           => _t('unknownError');
  String get refreshFilters         => _t('refreshFilters');
  String get addItem                => _t('addItem');
  String get noneSelected           => _t('noneSelected');
  String get filtersCached          => _t('filtersCached');
  String get filtersRefreshed       => _t('filtersRefreshed');
  String missingFilterFound(String field) =>
      isArabic ? 'فلتر مطلوب مكتشف: $field — يرجى المراجعة والمحاولة مجدداً'
               : 'Required filter found: $field — please review and retry';
  String aiFilledCount(int defs, int vals) =>
      isArabic
          ? 'تم اكتشاف $defs فلتر وملء $vals قيمة بواسطة الذكاء الاصطناعي ✓'
          : '$defs filter${defs == 1 ? '' : 's'} found, $vals value${vals == 1 ? '' : 's'} filled by AI ✓';
  String aiError(String e) =>
      isArabic ? 'خطأ AI: $e' : 'AI error: $e';
  String get aiAnalyzingReport => _t('aiAnalyzingReport');
  String get aiConnecting   => _t('aiConnecting');
  String get aiNoTools      => _t('aiNoTools');
  String get aiProcessing   => _t('aiProcessing');
  String get aiNoResult     => _t('aiNoResult');
  String get aiProvider     => _t('aiProvider');
  String get chatgptModel   => _t('chatgptModel');
  String get chatgptApiKey  => _t('chatgptApiKey');
  String get addAiKey       => _t('addAiKey');
  String aiAnalyzing(int count) =>
      isArabic ? '$count أداة ✓ — جاري دراسة فلاتر التقرير…'
               : '$count tool${count == 1 ? '' : 's'} ✓ — analyzing report filters…';
  String aiExecuting(String toolName) =>
      isArabic ? 'جاري تنفيذ: $toolName…' : 'Executing: $toolName…';

  // Chat History
  String get chatHistory          => _t('chatHistory');
  String get noSavedChats         => _t('noSavedChats');
  String get conversationSaved    => _t('conversationSaved');
  String get saveFailed           => _t('saveFailed');
  String get deleteConversation   => _t('deleteConversation');
  String get deleteConvConfirm    => _t('deleteConvConfirm');
  String get conversationDeleted  => _t('conversationDeleted');
  String get loadSessionConfirm   => _t('loadSessionConfirm');
  String get loadConversation     => _t('loadConversation');
  String get newChatSession       => _t('newChatSession');
  String get newChatConfirm       => _t('newChatConfirm');
  String get messages             => _t('messages');
  String get multipleSelection    => _t('multipleSelection');
  String get savedToSystem        => _t('savedToSystem');

  String get noModulesAvailable   => _t('noModulesAvailable');
  String get chooseModuleAction   => _t('chooseModuleAction');
  String get askAboutModule       => _t('askAboutModule');
  String get askAboutModuleSub    => _t('askAboutModuleSub');
  String get activateModuleAgent  => _t('activateModuleAgent');
  String get activateModuleAgentSub => _t('activateModuleAgentSub');
  String get moduleAlreadyActive  => _t('moduleAlreadyActive');
  String get resetToHR            => _t('resetToHR');
  String get moduleActivated      => _t('moduleActivated');
  String get activeModuleAgent    => _t('activeModuleAgent');
  String get moduleAskDashboard   => _t('moduleAskDashboard');
  String get moduleAskReports     => _t('moduleAskReports');
  String get moduleAskSummary     => _t('moduleAskSummary');

  String get savePdf           => _t('savePdf');
  String get saveExcel         => _t('saveExcel');
  String get sendByEmail       => _t('sendByEmail');
  String get sendEmailWithPdf  => _t('sendEmailWithPdf');
  String get emailAddress      => _t('emailAddress');
  String get emailSubject      => _t('emailSubject');
  String get dataReport        => _t('dataReport');
  String get send              => _t('send');
  String get chooseLogo        => _t('chooseLogo');

  // ── n8n Webhook Chat ─────────────────────────────────────────────────────
  String get n8nChatTitle       => _t('n8nChatTitle');
  String get n8nChatSubtitle    => _t('n8nChatSubtitle');
  String get n8nThinking        => _t('n8nThinking');
  String get n8nChatError       => _t('n8nChatError');
  String get n8nChatErrorBadge  => _t('n8nChatErrorBadge');
  String get n8nChatPlaceholder => _t('n8nChatPlaceholder');
  String get n8nChatEmpty       => _t('n8nChatEmpty');
  String get n8nNewChat         => _t('n8nNewChat');
  String get n8nNewChatConfirm  => _t('n8nNewChatConfirm');
  String get n8nSuggestion1     => _t('n8nSuggestion1');
  String get n8nSuggestion2     => _t('n8nSuggestion2');
  String get n8nSuggestion3     => _t('n8nSuggestion3');

  // ── Workflow / Document Viewer ─────────────────────────────────────────────
  String get wfDocumentDetails    => _t('wfDocumentDetails');
  String get wfWorkflowState      => _t('wfWorkflowState');
  String get wfNoEditInViewer     => _t('wfNoEditInViewer');
  String get wfSubmitDoc          => _t('wfSubmitDoc');
  String get wfCancelDoc          => _t('wfCancelDoc');
  String get wfDraft              => _t('wfDraft');
  String get wfSubmitted          => _t('wfSubmitted');
  String get wfCancelled          => _t('wfCancelled');
  String get wfExecutingAction    => _t('wfExecutingAction');
  String get wfNoActionsAvailable => _t('wfNoActionsAvailable');
  String get wfChooseAction       => _t('wfChooseAction');
  String get wfOpenDocument       => _t('wfOpenDocument');
  String get wfPendingApprovals   => _t('wfPendingApprovals');
  String get wfNoPendingApprovals => _t('wfNoPendingApprovals');
  String get wfApprovedApprovals  => _t('wfApprovedApprovals');
  String get wfNoApproved         => _t('wfNoApproved');
  String get wfApprovedOn         => _t('wfApprovedOn');
  String get wfCancelConfirmTitle => _t('wfCancelConfirmTitle');
  String get wfLast7              => _t('wfLast7');
  String get wfLast30             => _t('wfLast30');
  String get wfLast90             => _t('wfLast90');
  String get wfPendingForYou      => _t('wfPendingForYou');
  String get wfRefreshApprovals   => _t('wfRefreshApprovals');
  String get wfAllTypes           => _t('wfAllTypes');
  String get wfCurrentState       => _t('wfCurrentState');
  String get wfRequiredAction     => _t('wfRequiredAction');
  String get wfRealtimeConnected  => _t('wfRealtimeConnected');
  String get wfRealtimePolling    => _t('wfRealtimePolling');
  String get wfSourceDynamic      => _t('wfSourceDynamic');
  String get wfDynamicScanNotice  => _t('wfDynamicScanNotice');
  String get wfFacDenied          => _t('wfFacDenied');
  String get wfStateChanged       => _t('wfStateChanged');
  String get wfValidating         => _t('wfValidating');
  String get wfNoTransitions      => _t('wfNoTransitions');
  String get wfSearchHint         => _t('wfSearchHint');
  String get wfFallbackMode       => _t('wfFallbackMode');
  String get wfFallbackDetails    => _t('wfFallbackDetails');

  String wfChatConfirmation(String action, String docname, String newState) =>
      isArabic
          ? '✅ تم تنفيذ **$action** على `$docname`\nالحالة الجديدة: **$newState**'
          : '✅ **$action** executed on `$docname`\nNew state: **$newState**';

  String wfConfirmAction(String action, String docname) => isArabic
      ? 'هل تريد تنفيذ "$action" على المستند $docname؟'
      : 'Execute "$action" on document $docname?';
  String wfActionSuccess(String action, String state) => isArabic
      ? '✅ تم تنفيذ "$action" — الحالة الجديدة: $state'
      : '✅ "$action" executed — new state: $state';
  String wfActionFailed(String err) => isArabic
      ? '❌ فشل التنفيذ: $err'
      : '❌ Action failed: $err';
  String wfSubmitConfirm(String docname) => isArabic
      ? 'هل تريد تقديم $docname؟ لن يمكن التراجع عن هذا.'
      : 'Submit $docname? This cannot be undone.';
  String wfCancelConfirm(String docname) => isArabic
      ? 'هل تريد إلغاء $docname؟'
      : 'Cancel $docname?';

  String wfLastNDays(int n) =>
      isArabic ? 'آخر $n يوم' : 'Last $n days';

  String wfExecutingMsg(String action) =>
      isArabic ? '$action…' : '$action…';

  String wfActionDoneMsg(String action, String docname, String state) =>
      isArabic
          ? '$action ✓ — $docname → $state'
          : '$action ✓ — $docname → $state';

  String wfActionCancelledMsg(String action, String docname) =>
      isArabic
          ? '$action ✓ — $docname (ملغي)'
          : '$action ✓ — $docname (cancelled)';

  /// Translates common ERPNext workflow action names to Arabic when UI is Arabic.
  String wfLocalizeAction(String action) {
    if (!isArabic) return action;
    const map = {
      'approve':    'موافقة',
      'approved':   'موافقة',
      'reject':     'رفض',
      'rejected':   'رفض',
      'submit':     'تقديم',
      'cancel':     'إلغاء',
      'cancelled':  'ملغي',
      'review':     'مراجعة',
      'confirm':    'تأكيد',
      'confirmed':  'مؤكد',
      'decline':    'رفض',
      'accept':     'قبول',
      'accepted':   'مقبول',
      'authorize':  'تفويض',
      'complete':   'إكمال',
      'completed':  'مكتمل',
      'close':      'إغلاق',
      'closed':     'مغلق',
      'reopen':     'إعادة فتح',
      'hold':       'تعليق',
      'release':    'إصدار',
      'pending':    'معلق',
      'draft':      'مسودة',
      'open':       'مفتوح',
      'return':     'إرجاع',
      'revise':     'مراجعة',
      'forward':    'إحالة',
      'send':       'إرسال',
      'sent':       'مُرسَل',
    };
    return map[action.toLowerCase()] ?? action;
  }
}

// ---------------------------------------------------------------------------
// Delegate
// ---------------------------------------------------------------------------
class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'ar'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
