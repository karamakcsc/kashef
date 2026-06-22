// ─────────────────────────────────────────────────────────────────────────────
// OCR Workflow Pipeline — Data Models
// ─────────────────────────────────────────────────────────────────────────────

// ── Document types ────────────────────────────────────────────────────────────

enum OcrDocumentType {
  purchaseInvoice('purchase_invoice', 'Purchase Invoice', '🧾', 'Purchase Invoice'),
  salesInvoice   ('sales_invoice',    'Sales Invoice',    '📋', 'Sales Invoice'),
  paymentReceipt ('payment_receipt',  'Payment Receipt',  '💳', 'Payment Entry'),
  deliveryNote   ('delivery_note',    'Delivery Note',    '📦', 'Delivery Note'),
  quotation      ('quotation',        'Quotation',        '📝', 'Quotation'),
  expense        ('expense',          'Expense',          '💰', 'Expense Claim'),
  unknown        ('unknown',          'Unknown',          '❓', '');

  final String key;
  final String label;
  final String icon;
  final String erpNextDoctype; // exact ERPNext DocType name

  const OcrDocumentType(this.key, this.label, this.icon, this.erpNextDoctype);

  static OcrDocumentType fromKey(String k) =>
      values.firstWhere((e) => e.key == k, orElse: () => unknown);
}

// ── Intent ────────────────────────────────────────────────────────────────────

enum OcrIntent {
  createPurchaseInvoice ('create_purchase_invoice'),
  createSalesInvoice    ('create_sales_invoice'),
  createPaymentEntry    ('create_payment_entry'),
  createExpenseClaim    ('create_expense_claim'),
  updateExistingDocument('update_existing_document'),
  approveDocument       ('approve_document'),
  rejectDocument        ('reject_document'),
  unknownAction         ('unknown_action');

  final String key;
  const OcrIntent(this.key);

  static OcrIntent fromKey(String k) =>
      values.firstWhere((e) => e.key == k, orElse: () => unknownAction);

  String get label => switch (this) {
    OcrIntent.createPurchaseInvoice  => 'Create Purchase Invoice',
    OcrIntent.createSalesInvoice     => 'Create Sales Invoice',
    OcrIntent.createPaymentEntry     => 'Create Payment Entry',
    OcrIntent.createExpenseClaim     => 'Create Expense Claim',
    OcrIntent.updateExistingDocument => 'Update Document',
    OcrIntent.approveDocument        => 'Approve Document',
    OcrIntent.rejectDocument         => 'Reject Document',
    OcrIntent.unknownAction          => 'Unknown',
  };
}

// ── Input ─────────────────────────────────────────────────────────────────────

class OcrInput {
  final bool   success;
  final String engineUsed;
  final double confidence;
  final String rawText;
  final String cleanText;
  final String languageDetected;

  const OcrInput({
    required this.success,
    this.engineUsed       = 'visual_ai',
    required this.confidence,
    required this.rawText,
    required this.cleanText,
    this.languageDetected = 'unknown',
  });

  /// Build from Claude's visual analysis of a base64 image.
  factory OcrInput.fromVisualAnalysis(String text, {double confidence = 0.80}) =>
      OcrInput(
        success:  text.trim().isNotEmpty,
        engineUsed: 'claude_vision',
        confidence: confidence,
        rawText:    text,
        cleanText:  text.trim(),
      );

  /// Build from FAC extract-file-content-usage skill result.
  factory OcrInput.fromFacSkill(Map<String, dynamic> facResponse) {
    final text = facResponse['text']?.toString() ??
                 facResponse['content']?.toString() ?? '';
    return OcrInput(
      success:          text.trim().isNotEmpty,
      engineUsed:       facResponse['engine']?.toString()   ?? 'paddleocr',
      confidence:       (facResponse['confidence'] as num?)?.toDouble() ?? 0.75,
      rawText:          text,
      cleanText:        text.trim(),
      languageDetected: facResponse['language']?.toString() ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() => {
    'success':           success,
    'engine_used':       engineUsed,
    'confidence':        confidence,
    'raw_text':          rawText,
    'clean_text':        cleanText,
    'language_detected': languageDetected,
  };
}

// ── Entities ──────────────────────────────────────────────────────────────────

class OcrEntities {
  final String? supplierName;
  final String? customerName;
  final String? invoiceNumber;
  final String? date;
  final String? totalAmount;
  final String? currency;
  final String? taxAmount;
  final List<Map<String, dynamic>>? itemList;

  const OcrEntities({
    this.supplierName,
    this.customerName,
    this.invoiceNumber,
    this.date,
    this.totalAmount,
    this.currency,
    this.taxAmount,
    this.itemList,
  });

  factory OcrEntities.fromJson(Map<String, dynamic> j) => OcrEntities(
    supplierName:  _str(j['supplier']),
    customerName:  _str(j['customer']),
    invoiceNumber: _str(j['invoice_number']),
    date:          _str(j['date']),
    totalAmount:   _str(j['total']),
    currency:      _str(j['currency']),
    taxAmount:     _str(j['tax']),
    itemList:      (j['items'] as List?)?.cast<Map<String, dynamic>>(),
  );

  static String? _str(dynamic v) {
    if (v == null || v == 'null' || v.toString().isEmpty) return null;
    return v.toString();
  }

  /// Build ERPNext-ready field values from extracted entities.
  Map<String, dynamic> toErpNextData(OcrDocumentType type) {
    final data = <String, dynamic>{};
    if (supplierName  != null) data['supplier']                   = supplierName;
    if (customerName  != null) data['customer']                   = customerName;
    if (invoiceNumber != null) data['bill_no']                    = invoiceNumber;
    if (date          != null) data['bill_date']                  = date;
    if (currency      != null) data['currency']                   = currency;
    if (totalAmount   != null) data['total']                      = totalAmount;
    if (taxAmount     != null) data['total_taxes_and_charges']    = taxAmount;
    if (type != OcrDocumentType.unknown) {
      data['doctype'] = type.erpNextDoctype;
    }
    return data;
  }

  bool get hasMinimumData =>
      supplierName != null || customerName != null || invoiceNumber != null;

  Iterable<MapEntry<String, String>> get nonNullEntries sync* {
    if (supplierName  != null) yield MapEntry('Supplier',       supplierName!);
    if (customerName  != null) yield MapEntry('Customer',       customerName!);
    if (invoiceNumber != null) yield MapEntry('Invoice #',      invoiceNumber!);
    if (date          != null) yield MapEntry('Date',           date!);
    if (totalAmount   != null) yield MapEntry('Total',          totalAmount!);
    if (currency      != null) yield MapEntry('Currency',       currency!);
    if (taxAmount     != null) yield MapEntry('Tax',            taxAmount!);
  }
}

// ── FAC mapping ───────────────────────────────────────────────────────────────

class OcrFacMapping {
  final String skill;
  final String tool;
  final String action;
  final Map<String, dynamic> payload;

  const OcrFacMapping({
    required this.skill,
    required this.tool,
    required this.action,
    required this.payload,
  });

  factory OcrFacMapping.fromJson(Map<String, dynamic> j) => OcrFacMapping(
    skill:   j['skill']?.toString()  ?? '',
    tool:    j['tool']?.toString()   ?? 'create_document',
    action:  j['action']?.toString() ?? 'create',
    payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? {},
  );
}

// ── ERPNext action ────────────────────────────────────────────────────────────

class OcrErpNextAction {
  final String doctype;
  final String operation; // create | update | submit | cancel
  final Map<String, dynamic> data;

  const OcrErpNextAction({
    required this.doctype,
    required this.operation,
    required this.data,
  });

  factory OcrErpNextAction.fromJson(Map<String, dynamic> j) => OcrErpNextAction(
    doctype:   j['doctype']?.toString()   ?? '',
    operation: j['operation']?.toString() ?? 'create',
    data:      (j['data'] as Map?)?.cast<String, dynamic>() ?? {},
  );
}

// ── Workflow result ───────────────────────────────────────────────────────────

enum OcrStatus { success, failed, needsReview }

class OcrWorkflowResult {
  final OcrStatus         status;
  final OcrDocumentType   documentType;
  final OcrIntent         intent;
  final double            confidence;
  final OcrEntities       entities;
  final OcrFacMapping?    fac;
  final OcrErpNextAction? erpnext;
  final String            reasoning;
  final String?           failReason;
  final String?           rawJson; // preserved for debugging

  const OcrWorkflowResult({
    required this.status,
    required this.documentType,
    required this.intent,
    required this.confidence,
    required this.entities,
    this.fac,
    this.erpnext,
    required this.reasoning,
    this.failReason,
    this.rawJson,
  });

  // ── Convenience constructors ──────────────────────────────────────────────

  factory OcrWorkflowResult.failed(String reason) => OcrWorkflowResult(
    status:       OcrStatus.failed,
    documentType: OcrDocumentType.unknown,
    intent:       OcrIntent.unknownAction,
    confidence:   0,
    entities:     const OcrEntities(),
    reasoning:    reason,
    failReason:   reason,
  );

  factory OcrWorkflowResult.needsReview(String reason) => OcrWorkflowResult(
    status:       OcrStatus.needsReview,
    documentType: OcrDocumentType.unknown,
    intent:       OcrIntent.unknownAction,
    confidence:   0,
    entities:     const OcrEntities(),
    reasoning:    reason,
  );

  // ── JSON parsing ──────────────────────────────────────────────────────────

  factory OcrWorkflowResult.fromJson(
    Map<String, dynamic> j,
    String rawJson,
  ) {
    final statusStr = j['status']?.toString() ?? 'failed';
    final status = switch (statusStr) {
      'success'      => OcrStatus.success,
      'needs_review' => OcrStatus.needsReview,
      _              => OcrStatus.failed,
    };

    final entJson = j['entities'];
    final entities = entJson is Map<String, dynamic>
        ? OcrEntities.fromJson(entJson)
        : const OcrEntities();

    return OcrWorkflowResult(
      status:       status,
      documentType: OcrDocumentType.fromKey(j['document_type']?.toString() ?? ''),
      intent:       OcrIntent.fromKey(j['intent']?.toString() ?? ''),
      confidence:   (j['confidence'] as num?)?.toDouble() ?? 0,
      entities:     entities,
      fac:          j['fac'] is Map<String, dynamic>
          ? OcrFacMapping.fromJson(j['fac'] as Map<String, dynamic>)
          : null,
      erpnext:      j['erpnext'] is Map<String, dynamic>
          ? OcrErpNextAction.fromJson(j['erpnext'] as Map<String, dynamic>)
          : null,
      reasoning:    j['reasoning']?.toString() ?? '',
      failReason:   j['reason']?.toString(),
      rawJson:      rawJson,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool get isSuccess   => status == OcrStatus.success;
  bool get isFailed    => status == OcrStatus.failed;
  bool get isNeedsReview => status == OcrStatus.needsReview;

  /// True when the result has enough data to execute a FAC action.
  bool get canExecute  => isSuccess && erpnext != null && entities.hasMinimumData;

  /// A one-line summary for display.
  String get summary {
    return switch (status) {
      OcrStatus.success     => '${documentType.icon} ${documentType.label} — ${intent.label}',
      OcrStatus.needsReview => '⚠️ Needs human review — confidence too low',
      OcrStatus.failed      => '❌ ${failReason ?? "Processing failed"}',
    };
  }

  /// Build a pre-filled message to send to the AI to execute the result via FAC.
  String buildExecutionPrompt(String language) {
    final isAr = language == 'ar';
    if (!canExecute) return '';
    final payload = erpnext!.data;
    final doc     = erpnext!.doctype;
    return isAr
        ? 'نفّذ النتيجة التالية تلقائياً باستخدام FAC tool:\n'
          'DocType: $doc\n'
          'العملية: ${erpnext!.operation}\n'
          'البيانات: ${payload.toString()}\n'
          'استخدم create_document إذا كانت العملية create. تأكد من الصلاحيات.'
        : 'Execute the following OCR result automatically via FAC tool:\n'
          'DocType: $doc\n'
          'Operation: ${erpnext!.operation}\n'
          'Data: ${payload.toString()}\n'
          'Use create_document if operation is create. Validate permissions first.';
  }
}
