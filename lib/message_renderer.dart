import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_colors.dart';
import 'app_localizations.dart';
import 'web_download.dart';

// ---------------------------------------------------------------------------
// Public widget — entry point
// ---------------------------------------------------------------------------

/// Renders an AI message string that may contain:
/// - `<chart>JSON</chart>` blocks → fl_chart widget (with optional save button)
/// - `<export_pdf/>` tag → enables PDF export button on all tables
/// - `<send_email to="..." subject="...">body</send_email>` → opens device mail app
/// - `<system_email to="..." subject="...">body</system_email>` → sends via ERPNext
/// - Markdown table syntax (| col | col |) → HTML-style Flutter table
/// - Plain text → SelectableText
class MessageRenderer extends StatelessWidget {
  final String text;

  /// Font family applied only to plain-text segments — NOT to tables/charts.
  /// Pass 'Cairo' for Arabic, 'Inter' for English, null for system default.
  final String? fontFamily;

  /// Called when the user taps "Save to Dashboard" on a chart block.
  final void Function(Map<String, dynamic>)? onCreateChart;

  /// Called when the user taps "إرسال من النظام" — sends email via ERPNext API.
  /// htmlBody is already converted from markdown → HTML.
  /// pdfBytes is non-null when `export_pdf` tag is present and table data is available.
  final void Function(String to, String subject, String htmlBody, Uint8List? pdfBytes)? onSendSystemEmail;

  /// Called when the AI embeds an `<open_document doctype="X" docname="Y"/>` tag.
  /// The host page should navigate to DocumentViewerPage with the given params.
  final void Function(String doctype, String docname)? onOpenDocument;

  const MessageRenderer({
    super.key,
    required this.text,
    this.fontFamily,
    this.onCreateChart,
    this.onSendSystemEmail,
    this.onOpenDocument,
  });

  // Regex: <send_email to="..." subject="...">body</send_email> — device mail app
  static final _emailRx = RegExp(
    r'<send_email\s+to="([^"]*)"(?:\s+subject="([^"]*)")?[^>]*>([\s\S]*?)<\/send_email>',
    caseSensitive: false,
  );

  // Regex: <system_email to="..." subject="...">body</system_email> — ERPNext API
  static final _sysEmailRx = RegExp(
    r'<system_email\s+to="([^"]*)"(?:\s+subject="([^"]*)")?[^>]*>([\s\S]*?)<\/system_email>',
    caseSensitive: false,
  );

  // Regex: <open_document doctype="X" docname="Y"/> — opens DocumentViewerPage
  static final _openDocRx = RegExp(
    r'<open_document\s+doctype="([^"]+)"\s+docname="([^"]+)"\s*/?>',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    // ── detect tags ─────────────────────────────────────────────────────────
    final emailMatch    = _emailRx.firstMatch(text);
    final sysEmailMatch = _sysEmailRx.firstMatch(text);

    final emailTo      = emailMatch?.group(1) ?? '';
    final emailSubject = emailMatch?.group(2) ?? '';
    final emailBody    = emailMatch?.group(3)?.trim() ?? '';

    final sysTo      = sysEmailMatch?.group(1) ?? '';
    final sysSubject = sysEmailMatch?.group(2) ?? '';
    final sysBody    = sysEmailMatch?.group(3)?.trim() ?? '';

    // Collect all <open_document> matches before stripping
    final openDocMatches = _openDocRx.allMatches(text).toList();

    // Strip control tags from display text
    final cleanText = text
        .replaceAll(RegExp(r'<export_pdf\s*/?>', caseSensitive: false), '')
        .replaceAll(_emailRx, '')
        .replaceAll(_sysEmailRx, '')
        .replaceAll(_openDocRx, '')
        .trim();

    final segments = _parseSegments(cleanText);

    final children = <Widget>[];
    for (int i = 0; i < segments.length; i++) {
      children.add(_render(context, segments[i]));
      if (i < segments.length - 1) children.add(const SizedBox(height: 8));
    }

    // ── device email button ─────────────────────────────────────────────────
    if (emailTo.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(_EmailButton(to: emailTo, subject: emailSubject, body: emailBody));
    }

    // ── system email button (ERPNext) ───────────────────────────────────────
    if (sysTo.isNotEmpty && onSendSystemEmail != null) {
      // Always attach first table as PDF if present in the message
      List<String>? emailTableLines;
      for (final seg in segments) {
        if (seg.type == _SegType.table && seg.tableLines != null) {
          emailTableLines = seg.tableLines;
          break;
        }
      }
      children.add(const SizedBox(height: 8));
      children.add(_SystemEmailButton(
        to: sysTo,
        subject: sysSubject,
        body: sysBody,
        tableLines: emailTableLines,
        onSend: onSendSystemEmail!,
      ));
    }

    // ── open_document buttons ───────────────────────────────────────────────
    for (final m in openDocMatches) {
      final doctype = m.group(1) ?? '';
      final docname = m.group(2) ?? '';
      if (doctype.isNotEmpty && docname.isNotEmpty) {
        children.add(const SizedBox(height: 8));
        children.add(_OpenDocumentButton(
          doctype: doctype,
          docname: docname,
          onTap: onOpenDocument != null
              ? () => onOpenDocument!(doctype, docname)
              : null,
        ));
      }
    }

    if (children.length == 1) return children.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  // ── Segment parsing ───────────────────────────────────────────────────────

  List<_Segment> _parseSegments(String raw) {
    final result = <_Segment>[];
    final chartRx = RegExp(r'<chart>([\s\S]*?)<\/chart>', caseSensitive: false);
    int cursor = 0;

    for (final m in chartRx.allMatches(raw)) {
      if (m.start > cursor) {
        _splitTextTable(raw.substring(cursor, m.start).trim(), result);
      }
      final json = m.group(1)?.trim() ?? '';
      if (json.isNotEmpty) result.add(_Segment.chart(json));
      cursor = m.end;
    }
    if (cursor < raw.length) {
      _splitTextTable(raw.substring(cursor).trim(), result);
    }
    return result.where((s) => s.content.isNotEmpty).toList();
  }

  void _splitTextTable(String chunk, List<_Segment> out) {
    if (chunk.isEmpty) return;
    final lines = chunk.split('\n');
    final textBuf = StringBuffer();
    final tableBuf = <String>[];
    bool inTable = false;

    void flushText() {
      final s = textBuf.toString().trim();
      if (s.isNotEmpty) out.add(_Segment.text(s));
      textBuf.clear();
    }

    void flushTable() {
      if (tableBuf.isNotEmpty) {
        out.add(_Segment.table(List.from(tableBuf)));
        tableBuf.clear();
      }
    }

    for (final line in lines) {
      final t = line.trim();
      // Accept any line starting with | that has at least one more | (trailing | not required)
      final isTableLine = t.startsWith('|') && t.indexOf('|', 1) != -1;
      if (isTableLine) {
        if (!inTable) {
          flushText();
          inTable = true;
        }
        tableBuf.add(t);
      } else {
        if (inTable) {
          flushTable();
          inTable = false;
        }
        textBuf.writeln(line);
      }
    }
    if (inTable) {
      flushTable();
    } else {
      flushText();
    }
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  Widget _render(BuildContext context, _Segment s) {
    switch (s.type) {
      case _SegType.chart:
        return _ChartWidget(json: s.content, onCreateChart: onCreateChart);
      case _SegType.table:
        return _HtmlTable(
          rawLines: s.tableLines!,
          onSendEmailWithAttachment: onSendSystemEmail,
        );
      case _SegType.text:
        return SelectableText(
          s.content,
          style: TextStyle(
            color: AppColors.of(context).aiText,
            fontSize: 14,
            height: 1.5,
            fontFamily: fontFamily,
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Segment model
// ---------------------------------------------------------------------------

enum _SegType { text, table, chart }

class _Segment {
  final _SegType type;
  final String content;
  final List<String>? tableLines;

  const _Segment._({required this.type, required this.content, this.tableLines});

  factory _Segment.text(String s) =>
      _Segment._(type: _SegType.text, content: s);

  factory _Segment.table(List<String> lines) =>
      _Segment._(type: _SegType.table, content: lines.join('\n'), tableLines: lines);

  factory _Segment.chart(String json) =>
      _Segment._(type: _SegType.chart, content: json);
}

// ---------------------------------------------------------------------------
// HTML-Style Table — uses DataTable (works correctly with horizontal scroll)
// ---------------------------------------------------------------------------

class _HtmlTable extends StatefulWidget {
  final List<String> rawLines;
  /// Called when user taps "إرسال بالبريد" — same signature as onSendSystemEmail.
  final void Function(String to, String subject, String htmlBody, Uint8List? pdfBytes)? onSendEmailWithAttachment;

  const _HtmlTable({required this.rawLines, this.onSendEmailWithAttachment});

  @override
  State<_HtmlTable> createState() => _HtmlTableState();
}

class _HtmlTableState extends State<_HtmlTable> {
  bool _busy = false; // loading state for async operations

  static final _sepRx = RegExp(r'^[\|\-\:\s]+$');

  List<List<String>> _parse() {
    final rows = <List<String>>[];
    for (final line in widget.rawLines) {
      final t = line.trim();
      if (!t.startsWith('|') || t.indexOf('|', 1) == -1) continue;
      // Strip leading | and optional trailing |
      final inner = t.endsWith('|') ? t.substring(1, t.length - 1) : t.substring(1);
      if (_sepRx.hasMatch(inner.replaceAll('|', ''))) continue;
      rows.add(inner.split('|').map((c) => c.trim()).toList());
    }
    return rows;
  }

  static bool _isNumeric(String s) {
    final cleaned = s.replaceAll(RegExp(r'[,،%٪\s]'), '').trim();
    return cleaned.isNotEmpty && double.tryParse(cleaned) != null;
  }

  // ── PDF helpers ────────────────────────────────────────────────────────────

  Future<Uint8List> _buildPdfBytes(
      List<String> headers, List<List<String>> dataRows) async {
    final regular = await PdfGoogleFonts.cairoRegular();
    final bold    = await PdfGoogleFonts.cairoBold();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      textDirection: pw.TextDirection.rtl,
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: dataRows,
          headerStyle: pw.TextStyle(
              font: bold, fontWeight: pw.FontWeight.bold,
              color: PdfColors.white, fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0B1CE0)),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0F4FF)),
          cellStyle: pw.TextStyle(font: regular, fontSize: 9),
          headerAlignments: {for (int i = 0; i < headers.length; i++) i: pw.Alignment.centerLeft},
          cellAlignments:   {for (int i = 0; i < headers.length; i++) i: pw.Alignment.centerLeft},
          border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
        ),
      ],
    ));
    return doc.save();
  }

  String _buildHtmlBody(List<String> headers, List<List<String>> dataRows) {
    final buf = StringBuffer();
    buf.write('<html dir="rtl"><body style="font-family:Arial,sans-serif;direction:rtl;">');
    buf.write('<table border="1" cellpadding="7" cellspacing="0" '
        'style="border-collapse:collapse;width:100%;font-size:13px;">');
    buf.write('<tr style="background-color:#0B1CE0;color:#fff;">');
    for (final h in headers) {
      buf.write('<th style="padding:7px 10px;text-align:right;white-space:nowrap;">${_escHtml(h)}</th>');
    }
    buf.write('</tr>');
    for (int i = 0; i < dataRows.length; i++) {
      final bg = i.isOdd ? '#f0f4ff' : '#ffffff';
      buf.write('<tr style="background-color:$bg;">');
      for (final cell in dataRows[i]) {
        buf.write('<td style="padding:5px 10px;text-align:right;">${_escHtml(cell)}</td>');
      }
      buf.write('</tr>');
    }
    buf.write('</table></body></html>');
    return buf.toString();
  }

  // ── Filename helper ───────────────────────────────────────────────────────

  static String _reportFilename(String ext) {
    final dt = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    return 'report_$dt.$ext';
  }

  // ── Excel builder ─────────────────────────────────────────────────────────

  List<int> _buildExcelBytes(List<String> headers, List<List<String>> dataRows) {
    final xls = Excel.createExcel();
    final sheet = xls['Report'];
    sheet.appendRow(headers.map<CellValue>((h) => TextCellValue(h)).toList());
    for (final row in dataRows) {
      sheet.appendRow(row.map<CellValue>((c) => TextCellValue(c)).toList());
    }
    try { xls.delete('Sheet1'); } catch (_) {}
    return xls.save() ?? [];
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try { await fn(); } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _sharePdf(List<String> h, List<List<String>> d) async {
    final bytes    = await _buildPdfBytes(h, d);
    final filename = _reportFilename('pdf');
    if (kIsWeb) {
      downloadBytesInBrowser(bytes, filename, 'application/pdf');
      return;
    }
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  Future<void> _savePdfToDevice(
      BuildContext ctx, List<String> h, List<List<String>> d) async {
    final bytes    = await _buildPdfBytes(h, d);
    final filename = _reportFilename('pdf');
    if (kIsWeb) {
      downloadBytesInBrowser(bytes, filename, 'application/pdf');
      return;
    }
    final dir = await getExternalStorageDirectory();
    if (dir == null) throw Exception('لا يمكن الوصول إلى التخزين');
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('✅ تم الحفظ:\n${file.path}'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'مشاركة',
          textColor: Colors.white,
          onPressed: () => SharePlus.instance.share(
            ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')]),
          ),
        ),
      ));
    }
  }

  Future<void> _shareAsExcel(
      BuildContext ctx, List<String> h, List<List<String>> d) async {
    final bytes    = _buildExcelBytes(h, d);
    final filename = _reportFilename('xlsx');
    const mime     = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (kIsWeb) {
      downloadBytesInBrowser(bytes, filename, mime);
      return;
    }
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mime, name: filename)]),
    );
  }

  Future<void> _saveExcelToDevice(
      BuildContext ctx, List<String> h, List<List<String>> d) async {
    final bytes    = _buildExcelBytes(h, d);
    final filename = _reportFilename('xlsx');
    const mime     = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (kIsWeb) {
      downloadBytesInBrowser(bytes, filename, mime);
      return;
    }
    final dir = await getExternalStorageDirectory();
    if (dir == null) throw Exception('لا يمكن الوصول إلى التخزين');
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('✅ تم الحفظ:\n${file.path}'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'مشاركة',
          textColor: Colors.white,
          onPressed: () => SharePlus.instance.share(
            ShareParams(files: [XFile(file.path, mimeType: mime)]),
          ),
        ),
      ));
    }
  }

  /// Show dialog → collect email/subject →
  ///   Web:    open mailto: link directly (no ERPNext API)
  ///   Mobile: generate PDF + call ERPNext API callback
  Future<void> _showEmailDialog(
      BuildContext ctx, List<String> h, List<List<String>> d) async {
    if (!kIsWeb && widget.onSendEmailWithAttachment == null) return;
    final l10n        = AppLocalizations.of(ctx);
    final emailCtrl   = TextEditingController();
    final subjectCtrl = TextEditingController(text: l10n.dataReport);
    final confirmed   = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color.fromARGB(255, 138, 152, 230),
        title: Text(l10n.sendEmailWithPdf,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Color.fromARGB(255, 50, 49, 49)),
            decoration: InputDecoration(
              labelText: l10n.emailAddress,
              labelStyle: const TextStyle(color: Color.fromARGB(179, 41, 40, 40)),
              hintText: 'example@email.com',
              hintStyle: const TextStyle(color: Colors.white30),
              enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white38)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: subjectCtrl,
            style: const TextStyle(color: Color.fromARGB(255, 49, 47, 47)),
            decoration: InputDecoration(
              labelText: l10n.emailSubject,
              labelStyle: const TextStyle(color: Color.fromARGB(179, 55, 53, 53)),
              enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white38)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l10n.cancel, style: const TextStyle(color: Color.fromARGB(153, 218, 14, 14), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dCtx, true),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: Text(l10n.send),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent.shade700),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final to      = emailCtrl.text.trim();
    final subject = subjectCtrl.text.trim();
    if (to.isEmpty) return;

    if (kIsWeb) {
      if (!ctx.mounted) return;
      await _openMailtoWeb(ctx, to, subject, h, d);
      return;
    }

    // Mobile: send via ERPNext API with PDF attachment
    final pdfBytes = await _buildPdfBytes(h, d);
    final htmlBody = _buildHtmlBody(h, d);
    widget.onSendEmailWithAttachment!(to, subject, htmlBody, pdfBytes);
  }

  /// Web-only: open default mail client via mailto: link.
  Future<void> _openMailtoWeb(BuildContext ctx, String to, String subject,
      List<String> h, List<List<String>> d) async {
    final bodyLines = [h.join('\t'), ...d.map((r) => r.join('\t'))];
    final body      = bodyLines.join('\n');
    const maxLen    = 1800;

    Uri buildUri(String b) => Uri(
          scheme: 'mailto',
          path: to,
          queryParameters: {
            if (subject.isNotEmpty) 'subject': subject,
            if (b.isNotEmpty) 'body': b,
          },
        );

    final truncated = body.length > maxLen
        ? '${body.substring(0, maxLen)}...\n(البيانات مقطوعة)'
        : body;

    for (final b in [body, truncated, '']) {
      try {
        await launchUrl(buildUri(b), mode: LaunchMode.externalApplication);
        return;
      } catch (_) {}
    }

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('⚠️ تعذّر فتح تطبيق البريد'),
        backgroundColor: Colors.red,
      ));
    }
  }

  // ── Web: download PDF + open Outlook compose ─────────────────────────────
  //
  // mailto: cannot attach files (browser security restriction).
  // Workaround: auto-download PDF to browser Downloads folder, then open
  // Outlook compose with a professional bilingual body instructing the user
  // to attach the saved file.  One click → two things happen simultaneously.
  Future<void> _sendEmailWithPdfDownloadWeb(
      BuildContext ctx, List<String> h, List<List<String>> d) async {
    final l10n     = AppLocalizations.of(ctx);
    final filename = _reportFilename('pdf');

    // ① Generate + auto-download PDF into browser Downloads folder
    final pdfBytes = await _buildPdfBytes(h, d);
    if (!ctx.mounted) return;
    downloadBytesInBrowser(pdfBytes, filename, 'application/pdf');

    // ② Professional bilingual email body
    final body = l10n.isArabic
        ? 'السلام عليكم،\n\nيرجى الاطلاع على التقرير المرفق.\n\n'
          'ملاحظة: تم حفظ الملف "$filename" في مجلد Downloads تلقائياً —\n'
          'يرجى إرفاقه بهذا الإيميل قبل الإرسال.'
        : 'Dear,\n\nPlease find the attached report.\n\n'
          'Note: The file "$filename" was automatically saved to your Downloads folder —\n'
          'please attach it to this email before sending.';

    // ③ Open Outlook compose (subject + body pre-filled)
    await sendEmailViaOutlookDesktop(
      context: ctx,
      subject: l10n.dataReport,
      body: body,
    );

    // ④ Snackbar to guide the user
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(
          l10n.isArabic
              ? '📎 "$filename" محفوظ في Downloads — أرفقه بالإيميل قبل الإرسال'
              : '📎 "$filename" saved in Downloads — attach it before sending',
        ),
        backgroundColor: Colors.blue.shade700,
        duration: const Duration(seconds: 8),
      ));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  Widget _exportBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) =>
      TextButton.icon(
        onPressed: _busy ? null : onPressed,
        icon: _busy
            ? SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(color: color, strokeWidth: 2))
            : Icon(icon, size: 13),
        label: Text(label, style: TextStyle(fontSize: 10.5)),
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rows = _parse();
    if (rows.isEmpty) return const SizedBox.shrink();

    final c        = AppColors.of(context);
    final headers  = rows.first;
    final dataRows = rows.skip(1).toList();
    final colCount = headers.length;

    final isNumericCol = List<bool>.filled(colCount, false);
    for (int col = 0; col < colCount; col++) {
      if (dataRows.isEmpty) break;
      int n = 0;
      for (final row in dataRows) {
        if (col < row.length && _isNumeric(row[col])) n++;
      }
      isNumericCol[col] = n > dataRows.length * 0.5;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Table ────────────────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.surfaceHigh),
            color: Colors.transparent,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: c.surfaceHigh),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                      c.primary.withValues(alpha: 0.85)),
                  headingRowHeight: 42,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 48,
                  columnSpacing: 20,
                  horizontalMargin: 14,
                  showCheckboxColumn: false,
                  columns: headers.asMap().entries.map((e) => DataColumn(
                    numeric: isNumericCol[e.key],
                    label: Text(e.value,
                        style: TextStyle(
                            color: c.onPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5)),
                  )).toList(),
                  rows: dataRows.asMap().entries.map((rowEntry) => DataRow(
                    color: WidgetStateProperty.resolveWith((s) => rowEntry.key.isOdd
                        ? c.surfaceHigh.withValues(alpha: 0.5)
                        : Colors.transparent),
                    cells: List.generate(colCount, (colIdx) {
                      final cell = colIdx < rowEntry.value.length
                          ? rowEntry.value[colIdx] : '';
                      return DataCell(Text(cell,
                          style: TextStyle(
                              color: c.aiText,
                              fontSize: 12,
                              fontFamily: isNumericCol[colIdx] ? 'monospace' : null)));
                    }),
                  )).toList(),
                ),
              ),
            ),
          ),
        ),
        // ── Export buttons ────────────────────────────────────────────────────
        Builder(builder: (ctx) => Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            // PDF — share/download
            _exportBtn(
              icon: Icons.picture_as_pdf_rounded,
              label: 'PDF',
              color: Colors.redAccent.withValues(alpha: 0.85),
              onPressed: () => _run(() => _sharePdf(headers, dataRows)),
            ),
            // PDF save to device — mobile only (web uses same download as above)
            if (!kIsWeb)
              _exportBtn(
                icon: Icons.save_alt_rounded,
                label: AppLocalizations.of(ctx).savePdf,
                color: Colors.orangeAccent.withValues(alpha: 0.85),
                onPressed: () => _run(() => _savePdfToDevice(ctx, headers, dataRows)),
              ),
            // Excel (.xlsx) — share/download
            _exportBtn(
              icon: Icons.table_chart_rounded,
              label: 'Excel',
              color: Colors.greenAccent.withValues(alpha: 0.85),
              onPressed: () => _run(() => _shareAsExcel(ctx, headers, dataRows)),
            ),
            // Excel save to device — mobile only (web uses same download as above)
            if (!kIsWeb)
              _exportBtn(
                icon: Icons.save_rounded,
                label: AppLocalizations.of(ctx).saveExcel,
                color: Colors.tealAccent.withValues(alpha: 0.85),
                onPressed: () => _run(() => _saveExcelToDevice(ctx, headers, dataRows)),
              ),
            // Email:
            //   Web    → open Outlook directly via mailto: (no Flutter dialog)
            //   Mobile → collect email/subject in dialog then call ERPNext API
            if (widget.onSendEmailWithAttachment != null || kIsWeb)
              _exportBtn(
                icon: Icons.attach_email_rounded,
                label: AppLocalizations.of(ctx).sendByEmail,
                color: Colors.lightBlueAccent.withValues(alpha: 0.85),
                onPressed: () {
                  if (kIsWeb) {
                    // Web: auto-download PDF + open Outlook compose
                    _run(() => _sendEmailWithPdfDownloadWeb(ctx, headers, dataRows));
                  } else {
                    // Mobile: dialog → ERPNext API with PDF attachment
                    _run(() => _showEmailDialog(ctx, headers, dataRows));
                  }
                },
              ),
          ],
        )),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chart Widget
// ---------------------------------------------------------------------------

class _ChartWidget extends StatelessWidget {
  final String json;
  final void Function(Map<String, dynamic>)? onCreateChart;
  const _ChartWidget({required this.json, this.onCreateChart});

  static const _palette = [
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
  ];

  Color _color(String? hex, int fallbackIndex) {
    if (hex != null && hex.startsWith('#')) {
      try {
        return Color(int.parse('FF${hex.substring(1)}', radix: 16));
      } catch (_) {}
    }
    return _palette[fallbackIndex % _palette.length];
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Map<String, dynamic> data;
    try {
      data = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return SelectableText(
        json,
        style: TextStyle(color: c.textSecondary, fontSize: 11),
      );
    }

    final type = (data['type'] as String? ?? 'bar').toLowerCase();
    final title = data['title'] as String? ?? '';
    final labels = (data['labels'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final datasets = (data['datasets'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

    if (datasets.isEmpty) return const SizedBox.shrink();

    Widget chart;
    try {
      switch (type) {
        case 'line':
          chart = _line(context, labels, datasets);
        case 'pie':
          chart = _pie(context, labels, datasets);
        default:
          chart = _bar(context, labels, datasets);
      }
    } catch (_) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.surfaceHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title + save button row
          Row(
            children: [
              if (title.isNotEmpty)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6, left: 4),
                    child: Text(
                      title,
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              else
                const Spacer(),
              // Save to dashboard button
              if (onCreateChart != null)
                TextButton.icon(
                  onPressed: () => onCreateChart!(data),
                  icon: const Icon(Icons.add_chart_rounded, size: 14),
                  label: const Text('حفظ في الداشبورد',
                      style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: c.textSecondary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          SizedBox(height: 220, child: chart),
        ],
      ),
    );
  }

  // ── Bar ──────────────────────────────────────────────────────────────────

  Widget _bar(BuildContext context, List<String> labels, List<Map<String, dynamic>> datasets) {
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < labels.length; i++) {
      final rods = <BarChartRodData>[];
      for (int j = 0; j < datasets.length; j++) {
        final rawData = datasets[j]['data'] as List? ?? [];
        final v = rawData.length > i ? _toDouble(rawData[i]) : 0.0;
        rods.add(BarChartRodData(
          toY: v,
          color: _color(datasets[j]['color'] as String?, j),
          width: datasets.length > 1 ? 8 : 14,
          borderRadius: BorderRadius.circular(3),
        ));
      }
      groups.add(BarChartGroupData(
        x: i,
        barRods: rods,
        barsSpace: 3,
      ));
    }

    return BarChart(BarChartData(
      barGroups: groups,
      backgroundColor: Colors.transparent,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: AppColors.of(context).surfaceHigh.withValues(alpha: 0.6),
          strokeWidth: 0.5,
        ),
      ),
      titlesData: _titlesData(context, labels),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => AppColors.of(context).primaryDark,
          getTooltipItem: (group, gi, rod, ri) {
            final lbl = gi < labels.length ? labels[gi] : '';
            final dsLbl = ri < datasets.length
                ? (datasets[ri]['label'] as String? ?? '')
                : '';
            return BarTooltipItem(
              '$lbl${dsLbl.isNotEmpty ? '\n$dsLbl' : ''}\n${rod.toY.toStringAsFixed(1)}',
              TextStyle(color: AppColors.of(context).onPrimary, fontSize: 11),
            );
          },
        ),
      ),
    ));
  }

  // ── Line ─────────────────────────────────────────────────────────────────

  Widget _line(BuildContext context, List<String> labels, List<Map<String, dynamic>> datasets) {
    final lines = <LineChartBarData>[];
    for (int j = 0; j < datasets.length; j++) {
      final rawData = datasets[j]['data'] as List? ?? [];
      final color = _color(datasets[j]['color'] as String?, j);
      final spots = rawData.asMap().entries
          .map((e) => FlSpot(e.key.toDouble(), _toDouble(e.value)))
          .toList();
      lines.add(LineChartBarData(
        spots: spots,
        color: color,
        isCurved: true,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: color.withValues(alpha: 0.12),
        ),
      ));
    }

    return LineChart(LineChartData(
      lineBarsData: lines,
      backgroundColor: Colors.transparent,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: AppColors.of(context).surfaceHigh.withValues(alpha: 0.6),
          strokeWidth: 0.5,
        ),
      ),
      titlesData: _titlesData(context, labels),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppColors.of(context).primaryDark,
        ),
      ),
    ));
  }

  // ── Pie ──────────────────────────────────────────────────────────────────

  Widget _pie(BuildContext context, List<String> labels, List<Map<String, dynamic>> datasets) {
    final rawData = datasets.first['data'] as List? ?? [];
    final sections = rawData.asMap().entries.map((e) {
      final v = _toDouble(e.value);
      final lbl = e.key < labels.length ? labels[e.key] : '';
      return PieChartSectionData(
        value: v,
        color: _palette[e.key % _palette.length],
        title: lbl,
        titleStyle: TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        radius: 80,
        titlePositionPercentageOffset: 0.6,
      );
    }).toList();

    return PieChart(PieChartData(
      sections: sections,
      sectionsSpace: 2,
      centerSpaceRadius: 30,
      borderData: FlBorderData(show: false),
    ));
  }

  // ── Shared titles ─────────────────────────────────────────────────────────

  FlTitlesData _titlesData(BuildContext context, List<String> labels) {
    final c = AppColors.of(context);
    return FlTitlesData(
      topTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          getTitlesWidget: (v, _) => Text(
            v.toInt().toString(),
            style: TextStyle(color: c.textSecondary, fontSize: 9),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= labels.length) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                labels[i],
                style: TextStyle(color: c.textSecondary, fontSize: 10),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers — HTML conversion + PDF bytes for email attachment
// ---------------------------------------------------------------------------

/// Escape special HTML characters.
String _escHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Convert plain text (may contain markdown tables) to an HTML string.
String _bodyToHtml(String raw) {
  final sepRx = RegExp(r'^[\|\-\:\s]+$');
  final lines  = raw.split('\n');
  final buf    = StringBuffer();

  buf.write('<div style="font-family:Arial,sans-serif;font-size:13px;'
      'color:#222;line-height:1.6;direction:rtl;">');

  bool inTable  = false;
  bool firstRow = true;

  for (final line in lines) {
    final t            = line.trim();
    final isTableLine  = t.startsWith('|') && t.endsWith('|') && t.length > 1;

    if (isTableLine) {
      final inner = t.substring(1, t.length - 1);
      if (sepRx.hasMatch(inner.replaceAll('|', ''))) continue;

      final cells = inner.split('|').map((c) => c.trim()).toList();

      if (!inTable) {
        buf.write('<table border="1" cellpadding="7" cellspacing="0" style="'
            'border-collapse:collapse;width:100%;margin:8px 0;">');
        inTable  = true;
        firstRow = true;
      }

      if (firstRow) {
        buf.write('<tr style="background-color:#0B1CE0;color:#fff;">');
        for (final c in cells) {
          buf.write('<th style="padding:7px 10px;text-align:right;white-space:nowrap;">'
              '${_escHtml(c)}</th>');
        }
        buf.write('</tr>');
        firstRow = false;
      } else {
        buf.write('<tr>');
        for (final c in cells) {
          buf.write('<td style="padding:5px 10px;text-align:right;">'
              '${_escHtml(c)}</td>');
        }
        buf.write('</tr>');
      }
    } else {
      if (inTable) { buf.write('</table>'); inTable = false; }
      if (t.isNotEmpty) buf.write('<p style="margin:4px 0;">${_escHtml(t)}</p>');
    }
  }
  if (inTable) buf.write('</table>');
  buf.write('</div>');
  return buf.toString();
}

/// Generate PDF bytes from raw markdown table lines (used for email attachment).
Future<Uint8List> _buildAttachmentPdf(List<String> rawLines) async {
  final sepRx = RegExp(r'^[\|\-\:\s]+$');
  final rows  = <List<String>>[];

  for (final line in rawLines) {
    final t = line.trim();
    if (!t.startsWith('|') || !t.endsWith('|')) continue;
    final inner = t.substring(1, t.length - 1);
    if (sepRx.hasMatch(inner.replaceAll('|', ''))) continue;
    rows.add(inner.split('|').map((c) => c.trim()).toList());
  }
  if (rows.isEmpty) return Uint8List(0);

  final headers  = rows.first;
  final dataRows = rows.skip(1).toList();
  final regular  = await PdfGoogleFonts.cairoRegular();
  final bold     = await PdfGoogleFonts.cairoBold();

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(24),
    textDirection: pw.TextDirection.rtl,
    build: (ctx) => [
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: dataRows,
        headerStyle: pw.TextStyle(
            font: bold, fontWeight: pw.FontWeight.bold,
            color: PdfColors.white, fontSize: 10),
        headerDecoration:
            const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0B1CE0)),
        oddRowDecoration:
            const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0F4FF)),
        cellStyle: pw.TextStyle(font: regular, fontSize: 9),
        headerAlignments: {for (int i = 0; i < headers.length; i++) i: pw.Alignment.centerLeft},
        cellAlignments:   {for (int i = 0; i < headers.length; i++) i: pw.Alignment.centerLeft},
        border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
    ],
  ));
  return doc.save();
}

// ---------------------------------------------------------------------------
// System Email Button — converts body to HTML, optionally attaches PDF
// ---------------------------------------------------------------------------
class _SystemEmailButton extends StatefulWidget {
  final String to;
  final String subject;
  final String body;
  /// Non-null → generate PDF attachment before sending.
  final List<String>? tableLines;
  final void Function(String to, String subject, String htmlBody, Uint8List? pdfBytes) onSend;

  const _SystemEmailButton({
    required this.to,
    required this.subject,
    required this.body,
    required this.onSend,
    this.tableLines,
  });

  @override
  State<_SystemEmailButton> createState() => _SystemEmailButtonState();
}

class _SystemEmailButtonState extends State<_SystemEmailButton> {
  bool _loading = false;

  Future<void> _handleTap() async {
    setState(() => _loading = true);
    try {
      final htmlBody = _bodyToHtml(widget.body);

      Uint8List? pdfBytes;
      if (widget.tableLines != null && widget.tableLines!.isNotEmpty) {
        final bytes = await _buildAttachmentPdf(widget.tableLines!);
        if (bytes.isNotEmpty) pdfBytes = bytes;
      }

      widget.onSend(widget.to, widget.subject, htmlBody, pdfBytes);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAttachment = widget.tableLines != null;
    return TextButton.icon(
      onPressed: _loading ? null : _handleTap,
      icon: _loading
          ? const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(
                  color: Colors.greenAccent, strokeWidth: 2),
            )
          : Icon(hasAttachment ? Icons.attach_email_rounded : Icons.send_rounded, size: 14),
      label: Text(
        hasAttachment
            ? 'إرسال من النظام مع مرفق PDF إلى ${widget.to}'
            : 'إرسال من النظام إلى ${widget.to}',
        style: TextStyle(fontSize: 11),
      ),
      style: TextButton.styleFrom(
        foregroundColor: Colors.greenAccent.withValues(alpha: 0.9),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Web email helper — opens Classic Outlook (or default MAILTO handler) directly
// into a NEW COMPOSE window with subject + body pre-filled.
// No Flutter dialog is shown.  [to] may be empty — user types it in Outlook.
//
// ROOT CAUSE of empty subject/body:
//   Dart's Uri(queryParameters:{}) uses + for spaces (form-encoding).
//   Outlook 2019/2021 requires RFC 6068 percent-encoding (%20).
//   We build the URI manually with Uri.encodeComponent() to fix this.
//
// Body length budget:
//   Chrome/Edge enforce a ~2048-char limit on the full URI.
//   Arabic text encodes at ~6× expansion (%D8%A7%D9%84...).
//   We check the *encoded* body length directly and trim the *raw* body
//   until the encoded result fits, then append a truncation note.
//
// Windows setup (one-time per machine) — required to open CLASSIC Outlook:
//   Settings → Apps → Default apps → Email
//   → select "Microsoft Outlook" (the classic icon, NOT "New Outlook")
//   If "New Outlook" is selected, clicking the button opens the welcome/setup
//   screen instead of a compose window — this cannot be fixed from code.
//
// Browser setup (one-time per browser):
//   Chrome/Edge: first click shows "Open Microsoft Outlook?" — tick
//   "Always allow poc.kcsc.com.jo to open this type of link" → Done.
//   After that, Outlook opens instantly on every subsequent click.
//
// Nginx / base-href note:
//   mailto: is a client-side OS protocol — no server routing involved.
//   The /kashef/ base-href does not affect mailto: behaviour.
// ---------------------------------------------------------------------------
Future<void> sendEmailViaOutlookDesktop({
  required BuildContext context,
  String to = '',
  String subject = '',
  String body = '',
}) async {
  // Maximum encoded body length — stays within 2048-char URI budget.
  const int maxEncodedBody = 1400;

  // Trim raw body until its encoded form fits the budget.
  String trimmedBody = body;
  String encBody     = Uri.encodeComponent(trimmedBody);
  if (encBody.length > maxEncodedBody) {
    // Estimate safe raw limit (Arabic ~6×, Latin ~3×; use 5× as conservative avg).
    int rawLimit = (maxEncodedBody / 5).toInt();
    trimmedBody  = body.length > rawLimit
        ? '${body.substring(0, rawLimit)}\n...(تم الاقتصار — راجع التطبيق للبيانات الكاملة)'
        : body;
    encBody = Uri.encodeComponent(trimmedBody);
  }

  final encTo      = to.isNotEmpty ? Uri.encodeComponent(to) : '';
  final encSubject = Uri.encodeComponent(subject);

  // RFC 6068-compliant URI builder — uses %20, never +.
  String buildUri({bool withBody = true}) {
    final params = [
      if (subject.isNotEmpty)                  'subject=$encSubject',
      if (withBody && trimmedBody.isNotEmpty)  'body=$encBody',
    ];
    final query = params.isNotEmpty ? '?${params.join('&')}' : '';
    return 'mailto:$encTo$query';
  }

  // Try with body → fallback to subject-only (body may still be too long).
  for (final uri in [buildUri(withBody: true), buildUri(withBody: false)]) {
    try {
      // canLaunchUrl returns false for mailto: on web even when supported — skip it.
      await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
      return;
    } catch (_) {}
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
        '⚠️ تعذّر فتح Outlook.\n'
        'تأكد من ضبطه كتطبيق البريد الافتراضي:\n'
        'Settings → Apps → Default Apps → Email → Microsoft Outlook (Classic)',
      ),
      backgroundColor: Colors.red,
      duration: Duration(seconds: 6),
    ));
  }
}

// ---------------------------------------------------------------------------
// Email Button — opens device email app pre-filled with to/subject/body
// ---------------------------------------------------------------------------
// ─────────────────────────────────────────────────────────────────────────────
// Open Document button — rendered when AI embeds <open_document doctype/docname/>
// ─────────────────────────────────────────────────────────────────────────────

class _OpenDocumentButton extends StatelessWidget {
  final String doctype;
  final String docname;
  final VoidCallback? onTap;

  const _OpenDocumentButton({
    required this.doctype,
    required this.docname,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = AppLocalizations.of(context);
    return Material(
      color: c.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.primary.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, color: c.primary, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l.wfOpenDocument,
                      style: TextStyle(
                          color: c.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '$doctype · $docname',
                      style:
                          TextStyle(color: c.textSecondary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new_rounded, color: c.primary, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _EmailButton extends StatelessWidget {
  final String to;
  final String subject;
  final String body;

  const _EmailButton({
    required this.to,
    required this.subject,
    required this.body,
  });

  /// Convert markdown table lines to clean tab-separated plain text.
  static String _cleanBody(String raw) {
    final sepRx = RegExp(r'^[\|\-\:\s]+$');
    final lines = raw.split('\n');
    final out = <String>[];

    for (final line in lines) {
      final t = line.trim();
      // Separator line (|---|---|) → skip
      if (t.startsWith('|') && t.endsWith('|')) {
        final inner = t.substring(1, t.length - 1);
        if (sepRx.hasMatch(inner.replaceAll('|', ''))) continue;
        // Table data line → cells separated by spaces
        final cells = inner
            .split('|')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();
        out.add(cells.join('    '));
      } else {
        out.add(line);
      }
    }
    return out.join('\n').trim();
  }

  Future<void> _openEmail(BuildContext context) async {
    final cleanedBody = _cleanBody(body);

    // RFC 6068 requires %20 for spaces in mailto: URIs.
    // Dart's Uri(queryParameters:{}) uses + (form-encoding) which Outlook rejects.
    // Build the URI string manually with Uri.encodeComponent() instead.
    const int maxEncodedBody = 1400;

    String trimmedBody = cleanedBody;
    String encBody     = Uri.encodeComponent(trimmedBody);
    if (encBody.length > maxEncodedBody) {
      int rawLimit = (maxEncodedBody / 5).toInt();
      trimmedBody  = cleanedBody.length > rawLimit
          ? '${cleanedBody.substring(0, rawLimit)}\n...(تم الاقتصار)'
          : cleanedBody;
      encBody = Uri.encodeComponent(trimmedBody);
    }

    final encTo      = to.isNotEmpty ? Uri.encodeComponent(to) : '';
    final encSubject = Uri.encodeComponent(subject);

    String buildUriStr({bool withBody = true}) {
      final params = [
        if (subject.isNotEmpty)                 'subject=$encSubject',
        if (withBody && trimmedBody.isNotEmpty) 'body=$encBody',
      ];
      final query = params.isNotEmpty ? '?${params.join('&')}' : '';
      return 'mailto:$encTo$query';
    }

    for (final uriStr in [buildUriStr(withBody: true), buildUriStr(withBody: false)]) {
      try {
        final uri = Uri.parse(uriStr);
        // canLaunchUrl returns false for mailto: on web even when supported — skip it.
        final ok = kIsWeb || await canLaunchUrl(uri);
        if (ok) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم يتم العثور على تطبيق بريد على الجهاز'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _openEmail(context),
      icon: const Icon(Icons.email_rounded, size: 14),
      label: Text(
        'إرسال إلى $to',
        style: TextStyle(fontSize: 11),
      ),
      style: TextButton.styleFrom(
        foregroundColor: Colors.lightBlueAccent.withValues(alpha: 0.9),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
