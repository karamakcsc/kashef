import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'app_colors.dart';
import 'app_localizations.dart';
import 'aurora_widgets.dart';
import 'document_viewer_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class _FilterDef {
  final String fieldname;
  final String label;
  final String fieldtype;
  final String? options;
  final bool required;
  final String? defaultValue;

  _FilterDef({
    required this.fieldname,
    required this.label,
    required this.fieldtype,
    this.options,
    required this.required,
    this.defaultValue,
  });

  Map<String, dynamic> toJson() => {
        'fieldname': fieldname,
        'label': label,
        'fieldtype': fieldtype,
        if (options != null) 'options': options,
        'reqd': required ? 1 : 0,
        if (defaultValue != null) 'default': defaultValue,
      };

  factory _FilterDef.fromJson(Map<String, dynamic> j) {
    // options can be a String, a List<String>, or a List<Map> with 'value' key
    String? options;
    final rawOpts = j['options'];
    if (rawOpts is String) {
      options = rawOpts.isEmpty ? null : rawOpts;
    } else if (rawOpts is List) {
      final parts = rawOpts.map((o) {
        if (o is String) return o;
        if (o is Map) return o['value']?.toString() ?? o['label']?.toString() ?? '';
        return o.toString();
      }).where((s) => s.isNotEmpty).toList();
      options = parts.isEmpty ? null : parts.join('\n');
    }

    return _FilterDef(
      fieldname: j['fieldname'] as String? ?? '',
      label: j['label'] as String? ?? j['fieldname'] as String? ?? '',
      fieldtype: j['fieldtype'] as String? ?? 'Data',
      options: options,
      required: j['reqd'] == 1 || j['reqd'] == true || j['reqd'] == '1',
      defaultValue: j['default']?.toString(),
    );
  }
}

class _ColDef {
  final String label;
  final String fieldname;
  final String fieldtype;
  final double width;

  _ColDef(
      {required this.label,
      required this.fieldname,
      required this.fieldtype,
      required this.width});

  factory _ColDef.from(dynamic col) {
    if (col is String) {
      final parts = col.split(':');
      return _ColDef(
        label: parts[0],
        fieldname: parts[0].toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
        fieldtype: parts.length > 1 ? parts[1].split('/').first : 'Data',
        width: parts.length > 2 ? (double.tryParse(parts[2]) ?? 120) : 120,
      );
    }
    if (col is Map) {
      return _ColDef(
        label: col['label'] as String? ?? '',
        fieldname: col['fieldname'] as String? ?? '',
        fieldtype: col['fieldtype'] as String? ?? 'Data',
        width: ((col['width'] as num?) ?? 120).toDouble(),
      );
    }
    return _ColDef(
        label: col.toString(), fieldname: '', fieldtype: 'Data', width: 120);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page widget
// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { loading, form, running, results, error }

class ReportViewPage extends StatefulWidget {
  final String reportName;
  final String reportType;

  const ReportViewPage({
    super.key,
    required this.reportName,
    required this.reportType,
  });

  @override
  State<ReportViewPage> createState() => _ReportViewPageState();
}

class _ReportViewPageState extends State<ReportViewPage> {
  _Phase _phase = _Phase.loading;
  String? _errorMsg;

  List<_FilterDef> _filterDefs = [];
  final Map<String, dynamic> _filterValues = {};
  final _formKey = GlobalKey<FormState>();

  List<_ColDef> _columns = [];
  List<List<dynamic>> _rows = [];

  // ref_doctype — populated after first report fetch; enables row-tap to open
  // DocumentViewerPage when the column 'name' is present in results.
  String _refDoctype = '';

  String _settingsCompany = '';

  // AI config
  String _claudeApiKey  = '';
  String _mcpEndpoint   = 'frappe_assistant_core.api.fac_endpoint.handle_mcp';
  String _claudeModel   = 'claude-sonnet-4-6';
  bool   _aiLoading     = false;
  String _aiStatus      = '';
  int    _mcpId         = 0;
  int    _formGeneration = 0; // incremented to force-rebuild form after AI fill
  String _reportScript  = ''; // cached JS source for AI filter discovery

  @override
  void initState() {
    super.initState();
    _loadFilterDefs();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _authCtx() async {
    final baseUrl = await ApiService.getErpNextUrl();
    final headers = await ApiService.getAuthHeaders();
    final base = Uri.parse(baseUrl);
    return {'baseUrl': baseUrl, 'headers': headers, 'base': base};
  }

  Uri _uri(Uri base, String path, Map<String, String> params) => Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: path,
        queryParameters: params,
      );

  // ── Filter persistence ────────────────────────────────────────────────────

  /// Key for filter VALUES (what the user last entered).
  String get _prefsKey =>
      'report_filters_${widget.reportName.replaceAll(' ', '_')}';

  /// Key for filter DEFINITIONS (structure fetched from server — cached).
  String get _prefsDefsKey =>
      'report_defs_${widget.reportName.replaceAll(' ', '_')}';

  /// Save filter definitions to SharedPreferences.
  Future<void> _saveDefs(List<_FilterDef> defs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsDefsKey, jsonEncode(defs.map((d) => d.toJson()).toList()));
  }

  /// Load cached filter definitions. Returns null if no cache exists.
  Future<List<_FilterDef>?> _loadCachedDefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsDefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final defs = list
          .whereType<Map<String, dynamic>>()
          .map(_FilterDef.fromJson)
          .where((d) => d.fieldname.isNotEmpty)
          .toList();
      return defs.isEmpty ? null : defs;
    } catch (_) {
      return null;
    }
  }

  /// Load previously saved filter values from SharedPreferences and apply
  /// them on top of the current defaults (Company field is always skipped —
  /// it always comes from settings).
  Future<void> _loadSavedFilters() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      saved.forEach((k, v) {
        // Never override Company from saved — always use current settings.
        final def = _filterDefs.firstWhere(
          (d) => d.fieldname == k,
          orElse: () => _FilterDef(
              fieldname: '', label: '', fieldtype: '', required: false),
        );
        if (def.fieldname.isEmpty) return; // field no longer in defs
        if (def.fieldtype == 'Link' && def.options == 'Company') return;
        if (v != null && v.toString().isNotEmpty) {
          _filterValues[k] = v;
        }
      });
    } catch (_) {}
  }

  /// Persist the current filter values to SharedPreferences.
  Future<void> _saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    // Only save non-Company fields
    final toSave = Map<String, dynamic>.fromEntries(
      _filterValues.entries.where((e) {
        final def = _filterDefs.firstWhere(
          (d) => d.fieldname == e.key,
          orElse: () => _FilterDef(
              fieldname: '', label: '', fieldtype: '', required: false),
        );
        if (def.fieldtype == 'Link' && def.options == 'Company') return false;
        final v = e.value;
        if (v == null) return false;
        if (v is List) return v.isNotEmpty;
        return v.toString().isNotEmpty;
      }),
    );
    await prefs.setString(_prefsKey, jsonEncode(toSave));
  }

  // ── Step 1: load filter definitions ───────────────────────────────────────

  /// Apply smart defaults to every filter that has no value yet.
  void _applyDefaults(List<_FilterDef> defs) {
    final now = DateTime.now();
    final yearStart = '${now.year}-01-01';
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    for (final d in defs) {
      if (_filterValues[d.fieldname] != null &&
          _filterValues[d.fieldname].toString().isNotEmpty) { continue; }

      if (d.fieldtype == 'Link' && d.options == 'Company' &&
          _settingsCompany.isNotEmpty) {
        _filterValues[d.fieldname] = _settingsCompany;
      } else if (d.fieldtype == 'Link' && d.options == 'Fiscal Year') {
        _filterValues[d.fieldname] = now.year.toString();
      } else if (d.defaultValue != null && d.defaultValue!.isNotEmpty) {
        _filterValues[d.fieldname] = d.defaultValue;
      } else if (d.fieldtype == 'Select' &&
          d.options != null &&
          d.options!.isNotEmpty) {
        final first = d.options!
            .split('\n')
            .map((s) => s.trim())
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty) _filterValues[d.fieldname] = first;
      } else if (d.fieldtype == 'Date') {
        final fn = d.fieldname.toLowerCase();
        _filterValues[d.fieldname] =
            (fn.contains('from') || fn.contains('start')) ? yearStart : today;
      }
    }
  }

  /// Finish loading: assign defs, restore saved values, update UI.
  Future<void> _finishLoading(List<_FilterDef> defs) async {
    _applyDefaults(defs);
    _filterDefs = defs;
    await _loadSavedFilters();
    setState(() => _phase = _Phase.form);
    if (_claudeApiKey.isNotEmpty) _aiAutoFill();
  }

  Future<void> _loadFilterDefs({bool forceRefresh = false}) async {
    setState(() => _phase = _Phase.loading);

    final prefs = await SharedPreferences.getInstance();
    _settingsCompany = prefs.getString('erpnext_company') ?? '';
    _claudeApiKey    = prefs.getString('claude_api_key')  ?? '';
    _mcpEndpoint     = prefs.getString('ai_endpoint')
        ?? 'frappe_assistant_core.api.fac_endpoint.handle_mcp';
    _claudeModel     = prefs.getString('ai_model') ?? 'claude-sonnet-4-6';

    // ── Use cache when available (skip server round-trip) ──────────────────
    if (!forceRefresh) {
      final cached = await _loadCachedDefs();
      if (cached != null) {
        await _finishLoading(cached);
        return;
      }
    }

    // ── Fetch from server ──────────────────────────────────────────────────
    try {
      final ctx     = await _authCtx();
      final baseUrl = ctx['baseUrl'] as String;
      final headers = ctx['headers'] as Map<String, String>;
      final base    = ctx['base'] as Uri;

      List<_FilterDef>? defs;

      // Try 1: get_script
      final scriptRes = await http
          .get(
            _uri(base, '/api/method/frappe.desk.query_report.get_script',
                {'report_name': widget.reportName}),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      if (scriptRes.statusCode == 200) {
        final msg = jsonDecode(scriptRes.body)['message'];
        if (msg is Map) {
          _reportScript = msg['script'] as String? ?? '';
          defs = _parseFiltersField(msg['filters']);
          if (defs == null || defs.isEmpty) {
            defs = _extractFiltersFromJs(_reportScript);
          }
        } else if (msg is String) {
          _reportScript = msg;
          defs = _extractFiltersFromJs(msg);
        }
      }

      // Try 2: reportview.get_filters_and_columns
      if (defs == null || defs.isEmpty) {
        try {
          final fRes = await http
              .get(
                _uri(base,
                    '/api/method/frappe.desk.reportview.get_filters_and_columns',
                    {'doctype': widget.reportName}),
                headers: headers,
              )
              .timeout(const Duration(seconds: 10));
          if (fRes.statusCode == 200) {
            final fMsg = jsonDecode(fRes.body)['message'];
            if (fMsg is Map) defs = _parseFiltersField(fMsg['filters']);
          }
        } catch (_) {}
      }

      // Try 3: Report doc resource → filters field + ref_doctype for row-tap
      if (defs == null || defs.isEmpty || _refDoctype.isEmpty) {
        final docRes = await http
            .get(
              Uri.parse(
                  '$baseUrl/api/resource/Report/${Uri.encodeComponent(widget.reportName)}'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 10));
        if (docRes.statusCode == 200) {
          final data = jsonDecode(docRes.body)['data'] as Map?;
          if (defs == null || defs.isEmpty) {
            defs = _parseFiltersField(data?['filters']);
          }
          // Capture ref_doctype so tapping a result row opens DocumentViewerPage
          if (_refDoctype.isEmpty) {
            _refDoctype = data?['ref_doctype']?.toString() ?? '';
          }
        }
      }

      defs ??= _fallbackFilters();

      // Save defs to cache for next open
      await _saveDefs(defs);
      await _finishLoading(defs);

      // Show snackbar only when user explicitly refreshed
      if (forceRefresh && mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.filtersRefreshed),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      final fallback = _fallbackFilters();
      await _finishLoading(fallback);
    }
  }

  // ── Extract filter definitions from JavaScript source ─────────────────────
  //
  // Robust field-by-field regex extraction — avoids trying to JSON-parse JS
  // source which may contain unquoted keys, function values, depends_on
  // expressions, and options as arrays.

  List<_FilterDef>? _extractFiltersFromJs(String script) {
    if (script.isEmpty) return null;

    // Find the filters key — handles "filters", 'filters', or unquoted filters:
    int idx = script.indexOf('"filters"');
    if (idx == -1) idx = script.indexOf("'filters'");
    if (idx == -1) {
      // unquoted key:  filters: [
      final m = RegExp(r'\bfilters\s*:').firstMatch(script);
      idx = m?.start ?? -1;
    }
    if (idx == -1) return null;

    final bracketIdx = script.indexOf('[', idx);
    if (bracketIdx == -1) return null;

    // Bracket-match to find the closing ] of the filters array (string-aware).
    // A bare ] inside a string (e.g. in depends_on or label) must not count.
    int depth = 0, end = -1;
    bool inStrArr = false;
    String strCharArr = '';
    for (int i = bracketIdx; i < script.length; i++) {
      final c = script[i];
      if (!inStrArr && (c == '"' || c == "'")) {
        inStrArr = true;
        strCharArr = c;
        continue;
      }
      if (inStrArr) {
        if (c == '\\') { i++; continue; }
        if (c == strCharArr) inStrArr = false;
        continue;
      }
      if (c == '[') depth++;
      if (c == ']') {
        depth--;
        if (depth == 0) { end = i; break; }
      }
    }
    if (end == -1) return null;

    final filtersStr = script.substring(bracketIdx, end + 1);

    // Split into individual top-level { } objects.
    // Skip characters inside strings to avoid false bracket counts.
    final filterObjects = <String>[];
    int objDepth = 0, objStart = -1;
    bool inStr = false;
    String strChar = '';
    for (int i = 0; i < filtersStr.length; i++) {
      final c = filtersStr[i];
      // Toggle string mode (handle escaped quotes)
      if (!inStr && (c == '"' || c == "'")) {
        inStr = true; strChar = c;
        continue;
      }
      if (inStr) {
        if (c == '\\') { i++; continue; } // skip escaped char
        if (c == strChar) inStr = false;
        continue;
      }
      if (c == '{') {
        if (objDepth == 0) objStart = i;
        objDepth++;
      } else if (c == '}') {
        objDepth--;
        if (objDepth == 0 && objStart != -1) {
          filterObjects.add(filtersStr.substring(objStart, i + 1));
          objStart = -1;
        }
      }
    }

    // Extract fields from each object via targeted regex — no JSON parsing
    final defs = <_FilterDef>[];
    for (final obj in filterObjects) {
      final fieldname = _jsStr(obj, 'fieldname');
      if (fieldname == null || fieldname.isEmpty) continue;

      final fieldtype = _jsStr(obj, 'fieldtype');
      if (fieldtype == null || fieldtype.isEmpty) continue;

      final label = _jsStr(obj, 'label') ?? fieldname;
      final options = _jsOptions(obj);
      final reqd = RegExp(r'"?reqd"?\s*:\s*(1|true)\b').hasMatch(obj);
      final defaultVal = _jsStr(obj, 'default');

      defs.add(_FilterDef(
        fieldname: fieldname,
        label: label,
        fieldtype: fieldtype,
        options: options,
        required: reqd,
        defaultValue:
            (defaultVal == null || defaultVal.isEmpty) ? null : defaultVal,
      ));
    }

    return defs.isEmpty ? null : defs;
  }

  /// Extract a plain string value for [key] from a JS object fragment.
  /// Handles double-quotes, single-quotes, and `__("value")` / `__('value')` forms.
  String? _jsStr(String obj, String key) {
    // double-quoted value: "key": "value"  or  "key": __("value")
    final reDq = RegExp('"?$key"?\\s*:\\s*(?:__\\(["\'])?"((?:[^"\\\\]|\\\\.)*)"');
    final mDq = reDq.firstMatch(obj);
    if (mDq != null) return mDq.group(1);
    // single-quoted value: 'key': 'value'  or  'key': __('value')
    final reSq = RegExp('"?$key"?\\s*:\\s*(?:__\\(["\'])?\'((?:[^\'\\\\]|\\\\.)*)\'');
    final mSq = reSq.firstMatch(obj);
    return mSq?.group(1);
  }

  /// Extract the options value from a JS object, handling strings and arrays.
  String? _jsOptions(String obj) {
    // Find "options" key (quoted or unquoted)
    final keyMatch =
        RegExp(r'"?options"?\s*:\s*').firstMatch(obj);
    if (keyMatch == null) return null;

    final afterKey = obj.substring(keyMatch.end);

    // String value: options: "value" or options: 'value'
    final strDq = RegExp(r'^"([^"]*)"').firstMatch(afterKey);
    if (strDq != null) return strDq.group(1);
    final strSq = RegExp("^'([^']*)'").firstMatch(afterKey);
    if (strSq != null) return strSq.group(1);

    // Array value: use bracket matching to handle nested [] correctly
    if (afterKey.startsWith('[')) {
      int depth = 0, end = -1;
      for (int i = 0; i < afterKey.length; i++) {
        if (afterKey[i] == '[') depth++;
        if (afterKey[i] == ']') {
          depth--;
          if (depth == 0) { end = i; break; }
        }
      }
      if (end == -1) return null;
      final content = afterKey.substring(1, end);

      // Array of objects: [{value:"X",...}, ...]
      final valMatches =
          RegExp(r'"?value"?\s*:\s*"([^"]+)"').allMatches(content);
      if (valMatches.isNotEmpty) {
        return valMatches.map((m) => m.group(1)!).join('\n');
      }
      // Array of plain strings: ["X","Y"] or ['X','Y']
      final dqMatches = RegExp(r'"([^"]+)"').allMatches(content);
      if (dqMatches.isNotEmpty) {
        return dqMatches.map((m) => m.group(1)!).join('\n');
      }
      final sqMatches = RegExp("'([^']+)'").allMatches(content);
      if (sqMatches.isNotEmpty) {
        return sqMatches.map((m) => m.group(1)!).join('\n');
      }
    }
    return null;
  }

  List<_FilterDef>? _parseFiltersField(dynamic raw) {
    try {
      dynamic parsed = raw is String ? jsonDecode(raw) : raw;
      if (parsed is List) {
        final defs = parsed
            .whereType<Map<String, dynamic>>()
            .where((f) => f.containsKey('fieldtype'))
            .map(_FilterDef.fromJson)
            .where((f) => f.fieldname.isNotEmpty)
            .toList();
        return defs.isEmpty ? null : defs;
      }
    } catch (_) {}
    return null;
  }

  List<_FilterDef> _fallbackFilters() {
    final now = DateTime.now();
    final firstDay =
        '${now.year}-01-01';
    final lastDay =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    return [
      _FilterDef(
          fieldname: 'company',
          label: 'Company',
          fieldtype: 'Link',
          options: 'Company',
          required: true,
          defaultValue: _settingsCompany.isNotEmpty ? _settingsCompany : null),
      _FilterDef(
          fieldname: 'from_date',
          label: 'From Date',
          fieldtype: 'Date',
          required: false,
          defaultValue: firstDay),
      _FilterDef(
          fieldname: 'to_date',
          label: 'To Date',
          fieldtype: 'Date',
          required: false,
          defaultValue: lastDay),
    ];
  }

  // ── Step 2: run report ────────────────────────────────────────────────────

  /// Convert a snake_case fieldname to a Title Case label.
  String _toLabel(String fn) => fn
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  /// Ensure a Date field is present in both _filterDefs and _filterValues.
  void _ensureDate(String fn, String defaultVal) {
    if (!(_filterValues[fn]?.toString().isNotEmpty ?? false)) {
      _filterValues[fn] = defaultVal;
    }
    if (!_filterDefs.any((d) => d.fieldname == fn)) {
      _filterDefs = List.from(_filterDefs)
        ..add(_FilterDef(
          fieldname: fn,
          label: _toLabel(fn),
          fieldtype: 'Date',
          required: true,
          defaultValue: defaultVal,
        ));
    }
  }

  /// Ensure a Link field is present with a given doctype options and default.
  void _ensureLink(String fn, String label, String doctype, String defaultVal) {
    if (!_filterDefs.any((d) => d.fieldname == fn)) {
      _filterDefs = List.from(_filterDefs)
        ..add(_FilterDef(
          fieldname: fn,
          label: label,
          fieldtype: 'Link',
          options: doctype,
          required: true,
          defaultValue: defaultVal,
        ));
    }
    if (!(_filterValues[fn]?.toString().isNotEmpty ?? false)) {
      _filterValues[fn] = defaultVal;
    }
  }

  /// Ensure a Select field is present with a given options string and default.
  void _ensureSelect(String fn, String options, String defaultVal) {
    if (!_filterDefs.any((d) => d.fieldname == fn)) {
      _filterDefs = List.from(_filterDefs)
        ..add(_FilterDef(
          fieldname: fn,
          label: _toLabel(fn),
          fieldtype: 'Select',
          options: options,
          required: true,
          defaultValue: defaultVal,
        ));
    }
    if (!(_filterValues[fn]?.toString().isNotEmpty ?? false)) {
      _filterValues[fn] = defaultVal;
    }
  }

  Future<void> _runReport() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _phase = _Phase.running);

    try {
      final now = DateTime.now();
      final ys = '${now.year}-01-01';
      final td =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // ── Pre-run: fill every known filter that has no value ────────────────
      for (final d in List.from(_filterDefs)) {
        if (d.fieldtype == 'Date') {
          final v = _filterValues[d.fieldname];
          if (v == null || v.toString().isEmpty) {
            final fn = d.fieldname.toLowerCase();
            _filterValues[d.fieldname] =
                (fn.contains('from') || fn.contains('start')) ? ys : td;
          }
        }
        // Every Select must have a value — absent ones cause KeyError: None.
        if (d.fieldtype == 'Select') {
          final v = _filterValues[d.fieldname];
          if ((v == null || v.toString().isEmpty) &&
              d.options != null &&
              d.options!.isNotEmpty) {
            _filterValues[d.fieldname] = d.options!
                .split('\n')
                .firstWhere((s) => s.trim().isNotEmpty, orElse: () => '');
          }
        }
      }

      // ── Pre-run: smart defaults based on filter_based_on ─────────────────
      final fbo = _filterValues['filter_based_on']?.toString() ?? '';
      if (fbo == 'Date Range') {
        // Date Range mode: need period_start_date + period_end_date
        _ensureDate('period_start_date', ys);
        _ensureDate('period_end_date', td);
      } else if (fbo == 'Fiscal Year') {
        // Fiscal Year mode: need fiscal_year link
        if (!(_filterValues['fiscal_year']?.toString().isNotEmpty ?? false)) {
          _filterValues['fiscal_year'] = now.year.toString();
        }
      }

      // Persist filter values so next open restores them.
      await _saveFilters();

      // Remove null / empty values before sending.
      // List values (MultiSelectList) are kept if non-empty.
      final cleanFilters = Map<String, dynamic>.fromEntries(
        _filterValues.entries.where((e) {
          final v = e.value;
          if (v == null) return false;
          if (v is List) return v.isNotEmpty;
          return v.toString().isNotEmpty;
        }),
      );

      final result = await ApiService.post(
        '/api/method/frappe.desk.query_report.run',
        {
          'report_name': widget.reportName,
          'filters': jsonEncode(cleanFilters),
          'report_type': widget.reportType,
          'ignore_prepared_report': 1,
        },
      );

      final msg = (result['message'] as Map<String, dynamic>? ?? {});
      final rawCols = msg['columns'] as List<dynamic>? ?? [];
      final rawRows = msg['result'] as List<dynamic>? ?? [];

      final cols = rawCols.map(_ColDef.from).toList();

      final rows = rawRows
          .where((r) => r != null && r is! String)
          .map<List<dynamic>>((r) {
            if (r is List) return r;
            if (r is Map) {
              return cols.map((c) => r[c.fieldname] ?? '').toList();
            }
            return [];
          })
          .where((r) => r.isNotEmpty)
          .toList();

      setState(() {
        _columns = cols;
        _rows = rows;
        _phase = _Phase.results;
      });
    } catch (e) {
      _handleRunError(e.toString());
    }
  }

  /// Universal error handler — auto-heals known Frappe validation errors by
  /// injecting the missing filter(s) and returning to the form for review.
  void _handleRunError(String errStr) {
    final l = AppLocalizations.of(context);
    bool healed = false;
    String msg = '';

    final now = DateTime.now();
    final ys = '${now.year}-01-01';
    final td =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // ── KeyError: None ─────────────────────────────────────────────────────
    // A Select/Link field was absent from the filter dict on the server.
    if (errStr.contains('KeyError: None') ||
        errStr.contains("KeyError: 'None'")) {
      _ensureSelect(
          'filter_based_on', 'Fiscal Year\nDate Range', 'Date Range');
      _ensureSelect(
          'periodicity', 'Monthly\nQuarterly\nHalf-Yearly\nAnnually', 'Annually');
      // Also ensure date fields for "Date Range" mode
      _ensureDate('period_start_date', ys);
      _ensureDate('period_end_date', td);
      healed = true;
      msg = l.missingFiltersAdded;
    }

    // ── "Start Year and End Year are mandatory" ────────────────────────────
    // Balance Sheet / P&L reports use start_year + end_year (Fiscal Year links).
    else if ((errStr.contains('Start Year') || errStr.contains('start_year')) &&
        errStr.contains('mandatory')) {
      final yearStr = now.year.toString();
      _ensureLink('start_year', 'Start Year', 'Fiscal Year', yearStr);
      _ensureLink('end_year', 'End Year', 'Fiscal Year', yearStr);
      healed = true;
      msg = l.fiscalYearFiltersAdded;
    }

    // ── "From Date and To Date are mandatory" ──────────────────────────────
    // Frappe financial reports throw this when period_start/end_date are absent.
    else if (errStr.contains('From Date') && errStr.contains('mandatory')) {
      _ensureDate('period_start_date', ys);
      _ensureDate('period_end_date', td);
      // Make sure filter_based_on is set to Date Range
      _ensureSelect(
          'filter_based_on', 'Fiscal Year\nDate Range', 'Date Range');
      if (!(_filterValues['filter_based_on']?.toString().isNotEmpty ?? false)) {
        _filterValues['filter_based_on'] = 'Date Range';
      }
      healed = true;
      msg = l.dateFiltersAdded;
    }

    // ── "Missing required filter: <fieldname>" ────────────────────────────
    else {
      final missingMatch =
          RegExp(r'Missing required filter[:\s]+(\w+)').firstMatch(errStr);
      if (missingMatch != null) {
        final fn = missingMatch.group(1)!;
        final fnL = fn.toLowerCase();
        final def = (fnL.contains('from') || fnL.contains('start')) ? ys : td;
        if (!_filterDefs.any((d) => d.fieldname == fn)) {
          _filterDefs = List.from(_filterDefs)
            ..add(_FilterDef(
              fieldname: fn,
              label: _toLabel(fn),
              fieldtype: 'Date',
              required: true,
              defaultValue: def,
            ));
        }
        _filterValues[fn] ??= def;
        healed = true;
        msg = l.missingFilterFound(fn);
      }
    }

    // ── Generic "X is mandatory" ───────────────────────────────────────────
    if (!healed) {
      // e.g. "ValidationError: Company is mandatory"
      //      "period_start_date is mandatory"
      final mandMatch = RegExp(
              r'(?:ValidationError[:\s]+)?(\w[\w\s]*?) (?:is mandatory|is required)',
              caseSensitive: false)
          .firstMatch(errStr);
      if (mandMatch != null) {
        final raw = mandMatch.group(1)!.trim();
        // Convert "Period Start Date" → "period_start_date" if needed
        final fn = raw.toLowerCase().replaceAll(' ', '_');
        final def = (fn.contains('from') || fn.contains('start')) ? ys : td;
        if (!_filterDefs.any((d) => d.fieldname == fn)) {
          _filterDefs = List.from(_filterDefs)
            ..add(_FilterDef(
              fieldname: fn,
              label: raw,
              fieldtype: 'Date',
              required: true,
              defaultValue: def,
            ));
          _filterValues[fn] = def;
          healed = true;
          msg = l.missingFilterFound(fn);
        }
      }
    }

    // ── AttributeError / TypeError — server-side data/tree error ─────────────
    // Can't fix by changing filters; return to form so user can adjust values.
    if (!healed &&
        (errStr.contains('AttributeError') ||
            errStr.contains('TypeError') ||
            errStr.contains('NoneType'))) {
      healed = true;
      msg = l.reportDataError;
    }

    if (healed) {
      setState(() {
        _formGeneration++;
        _phase = _Phase.form;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } else {
      setState(() {
        _errorMsg = errStr;
        _phase = _Phase.error;
      });
    }
  }

  // ── AI Auto-Fill ─────────────────────────────────────────────────────────

  /// One MCP JSON-RPC call to the Frappe server.
  Future<Map<String, dynamic>> _mcpRequest(
      String method, Map<String, dynamic> params) async {
    final baseUrl = await ApiService.getErpNextUrl();
    final headers = await ApiService.getAiAuthHeaders();
    final id = ++_mcpId;

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/method/$_mcpEndpoint'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'method': method,
            'params': params,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('MCP HTTP ${response.statusCode}: ${response.body}');
    }

    final outer = jsonDecode(response.body) as Map<String, dynamic>;
    if (outer.containsKey('exc_type')) {
      throw Exception('Frappe error: ${outer['exception'] ?? response.body}');
    }

    final msg = outer['message'];
    Map<String, dynamic> rpc;
    if (msg is String) {
      rpc = jsonDecode(msg) as Map<String, dynamic>;
    } else if (msg is Map) {
      rpc = Map<String, dynamic>.from(msg);
    } else {
      rpc = outer;
    }
    if (rpc.containsKey('error')) {
      throw Exception(rpc['error']['message']?.toString() ?? rpc['error'].toString());
    }
    return rpc;
  }

  /// Initialize MCP session and return available tools.
  Future<List<Map<String, dynamic>>> _getMcpTools() async {
    try {
      await _mcpRequest('initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'fikra_report', 'version': '1.0'},
      });
    } catch (_) {}
    final res = await _mcpRequest('tools/list', {});
    final toolsList = (res['result'] as Map? ?? {})['tools'] as List? ?? [];
    return toolsList.map((t) => Map<String, dynamic>.from(t as Map)).toList();
  }

  /// Convert MCP tool defs → Claude tools format.
  List<Map<String, dynamic>> _toClaudeTools(List<Map<String, dynamic>> tools) =>
      tools.map((t) => {
            'name': t['name'] as String? ?? '',
            'description': t['description'] as String? ?? '',
            'input_schema': t['inputSchema'] as Map? ??
                {'type': 'object', 'properties': {}},
          }).toList();

  /// Call Claude API with messages + tools.
  Future<Map<String, dynamic>> _callClaude(
      List<Map<String, dynamic>> messages,
      List<Map<String, dynamic>> tools) async {
    final response = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'x-api-key': _claudeApiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': _claudeModel,
            'max_tokens': 2048,
            'system':
                'أنت مساعد ERPNext متخصص في تحديد قيم فلاتر التقارير. '
                'استخدم الأدوات للاستعلام عن البيانات الفعلية من النظام فقط. '
                'أجب دائماً بـ JSON خالص بدون أي نص إضافي.',
            'messages': messages,
            if (tools.isNotEmpty) 'tools': tools,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error']?['message'] ?? 'Claude error ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Execute one MCP tool call.
  Future<String> _executeMcpTool(
      String name, Map<String, dynamic> input) async {
    final res = await _mcpRequest('tools/call', {'name': name, 'arguments': input});
    final content = (res['result'] as Map? ?? {})['content'] as List? ?? [];
    String out = content.isEmpty
        ? (res['result'] ?? '').toString()
        : content.map((c) => (c as Map)['text']?.toString() ?? '').join('\n');
    if (out.length > 3000) out = out.substring(0, 3000);
    return out;
  }

  /// Use Claude + MCP to discover ALL filter definitions from JS source,
  /// then fill values from live system data.
  Future<void> _aiAutoFill() async {
    if (_claudeApiKey.isEmpty) return;
    final l = AppLocalizations.of(context);

    setState(() {
      _aiLoading = true;
      _aiStatus  = l.aiConnecting;
    });

    try {
      // 1. Get MCP tools
      final mcpTools    = await _getMcpTools();
      final claudeTools = _toClaudeTools(mcpTools);

      if (mcpTools.isEmpty) {
        throw Exception(l.aiNoTools);
      }

      setState(() => _aiStatus = l.aiAnalyzing(mcpTools.length));

      // 2. Build prompt — send JS source so Claude can extract ALL filters
      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final currentFiltersDesc = _filterDefs.map((f) {
        final current = _filterValues[f.fieldname];
        return {
          'fieldname': f.fieldname,
          'label': f.label,
          'fieldtype': f.fieldtype,
          if (f.options != null) 'options': f.options!.split('\n'),
          'required': f.required,
          if (current != null && current.toString().isNotEmpty)
            'current_value': current.toString(),
        };
      }).toList();

      // Truncate JS source to avoid exceeding token limits
      final scriptSnippet = _reportScript.isNotEmpty
          ? (_reportScript.length > 8000
              ? '${_reportScript.substring(0, 8000)}\n...(truncated)'
              : _reportScript)
          : '';

      final scriptSection = scriptSnippet.isNotEmpty
          ? '\n\nكود JavaScript للتقرير — استخدمه لاستخراج جميع الفلاتر:\n```javascript\n$scriptSnippet\n```'
          : '';

      final prompt =
          'أنت مساعد ERPNext متخصص. المستخدم يريد تشغيل التقرير التالي:\n'
          '- اسم التقرير: "${widget.reportName}"\n'
          '- نوع التقرير: "${widget.reportType}"\n'
          '- الشركة: "$_settingsCompany"\n'
          '- التاريخ الحالي: "$todayStr"\n'
          '\n'
          'الفلاتر المكتشفة حتى الآن (قد تكون غير مكتملة):\n'
          '${jsonEncode(currentFiltersDesc)}'
          '$scriptSection\n'
          '\n'
          'المهمة:\n'
          '1. ادرس كود JavaScript للتقرير لاستخراج جميع حقول الفلتر '
          '(fieldname, label, fieldtype, options, reqd, default)\n'
          '2. استخدم الأدوات للاستعلام من النظام عن القيم الفعلية '
          '(شركات، سنوات مالية، عملات، مراكز تكلفة، إلخ)\n'
          '3. لكل حقل Link، اقترح قيمة موجودة فعلاً في النظام\n'
          '4. للتواريخ، استخدم نطاق السنة المالية الحالية\n'
          '5. للحقول من نوع Select، استخدم قيمة من القائمة فقط\n'
          '\n'
          'أرجع JSON فقط بهذا الشكل بالضبط (بدون أي نص إضافي):\n'
          '{\n'
          '  "filters": [\n'
          '    {"fieldname":"...","label":"...","fieldtype":"...","options":"...","reqd":0,"default":"..."},\n'
          '    ...\n'
          '  ],\n'
          '  "values": {\n'
          '    "fieldname": "value",\n'
          '    ...\n'
          '  }\n'
          '}';

      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': prompt}
      ];

      // 3. Agentic loop — Claude queries system then returns filter defs + values
      String finalText = '';

      for (int turn = 0; turn < 12; turn++) {
        final claudeRes = await _callClaude(messages, claudeTools);
        final stopReason = claudeRes['stop_reason'] as String? ?? 'end_turn';
        final content = claudeRes['content'] as List? ?? [];

        messages.add({'role': 'assistant', 'content': content});

        if (stopReason == 'end_turn' || stopReason == 'stop_sequence') {
          for (final block in content) {
            if ((block as Map)['type'] == 'text') {
              finalText += block['text']?.toString() ?? '';
            }
          }
          break;
        }

        if (stopReason == 'tool_use') {
          final toolResults = <Map<String, dynamic>>[];
          for (final block in content) {
            final b = block as Map;
            if (b['type'] != 'tool_use') continue;
            final toolName  = b['name']  as String? ?? '';
            final toolInput = Map<String, dynamic>.from(b['input'] as Map? ?? {});
            final toolUseId = b['id']    as String? ?? '';

            setState(() => _aiStatus = l.aiExecuting(toolName));

            String result;
            bool isError = false;
            try {
              result = await _executeMcpTool(toolName, toolInput);
            } catch (e) {
              result = 'خطأ: $e';
              isError = true;
            }
            toolResults.add({
              'type': 'tool_result',
              'tool_use_id': toolUseId,
              'content': result,
              if (isError) 'is_error': true,
            });
          }
          messages.add({'role': 'user', 'content': toolResults});
          setState(() => _aiStatus = l.aiProcessing);
          continue;
        }
        break;
      }

      // 4. Parse JSON from Claude's reply
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(finalText);
      if (jsonMatch == null) {
        throw Exception(l.aiNoResult);
      }
      final aiResult = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;

      // 5. Update filter DEFINITIONS if AI discovered new/complete set
      final rawAiFilters = aiResult['filters'];
      if (rawAiFilters is List && rawAiFilters.isNotEmpty) {
        final aiDefs = rawAiFilters
            .whereType<Map<String, dynamic>>()
            .where((f) =>
                (f['fieldname'] as String? ?? '').isNotEmpty &&
                (f['fieldtype'] as String? ?? '').isNotEmpty)
            .map((f) {
              // options can be a String or a List from the AI response
              String? opts;
              final rawOpts = f['options'];
              if (rawOpts is String && rawOpts.isNotEmpty) {
                opts = rawOpts;
              } else if (rawOpts is List) {
                opts = rawOpts.map((o) => o.toString()).join('\n');
              }
              return _FilterDef(
                fieldname: f['fieldname'].toString(),
                label: f['label']?.toString() ?? f['fieldname'].toString(),
                fieldtype: f['fieldtype'].toString(),
                options: opts,
                required: f['reqd'] == 1 || f['reqd'] == true || f['reqd'] == '1',
                defaultValue: f['default']?.toString(),
              );
            })
            .toList();

        if (aiDefs.isNotEmpty) {
          // Preserve defaults for newly discovered fields
          final existingNames = _filterDefs.map((f) => f.fieldname).toSet();
          final yearStart = '${now.year}-01-01';
          for (final d in aiDefs) {
            if (existingNames.contains(d.fieldname)) continue;
            // New field — apply sensible default
            if (d.fieldtype == 'Link' &&
                d.options == 'Company' &&
                _settingsCompany.isNotEmpty) {
              _filterValues[d.fieldname] = _settingsCompany;
            } else if (d.defaultValue != null &&
                d.defaultValue!.isNotEmpty) {
              _filterValues[d.fieldname] = d.defaultValue!;
            } else if (d.fieldtype == 'Date') {
              final fn = d.fieldname.toLowerCase();
              _filterValues[d.fieldname] =
                  (fn.contains('from') || fn.contains('start'))
                      ? yearStart
                      : todayStr;
            }
          }
          // Replace defs entirely — AI has the most complete picture
          _filterDefs = aiDefs;
        }
      }

      // 6. Apply values — only for fields in our (now possibly updated) defs
      final rawValues = aiResult['values'] as Map<String, dynamic>? ?? {};
      final knownFields = _filterDefs.map((f) => f.fieldname).toSet();
      rawValues.forEach((k, v) {
        if (knownFields.contains(k) && v != null && v.toString().isNotEmpty) {
          _filterValues[k] = v.toString();
        }
      });

      // 7. Rebuild form with updated defs + values
      setState(() {
        _formGeneration++;
        _aiLoading = false;
        _aiStatus  = '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.aiFilledCount(_filterDefs.length, rawValues.length)),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _aiLoading = false;
        _aiStatus  = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.aiError(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // ── Link-field search ─────────────────────────────────────────────────────

  Future<List<String>> _searchLink(String doctype, String query) async {
    try {
      final ctx = await _authCtx();
      final uri = _uri(
        ctx['base'] as Uri,
        '/api/method/frappe.client.get_list',
        {
          'doctype': doctype,
          'fields': '["name"]',
          'filters': '[["name","like","%$query%"]]',
          'limit': '30',
        },
      );
      final res = await http
          .get(uri, headers: ctx['headers'] as Map<String, String>)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['message'] as List<dynamic>? ?? [];
        return data
            .map((e) => e['name'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: GradientAppBar(
        title: Text(widget.reportName,
            style: const TextStyle(fontSize: 15),
            overflow: TextOverflow.ellipsis),
        actions: [
          if (_phase == _Phase.results)
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white),
              tooltip: AppLocalizations.of(context).changeFilters,
              onPressed: () => setState(() => _phase = _Phase.form),
            ),
          if (_phase == _Phase.form || _phase == _Phase.results)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: AppLocalizations.of(context).refreshFilters,
              onPressed: () => _loadFilterDefs(forceRefresh: true),
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final l = AppLocalizations.of(context);
    switch (_phase) {
      case _Phase.loading:
        return _centeredMessage(
            const CircularProgressIndicator(color: Colors.white),
            l.loadingParams);

      case _Phase.running:
        return _centeredMessage(
            const CircularProgressIndicator(color: Colors.white),
            l.runningReport);

      case _Phase.form:
        return _buildForm();

      case _Phase.results:
        return _buildResults();

      case _Phase.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, color: Colors.white54, size: 48),
              const SizedBox(height: 16),
              Text(_errorMsg ?? l.unknownError,
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => setState(() => _phase = _Phase.form),
                icon: const Icon(Icons.arrow_back),
                label: Text(l.backToFilters),
              ),
            ]),
          ),
        );
    }
  }

  Widget _centeredMessage(Widget indicator, String text) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          indicator,
          const SizedBox(height: 16),
          Text(text,
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      );

  // ── Filter form ───────────────────────────────────────────────────────────

  Widget _buildForm() {
    final l = AppLocalizations.of(context);
    return Stack(
      children: [
        Form(
          key: _formKey,
          child: ListView(
            key: ValueKey(_formGeneration),
            padding: const EdgeInsets.all(16),
            children: [
              // ── Header row: label + AI button ──────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        const Icon(Icons.tune, color: Colors.white54, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          l.reportParams(_filterDefs.length),
                          style: TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: l.aiAutoFillTooltip,
                    child: ElevatedButton.icon(
                      onPressed: _aiLoading ? null : _aiAutoFill,
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('AI', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              ..._filterDefs.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildField(d),
                  )),

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _runReport,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l.runReport),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ],
          ),
        ),

        // ── AI loading overlay ────────────────────────────────────────────
        if (_aiLoading)
          Container(
            color: Colors.black54,
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.of(context).primaryDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.6)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: Colors.deepPurpleAccent, size: 36),
                    const SizedBox(height: 16),
                    Text(
                      l.aiAnalyzingReport,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(
                      backgroundColor: Colors.white12,
                      color: Colors.deepPurpleAccent,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _aiStatus,
                      style: TextStyle(
                          color: Colors.white60, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildField(_FilterDef def) {
    switch (def.fieldtype) {
      case 'Check':
        return _CheckField(def: def, values: _filterValues);
      case 'Select':
        return _SelectField(def: def, values: _filterValues);
      case 'Date':
        return _DateField(def: def, values: _filterValues);
      case 'Link':
        if (def.options == 'Company') {
          return _ReadonlyCompanyField(label: def.label, value: _settingsCompany);
        }
        return _LinkField(
            def: def, values: _filterValues, searchFn: _searchLink);
      case 'MultiSelectList':
      case 'Table MultiSelect':
        return _MultiSelectField(
            def: def, values: _filterValues, searchFn: _searchLink);
      default:
        return _DataField(def: def, values: _filterValues);
    }
  }

  // ── Results ───────────────────────────────────────────────────────────────

  Widget _buildResults() {
    final l = AppLocalizations.of(context);
    if (_rows.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inbox, color: Colors.white38, size: 56),
          const SizedBox(height: 12),
          Text(l.noDataFilters, style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => setState(() => _phase = _Phase.form),
            icon: const Icon(Icons.tune),
            label: Text(l.changeFilters),
          ),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            l.rowColCount(_rows.length, _columns.length),
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildTable(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    return DataTable(
      headingRowColor:
          WidgetStateProperty.all(Colors.white.withValues(alpha: 0.15)),
      dataRowColor:
          WidgetStateProperty.all(Colors.white.withValues(alpha: 0.04)),
      headingTextStyle: TextStyle(
          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      dataTextStyle:
          TextStyle(color: Colors.white70, fontSize: 11),
      columnSpacing: 16,
      dividerThickness: 0.3,
      columns: _columns
          .map((c) => DataColumn(
                label: SizedBox(
                  width: c.width.clamp(80, 220),
                  child: Text(c.label, overflow: TextOverflow.ellipsis),
                ),
              ))
          .toList(),
      rows: _rows.map((row) {
        // Some reports prefix row with indent level (integer)
        final offset =
            (row.isNotEmpty && row[0] is int && _columns.isNotEmpty &&
                    row.length > _columns.length)
                ? 1
                : 0;

        // Determine if this row can navigate to a document:
        // requires a known ref_doctype AND a column named 'name'
        final nameColIdx = _refDoctype.isNotEmpty
            ? _columns.indexWhere((c) => c.fieldname == 'name')
            : -1;
        final docname = nameColIdx >= 0 &&
                (nameColIdx + offset) < row.length
            ? row[nameColIdx + offset]?.toString() ?? ''
            : '';

        return DataRow(
          // Tapping a row opens the document in DocumentViewerPage
          onSelectChanged: docname.isNotEmpty
              ? (_) => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DocumentViewerPage(
                        doctype: _refDoctype,
                        docname: docname,
                      ),
                    ),
                  )
              : null,
          cells: List.generate(_columns.length, (i) {
            final val = (i + offset) < row.length ? row[i + offset] : '';
            return DataCell(
              SizedBox(
                width: _columns[i].width.clamp(80, 220),
                child: Text(
                  _fmt(val, _columns[i].fieldtype),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: row.length > _columns.length &&
                            row[0] is int &&
                            (row[0] as int) == 0
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            );
          }),
        );
      }).toList(),
    );
  }

  String _fmt(dynamic v, String type) {
    if (v == null || v == '' || v == 0 && type == 'Data') return '';
    if (v is num && (type == 'Currency' || type == 'Float' || type == 'Percent')) {
      return v.toStringAsFixed(2);
    }
    return v.toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Field widgets
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _dec(String label, bool req) => InputDecoration(
      labelText: req ? '$label *' : label,
      labelStyle: TextStyle(color: Colors.white60, fontSize: 13),
      enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white30),
          borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white70),
          borderRadius: BorderRadius.circular(8)),
      errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.redAccent),
          borderRadius: BorderRadius.circular(8)),
      focusedErrorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.redAccent),
          borderRadius: BorderRadius.circular(8)),
    );

// ── Text / Number field ───────────────────────────────────────────────────────
class _DataField extends StatelessWidget {
  final _FilterDef def;
  final Map<String, dynamic> values;
  const _DataField({required this.def, required this.values});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: values[def.fieldname]?.toString() ?? def.defaultValue ?? '',
      style: TextStyle(color: Colors.white),
      decoration: _dec(def.label, def.required),
      keyboardType: (def.fieldtype == 'Int' ||
              def.fieldtype == 'Float' ||
              def.fieldtype == 'Currency')
          ? TextInputType.number
          : TextInputType.text,
      validator: def.required
          ? (v) => (v == null || v.isEmpty) ? '${def.label} is required' : null
          : null,
      onChanged: (v) => values[def.fieldname] = v.isEmpty ? null : v,
    );
  }
}

// ── Select field ──────────────────────────────────────────────────────────────
class _SelectField extends StatefulWidget {
  final _FilterDef def;
  final Map<String, dynamic> values;
  const _SelectField({required this.def, required this.values});
  @override
  State<_SelectField> createState() => _SelectFieldState();
}

class _SelectFieldState extends State<_SelectField> {
  late String? _val;
  @override
  void initState() {
    super.initState();
    _val = widget.values[widget.def.fieldname]?.toString() ??
        widget.def.defaultValue;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final opts = (widget.def.options ?? '')
        .split('\n')
        .where((o) => o.isNotEmpty)
        .toList();
    final items = ['', ...opts];
    if (_val != null && !items.contains(_val)) _val = null;

    return DropdownButtonFormField<String>(
      initialValue: _val,
      decoration: _dec(widget.def.label, widget.def.required),
      dropdownColor: AppColors.of(context).primaryDark,
      style: TextStyle(color: Colors.white),
      items: items
          .map((o) => DropdownMenuItem(
              value: o,
              child: Text(o.isEmpty ? l.selectPlaceholder : o)))
          .toList(),
      validator: widget.def.required
          ? (v) => (v == null || v.isEmpty)
              ? '${widget.def.label} ${l.isRequired}'
              : null
          : null,
      onChanged: (v) {
        setState(() => _val = v);
        widget.values[widget.def.fieldname] = v?.isEmpty ?? true ? null : v;
      },
    );
  }
}

// ── Date field ────────────────────────────────────────────────────────────────
class _DateField extends StatefulWidget {
  final _FilterDef def;
  final Map<String, dynamic> values;
  const _DateField({required this.def, required this.values});
  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  final _ctrl = TextEditingController();
  @override
  void initState() {
    super.initState();
    final init = widget.values[widget.def.fieldname]?.toString() ??
        widget.def.defaultValue ??
        '';
    _ctrl.text = init;
    if (init.isNotEmpty) widget.values[widget.def.fieldname] = init;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_ctrl.text) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark(),
        child: child!,
      ),
    );
    if (date != null) {
      final s =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      setState(() => _ctrl.text = s);
      widget.values[widget.def.fieldname] = s;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      readOnly: true,
      style: TextStyle(color: Colors.white),
      decoration: _dec(widget.def.label, widget.def.required).copyWith(
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today,
              color: Colors.white54, size: 18),
          onPressed: _pick,
        ),
      ),
      validator: widget.def.required
          ? (v) =>
              (v == null || v.isEmpty) ? '${widget.def.label} is required' : null
          : null,
      onTap: _pick,
    );
  }
}

// ── Check / Switch field ──────────────────────────────────────────────────────
class _CheckField extends StatefulWidget {
  final _FilterDef def;
  final Map<String, dynamic> values;
  const _CheckField({required this.def, required this.values});
  @override
  State<_CheckField> createState() => _CheckFieldState();
}

class _CheckFieldState extends State<_CheckField> {
  late bool _val;
  @override
  void initState() {
    super.initState();
    final init = widget.values[widget.def.fieldname];
    _val = init == 1 || init == true || init == '1';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SwitchListTile(
        title: Text(widget.def.label,
            style: TextStyle(color: Colors.white, fontSize: 14)),
        value: _val,
        activeThumbColor: AppColors.of(context).primary,
        onChanged: (v) {
          setState(() => _val = v);
          widget.values[widget.def.fieldname] = v ? 1 : 0;
        },
      ),
    );
  }
}

// ── Link field ────────────────────────────────────────────────────────────────
class _LinkField extends StatefulWidget {
  final _FilterDef def;
  final Map<String, dynamic> values;
  final Future<List<String>> Function(String doctype, String query) searchFn;
  const _LinkField(
      {required this.def, required this.values, required this.searchFn});
  @override
  State<_LinkField> createState() => _LinkFieldState();
}

class _LinkFieldState extends State<_LinkField> {
  final _ctrl = TextEditingController();
  @override
  void initState() {
    super.initState();
    final init = widget.values[widget.def.fieldname]?.toString() ??
        widget.def.defaultValue ??
        '';
    _ctrl.text = init;
    if (init.isNotEmpty) widget.values[widget.def.fieldname] = init;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _openSearch() async {
    final doctype = widget.def.options ?? '';
    if (doctype.isEmpty) return;
    final results = await widget.searchFn(doctype, _ctrl.text);
    if (!mounted) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (_) =>
          _SearchDialog(title: 'Select ${widget.def.label}', items: results),
    );
    if (picked != null) {
      setState(() => _ctrl.text = picked);
      widget.values[widget.def.fieldname] = picked;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      style: TextStyle(color: Colors.white),
      decoration: _dec(widget.def.label, widget.def.required).copyWith(
        suffixIcon: IconButton(
          icon: const Icon(Icons.search, color: Colors.white54, size: 18),
          onPressed: _openSearch,
        ),
        hintText: widget.def.options != null ? 'Search ${widget.def.options}…' : null,
        hintStyle: TextStyle(color: Colors.white30, fontSize: 12),
      ),
      validator: widget.def.required
          ? (v) =>
              (v == null || v.isEmpty) ? '${widget.def.label} is required' : null
          : null,
      onChanged: (v) =>
          widget.values[widget.def.fieldname] = v.isEmpty ? null : v,
      onTap: _openSearch,
    );
  }
}

// ── MultiSelect field (MultiSelectList / Table MultiSelect) ──────────────────
class _MultiSelectField extends StatefulWidget {
  final _FilterDef def;
  final Map<String, dynamic> values;
  final Future<List<String>> Function(String doctype, String query) searchFn;
  const _MultiSelectField(
      {required this.def, required this.values, required this.searchFn});
  @override
  State<_MultiSelectField> createState() => _MultiSelectFieldState();
}

class _MultiSelectFieldState extends State<_MultiSelectField> {
  List<String> _selected = [];

  @override
  void initState() {
    super.initState();
    final init = widget.values[widget.def.fieldname];
    if (init is List) {
      _selected = List<String>.from(init.map((e) => e.toString()));
    } else if (init is String && init.isNotEmpty) {
      _selected = init.split('\n').where((s) => s.isNotEmpty).toList();
    }
  }

  void _remove(String value) {
    setState(() => _selected.remove(value));
    widget.values[widget.def.fieldname] =
        _selected.isEmpty ? null : List<String>.from(_selected);
  }

  Future<void> _openSearch() async {
    final opts = widget.def.options ?? '';
    List<String> items;
    // If options looks like a newline-separated list of values, use those.
    // Otherwise treat options as a doctype name and query the server.
    if (opts.contains('\n') || (opts.isNotEmpty && opts.length < 50 && !opts.contains(' '))) {
      if (opts.contains('\n')) {
        items = opts.split('\n').where((s) => s.trim().isNotEmpty).toList();
      } else {
        items = await widget.searchFn(opts, '');
      }
    } else {
      items = opts.isNotEmpty
          ? opts.split('\n').where((s) => s.trim().isNotEmpty).toList()
          : [];
    }
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final picked = await showDialog<String>(
      context: context,
      builder: (_) =>
          _SearchDialog(title: l.selectField(widget.def.label), items: items),
    );
    if (picked != null &&
        picked.isNotEmpty &&
        !_selected.contains(picked)) {
      setState(() => _selected.add(picked));
      widget.values[widget.def.fieldname] = List<String>.from(_selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isReqd = widget.def.required;
    final borderColor =
        isReqd && _selected.isEmpty ? Colors.redAccent.withValues(alpha: 0.6) : Colors.white30;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                isReqd ? '${widget.def.label} *' : widget.def.label,
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ),
            GestureDetector(
              onTap: _openSearch,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add, size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(l.addItem,
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          if (_selected.isEmpty)
            Text(l.noneSelected,
                style: TextStyle(color: Colors.white30, fontSize: 12))
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _selected
                  .map((v) => InputChip(
                        label: Text(v,
                            style: TextStyle(
                                fontSize: 12, color: Colors.white)),
                        backgroundColor:
                            AppColors.of(context).primary.withValues(alpha: 0.35),
                        deleteIconColor: Colors.white60,
                        onDeleted: () => _remove(v),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

// ── Readonly Company field ────────────────────────────────────────────────────
class _ReadonlyCompanyField extends StatelessWidget {
  final String label;
  final String value;
  const _ReadonlyCompanyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.lock_outline, color: Colors.white38, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: Colors.white60, fontSize: 11)),
              const SizedBox(height: 4),
              Text(
                value.isEmpty ? 'Not configured — go to Settings' : value,
                style: TextStyle(
                  color: value.isEmpty ? Colors.white30 : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Search dialog (for Link fields) ──────────────────────────────────────────
class _SearchDialog extends StatefulWidget {
  final String title;
  final List<String> items;
  const _SearchDialog({required this.title, required this.items});
  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final filtered = widget.items
        .where((i) => i.toLowerCase().contains(_q.toLowerCase()))
        .toList();

    return AlertDialog(
      backgroundColor: AppColors.of(context).primaryDark,
      title:
          Text(widget.title, style: TextStyle(color: Colors.white, fontSize: 15)),
      content: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: Column(children: [
          TextField(
            autofocus: true,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '${l.search}…',
              hintStyle: TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white70)),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(l.noResults,
                        style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      title: Text(filtered[i],
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13)),
                      onTap: () => Navigator.pop(context, filtered[i]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}
