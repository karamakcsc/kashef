import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ocr_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OcrWorkflowEngine — Standalone AI processor for OCR-to-ERPNext automation
//
// Architecture:
//   OCR text (already extracted)
//     → Claude API (structured extraction with business-rules system prompt)
//     → OcrWorkflowResult (deterministic JSON)
//     → Caller executes FAC tools based on the result
//
// This engine does NOT perform OCR and does NOT call FAC tools.
// OCR: handled by FAC extract-file-content-usage skill or Claude vision.
// FAC execution: handled by the AI assistant tool loop or by the caller.
// ─────────────────────────────────────────────────────────────────────────────

class OcrWorkflowEngine {
  OcrWorkflowEngine._();
  static final OcrWorkflowEngine _instance = OcrWorkflowEngine._();
  factory OcrWorkflowEngine() => _instance;

  // ── System prompt (cached at Claude via prompt-caching) ───────────────────

  static const String _systemPrompt = r'''
You are a deterministic AI Workflow Engine.
You receive OCR-extracted text from business documents and return ONLY a valid JSON structure.

══ INPUT FORMAT ══
You receive a JSON object:
{
  "success": true,
  "engine_used": "paddleocr | easyocr | claude_vision",
  "confidence": 0.0 - 1.0,
  "raw_text": "...",
  "clean_text": "...",
  "language_detected": "ar/en/unknown"
}

══ TASK 1 — DOCUMENT CLASSIFICATION ══
Classify into exactly ONE type:
  purchase_invoice | sales_invoice | payment_receipt |
  delivery_note | quotation | expense | unknown

Classification signals:
  purchase_invoice : "فاتورة شراء", "purchase invoice", "bill from supplier", vendor name + amount
  sales_invoice    : "فاتورة مبيعات", "invoice to customer", "tax invoice", customer + items sold
  payment_receipt  : "إيصال دفع", "receipt", "payment voucher", "paid", amount + date
  delivery_note    : "مذكرة تسليم", "delivery", "dispatch note", items + destination
  quotation        : "عرض سعر", "quotation", "offer", validity + pricing
  expense          : "مصروف", "expense", "receipt" (for reimbursement), employee + cost

══ TASK 2 — ENTITY EXTRACTION ══
Extract ONLY what is explicitly present in the text. null for anything absent.
  supplier      — vendor/supplier name (for purchase_invoice/expense)
  customer      — customer/buyer name (for sales_invoice/quotation)
  invoice_number — reference number, bill no, invoice ID, رقم الفاتورة
  date          — any document date, ISO format YYYY-MM-DD if possible
  total         — final payable amount (numeric string)
  currency      — 3-letter code: SAR JOD USD EUR GBP AED KWD
  tax           — tax amount (numeric string, null if not shown)

EXTRACTION RULES:
• NEVER invent or guess values — only extract explicitly written text
• For Arabic numbers (١٢٣) → convert to Western digits (123)
• For ambiguous currency → use context or leave null
• Dates in "DD/MM/YYYY" → convert to "YYYY-MM-DD"

══ TASK 3 — INTENT DETECTION ══
Map to exactly ONE intent:
  create_purchase_invoice  — new purchase invoice to record
  create_sales_invoice     — new sales invoice to record
  create_payment_entry     — record a payment made or received
  create_expense_claim     — employee expense to reimburse
  update_existing_document — document references an existing record to update
  approve_document         — document requires workflow approval
  reject_document          — document is to be rejected
  unknown_action           — cannot determine intent

══ TASK 4 — FAC MAPPING ══
Map intent to the correct FAC skill and tool:

Intent → FAC skill and tool:
  create_purchase_invoice  → skill:"fac.create_purchase_invoice" tool:"create_document"
  create_sales_invoice     → skill:"fac.create_sales_invoice"    tool:"create_document"
  create_payment_entry     → skill:"fac.create_payment"          tool:"create_document"
  create_expense_claim     → skill:"fac.create_expense"          tool:"create_document"
  update_existing_document → skill:"fac.update_document"         tool:"update_document"
  approve_document         → skill:"fac.workflow_approval"        tool:"run_workflow"
  reject_document          → skill:"fac.workflow_rejection"       tool:"run_workflow"
  unknown_action           → skill:"fac.unknown"                  tool:"get_document"

Payload = ERPNext-ready field values. Use exact ERPNext field names:
  supplier, customer, bill_no, bill_date, currency, total, total_taxes_and_charges

══ TASK 5 — ERPNEXT MAPPING ══
  doctype   — exact ERPNext DocType (e.g. "Purchase Invoice", "Sales Invoice", "Payment Entry")
  operation — create | update | submit | cancel
  data      — field → value mapping for the FAC tool call

══ CONFIDENCE GATE ══
  If input confidence < 0.60 → set status = "needs_review" (do NOT set to failed)
  If document type unclear   → document_type = "unknown", intent = "unknown_action"
  If text is complete gibberish → status = "failed", reason = "unreadable_text"

══ BUSINESS RULES (non-negotiable) ══
• NEVER invent, guess, or hallucinate data
• NEVER bypass FAC — all actions must route through FAC tools
• NEVER execute ERPNext actions directly — only prepare payload
• Always validate confidence before setting status = "success"

══ OUTPUT — STRICT FORMAT ══
Return ONLY valid JSON. No markdown. No explanation. No additional text.
{
  "status": "success | needs_review | failed",
  "document_type": "...",
  "intent": "...",
  "confidence": 0.0,
  "entities": {
    "supplier": null,
    "customer": null,
    "invoice_number": null,
    "date": null,
    "total": null,
    "currency": null,
    "tax": null
  },
  "fac": {
    "skill": "...",
    "tool": "...",
    "action": "...",
    "payload": {}
  },
  "erpnext": {
    "doctype": "...",
    "operation": "create",
    "data": {}
  },
  "reasoning": "one concise sentence explaining the classification and extracted entities"
}
''';

  // ── Public API ────────────────────────────────────────────────────────────

  /// Processes OCR input and returns a deterministic workflow result.
  ///
  /// Tries Claude first, falls back to ChatGPT.
  /// Returns [OcrWorkflowResult.failed] on unrecoverable errors — never throws.
  Future<OcrWorkflowResult> processOcrResult(OcrInput input) async {
    debugPrint('[OCR-Engine] ─────────────────────────────────────────────');
    debugPrint('[OCR-Engine] engine=${input.engineUsed}  conf=${input.confidence.toStringAsFixed(2)}  lang=${input.languageDetected}');
    debugPrint('[OCR-Engine] text(${input.cleanText.length}ch): '
        '${input.cleanText.substring(0, input.cleanText.length.clamp(0, 120))}…');

    // Guard — invalid or empty OCR
    if (!input.success || input.cleanText.trim().isEmpty) {
      debugPrint('[OCR-Engine] ❌ Empty or failed OCR input');
      return OcrWorkflowResult.failed('invalid_ocr_input');
    }
    if (input.confidence < 0.30) {
      debugPrint('[OCR-Engine] ❌ Confidence ${input.confidence} below minimum 0.30');
      return OcrWorkflowResult.failed('low_confidence_or_unreadable');
    }

    // Try Claude primary
    try {
      final result = await _callClaude(input);
      debugPrint('[OCR-Engine] ✅ Claude result: ${result.status.name}  '
          'type=${result.documentType.key}  intent=${result.intent.key}  '
          'conf=${result.confidence.toStringAsFixed(2)}');
      return result;
    } catch (e) {
      debugPrint('[OCR-Engine] ⚠️ Claude failed ($e) — trying ChatGPT fallback');
    }

    // Fallback to ChatGPT
    try {
      final result = await _callChatGPT(input);
      debugPrint('[OCR-Engine] ✅ ChatGPT fallback: ${result.status.name}  '
          'type=${result.documentType.key}');
      return result;
    } catch (e) {
      debugPrint('[OCR-Engine] ❌ Both providers failed: $e');
      return OcrWorkflowResult.failed('ai_extraction_failed');
    }
  }

  /// Convenience: build OcrInput from plain extracted text (e.g. from AI visual analysis).
  Future<OcrWorkflowResult> processText(
    String text, {
    double confidence = 0.80,
    String engine = 'visual_ai',
    String language = 'unknown',
  }) =>
      processOcrResult(OcrInput(
        success:          text.trim().isNotEmpty,
        engineUsed:       engine,
        confidence:       confidence,
        rawText:          text,
        cleanText:        text.trim(),
        languageDetected: language,
      ));

  // ── Claude API ────────────────────────────────────────────────────────────

  Future<OcrWorkflowResult> _callClaude(OcrInput input) async {
    final prefs  = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('claude_api_key') ?? '';
    if (apiKey.isEmpty) throw Exception('Claude API key not configured');

    final model = prefs.getString('ai_model') ?? 'claude-sonnet-4-6';
    debugPrint('[OCR-Engine] POST Claude ($model)');

    final response = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'x-api-key':          apiKey,
            'anthropic-version':  '2023-06-01',
            'anthropic-beta':     'prompt-caching-2024-07-31',
            'content-type':       'application/json',
          },
          body: jsonEncode({
            'model':      model,
            'max_tokens': 1024,
            'system': [
              {
                'type': 'text',
                'text': _systemPrompt,
                'cache_control': {'type': 'ephemeral'}, // cache the system prompt
              }
            ],
            'messages': [
              {
                'role':    'user',
                'content': jsonEncode(input.toJson()),
              }
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));

    debugPrint('[OCR-Engine] Claude HTTP ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception(
          'Claude ${response.statusCode}: '
          '${response.body.substring(0, response.body.length.clamp(0, 200))}');
    }

    final body    = jsonDecode(response.body) as Map<String, dynamic>;
    final rawText = (body['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';

    debugPrint('[OCR-Engine] Claude raw: ${rawText.substring(0, rawText.length.clamp(0, 200))}');

    return _parseResponse(rawText, input.confidence);
  }

  // ── ChatGPT API (fallback) ────────────────────────────────────────────────

  Future<OcrWorkflowResult> _callChatGPT(OcrInput input) async {
    final prefs  = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('chatgpt_api_key') ?? '';
    if (apiKey.isEmpty) throw Exception('ChatGPT API key not configured');

    final model = prefs.getString('chatgpt_model') ?? 'gpt-4o';
    debugPrint('[OCR-Engine] POST ChatGPT ($model) — fallback');

    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'content-type':  'application/json',
          },
          body: jsonEncode({
            'model':           model,
            'max_tokens':      1024,
            'response_format': {'type': 'json_object'}, // force valid JSON
            'messages': [
              {'role': 'system', 'content': _systemPrompt},
              {'role': 'user',   'content': jsonEncode(input.toJson())},
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));

    debugPrint('[OCR-Engine] ChatGPT HTTP ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception('ChatGPT ${response.statusCode}');
    }

    final body    = jsonDecode(response.body) as Map<String, dynamic>;
    final rawText = body['choices']?[0]?['message']?['content']?.toString() ?? '';

    return _parseResponse(rawText, input.confidence);
  }

  // ── Response parser ───────────────────────────────────────────────────────

  OcrWorkflowResult _parseResponse(String rawText, double inputConfidence) {
    // Strip markdown code fences if present
    String jsonStr = rawText.trim();
    if (jsonStr.startsWith('```')) {
      final start = jsonStr.indexOf('\n') + 1;
      final end   = jsonStr.lastIndexOf('```');
      if (start > 0 && end > start) jsonStr = jsonStr.substring(start, end).trim();
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[OCR-Engine] ❌ JSON parse failed: $e — raw: ${jsonStr.substring(0, jsonStr.length.clamp(0, 200))}');
      return OcrWorkflowResult.failed('json_parse_error');
    }

    // Failed status from engine
    if (json['status'] == 'failed') {
      return OcrWorkflowResult.failed(json['reason']?.toString() ?? 'engine_reported_failure');
    }

    // Average input confidence with engine-estimated confidence
    final engineConf = (json['confidence'] as num?)?.toDouble() ?? inputConfidence;
    final finalConf  = (engineConf + inputConfidence) / 2.0;

    // Apply confidence gate — downgrade to needs_review if too low
    final mergedJson = Map<String, dynamic>.from(json);
    mergedJson['confidence'] = finalConf;
    if (finalConf < 0.55 && mergedJson['status'] == 'success') {
      debugPrint('[OCR-Engine] ⚠️ finalConf=$finalConf → downgrading to needs_review');
      mergedJson['status'] = 'needs_review';
    }

    return OcrWorkflowResult.fromJson(mergedJson, jsonStr);
  }
}
