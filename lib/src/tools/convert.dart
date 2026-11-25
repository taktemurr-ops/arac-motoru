/// Çeviriciler: birim, mutfak ölçüsü, beden/ayakkabı, lastik, yakıt,
/// elektrik, boya/fayans, takvim (Hicri, Rumi), yaş ve tarih farkı.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';

// ------------------------------------------------------------------ birim

class _Unit {
  final String sym;
  final double f; // temel birime çarpan
  const _Unit(this.sym, this.f);
}

const Map<String, List<_Unit>> _units = {
  'c_length': [
    _Unit('mm', 0.001), _Unit('cm', 0.01), _Unit('m', 1), _Unit('km', 1000), _Unit('in', 0.0254),
    _Unit('ft', 0.3048), _Unit('yd', 0.9144), _Unit('mi', 1609.344), _Unit('nmi', 1852),
  ],
  'c_weight': [
    _Unit('mg', 1e-6), _Unit('g', 0.001), _Unit('kg', 1), _Unit('t', 1000), _Unit('oz', 0.028349523125),
    _Unit('lb', 0.45359237), _Unit('st', 6.35029318),
  ],
  'c_temp': [_Unit('°C', 0), _Unit('°F', 0), _Unit('K', 0)],
  'c_area': [
    _Unit('cm²', 1e-4), _Unit('m²', 1), _Unit('dönüm', 1000), _Unit('ha', 1e4), _Unit('km²', 1e6),
    _Unit('ft²', 0.09290304), _Unit('acre', 4046.8564224), _Unit('mi²', 2589988.110336),
  ],
  'c_volume': [
    _Unit('mL', 1e-6), _Unit('L', 1e-3), _Unit('m³', 1), _Unit('fl oz (US)', 2.95735295625e-5),
    _Unit('cup (US)', 2.365882365e-4), _Unit('pt (US)', 4.73176473e-4), _Unit('gal (US)', 3.785411784e-3),
    _Unit('gal (UK)', 4.54609e-3), _Unit('ft³', 0.028316846592),
  ],
  'c_speed': [
    _Unit('m/s', 1), _Unit('km/h', 1 / 3.6), _Unit('mph', 0.44704), _Unit('kn', 1852 / 3600), _Unit('ft/s', 0.3048),
  ],
  'c_time': [
    _Unit('ms', 0.001), _Unit('s', 1), _Unit('min', 60), _Unit('h', 3600), _Unit('d', 86400), _Unit('wk', 604800),
    _Unit('yr', 31557600),
  ],
  'c_data': [
    _Unit('bit', 0.125), _Unit('B', 1), _Unit('KB', 1e3), _Unit('MB', 1e6), _Unit('GB', 1e9), _Unit('TB', 1e12),
    _Unit('KiB', 1024), _Unit('MiB', 1048576), _Unit('GiB', 1073741824),
  ],
  'c_pressure': [
    _Unit('Pa', 1), _Unit('hPa', 100), _Unit('kPa', 1000), _Unit('bar', 1e5), _Unit('atm', 101325),
    _Unit('psi', 6894.757293168), _Unit('mmHg', 133.322387415),
  ],
  'c_energy': [
    _Unit('J', 1), _Unit('kJ', 1000), _Unit('cal', 4.184), _Unit('kcal', 4184), _Unit('Wh', 3600), _Unit('kWh', 3.6e6),
    _Unit('BTU', 1055.05585262),
  ],
};

double _toKelvin(double v, String u) => u == '°C' ? v + 273.15 : (u == '°F' ? (v - 32) * 5 / 9 + 273.15 : v);
double _fromKelvin(double k, String u) => u == '°C' ? k - 273.15 : (u == '°F' ? (k - 273.15) * 9 / 5 + 32 : k);

class UnitTool extends StatefulWidget {
  final ToolContext t;
  const UnitTool(this.t, {super.key});

  @override
  State<UnitTool> createState() => _UnitToolState();
}

class _UnitToolState extends State<UnitTool> {
  String _cat = 'c_length';
  int _from = 2, _to = 3;
  final _v = TextEditingController(text: '1');

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  double? _convert(double v, _Unit a, _Unit b) {
    if (_cat == 'c_temp') return _fromKelvin(_toKelvin(v, a.sym), b.sym);
    return v * a.f / b.f;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final list = _units[_cat]!;
    final v = parseNumber(_v.text);
    return ToolList(children: [
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          for (final c in _units.keys)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(L(t, c)),
                selected: c == _cat,
                onSelected: (_) => setState(() {
                  _cat = c;
                  _from = 0;
                  _to = math.min<int>(1, _units[c]!.length - 1);
                }),
              ),
            ),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          AppNumberField(controller: _v, label: L(t, 'value'), signed: true, onChanged: (_) => setState(() {})),
          Row(children: [
            Expanded(
              child: Pick<int>(
                label: L(t, 'from'),
                values: List.generate(list.length, (i) => i),
                text: (i) => list[i].sym,
                value: _from,
                onChanged: (i) => setState(() => _from = i),
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
              child: Pick<int>(
                label: L(t, 'to'),
                values: List.generate(list.length, (i) => i),
                text: (i) => list[i].sym,
                value: _to,
                onChanged: (i) => setState(() => _to = i),
              ),
            ),
          ]),
          AppResult(
            label: '${_v.text} ${list[_from].sym} =',
            value: v == null ? '—' : '${formatNumber(_convert(v, list[_from], list[_to])!, digits: 8)} ${list[_to].sym}',
            lang: t.lang,
            big: true,
          ),
        ]),
      ),
      if (v != null)
        AppPanel(
          child: Column(children: [
            for (final u in list)
              if (u != list[_from])
                AppResult(label: u.sym, value: formatNumber(_convert(v, list[_from], u)!, digits: 8), lang: t.lang),
          ]),
        ),
    ]);
  }
}

// ------------------------------------------------------------ mutfak ölçüsü

class KitchenTool extends StatefulWidget {
  final ToolContext t;
  const KitchenTool(this.t, {super.key});

  @override
  State<KitchenTool> createState() => _KitchenToolState();
}

class _KitchenToolState extends State<KitchenTool> {
  // Yoğunluk (g/mL): su, un, toz şeker, tereyağı, pirinç, süt, sıvı yağ, bal.
  static const _density = [1.0, 0.53, 0.85, 0.911, 0.85, 1.03, 0.92, 1.42];
  // mL karşılığı; 6 = gram (kütle), 7 = mL.
  static const _ml = [200.0, 100.0, 15.0, 10.0, 5.0, 240.0, 0.0, 1.0];
  int _ing = 1, _from = 0, _to = 6;
  final _v = TextEditingController(text: '1');

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  double _toGrams(double v, int unit) => unit == 6 ? v : v * _ml[unit] * _density[_ing];
  double _fromGrams(double g, int unit) => unit == 6 ? g : g / (_ml[unit] * _density[_ing]);

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final ing = Ls(t, 'ing_names');
    final units = Ls(t, 'units_kitchen');
    final v = parseNumber(_v.text);
    final g = v == null ? null : _toGrams(v, _from);
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          Pick<int>(
            label: L(t, 'ingredient'),
            values: List.generate(ing.length, (i) => i),
            text: (i) => ing[i],
            value: _ing,
            onChanged: (i) => setState(() => _ing = i),
          ),
          AppNumberField(controller: _v, label: L(t, 'amount'), onChanged: (_) => setState(() {})),
          Pick<int>(
            label: L(t, 'from'),
            values: List.generate(units.length, (i) => i),
            text: (i) => units[i],
            value: _from,
            onChanged: (i) => setState(() => _from = i),
          ),
          Pick<int>(
            label: L(t, 'to'),
            values: List.generate(units.length, (i) => i),
            text: (i) => units[i],
            value: _to,
            onChanged: (i) => setState(() => _to = i),
          ),
          AppResult(
            label: units[_to],
            value: g == null ? '—' : formatNumber(_fromGrams(g, _to), digits: 2),
            lang: t.lang,
            big: true,
          ),
        ]),
      ),
      if (g != null)
        AppPanel(
          child: Column(children: [
            for (var u = 0; u < units.length; u++)
              if (u != _from) AppResult(label: units[u], value: formatNumber(_fromGrams(g, u), digits: 2), lang: t.lang),
          ]),
        ),
      AppInfoCard(L(t, 'approx')),
    ]);
  }
}

// ----------------------------------------------------- beden ve ayakkabı

class SizeTool extends StatefulWidget {
  final ToolContext t;
  const SizeTool(this.t, {super.key});

  @override
  State<SizeTool> createState() => _SizeToolState();
}

class _SizeToolState extends State<SizeTool> {
  int _mode = 0;
  int _row = 5;

  static const _shoeHead = ['EU', 'UK', 'US ♂', 'US ♀', 'cm'];
  static const _shoes = [
    ['35', '2.5', '3.5', '5', '22'],
    ['36', '3.5', '4.5', '6', '22.5'],
    ['37', '4', '5', '6.5', '23.5'],
    ['38', '5', '6', '7.5', '24'],
    ['39', '6', '7', '8.5', '25'],
    ['40', '6.5', '7.5', '9', '25.5'],
    ['41', '7', '8', '9.5', '26'],
    ['42', '8', '9', '10.5', '27'],
    ['43', '9', '10', '11.5', '27.5'],
    ['44', '9.5', '10.5', '12', '28.5'],
    ['45', '10.5', '11.5', '13', '29'],
    ['46', '11', '12', '13.5', '30'],
    ['47', '12', '13', '14.5', '30.5'],
    ['48', '13', '14', '15.5', '31.5'],
  ];
  static const _womenHead = ['EU', 'US', 'UK', 'INT'];
  static const _women = [
    ['32', '0', '4', 'XXS'],
    ['34', '2', '6', 'XS'],
    ['36', '4', '8', 'S'],
    ['38', '6', '10', 'M'],
    ['40', '8', '12', 'M/L'],
    ['42', '10', '14', 'L'],
    ['44', '12', '16', 'XL'],
    ['46', '14', '18', 'XXL'],
    ['48', '16', '20', '3XL'],
  ];
  static const _menHead = ['EU', 'US/UK (in)', 'INT'];
  static const _men = [
    ['44', '34', 'XS'],
    ['46', '36', 'S'],
    ['48', '38', 'M'],
    ['50', '40', 'L'],
    ['52', '42', 'L/XL'],
    ['54', '44', 'XL'],
    ['56', '46', 'XXL'],
    ['58', '48', '3XL'],
  ];

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final s = AppLook.of(context);
    final head = [_shoeHead, _womenHead, _menHead][_mode];
    final rows = [_shoes, _women, _men][_mode];
    final sel = _row.clamp(0, rows.length - 1);
    return ToolList(children: [
      Choice<int>(
        values: const [0, 1, 2],
        labels: [L(t, 'shoes'), '${L(t, 'clothing')} · ${L(t, 'women')}', '${L(t, 'clothing')} · ${L(t, 'men')}'],
        selected: _mode,
        onChanged: (v) => setState(() => _mode = v),
      ),
      AppPanel(
        child: Row(children: [
          for (var i = 0; i < head.length; i++)
            Expanded(
              child: Column(children: [
                Text(head[i], style: const TextStyle(color: Colors.white60)),
                Text(rows[sel][i], style: TextStyle(color: s.number, fontSize: 26, fontWeight: FontWeight.w900)),
              ]),
            ),
        ]),
      ),
      AppPanel(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (var r = 0; r < rows.length; r++)
            InkWell(
              onTap: () => setState(() => _row = r),
              child: Container(
                color: r == sel ? s.accent.withValues(alpha: 0.18) : null,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Row(children: [for (final c in rows[r]) Expanded(child: Text(c, textAlign: TextAlign.center))]),
              ),
            ),
        ]),
      ),
      AppInfoCard(L(t, 'approx')),
    ]);
  }
}

// ------------------------------------------------------------------ lastik

class TireTool extends StatefulWidget {
  final ToolContext t;
  const TireTool(this.t, {super.key});

  @override
  State<TireTool> createState() => _TireToolState();
}

class _TireToolState extends State<TireTool> {
  final _a = [TextEditingController(text: '205'), TextEditingController(text: '55'), TextEditingController(text: '16')];
  final _b = [TextEditingController(text: '225'), TextEditingController(text: '45'), TextEditingController(text: '17')];

  @override
  void dispose() {
    for (final c in [..._a, ..._b]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _diam(List<TextEditingController> c) {
    final w = parseNumber(c[0].text), r = parseNumber(c[1].text), rim = parseNumber(c[2].text);
    if (w == null || r == null || rim == null) return null;
    return rim * 25.4 + 2 * w * r / 100;
  }

  Widget _inputs(List<TextEditingController> c, String title) => AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          Row(children: [
            Expanded(child: AppNumberField(controller: c[0], label: 'mm', onChanged: (_) => setState(() {}))),
            const Text(' / '),
            Expanded(child: AppNumberField(controller: c[1], label: '%', onChanged: (_) => setState(() {}))),
            const Text(' R '),
            Expanded(child: AppNumberField(controller: c[2], label: 'in', onChanged: (_) => setState(() {}))),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final da = _diam(_a), db = _diam(_b);
    String mm(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} mm';
    return ToolList(children: [
      _inputs(_a, L(t, 'current_tire')),
      _inputs(_b, L(t, 'new_tire')),
      AppPanel(
        child: Column(children: [
          AppResult(label: '${L(t, 'diameter')} 1', value: mm(da), lang: t.lang),
          AppResult(label: '${L(t, 'diameter')} 2', value: mm(db), lang: t.lang),
          AppResult(label: 'Δ', value: da == null || db == null ? '—' : '${formatNumber((db - da) / da * 100, digits: 2)} %', lang: t.lang),
          AppResult(label: '⌀ × π (2)', value: mm(db == null ? null : db * math.pi), lang: t.lang),
          AppResult(
            label: L(t, 'speedo'),
            value: da == null || db == null ? '—' : '${(100 * db / da).toStringAsFixed(1)} km/h',
            lang: t.lang,
            big: true,
          ),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------------- yakıt

class FuelTool extends StatefulWidget {
  final ToolContext t;
  const FuelTool(this.t, {super.key});

  @override
  State<FuelTool> createState() => _FuelToolState();
}

class _FuelToolState extends State<FuelTool> {
  final _d = TextEditingController(text: '450');
  final _f = TextEditingController(text: '32');
  final _p = TextEditingController(text: '45');

  @override
  void dispose() {
    _d.dispose();
    _f.dispose();
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final d = parseNumber(_d.text), f = parseNumber(_f.text), p = parseNumber(_p.text);
    final l100 = d == null || f == null || d == 0 ? null : f / d * 100;
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          AppNumberField(controller: _d, label: '${L(t, 'distance')} (km)', onChanged: (_) => setState(() {})),
          AppNumberField(controller: _f, label: L(t, 'fuel_used'), onChanged: (_) => setState(() {})),
          AppNumberField(controller: _p, label: L(t, 'price_l'), onChanged: (_) => setState(() {})),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          AppResult(label: L(t, 'consumption'), value: l100 == null ? '—' : '${l100.toStringAsFixed(2)} L/100 km', lang: t.lang, big: true),
          AppResult(label: 'km/L', value: l100 == null ? '—' : (100 / l100).toStringAsFixed(2), lang: t.lang),
          AppResult(label: 'mpg (US)', value: l100 == null ? '—' : (235.214583 / l100).toStringAsFixed(2), lang: t.lang),
          AppResult(label: 'mpg (UK)', value: l100 == null ? '—' : (282.480936 / l100).toStringAsFixed(2), lang: t.lang),
          AppResult(label: L(t, 'trip_cost'), value: f == null || p == null ? '—' : formatNumber(f * p, digits: 2), lang: t.lang),
          AppResult(
              label: '${L(t, 'trip_cost')} / 100 km',
              value: l100 == null || p == null ? '—' : formatNumber(l100 * p, digits: 2),
              lang: t.lang),
        ]),
      ),
    ]);
  }
}

// ----------------------------------------------------------- elektrik (Ohm)

class OhmTool extends StatefulWidget {
  final ToolContext t;
  const OhmTool(this.t, {super.key});

  @override
  State<OhmTool> createState() => _OhmToolState();
}

class _OhmToolState extends State<OhmTool> {
  final _c = List.generate(4, (_) => TextEditingController());

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  /// V, I, R, P değerlerinden ikisi verildiğinde hepsini bulur.
  static List<double>? solve(double? v, double? i, double? r, double? p) {
    if (v != null && i != null) return [v, i, v / i, v * i];
    if (v != null && r != null) return [v, v / r, r, v * v / r];
    if (v != null && p != null) return [v, p / v, v * v / p, p];
    if (i != null && r != null) return [i * r, i, r, i * i * r];
    if (i != null && p != null) return [p / i, i, p / (i * i), p];
    if (r != null && p != null) return [math.sqrt(p * r), math.sqrt(p / r), r, p];
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final vals = [for (final c in _c) parseNumber(c.text)];
    final given = vals.where((v) => v != null).length;
    final res = given == 2 ? solve(vals[0], vals[1], vals[2], vals[3]) : null;
    final names = [L(t, 'voltage'), L(t, 'current'), L(t, 'resistance'), L(t, 'power')];
    const units = ['V', 'A', 'Ω', 'W'];
    return ToolList(children: [
      AppInfoCard(L(t, 'enter_two'), icon: Icons.electric_bolt_rounded),
      AppPanel(
        child: Column(children: [
          for (var i = 0; i < 4; i++)
            AppNumberField(controller: _c[i], label: names[i], suffix: units[i], onChanged: (_) => setState(() {})),
          TextButton(
            onPressed: () => setState(() {
              for (final c in _c) {
                c.clear();
              }
            }),
            child: Text(L(t, 'clear')),
          ),
        ]),
      ),
      if (res != null)
        AppPanel(
          child: Column(children: [
            for (var i = 0; i < 4; i++)
              AppResult(label: names[i], value: '${formatNumber(res[i], digits: 4)} ${units[i]}', lang: t.lang, big: vals[i] == null),
          ]),
        ),
    ]);
  }
}

// --------------------------------------------------------- boya ve fayans

class PaintTool extends StatefulWidget {
  final ToolContext t;
  const PaintTool(this.t, {super.key});

  @override
  State<PaintTool> createState() => _PaintToolState();
}

class _PaintToolState extends State<PaintTool> {
  int _mode = 0;
  final _w = TextEditingController(text: '4');
  final _h = TextEditingController(text: '2.7');
  final _coats = TextEditingController(text: '2');
  final _cov = TextEditingController(text: '10');
  final _tw = TextEditingController(text: '60');
  final _th = TextEditingController(text: '60');
  final _waste = TextEditingController(text: '10');

  @override
  void dispose() {
    for (final c in [_w, _h, _coats, _cov, _tw, _th, _waste]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final w = parseNumber(_w.text), h = parseNumber(_h.text);
    final area = w == null || h == null ? null : w * h;
    void re(String _) => setState(() {});
    final rows = <Widget>[];
    if (_mode == 0) {
      final coats = parseNumber(_coats.text) ?? 1.0, cov = parseNumber(_cov.text);
      rows.addAll([
        AppNumberField(controller: _coats, label: L(t, 'coats'), onChanged: re),
        AppNumberField(controller: _cov, label: L(t, 'coverage'), onChanged: re),
        AppResult(label: L(t, 'area'), value: area == null ? '—' : '${formatNumber(area, digits: 2)} m²', lang: t.lang),
        AppResult(
          label: L(t, 'paint_needed'),
          value: area == null || cov == null || cov == 0 ? '—' : '${formatNumber(area * coats / cov, digits: 2)} L',
          lang: t.lang,
          big: true,
        ),
      ]);
    } else {
      final tw = parseNumber(_tw.text), th = parseNumber(_th.text), waste = parseNumber(_waste.text) ?? 0.0;
      int? tiles;
      if (area != null && tw != null && th != null && tw > 0 && th > 0) {
        tiles = (area / (tw / 100 * th / 100) * (1 + waste / 100)).ceil();
      }
      rows.addAll([
        Row(children: [
          Expanded(child: AppNumberField(controller: _tw, label: '${L(t, 'tile')} ${L(t, 'width')} (cm)', onChanged: re)),
          const SizedBox(width: 10),
          Expanded(child: AppNumberField(controller: _th, label: '${L(t, 'tile')} ${L(t, 'length')} (cm)', onChanged: re)),
        ]),
        AppNumberField(controller: _waste, label: L(t, 'waste'), onChanged: re),
        AppResult(label: L(t, 'area'), value: area == null ? '—' : '${formatNumber(area, digits: 2)} m²', lang: t.lang),
        AppResult(label: L(t, 'tiles_needed'), value: tiles?.toString() ?? '—', lang: t.lang, big: true),
      ]);
    }
    return ToolList(children: [
      Choice<int>(
          values: const [0, 1], labels: [L(t, 'wall'), L(t, 'floor')], selected: _mode, onChanged: (v) => setState(() => _mode = v)),
      AppPanel(
        child: Column(children: [
          Row(children: [
            Expanded(child: AppNumberField(controller: _w, label: '${L(t, 'width')} (m)', onChanged: re)),
            const SizedBox(width: 10),
            Expanded(
                child: AppNumberField(controller: _h, label: '${L(t, _mode == 0 ? 'height' : 'length')} (m)', onChanged: re)),
          ]),
          ...rows,
        ]),
      ),
    ]);
  }
}

// ----------------------------------------------------- takvim çevirici

int _jdn(int y, int m, int d) {
  final a = (14 - m) ~/ 12;
  final yy = y + 4800 - a, mm = m + 12 * a - 3;
  return d + (153 * mm + 2) ~/ 5 + 365 * yy + yy ~/ 4 - yy ~/ 100 + yy ~/ 400 - 32045;
}

(int, int, int) _fromJdn(int j) {
  final a = j + 32044;
  final b = (4 * a + 3) ~/ 146097;
  final c = a - 146097 * b ~/ 4;
  final d = (4 * c + 3) ~/ 1461;
  final e = c - 1461 * d ~/ 4;
  final m = (5 * e + 2) ~/ 153;
  return (100 * b + d - 4800 + m ~/ 10, m + 3 - 12 * (m ~/ 10), e - (153 * m + 2) ~/ 5 + 1);
}

int _julianJdn(int y, int m, int d) {
  final a = (14 - m) ~/ 12;
  final yy = y + 4800 - a, mm = m + 12 * a - 3;
  return d + (153 * mm + 2) ~/ 5 + 365 * yy + yy ~/ 4 - 32083;
}

(int, int, int) _julianFromJdn(int j) {
  final c = j + 32082;
  final d = (4 * c + 3) ~/ 1461;
  final e = c - 1461 * d ~/ 4;
  final m = (5 * e + 2) ~/ 153;
  return (d - 4800 + m ~/ 10, m + 3 - 12 * (m ~/ 10), e - (153 * m + 2) ~/ 5 + 1);
}

// Tablo usulü Hicri takvim (Kuwait algoritmasıyla aynı aritmetik).
const _islamicEpoch = 1948440;
int _hijriJdn(int y, int m, int d) =>
    d + (29.5 * (m - 1)).ceil() + (y - 1) * 354 + ((3 + 11 * y) / 30).floor() + _islamicEpoch - 1;

(int, int, int) _hijriFromJdn(int j) {
  final y = ((30 * (j - _islamicEpoch) + 10646) / 10631).floor();
  final m = math.min<int>(12, ((j - (29 + _hijriJdn(y, 1, 1))) / 29.5).ceil() + 1);
  final d = j - _hijriJdn(y, m, 1) + 1;
  return (y, m, d);
}

// Rumi: 1917'ye kadar Jülyen gün/ay, sonrasında Miladi gün/ay; yıl Mart'ta başlar.
final int _rumiReform = _jdn(1917, 3, 1);

(int, int, int) _rumiFromJdn(int j) {
  final (y, m, d) = j < _rumiReform ? _julianFromJdn(j) : _fromJdn(j);
  return (m >= 3 ? y - 584 : y - 585, m, d);
}

int _rumiJdn(int ry, int m, int d) {
  final y = m >= 3 ? ry + 584 : ry + 585;
  final g = _jdn(y, m, d);
  return g >= _rumiReform ? g : _julianJdn(y, m, d);
}

class CalendarTool extends StatefulWidget {
  final ToolContext t;
  const CalendarTool(this.t, {super.key});

  @override
  State<CalendarTool> createState() => _CalendarToolState();
}

class _CalendarToolState extends State<CalendarTool> {
  int _src = 0; // 0 Miladi, 1 Hicri, 2 Rumi
  final _c = [TextEditingController(), TextEditingController(), TextEditingController()];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _c[0].text = '${n.day}';
    _c[1].text = '${n.month}';
    _c[2].text = '${n.year}';
  }

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  String _f((int, int, int) v) =>
      '${v.$3.toString().padLeft(2, '0')}.${v.$2.toString().padLeft(2, '0')}.${v.$1}';

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final d = int.tryParse(_c[0].text.trim()), m = int.tryParse(_c[1].text.trim()), y = int.tryParse(_c[2].text.trim());
    int? j;
    if (d != null && m != null && y != null && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      j = switch (_src) {
        0 => _jdn(y, m, d),
        1 => d <= 30 ? _hijriJdn(y, m, d) : null,
        _ => _rumiJdn(y, m, d),
      };
    }
    final names = [L(t, 'gregorian'), L(t, 'hijri'), L(t, 'rumi')];
    String weekday = '';
    if (j != null) {
      final (gy, gm, gd) = _fromJdn(j);
      weekday = MaterialLocalizations.of(context).formatFullDate(DateTime(gy, gm, gd));
    }
    return ToolList(children: [
      Choice<int>(values: const [0, 1, 2], labels: names, selected: _src, onChanged: (v) => setState(() => _src = v)),
      AppPanel(
        child: Row(children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AppNumberField(
                    controller: _c[i], label: ['dd', 'mm', 'yyyy'][i], decimal: false, onChanged: (_) => setState(() {})),
              ),
            ),
        ]),
      ),
      AppPanel(
        child: j == null
            ? Text(L(t, 'invalid'))
            : Column(children: [
                AppResult(label: names[0], value: _f(_fromJdn(j)), lang: t.lang, big: _src != 0),
                AppResult(label: names[1], value: '${_f(_hijriFromJdn(j))} AH', lang: t.lang, big: _src != 1),
                AppResult(label: names[2], value: _f(_rumiFromJdn(j)), lang: t.lang, big: _src != 2),
                Align(alignment: AlignmentDirectional.centerStart, child: Text(weekday, style: const TextStyle(color: Colors.white70))),
              ]),
      ),
      AppInfoCard(L(t, 'hijri_note')),
    ]);
  }
}

// ----------------------------------------------------- yaş ve tarih farkı

/// İki tarih arasındaki yıl, ay, gün farkı.
(int, int, int) dateDiff(DateTime a, DateTime b) {
  if (b.isBefore(a)) {
    final x = a;
    a = b;
    b = x;
  }
  var y = b.year - a.year, m = b.month - a.month, d = b.day - a.day;
  if (d < 0) {
    m -= 1;
    d += DateTime(b.year, b.month, 0).day;
  }
  if (m < 0) {
    y -= 1;
    m += 12;
  }
  return (y, m, d);
}

class AgeTool extends StatefulWidget {
  final ToolContext t;
  const AgeTool(this.t, {super.key});

  @override
  State<AgeTool> createState() => _AgeToolState();
}

class _AgeToolState extends State<AgeTool> {
  DateTime _a = DateTime(2000, 1, 1);
  DateTime _b = DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.t.store.read('birth').then((v) {
      final d = v == null ? null : DateTime.tryParse(v);
      if (d != null && mounted) setState(() => _a = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final a = DateUtils.dateOnly(_a), b = DateUtils.dateOnly(_b);
    final (y, m, d) = dateDiff(a, b);
    final days = b.difference(a).inDays.abs();
    var next = DateTime(b.year, a.month, a.day);
    if (!next.isAfter(b)) next = DateTime(b.year + 1, a.month, a.day);
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          DateRow(
            label: L(t, 'birth'),
            value: _a,
            onChanged: (v) {
              setState(() => _a = v);
              t.store.write('birth', v.toIso8601String());
            },
          ),
          DateRow(label: L(t, 'to'), value: _b, onChanged: (v) => setState(() => _b = v)),
        ]),
      ),
      BigReadout('$y', unit: L(t, 'years'), caption: L(t, 'age')),
      AppPanel(
        child: Column(children: [
          AppResult(label: L(t, 'result'), value: '$y ${L(t, 'years')} $m ${L(t, 'months')} $d ${L(t, 'days')}', lang: t.lang),
          AppResult(label: L(t, 'days'), value: '$days', lang: t.lang),
          AppResult(label: L(t, 'weeks'), value: '${days ~/ 7}', lang: t.lang),
          AppResult(label: L(t, 'months'), value: '${y * 12 + m}', lang: t.lang),
          AppResult(label: L(t, 'hours'), value: '${days * 24}', lang: t.lang),
          AppResult(label: L(t, 'next_birthday'), value: '${next.difference(b).inDays} ${L(t, 'days')}', lang: t.lang),
        ]),
      ),
    ]);
  }
}
