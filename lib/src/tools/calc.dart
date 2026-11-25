/// Hesaplama araçları: hesap makinesi, bilimsel, yüzde/kesir, denklem,
/// grafik, matris/istatistik, Roma rakamı, sayı tabanı.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../expr.dart';

// ------------------------------------------------------------ hesap makinesi

class CalculatorTool extends StatefulWidget {
  final ToolContext t;
  final bool scientific;
  const CalculatorTool(this.t, {super.key, this.scientific = false});

  @override
  State<CalculatorTool> createState() => _CalculatorToolState();
}

class _CalculatorToolState extends State<CalculatorTool> {
  String _expr = '';
  String _preview = '';
  bool _deg = true;
  List<String> _history = [];

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readStrings('history').then((h) {
      if (mounted) setState(() => _history = h);
    });
  }

  void _press(String k) {
    setState(() {
      switch (k) {
        case 'C':
          _expr = '';
        case '⌫':
          if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
        case '=':
          final v = Expr.tryEval(_expr, degrees: _deg);
          if (v != null) {
            final line = '$_expr = ${formatNumber(v, digits: 10)}';
            _history.insert(0, line);
            if (_history.length > 30) _history = _history.sublist(0, 30);
            t.store.writeStrings('history', _history);
            _expr = formatNumber(v, digits: 10);
          }
        default:
          _expr += k;
      }
      final v = Expr.tryEval(_expr, degrees: _deg);
      _preview = v == null || _expr.isEmpty ? '' : formatNumber(v, digits: 10);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    final basic = [
      ['C', '(', ')', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['%', '0', '.', '='],
    ];
    final sci = [
      ['sin(', 'cos(', 'tan(', '^'],
      ['asin(', 'acos(', 'atan(', '√('],
      ['ln(', 'log(', 'π', 'e'],
      ['!', 'abs(', 'exp(', '⌫'],
    ];
    Widget key(String k) {
      final op = '÷×−+=^'.contains(k) && k.length == 1;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: widget.scientific ? 52 : 64,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: k == '='
                    ? s.play
                    : op
                        ? s.accent.withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.08),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => _press(k),
              child: Text(k.replaceAll('(', ''), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
    }

    return ToolList(children: [
      AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SelectableText(_expr.isEmpty ? '0' : _expr,
              textAlign: TextAlign.end, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(_preview, style: TextStyle(color: s.number.withValues(alpha: 0.8), fontSize: 20)),
        ]),
      ),
      if (widget.scientific)
        Choice<bool>(
          values: const [true, false],
          labels: const ['DEG', 'RAD'],
          selected: _deg,
          onChanged: (v) {
            _deg = v;
            _press('');
          },
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(children: [
          if (widget.scientific) for (final r in sci) Row(children: [for (final k in r) key(k)]),
          for (final r in basic) Row(children: [for (final k in r) key(k)]),
          if (!widget.scientific) Row(children: [key('⌫')]),
        ]),
      ),
      if (_history.isNotEmpty) ...[
        AppHeading(L(t, 'history'), icon: Icons.history_rounded),
        for (final h in _history.take(10))
          ListTile(
            dense: true,
            title: Text(h, style: const TextStyle(color: Colors.white70)),
            onTap: () => setState(() => _expr = h.split(' = ').last),
          ),
        TextButton(
          onPressed: () {
            setState(() => _history = []);
            t.store.writeStrings('history', const []);
          },
          child: Text(L(t, 'clear')),
        ),
      ],
    ]);
  }
}

// --------------------------------------------------------- yüzde ve kesir

class PercentTool extends StatefulWidget {
  final ToolContext t;
  const PercentTool(this.t, {super.key});

  @override
  State<PercentTool> createState() => _PercentToolState();
}

class _PercentToolState extends State<PercentTool> {
  final _x = TextEditingController(text: '20');
  final _y = TextEditingController(text: '150');
  final _num = TextEditingController(text: '18');
  final _den = TextEditingController(text: '24');
  final _dec = TextEditingController(text: '0.375');

  @override
  void dispose() {
    for (final c in [_x, _y, _num, _den, _dec]) {
      c.dispose();
    }
    super.dispose();
  }

  static int _gcd(int a, int b) => b == 0 ? a.abs() : _gcd(b, a % b);

  /// Ondalığı kesre çevirir (sürekli kesir).
  static (int, int) _toFraction(double v) {
    var h1 = 1, h0 = 0, k1 = 0, k0 = 1;
    var b = v;
    for (var i = 0; i < 30; i++) {
      final a = b.floor();
      final h2 = a * h1 + h0, k2 = a * k1 + k0;
      h0 = h1;
      h1 = h2;
      k0 = k1;
      k1 = k2;
      if (k1 > 1000000 || (v - h1 / k1).abs() < 1e-10) break;
      final f = b - a;
      if (f.abs() < 1e-12) break;
      b = 1 / f;
    }
    return (h1, k1);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final x = parseNumber(_x.text), y = parseNumber(_y.text);
    String f(double? v) => v == null || v.isNaN || v.isInfinite ? '—' : formatNumber(v, digits: 4);
    final n = int.tryParse(_num.text.trim()), d = int.tryParse(_den.text.trim());
    String simp = '—';
    if (n != null && d != null && d != 0) {
      final g = _gcd(n, d);
      simp = '${n ~/ g}/${d ~/ g} = ${formatNumber(n / d, digits: 6)}';
    }
    final dv = parseNumber(_dec.text);
    String back = '—';
    if (dv != null) {
      final (p, q) = _toFraction(dv);
      back = q == 1 ? '$p' : '$p/$q';
    }
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          Row(children: [
            Expanded(child: AppNumberField(controller: _x, label: 'X', onChanged: (_) => setState(() {}))),
            const SizedBox(width: 10),
            Expanded(child: AppNumberField(controller: _y, label: 'Y', onChanged: (_) => setState(() {}))),
          ]),
          AppResult(
              label: L(t, 'pct_of'), value: f(x == null || y == null ? null : x * y / 100), lang: t.lang),
          AppResult(label: L(t, 'pct_is'), value: '${f(x == null || y == null ? null : x / y * 100)} %', lang: t.lang),
          AppResult(
              label: L(t, 'pct_change'),
              value: '${f(x == null || y == null ? null : (y - x) / x.abs() * 100)} %',
              lang: t.lang),
          AppResult(label: 'Y + X%', value: f(x == null || y == null ? null : y * (1 + x / 100)), lang: t.lang),
          AppResult(label: 'Y − X%', value: f(x == null || y == null ? null : y * (1 - x / 100)), lang: t.lang),
        ]),
      ),
      AppHeading(L(t, 'fraction'), icon: Icons.percent_rounded),
      AppPanel(
        child: Column(children: [
          Row(children: [
            Expanded(
                child: AppNumberField(controller: _num, label: 'a', decimal: false, signed: true, onChanged: (_) => setState(() {}))),
            const Padding(padding: EdgeInsets.all(8), child: Text('/', style: TextStyle(fontSize: 28))),
            Expanded(
                child: AppNumberField(controller: _den, label: 'b', decimal: false, signed: true, onChanged: (_) => setState(() {}))),
          ]),
          AppResult(label: 'a/b', value: simp, lang: t.lang, big: true),
          AppNumberField(controller: _dec, label: '0.x', signed: true, onChanged: (_) => setState(() {})),
          AppResult(label: L(t, 'fraction'), value: back, lang: t.lang, big: true),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------- denklem çözücü

class EquationTool extends StatefulWidget {
  final ToolContext t;
  const EquationTool(this.t, {super.key});

  @override
  State<EquationTool> createState() => _EquationToolState();
}

class _EquationToolState extends State<EquationTool> {
  int _mode = 1;
  final _c = List.generate(6, (i) => TextEditingController(text: ['1', '-3', '2', '1', '1', '5'][i]));

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  double _v(int i) => parseNumber(_c[i].text) ?? 0.0;

  String _fmt(double v) => formatNumber(v, digits: 6);

  List<String> _solve() {
    final t = widget.t;
    switch (_mode) {
      case 0: // ax + b = 0
        final a = _v(0), b = _v(1);
        if (a == 0) return [L(t, b == 0 ? 'infinite' : 'no_solution')];
        return ['x = ${_fmt(-b / a)}'];
      case 1: // ax² + bx + c = 0
        final a = _v(0), b = _v(1), c = _v(2);
        if (a == 0) {
          if (b == 0) return [L(t, c == 0 ? 'infinite' : 'no_solution')];
          return ['x = ${_fmt(-c / b)}'];
        }
        final d = b * b - 4 * a * c;
        if (d > 0) {
          final s = math.sqrt(d);
          return ['Δ = ${_fmt(d)}', 'x₁ = ${_fmt((-b + s) / (2 * a))}', 'x₂ = ${_fmt((-b - s) / (2 * a))}'];
        }
        if (d == 0) return ['Δ = 0', 'x = ${_fmt(-b / (2 * a))}'];
        final re = -b / (2 * a), im = math.sqrt(-d) / (2 * a).abs();
        return ['Δ = ${_fmt(d)}', 'x₁ = ${_fmt(re)} + ${_fmt(im)}i', 'x₂ = ${_fmt(re)} − ${_fmt(im)}i'];
      default: // a1x + b1y = c1 ; a2x + b2y = c2
        final a1 = _v(0), b1 = _v(1), c1 = _v(2), a2 = _v(3), b2 = _v(4), c2 = _v(5);
        final det = a1 * b2 - a2 * b1;
        if (det == 0) {
          final dx = c1 * b2 - c2 * b1, dy = a1 * c2 - a2 * c1;
          return [L(t, dx == 0 && dy == 0 ? 'infinite' : 'no_solution')];
        }
        return ['x = ${_fmt((c1 * b2 - c2 * b1) / det)}', 'y = ${_fmt((a1 * c2 - a2 * c1) / det)}'];
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final labels = [
      ['a', 'b'],
      ['a', 'b', 'c'],
      ['a₁', 'b₁', 'c₁', 'a₂', 'b₂', 'c₂'],
    ][_mode];
    final form = ['ax + b = 0', 'ax² + bx + c = 0', 'a₁x + b₁y = c₁\na₂x + b₂y = c₂'][_mode];
    return ToolList(children: [
      Choice<int>(
        values: const [0, 1, 2],
        labels: [L(t, 'linear'), L(t, 'quadratic'), L(t, 'system2')],
        selected: _mode,
        onChanged: (v) => setState(() => _mode = v),
      ),
      AppPanel(
        child: Column(children: [
          Text(form, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, children: [
            for (var i = 0; i < labels.length; i++)
              SizedBox(
                width: 100,
                child: AppNumberField(controller: _c[i], label: labels[i], signed: true, onChanged: (_) => setState(() {})),
              ),
          ]),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          for (final r in _solve()) AppResult(label: '', value: r, lang: t.lang, big: true),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ grafik

class GraphTool extends StatefulWidget {
  final ToolContext t;
  const GraphTool(this.t, {super.key});

  @override
  State<GraphTool> createState() => _GraphToolState();
}

class _GraphToolState extends State<GraphTool> {
  final _f = TextEditingController(text: 'sin(x)');
  final _g = TextEditingController(text: 'x^2/10');
  double _cx = 0, _cy = 0, _span = 20;
  double _startSpan = 20;

  @override
  void initState() {
    super.initState();
    widget.t.store.read('f').then((v) {
      if (v != null && mounted) setState(() => _f.text = v);
    });
  }

  @override
  void dispose() {
    _f.dispose();
    _g.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    final fs = <(Expr, Color)>[];
    for (final (c, col) in [(_f, s.accent), (_g, Colors.orangeAccent)]) {
      if (c.text.trim().isEmpty) continue;
      try {
        final e = Expr(c.text);
        e.eval(0);
        fs.add((e, col));
      } catch (_) {/* geçersiz ifade çizilmez */}
    }
    return ToolList(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          AppTextField(
              controller: _f,
              label: 'f(x) =',
              onChanged: (v) {
                widget.t.store.write('f', v);
                setState(() {});
              }),
          AppTextField(controller: _g, label: 'g(x) =', onChanged: (_) => setState(() {})),
        ]),
      ),
      AppPanel(
        padding: const EdgeInsets.all(4),
        child: AspectRatio(
          aspectRatio: 1,
          child: GestureDetector(
            onScaleStart: (_) => _startSpan = _span,
            onScaleUpdate: (d) => setState(() {
              _span = (_startSpan / d.scale).clamp(0.01, 1e6);
              final unit = _span / 300;
              _cx -= d.focalPointDelta.dx * unit;
              _cy += d.focalPointDelta.dy * unit;
            }),
            onDoubleTap: () => setState(() {
              _cx = 0;
              _cy = 0;
              _span = 20;
            }),
            child: ClipRect(child: CustomPaint(painter: _GraphPainter(fs, _cx, _cy, _span))),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('x: ${formatNumber(_cx - _span / 2, digits: 2)} … ${formatNumber(_cx + _span / 2, digits: 2)}',
            style: const TextStyle(color: Colors.white60)),
      ),
    ]);
  }
}

class _GraphPainter extends CustomPainter {
  final List<(Expr, Color)> fs;
  final double cx, cy, span;
  _GraphPainter(this.fs, this.cx, this.cy, this.span);

  @override
  void paint(Canvas canvas, Size size) {
    final ppu = size.width / span;
    Offset toPx(double x, double y) => Offset(size.width / 2 + (x - cx) * ppu, size.height / 2 - (y - cy) * ppu);
    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    final step = math.pow(10, (math.log(span / 8) / math.ln10).floor()).toDouble();
    final x0 = cx - span / 2, x1 = cx + span / 2;
    final yHalf = size.height / ppu / 2;
    for (var gx = (x0 / step).floor() * step; gx <= x1; gx += step) {
      final p = toPx(gx, 0).dx;
      canvas.drawLine(Offset(p, 0), Offset(p, size.height), grid);
    }
    for (var gy = ((cy - yHalf) / step).floor() * step; gy <= cy + yHalf; gy += step) {
      final p = toPx(0, gy).dy;
      canvas.drawLine(Offset(0, p), Offset(size.width, p), grid);
    }
    final axis = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.4;
    final o = toPx(0, 0);
    canvas.drawLine(Offset(0, o.dy), Offset(size.width, o.dy), axis);
    canvas.drawLine(Offset(o.dx, 0), Offset(o.dx, size.height), axis);
    for (final (e, col) in fs) {
      final paint = Paint()
        ..color = col
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke;
      final path = Path();
      var pen = false;
      final n = size.width.round() * 2;
      double? prevY;
      for (var i = 0; i <= n; i++) {
        final x = x0 + span * i / n;
        double y;
        try {
          y = e.eval(x);
        } catch (_) {
          y = double.nan;
        }
        if (!y.isFinite || (prevY != null && (y - prevY).abs() > yHalf * 4)) {
          pen = false;
          prevY = y.isFinite ? y : null;
          continue;
        }
        final p = toPx(x, y);
        if (pen) {
          path.lineTo(p.dx, p.dy.clamp(-1e4, 1e4));
        } else {
          path.moveTo(p.dx, p.dy.clamp(-1e4, 1e4));
          pen = true;
        }
        prevY = y;
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}

// ------------------------------------------------ matris ve istatistik

class MatrixTool extends StatefulWidget {
  final ToolContext t;
  const MatrixTool(this.t, {super.key});

  @override
  State<MatrixTool> createState() => _MatrixToolState();
}

class _MatrixToolState extends State<MatrixTool> {
  int _n = 3;
  final _m = List.generate(9, (i) => TextEditingController(text: [2, 1, 0, 1, 3, 1, 0, 1, 4][i].toString()));
  final _data = TextEditingController(text: '4, 8, 15, 16, 23, 42');

  @override
  void dispose() {
    for (final c in _m) {
      c.dispose();
    }
    _data.dispose();
    super.dispose();
  }

  List<List<double>> get _a => [
        for (var r = 0; r < _n; r++) [for (var c = 0; c < _n; c++) parseNumber(_m[r * 3 + c].text) ?? 0.0],
      ];

  static double _det(List<List<double>> a) {
    final n = a.length;
    if (n == 2) return a[0][0] * a[1][1] - a[0][1] * a[1][0];
    return a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) -
        a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
        a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]);
  }

  static List<List<double>>? _inv(List<List<double>> a) {
    final n = a.length;
    final m = [
      for (var r = 0; r < n; r++) [...a[r], for (var c = 0; c < n; c++) r == c ? 1.0 : 0.0],
    ];
    for (var c = 0; c < n; c++) {
      var p = c;
      for (var r = c + 1; r < n; r++) {
        if (m[r][c].abs() > m[p][c].abs()) p = r;
      }
      if (m[p][c].abs() < 1e-12) return null;
      final tmp = m[c];
      m[c] = m[p];
      m[p] = tmp;
      final d = m[c][c];
      for (var k = 0; k < 2 * n; k++) {
        m[c][k] /= d;
      }
      for (var r = 0; r < n; r++) {
        if (r == c) continue;
        final f = m[r][c];
        for (var k = 0; k < 2 * n; k++) {
          m[r][k] -= f * m[c][k];
        }
      }
    }
    return [for (var r = 0; r < n; r++) m[r].sublist(n)];
  }

  Widget _matrix(List<List<double>> m) => Text(
        m.map((r) => r.map((v) => formatNumber(v, digits: 4).padLeft(9)).join(' ')).join('\n'),
        style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 15),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final a = _a;
    final inv = _inv(a);
    final xs = [
      for (final p in _data.text.split(RegExp(r'[\s;,]+')))
        if (parseNumber(p) != null) parseNumber(p)!,
    ];
    final stats = <(String, String)>[];
    if (xs.isNotEmpty) {
      final sorted = [...xs]..sort();
      final n = xs.length;
      final mean = xs.reduce((p, q) => p + q) / n;
      final median = n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
      final varPop = xs.map((v) => (v - mean) * (v - mean)).reduce((p, q) => p + q) / n;
      final varSample = n > 1 ? varPop * n / (n - 1) : 0.0;
      final counts = <double, int>{};
      for (final v in xs) {
        counts[v] = (counts[v] ?? 0) + 1;
      }
      final top = counts.values.reduce(math.max);
      final modes = top > 1 ? [for (final e in counts.entries) if (e.value == top) formatNumber(e.key)] : <String>['—'];
      stats.addAll([
        (L(t, 'count'), '$n'),
        (L(t, 'sum'), formatNumber(xs.reduce((p, q) => p + q))),
        (L(t, 'average'), formatNumber(mean, digits: 4)),
        (L(t, 'median'), formatNumber(median, digits: 4)),
        ('Mod', modes.join(', ')),
        (L(t, 'minimum'), formatNumber(sorted.first)),
        (L(t, 'maximum'), formatNumber(sorted.last)),
        ('σ', formatNumber(math.sqrt(varPop), digits: 4)),
        ('s', formatNumber(math.sqrt(varSample), digits: 4)),
        ('σ²', formatNumber(varPop, digits: 4)),
      ]);
    }
    return ToolList(children: [
      Choice<int>(values: const [2, 3], labels: const ['2×2', '3×3'], selected: _n, onChanged: (v) => setState(() => _n = v)),
      AppPanel(
        child: Column(children: [
          for (var r = 0; r < _n; r++)
            Row(children: [
              for (var c = 0; c < _n; c++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: AppNumberField(
                        controller: _m[r * 3 + c], label: 'a${r + 1}${c + 1}', signed: true, onChanged: (_) => setState(() {})),
                  ),
                ),
            ]),
          AppResult(label: L(t, 'determinant'), value: formatNumber(_det(a), digits: 6), lang: t.lang, big: true),
        ]),
      ),
      AppHeading(L(t, 'inverse')),
      AppPanel(child: inv == null ? Text(L(t, 'no_solution')) : _matrix(inv)),
      AppHeading('Aᵀ'),
      AppPanel(child: _matrix([for (var c = 0; c < _n; c++) [for (var r = 0; r < _n; r++) a[r][c]]])),
      AppHeading(L(t, 'average'), icon: Icons.query_stats_rounded),
      AppPanel(
        child: Column(children: [
          AppTextField(controller: _data, label: L(t, 'numbers_hint'), maxLines: 3, onChanged: (_) => setState(() {})),
          for (final (k, v) in stats) AppResult(label: k, value: v, lang: t.lang),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------ Roma rakamı

String toRoman(int n) {
  if (n <= 0 || n > 3999) return '';
  const v = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const s = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
  final b = StringBuffer();
  for (var i = 0; i < v.length; i++) {
    while (n >= v[i]) {
      b.write(s[i]);
      n -= v[i];
    }
  }
  return b.toString();
}

int? fromRoman(String r) {
  r = r.trim().toUpperCase();
  if (r.isEmpty || !RegExp(r'^[MDCLXVI]+$').hasMatch(r)) return null;
  const m = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100, 'D': 500, 'M': 1000};
  var total = 0;
  for (var i = 0; i < r.length; i++) {
    final a = m[r[i]]!, b = i + 1 < r.length ? m[r[i + 1]]! : 0;
    total += a < b ? -a : a;
  }
  return toRoman(total) == r ? total : null;
}

class RomanTool extends StatefulWidget {
  final ToolContext t;
  const RomanTool(this.t, {super.key});

  @override
  State<RomanTool> createState() => _RomanToolState();
}

class _RomanToolState extends State<RomanTool> {
  final _n = TextEditingController(text: '2026');
  final _r = TextEditingController(text: 'MMXXVI');

  @override
  void dispose() {
    _n.dispose();
    _r.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          AppNumberField(
            controller: _n,
            label: '1 – 3999',
            decimal: false,
            onChanged: (v) => setState(() {
              final n = int.tryParse(v.trim());
              _r.text = n == null ? '' : toRoman(n);
            }),
          ),
          AppTextField(
            controller: _r,
            label: 'I V X L C D M',
            onChanged: (v) => setState(() {
              final n = fromRoman(v);
              _n.text = n?.toString() ?? '';
            }),
          ),
          AppResult(
            label: L(t, 'result'),
            value: _n.text.isEmpty || _r.text.isEmpty ? L(t, 'invalid') : '${_n.text} = ${_r.text}',
            lang: t.lang,
            big: true,
          ),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------- sayı tabanı

class BaseTool extends StatefulWidget {
  final ToolContext t;
  const BaseTool(this.t, {super.key});

  @override
  State<BaseTool> createState() => _BaseToolState();
}

class _BaseToolState extends State<BaseTool> {
  static const _bases = [2, 8, 10, 16];
  static const _names = ['BIN', 'OCT', 'DEC', 'HEX'];
  final _c = List.generate(4, (_) => TextEditingController());
  bool _bad = false;

  @override
  void initState() {
    super.initState();
    _set(BigInt.from(255), -1);
  }

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(BigInt v, int except) {
    for (var i = 0; i < 4; i++) {
      if (i != except) _c[i].text = v.toRadixString(_bases[i]).toUpperCase();
    }
  }

  void _changed(int i, String text) {
    final s = text.trim().replaceAll(' ', '');
    final neg = s.startsWith('-');
    final body = neg ? s.substring(1) : s;
    final ok = body.isNotEmpty && RegExp(_bases[i] == 16 ? r'^[0-9a-fA-F]+$' : '^[0-${_bases[i] - 1}]+\$').hasMatch(body);
    setState(() {
      _bad = !ok && s.isNotEmpty;
      if (ok) {
        final v = BigInt.parse(body, radix: _bases[i]);
        _set(neg ? -v : v, i);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          for (var i = 0; i < 4; i++)
            AppTextField(controller: _c[i], label: '${_names[i]} (${_bases[i]})', onChanged: (v) => _changed(i, v)),
          if (_bad) Text(L(t, 'invalid'), style: const TextStyle(color: Colors.orangeAccent)),
        ]),
      ),
    ]);
  }
}
