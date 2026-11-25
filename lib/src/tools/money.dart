/// Para ve iş: döviz çevirici, maaş net-brüt, kıdem/ihbar tazminatı,
/// not ortalaması.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:studio_core/apps/apps.dart';

import '../common.dart';

// ------------------------------------------------------------------ döviz

/// Avrupa Merkez Bankası günlük referans kurları (Frankfurter üzerinden,
/// anahtarsız). Son başarılı yanıt saklanır; çevrimdışıyken o kullanılır.
class CurrencyTool extends StatefulWidget {
  final ToolContext t;
  const CurrencyTool(this.t, {super.key});

  @override
  State<CurrencyTool> createState() => _CurrencyToolState();
}

class _CurrencyToolState extends State<CurrencyTool> {
  static const _urls = [
    'https://api.frankfurter.dev/v1/latest?base=EUR',
    'https://api.frankfurter.app/latest?from=EUR',
  ];
  static const source = 'European Central Bank (via frankfurter.dev)';
  Map<String, double> _rates = {};
  String? _date;
  bool _cached = false;
  bool _loading = false;
  String _from = 'USD', _to = 'TRY';
  final _amount = TextEditingController(text: '100');

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _from = await t.store.read('from') ?? _from;
    _to = await t.store.read('to') ?? _to;
    final raw = await t.store.read('rates');
    if (raw != null) _apply(raw, cached: true);
    if (mounted) setState(() {});
    await _refresh();
  }

  bool _apply(String raw, {required bool cached}) {
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      final r = (j['rates'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()));
      r['EUR'] = 1.0;
      _rates = r;
      _date = j['date'] as String?;
      _cached = cached;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    for (final u in _urls) {
      try {
        final res = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200 && _apply(res.body, cached: false)) {
          await t.store.write('rates', res.body);
          break;
        }
      } catch (_) {/* sıradaki adres ya da önbellek */}
    }
    if (mounted) setState(() => _loading = false);
  }

  double? _convert(double v) {
    final a = _rates[_from], b = _rates[_to];
    if (a == null || b == null) return null;
    return v / a * b;
  }

  @override
  Widget build(BuildContext context) {
    final codes = _rates.keys.toList()..sort();
    final v = parseNumber(_amount.text);
    final r = v == null ? null : _convert(v);
    return ToolList(children: [
      if (_rates.isEmpty)
        AppInfoCard(_loading ? '…' : L(t, 'no_data'), icon: Icons.cloud_off_rounded)
      else ...[
        AppPanel(
          child: Column(children: [
            AppNumberField(controller: _amount, label: L(t, 'amount'), onChanged: (_) => setState(() {})),
            Row(children: [
              Expanded(
                child: Pick<String>(
                  label: L(t, 'from'),
                  values: codes,
                  text: (c) => c,
                  value: codes.contains(_from) ? _from : codes.first,
                  onChanged: (c) {
                    setState(() => _from = c);
                    t.store.write('from', c);
                  },
                ),
              ),
              IconButton(
                tooltip: L(t, 'swap'),
                icon: const Icon(Icons.swap_horiz_rounded),
                onPressed: () => setState(() {
                  final x = _from;
                  _from = _to;
                  _to = x;
                }),
              ),
              Expanded(
                child: Pick<String>(
                  label: L(t, 'to'),
                  values: codes,
                  text: (c) => c,
                  value: codes.contains(_to) ? _to : codes.first,
                  onChanged: (c) {
                    setState(() => _to = c);
                    t.store.write('to', c);
                  },
                ),
              ),
            ]),
            AppResult(
              label: '${_amount.text} $_from =',
              value: r == null ? '—' : '${formatNumber(r, digits: 4)} $_to',
              lang: t.lang,
              big: true,
            ),
            AppResult(
              label: '1 $_from',
              value: _convert(1) == null ? '—' : '${formatNumber(_convert(1)!, digits: 6)} $_to',
              lang: t.lang,
            ),
          ]),
        ),
        AppPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.tx('as_of', {'date': _date ?? '—'})),
            Text(t.tx('source', {'src': source}), style: const TextStyle(color: Colors.white70)),
            if (_cached) Text(t.tx('offline_cache'), style: const TextStyle(color: Colors.amberAccent)),
          ]),
        ),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: OutlinedButton.icon(
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(L(t, 'refresh')),
        ),
      ),
    ]);
  }
}

// -------------------------------------------------- Türkiye bordro (2026)

/// 2026 Türkiye bordro parametreleri. Kaynak: GİB gelir vergisi tarifesi
/// (GVK md. 103, 2026), SGK prime esas kazanç alt/üst sınırları, damga
/// vergisi oranı. Kullanıcı değiştirebilir; "Varsayılanlara dön" bunlara döner.
class TrPayroll {
  double minWage;
  double sgkRate;
  double unempRate;
  double ceiling;
  double stampRate;
  List<double> limits;
  List<double> rates;

  TrPayroll({
    this.minWage = 33030.00,
    this.sgkRate = 0.14,
    this.unempRate = 0.01,
    this.ceiling = 297270.00,
    this.stampRate = 0.00759,
    List<double>? limits,
    List<double>? rates,
  })  : limits = limits ?? [190000, 400000, 1500000, 5300000],
        rates = rates ?? [0.15, 0.20, 0.27, 0.35, 0.40];

  static const asOf = '2026-01-01';
  static const source = 'GİB 2026 gelir vergisi tarifesi · SGK 2026 PEK sınırları';

  Map<String, Object?> toJson() => {
        'minWage': minWage,
        'sgkRate': sgkRate,
        'unempRate': unempRate,
        'ceiling': ceiling,
        'stampRate': stampRate,
        'limits': limits,
        'rates': rates,
      };

  static TrPayroll fromJson(Map<String, Object?> j) {
    double d(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    List<double>? l(String k) => (j[k] as List?)?.map((e) => (e as num).toDouble()).toList();
    final p = TrPayroll();
    return TrPayroll(
      minWage: d('minWage', p.minWage),
      sgkRate: d('sgkRate', p.sgkRate),
      unempRate: d('unempRate', p.unempRate),
      ceiling: d('ceiling', p.ceiling),
      stampRate: d('stampRate', p.stampRate),
      limits: l('limits') ?? p.limits,
      rates: l('rates') ?? p.rates,
    );
  }

  /// Birikimli matrah için toplam gelir vergisi.
  double taxOn(double cum) {
    var tax = 0.0, prev = 0.0;
    for (var i = 0; i < rates.length; i++) {
      final top = i < limits.length ? limits[i] : double.infinity;
      if (cum <= prev) break;
      tax += (math.min(cum, top) - prev) * rates[i];
      prev = top;
    }
    return tax;
  }

  /// Sabit brüt ücretle bir yılın aylık dökümü.
  List<PayMonth> year(double gross) {
    final out = <PayMonth>[];
    var cum = 0.0, cumMin = 0.0;
    final minBase = minWage * (1 - sgkRate - unempRate);
    for (var m = 1; m <= 12; m++) {
      final base = math.min(gross, ceiling);
      final sgk = base * sgkRate, unemp = base * unempRate;
      final taxable = math.max(0.0, gross - sgk - unemp);
      final tax = taxOn(cum + taxable) - taxOn(cum);
      final minTax = taxOn(cumMin + minBase) - taxOn(cumMin);
      final exempt = math.min(tax, minTax);
      final stamp = math.max(0.0, gross * stampRate - minWage * stampRate);
      cum += taxable;
      cumMin += minBase;
      out.add(PayMonth(m, gross, sgk, unemp, tax, exempt, stamp));
    }
    return out;
  }

  /// [month] ayında [net] ele geçecek brüt (ikili arama).
  double grossFor(double net, int month) {
    var lo = net, hi = net * 3 + 10000;
    for (var i = 0; i < 80; i++) {
      final mid = (lo + hi) / 2;
      if (year(mid)[month - 1].net < net) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }
}

class PayMonth {
  final int month;
  final double gross, sgk, unemp, tax, exempt, stamp;
  const PayMonth(this.month, this.gross, this.sgk, this.unemp, this.tax, this.exempt, this.stamp);
  double get net => gross - sgk - unemp - (tax - exempt) - stamp;
}

String money(double v) {
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final neg = parts[0].startsWith('-');
  final digits = neg ? parts[0].substring(1) : parts[0];
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
    b.write(digits[i]);
  }
  return '${neg ? '-' : ''}$b,${parts[1]} ₺';
}

class SalaryTool extends StatefulWidget {
  final ToolContext t;
  const SalaryTool(this.t, {super.key});

  @override
  State<SalaryTool> createState() => _SalaryToolState();
}

class _SalaryToolState extends State<SalaryTool> {
  TrPayroll _p = TrPayroll();
  bool _toNet = true;
  int _month = 1;
  final _v = TextEditingController(text: '50000');

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readMap('params').then((m) {
      if (m.isNotEmpty && mounted) setState(() => _p = TrPayroll.fromJson(m));
    });
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  Future<void> _editParams() async {
    final fields = <String, TextEditingController>{
      'Asgari ücret (brüt)': TextEditingController(text: _p.minWage.toStringAsFixed(2)),
      'SGK %': TextEditingController(text: (_p.sgkRate * 100).toString()),
      'İşsizlik %': TextEditingController(text: (_p.unempRate * 100).toString()),
      'SGK tavan': TextEditingController(text: _p.ceiling.toStringAsFixed(2)),
      'Damga ‰': TextEditingController(text: (_p.stampRate * 1000).toString()),
      'Dilimler': TextEditingController(text: _p.limits.map((e) => e.toStringAsFixed(0)).join(' ')),
      'Oranlar %': TextEditingController(text: _p.rates.map((e) => formatNumber(e * 100)).join(' ')),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L(t, 'parameters')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in fields.entries) AppTextField(controller: e.value, label: e.key),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, null), child: Text(t.core('cancel'))),
          TextButton(
            onPressed: () {
              setState(() => _p = TrPayroll());
              t.store.writeMap('params', _p.toJson());
              Navigator.pop(c, false);
            },
            child: Text(L(t, 'defaults')),
          ),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.core('ok'))),
        ],
      ),
    );
    if (ok == true) {
      final v = fields.values.toList();
      List<double> nums(String s) => [for (final p in s.trim().split(RegExp(r'\s+'))) if (parseNumber(p) != null) parseNumber(p)!];
      final limits = nums(v[5].text), rates = nums(v[6].text).map((e) => e / 100).toList();
      setState(() {
        _p = TrPayroll(
          minWage: parseNumber(v[0].text) ?? _p.minWage,
          sgkRate: (parseNumber(v[1].text) ?? _p.sgkRate * 100) / 100,
          unempRate: (parseNumber(v[2].text) ?? _p.unempRate * 100) / 100,
          ceiling: parseNumber(v[3].text) ?? _p.ceiling,
          stampRate: (parseNumber(v[4].text) ?? _p.stampRate * 1000) / 1000,
          limits: rates.length == limits.length + 1 ? limits : _p.limits,
          rates: rates.length == limits.length + 1 ? rates : _p.rates,
        );
      });
      await t.store.writeMap('params', _p.toJson());
    }
    for (final c in fields.values) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = parseNumber(_v.text);
    final gross = v == null ? null : (_toNet ? v : _p.grossFor(v, _month));
    final months = gross == null ? <PayMonth>[] : _p.year(gross);
    final sel = months.isEmpty ? null : months[_month - 1];
    final loc = MaterialLocalizations.of(context);
    String monthName(int m) => loc.formatMonthYear(DateTime(2026, m)).split(' ').first;
    return ToolList(children: [
      Choice<bool>(
        values: const [true, false],
        labels: [L(t, 'gross_to_net'), L(t, 'net_to_gross')],
        selected: _toNet,
        onChanged: (b) => setState(() => _toNet = b),
      ),
      AppPanel(
        child: Column(children: [
          AppNumberField(controller: _v, label: L(t, _toNet ? 'gross' : 'net'), suffix: '₺', onChanged: (_) => setState(() {})),
          Pick<int>(
            label: L(t, 'month'),
            values: List.generate(12, (i) => i + 1),
            text: monthName,
            value: _month,
            onChanged: (m) => setState(() => _month = m),
          ),
        ]),
      ),
      if (sel != null)
        AppPanel(
          child: Column(children: [
            AppResult(label: L(t, 'gross'), value: money(sel.gross), lang: t.lang, big: !_toNet),
            AppResult(label: L(t, 'sgk'), value: money(sel.sgk), lang: t.lang),
            AppResult(label: L(t, 'unemployment'), value: money(sel.unemp), lang: t.lang),
            AppResult(label: L(t, 'income_tax'), value: money(sel.tax), lang: t.lang),
            AppResult(label: L(t, 'exemption'), value: '− ${money(sel.exempt)}', lang: t.lang),
            AppResult(label: L(t, 'stamp_tax'), value: money(sel.stamp), lang: t.lang),
            AppResult(label: L(t, 'net'), value: money(sel.net), lang: t.lang, big: _toNet),
          ]),
        ),
      if (months.isNotEmpty) ...[
        AppHeading(L(t, 'annual'), icon: Icons.calendar_month_rounded),
        AppPanel(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: Column(children: [
            for (final m in months)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 90, child: Text(monthName(m.month), style: const TextStyle(color: Colors.white70))),
                  Expanded(child: Text(money(m.net), textAlign: TextAlign.end)),
                ]),
              ),
            const Divider(),
            AppResult(label: '${L(t, 'net')} · ${L(t, 'annual')}', value: money(months.fold(0.0, (a, m) => a + m.net)), lang: t.lang),
          ]),
        ),
      ],
      AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.tx('source', {'src': TrPayroll.source}), style: const TextStyle(color: Colors.white70)),
          Text(t.tx('as_of', {'date': TrPayroll.asOf}), style: const TextStyle(color: Colors.white70)),
          TextButton.icon(onPressed: _editParams, icon: const Icon(Icons.tune_rounded), label: Text(L(t, 'parameters'))),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------- kıdem ve ihbar tazminatı

class SeveranceTool extends StatefulWidget {
  final ToolContext t;
  const SeveranceTool(this.t, {super.key});

  @override
  State<SeveranceTool> createState() => _SeveranceToolState();
}

class _SeveranceToolState extends State<SeveranceTool> {
  /// Kıdem tazminatı tavanları (başlangıç tarihi → tutar). Kaynak: ÇSGB /
  /// memur maaş katsayısı genelgeleri; 2026 ikinci yarı tutarı 73.729,87 ₺.
  static final List<(DateTime, double)> ceilings = [
    (DateTime(2025, 1, 1), 46655.43),
    (DateTime(2025, 7, 1), 53919.68),
    (DateTime(2026, 1, 1), 64948.77),
    (DateTime(2026, 7, 1), 73729.87),
  ];
  static const asOf = '2026-07-01';

  DateTime _start = DateTime(2020, 3, 1);
  DateTime _end = DateTime.now();
  final _gross = TextEditingController(text: '50000');
  final _extras = TextEditingController(text: '0');
  final _ceiling = TextEditingController();
  final _taxRate = TextEditingController(text: '15');

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _ceiling.text = _ceilingFor(_end).toStringAsFixed(2);
  }

  @override
  void dispose() {
    for (final c in [_gross, _extras, _ceiling, _taxRate]) {
      c.dispose();
    }
    super.dispose();
  }

  static double _ceilingFor(DateTime d) {
    var v = ceilings.first.$2;
    for (final (from, amount) in ceilings) {
      if (!d.isBefore(from)) v = amount;
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final days = DateUtils.dateOnly(_end).difference(DateUtils.dateOnly(_start)).inDays + 1;
    final years = days / 365;
    final monthly = (parseNumber(_gross.text) ?? 0.0) + (parseNumber(_extras.text) ?? 0.0);
    final cap = parseNumber(_ceiling.text) ?? _ceilingFor(_end);
    const stampRate = 0.00759;
    final kidemGross = days >= 365 ? math.min(monthly, cap) * years : 0.0;
    final kidemNet = kidemGross * (1 - stampRate);
    final weeks = days < 182 ? 2 : (days < 547 ? 4 : (days < 1095 ? 6 : 8));
    final ihbarGross = monthly / 30 * weeks * 7;
    final taxRate = (parseNumber(_taxRate.text) ?? 15.0) / 100;
    final ihbarNet = ihbarGross * (1 - taxRate - stampRate);
    final (y, m, d) = (days ~/ 365, (days % 365) ~/ 30, (days % 365) % 30);
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          DateRow(label: L(t, 'start_date'), value: _start, onChanged: (v) => setState(() => _start = v)),
          DateRow(
            label: L(t, 'end_date'),
            value: _end,
            onChanged: (v) => setState(() {
              _end = v;
              _ceiling.text = _ceilingFor(v).toStringAsFixed(2);
            }),
          ),
          AppNumberField(controller: _gross, label: '${L(t, 'gross')} (${L(t, 'month')})', suffix: '₺', onChanged: (_) => setState(() {})),
          AppNumberField(controller: _extras, label: L(t, 'extras'), suffix: '₺', onChanged: (_) => setState(() {})),
          AppNumberField(controller: _ceiling, label: L(t, 'ceiling'), suffix: '₺', onChanged: (_) => setState(() {})),
          AppNumberField(controller: _taxRate, label: '${L(t, 'income_tax')} % (${L(t, 'notice')})', onChanged: (_) => setState(() {})),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          AppResult(label: L(t, 'service'), value: '$y ${L(t, 'years')} $m ${L(t, 'months')} $d ${L(t, 'days')}', lang: t.lang),
          AppResult(label: '${L(t, 'severance')} (${L(t, 'gross')})', value: money(kidemGross), lang: t.lang),
          AppResult(label: L(t, 'stamp_tax'), value: money(kidemGross * stampRate), lang: t.lang),
          AppResult(label: '${L(t, 'severance')} (${L(t, 'net')})', value: money(kidemNet), lang: t.lang, big: true),
          const Divider(),
          AppResult(label: '${L(t, 'notice')} ($weeks ${L(t, 'weeks')})', value: money(ihbarGross), lang: t.lang),
          AppResult(label: '${L(t, 'notice')} (${L(t, 'net')})', value: money(ihbarNet), lang: t.lang, big: true),
        ]),
      ),
      AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.tx('source', {'src': '4857 s. İş K. md. 17 · 1475 s. K. md. 14 · ÇSGB tavan genelgesi'}),
              style: const TextStyle(color: Colors.white70)),
          Text(t.tx('as_of', {'date': asOf}), style: const TextStyle(color: Colors.white70)),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------- not ortalaması

class GpaTool extends StatefulWidget {
  final ToolContext t;
  const GpaTool(this.t, {super.key});

  @override
  State<GpaTool> createState() => _GpaToolState();
}

class _GpaToolState extends State<GpaTool> {
  static const _scales = <String, Map<String, double>>{
    '4.0 (AA–FF)': {'AA': 4, 'BA': 3.5, 'BB': 3, 'CB': 2.5, 'CC': 2, 'DC': 1.5, 'DD': 1, 'FD': 0.5, 'FF': 0},
    '4.0 (A–F)': {
      'A': 4, 'A-': 3.7, 'B+': 3.3, 'B': 3, 'B-': 2.7, 'C+': 2.3, 'C': 2, 'C-': 1.7, 'D+': 1.3, 'D': 1, 'F': 0,
    },
    '100': {},
  };
  String _scale = '4.0 (AA–FF)';
  List<Map<String, Object?>> _rows = [];

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _scale = await t.store.read('scale') ?? _scale;
    if (!_scales.containsKey(_scale)) _scale = _scales.keys.first;
    _rows = await t.store.readList('rows');
    if (_rows.isEmpty) {
      _rows = [
        {'name': '1', 'credit': 4.0, 'grade': _scale == '100' ? '85' : _scales[_scale]!.keys.first},
      ];
    }
    if (mounted) setState(() {});
  }

  void _save() {
    t.store.writeList('rows', _rows);
    t.store.write('scale', _scale);
  }

  double? _points(String g) => _scale == '100' ? parseNumber(g) : _scales[_scale]![g];

  @override
  Widget build(BuildContext context) {
    var sum = 0.0, cr = 0.0;
    for (final r in _rows) {
      final c = (r['credit'] as num?)?.toDouble() ?? 0.0;
      final p = _points('${r['grade']}');
      if (p != null && c > 0) {
        sum += p * c;
        cr += c;
      }
    }
    final grades = _scales[_scale]!.keys.toList();
    return ToolList(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Pick<String>(
          label: L(t, 'scale'),
          values: _scales.keys.toList(),
          text: (s) => s,
          value: _scale,
          onChanged: (s) => setState(() {
            _scale = s;
            for (final r in _rows) {
              r['grade'] = s == '100' ? '85' : _scales[s]!.keys.first;
            }
            _save();
          }),
        ),
      ),
      BigReadout(cr == 0 ? '—' : (sum / cr).toStringAsFixed(2), caption: L(t, 'gpa'), unit: '${formatNumber(cr)} ${L(t, 'credit')}'),
      for (var i = 0; i < _rows.length; i++)
        AppPanel(
          child: Row(children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                key: ValueKey('n$i${_rows.length}'),
                initialValue: '${_rows[i]['name'] ?? ''}',
                decoration: InputDecoration(labelText: L(t, 'course')),
                onChanged: (v) {
                  _rows[i]['name'] = v;
                  _save();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextFormField(
                key: ValueKey('c$i${_rows.length}'),
                initialValue: formatNumber((_rows[i]['credit'] as num?)?.toDouble() ?? 0),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: L(t, 'credit')),
                onChanged: (v) => setState(() {
                  _rows[i]['credit'] = parseNumber(v) ?? 0;
                  _save();
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _scale == '100'
                  ? TextFormField(
                      key: ValueKey('g$i${_rows.length}$_scale'),
                      initialValue: '${_rows[i]['grade']}',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: L(t, 'grade')),
                      onChanged: (v) => setState(() {
                        _rows[i]['grade'] = v;
                        _save();
                      }),
                    )
                  : DropdownButton<String>(
                      isExpanded: true,
                      value: grades.contains('${_rows[i]['grade']}') ? '${_rows[i]['grade']}' : grades.first,
                      items: [for (final g in grades) DropdownMenuItem(value: g, child: Text(g))],
                      onChanged: (g) => setState(() {
                        _rows[i]['grade'] = g;
                        _save();
                      }),
                    ),
            ),
            IconButton(
              tooltip: L(t, 'delete'),
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() {
                _rows.removeAt(i);
                _save();
              }),
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: Text(L(t, 'add')),
          onPressed: () => setState(() {
            _rows.add({'name': '${_rows.length + 1}', 'credit': 3.0, 'grade': _scale == '100' ? '85' : grades.first});
            _save();
          }),
        ),
      ),
    ]);
  }
}
