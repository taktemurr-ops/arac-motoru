/// Rastgele ve sayaç araçları: zar/yazı-tura/sayı, karar çarkı, sayaç,
/// skor tutucu, rastgele isim ve takım.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';

final math.Random _rng = _secure();

math.Random _secure() {
  try {
    return math.Random.secure();
  } catch (_) {
    return math.Random();
  }
}

// ------------------------------------------------- zar, yazı-tura, sayı

class DiceTool extends StatefulWidget {
  final ToolContext t;
  const DiceTool(this.t, {super.key});

  @override
  State<DiceTool> createState() => _DiceToolState();
}

class _DiceToolState extends State<DiceTool> {
  int _mode = 0;
  int _count = 2;
  List<int> _dice = [3, 5];
  bool? _heads;
  final _min = TextEditingController(text: '1');
  final _max = TextEditingController(text: '100');
  int? _number;
  final List<String> _log = [];

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _go() {
    HapticFeedback.mediumImpact();
    final t = widget.t;
    setState(() {
      switch (_mode) {
        case 0:
          _dice = List.generate(_count, (_) => _rng.nextInt(6) + 1);
          _log.insert(0, '${_dice.join(' + ')} = ${_dice.reduce((a, b) => a + b)}');
        case 1:
          _heads = _rng.nextBool();
          _log.insert(0, L(t, _heads! ? 'heads' : 'tails'));
        default:
          final a = int.tryParse(_min.text.trim()) ?? 1, b = int.tryParse(_max.text.trim()) ?? 100;
          final lo = math.min(a, b), hi = math.max(a, b);
          _number = lo + _rng.nextInt(hi - lo + 1);
          _log.insert(0, '$_number');
      }
      if (_log.length > 20) _log.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final s = AppLook.of(context);
    Widget face(int v) => Container(
          width: 72,
          height: 72,
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: CustomPaint(painter: _DiePainter(v)),
        );
    return ToolList(children: [
      Choice<int>(
        values: const [0, 1, 2],
        labels: [L(t, 'dice'), L(t, 'coin'), L(t, 'number')],
        selected: _mode,
        onChanged: (v) => setState(() => _mode = v),
      ),
      if (_mode == 0) ...[
        Center(child: Wrap(alignment: WrapAlignment.center, children: [for (final d in _dice) face(d)])),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            onPressed: _count > 1 ? () => setState(() => _dice = List.filled(--_count, 1)) : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          Text('$_count', style: const TextStyle(fontSize: 22)),
          IconButton(
            onPressed: _count < 6 ? () => setState(() => _dice = List.filled(++_count, 1)) : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ]),
      ],
      if (_mode == 1)
        Center(
          child: Container(
            width: 160,
            height: 160,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [Color(0xFFFFE082), Color(0xFFFFB300)]),
              boxShadow: [BoxShadow(color: s.accent.withValues(alpha: 0.3), blurRadius: 16)],
            ),
            child: Text(_heads == null ? '?' : L(t, _heads! ? 'heads' : 'tails'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.brown, fontSize: 24, fontWeight: FontWeight.w900)),
          ),
        ),
      if (_mode == 2) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: AppNumberField(controller: _min, label: L(t, 'minimum'), decimal: false, signed: true)),
            const SizedBox(width: 10),
            Expanded(child: AppNumberField(controller: _max, label: L(t, 'maximum'), decimal: false, signed: true)),
          ]),
        ),
        BigReadout(_number?.toString() ?? '—'),
      ],
      Padding(
        padding: const EdgeInsets.all(16),
        child: AppButton(label: L(t, _mode == 2 ? 'generate' : 'roll'), icon: Icons.casino_rounded, onPressed: _go),
      ),
      if (_log.isNotEmpty) AppHeading(L(t, 'history'), icon: Icons.history_rounded),
      for (final l in _log) ListTile(dense: true, title: Text(l, style: const TextStyle(color: Colors.white70))),
    ]);
  }
}

class _DiePainter extends CustomPainter {
  final int v;
  _DiePainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF263238);
    final r = size.width * 0.09;
    double c(double f) => size.width * f;
    final pos = <int, List<Offset>>{
      1: [Offset(c(.5), c(.5))],
      2: [Offset(c(.28), c(.28)), Offset(c(.72), c(.72))],
      3: [Offset(c(.28), c(.28)), Offset(c(.5), c(.5)), Offset(c(.72), c(.72))],
      4: [Offset(c(.28), c(.28)), Offset(c(.72), c(.28)), Offset(c(.28), c(.72)), Offset(c(.72), c(.72))],
      5: [Offset(c(.28), c(.28)), Offset(c(.72), c(.28)), Offset(c(.5), c(.5)), Offset(c(.28), c(.72)), Offset(c(.72), c(.72))],
      6: [
        Offset(c(.28), c(.25)), Offset(c(.72), c(.25)), Offset(c(.28), c(.5)),
        Offset(c(.72), c(.5)), Offset(c(.28), c(.75)), Offset(c(.72), c(.75)),
      ],
    };
    for (final o in pos[v] ?? const <Offset>[]) {
      canvas.drawCircle(o, r, p);
    }
  }

  @override
  bool shouldRepaint(_DiePainter old) => old.v != v;
}

// ------------------------------------------------------------ karar çarkı

class WheelTool extends StatefulWidget {
  final ToolContext t;
  const WheelTool(this.t, {super.key});

  @override
  State<WheelTool> createState() => _WheelToolState();
}

class _WheelToolState extends State<WheelTool> with SingleTickerProviderStateMixin {
  final _opts = TextEditingController();
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  double _from = 0, _to = 0;
  String? _result;

  ToolContext get t => widget.t;

  List<String> get _items => [for (final l in _opts.text.split('\n')) if (l.trim().isNotEmpty) l.trim()];

  @override
  void initState() {
    super.initState();
    t.store.read('options').then((v) {
      if (!mounted) return;
      setState(() => _opts.text = v ?? 'A\nB\nC\nD');
    });
    _a.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _a.dispose();
    _opts.dispose();
    super.dispose();
  }

  Future<void> _spin() async {
    final items = _items;
    if (items.length < 2 || _a.isAnimating) return;
    HapticFeedback.selectionClick();
    final pick = _rng.nextInt(items.length);
    final seg = 2 * math.pi / items.length;
    // Seçilen dilimin ortası üstteki oka gelsin.
    final target = -(pick * seg + seg / 2) - math.pi / 2;
    _from = _to % (2 * math.pi);
    _to = target - 2 * math.pi * (5 + _rng.nextInt(3));
    while (_to > _from - 4 * math.pi) {
      _to -= 2 * math.pi;
    }
    setState(() => _result = null);
    await _a.forward(from: 0);
    if (mounted) setState(() => _result = items[pick]);
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final angle = _from + (_to - _from) * Curves.easeOutCubic.transform(_a.value);
    return ToolList(children: [
      Center(
        child: SizedBox(
          width: 300,
          height: 320,
          child: Stack(alignment: Alignment.topCenter, children: [
            Positioned(
              top: 20,
              child: SizedBox(
                width: 300,
                height: 300,
                child: Transform.rotate(angle: angle, child: CustomPaint(painter: _WheelPainter(items))),
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 52, color: Colors.white),
          ]),
        ),
      ),
      if (_result != null) BigReadout(_result!),
      Padding(
        padding: const EdgeInsets.all(16),
        child: AppButton(label: L(t, 'spin'), icon: Icons.refresh_rounded, onPressed: items.length < 2 ? null : _spin),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppTextField(
          controller: _opts,
          label: L(t, 'options_hint'),
          maxLines: 6,
          onChanged: (v) {
            t.store.write('options', v);
            setState(() {});
          },
        ),
      ),
    ]);
  }
}

class _WheelPainter extends CustomPainter {
  final List<String> items;
  _WheelPainter(this.items);

  static const _colors = [
    Color(0xFF4FC3F7), Color(0xFF81C784), Color(0xFFFFB74D), Color(0xFFBA68C8),
    Color(0xFFE57373), Color(0xFF4DB6AC), Color(0xFFFFD54F), Color(0xFF7986CB),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty) return;
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final seg = 2 * math.pi / items.length;
    for (var i = 0; i < items.length; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * seg, seg, true,
          Paint()..color = _colors[i % _colors.length]);
      final tp = TextPainter(
        text: TextSpan(
            text: items[i].length > 14 ? '${items[i].substring(0, 13)}…' : items[i],
            style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r * 0.8);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i * seg + seg / 2);
      tp.paint(canvas, Offset(r * 0.25, -tp.height / 2));
      canvas.restore();
    }
    canvas.drawCircle(c, r * 0.08, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.items.join('\n') != items.join('\n');
}

// ------------------------------------------------------------------ sayaç

class CounterTool extends StatefulWidget {
  final ToolContext t;
  const CounterTool(this.t, {super.key});

  @override
  State<CounterTool> createState() => _CounterToolState();
}

class _CounterToolState extends State<CounterTool> {
  int _n = 0;
  int _step = 1;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readInt('n').then((v) {
      if (mounted) setState(() => _n = v);
    });
  }

  void _add(int d) {
    HapticFeedback.lightImpact();
    setState(() => _n += d);
    t.store.write('n', '$_n');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    return Column(children: [
      Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _add(_step),
          child: Center(
            child: FittedBox(
              child: Text('$_n', style: TextStyle(color: s.number, fontSize: 160, fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ),
      Choice<int>(values: const [1, 5, 10], labels: const ['+1', '+5', '+10'], selected: _step, onChanged: (v) => setState(() => _step = v)),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => _add(-_step), child: Text('−$_step'))),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                setState(() => _n = 0);
                t.store.write('n', '0');
              },
              child: Text(L(t, 'reset')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: () => _add(_step), child: Text('+$_step'))),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------ skor tutucu

class ScoreTool extends StatefulWidget {
  final ToolContext t;
  const ScoreTool(this.t, {super.key});

  @override
  State<ScoreTool> createState() => _ScoreToolState();
}

class _ScoreToolState extends State<ScoreTool> {
  List<Map<String, Object?>> _p = [];

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readList('players').then((v) {
      if (!mounted) return;
      setState(() => _p = v.isEmpty
          ? [
              {'name': '${L(t, 'player')} 1', 'score': 0},
              {'name': '${L(t, 'player')} 2', 'score': 0},
            ]
          : v);
    });
  }

  void _save() => t.store.writeList('players', _p);

  void _bump(int i, int d) {
    HapticFeedback.selectionClick();
    setState(() => _p[i]['score'] = ((_p[i]['score'] as num?)?.toInt() ?? 0) + d);
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    final best = _p.isEmpty ? 0 : _p.map((e) => (e['score'] as num?)?.toInt() ?? 0).reduce(math.max);
    return ToolList(children: [
      for (var i = 0; i < _p.length; i++)
        AppPanel(
          child: Column(children: [
            Row(children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('p$i${_p.length}'),
                  initialValue: '${_p[i]['name']}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  decoration: const InputDecoration(border: InputBorder.none),
                  onChanged: (v) {
                    _p[i]['name'] = v;
                    _save();
                  },
                ),
              ),
              if (((_p[i]['score'] as num?)?.toInt() ?? 0) == best && best != 0)
                const Icon(Icons.emoji_events_rounded, color: Colors.amber),
              IconButton(
                tooltip: L(t, 'delete'),
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() {
                  _p.removeAt(i);
                  _save();
                }),
              ),
            ]),
            Row(children: [
              for (final d in [-5, -1])
                Expanded(child: OutlinedButton(onPressed: () => _bump(i, d), child: Text('$d'))),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text('${_p[i]['score']}', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: s.number)),
                ),
              ),
              for (final d in [1, 5])
                Expanded(child: FilledButton(onPressed: () => _bump(i, d), child: Text('+$d'))),
            ]),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(L(t, 'add')),
              onPressed: () => setState(() {
                _p.add({'name': '${L(t, 'player')} ${_p.length + 1}', 'score': 0});
                _save();
              }),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(L(t, 'reset')),
              onPressed: () => setState(() {
                for (final p in _p) {
                  p['score'] = 0;
                }
                _save();
              }),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ----------------------------------------------- rastgele isim ve takım

class TeamTool extends StatefulWidget {
  final ToolContext t;
  const TeamTool(this.t, {super.key});

  @override
  State<TeamTool> createState() => _TeamToolState();
}

class _TeamToolState extends State<TeamTool> {
  final _names = TextEditingController();
  int _teams = 2;
  String? _picked;
  List<List<String>> _result = [];

  ToolContext get t => widget.t;

  List<String> get _list => [for (final l in _names.text.split('\n')) if (l.trim().isNotEmpty) l.trim()];

  @override
  void initState() {
    super.initState();
    t.store.read('names').then((v) {
      if (mounted && v != null) setState(() => _names.text = v);
    });
  }

  @override
  void dispose() {
    _names.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return ToolList(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppTextField(
          controller: _names,
          label: '${L(t, 'names_hint')} · ${list.length}',
          maxLines: 8,
          onChanged: (v) {
            t.store.write('names', v);
            setState(() {});
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppButton(
          label: L(t, 'pick_one'),
          icon: Icons.person_search_rounded,
          onPressed: list.isEmpty
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  setState(() => _picked = list[_rng.nextInt(list.length)]);
                },
        ),
      ),
      if (_picked != null) BigReadout(_picked!),
      AppHeading(L(t, 'teams'), icon: Icons.groups_rounded),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
            onPressed: _teams > 2 ? () => setState(() => _teams--) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
        Text('$_teams', style: const TextStyle(fontSize: 22)),
        IconButton(
            onPressed: _teams < 12 ? () => setState(() => _teams++) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppButton(
          label: L(t, 'make_teams'),
          icon: Icons.shuffle_rounded,
          onPressed: list.length < 2
              ? null
              : () => setState(() {
                    final sh = [...list]..shuffle(_rng);
                    _result = List.generate(_teams, (_) => <String>[]);
                    for (var i = 0; i < sh.length; i++) {
                      _result[i % _teams].add(sh[i]);
                    }
                  }),
        ),
      ),
      for (var i = 0; i < _result.length; i++)
        AppPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${L(t, 'teams')} ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            Text(_result[i].join(', '), style: const TextStyle(color: Colors.white70)),
          ]),
        ),
    ]);
  }
}
