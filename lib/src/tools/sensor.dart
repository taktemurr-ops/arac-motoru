/// Sensör ve ölçüm araçları: pusula, su terazisi, cetvel, GPS hız,
/// rakım, barometre, titreşim, metal dedektörü, açı ölçer.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';

double _deg(double r) => r * 180 / math.pi;

// ------------------------------------------------------------------ pusula

class CompassTool extends StatefulWidget {
  final ToolContext t;
  const CompassTool(this.t, {super.key});

  @override
  State<CompassTool> createState() => _CompassToolState();
}

class _CompassToolState extends State<CompassTool> {
  final _acc = SensorWatch<AccelerometerEvent>();
  final _mag = SensorWatch<MagnetometerEvent>();
  double? _heading;
  double _smooth = 0;

  @override
  void initState() {
    super.initState();
    _acc.start(() => accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval), (_) {}, _changed);
    _mag.start(() => magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval), (_) => _update(), _changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Android getRotationMatrix + getOrientation ile aynı hesap.
  void _update() {
    final a = _acc.last, m = _mag.last;
    if (a == null || m == null) return;
    final ax = a.x, ay = a.y, az = a.z;
    final ex = m.x, ey = m.y, ez = m.z;
    var hx = ey * az - ez * ay, hy = ez * ax - ex * az, hz = ex * ay - ey * ax;
    final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
    if (normH < 0.1) return;
    hx /= normH;
    hy /= normH;
    hz /= normH;
    final normA = math.sqrt(ax * ax + ay * ay + az * az);
    final nx = ax / normA, nz = az / normA;
    final my = nz * hx - nx * hz;
    var h = _deg(math.atan2(hy, my));
    if (h < 0) h += 360;
    // Açısal yumuşatma (359° → 0° geçişinde sıçramaz).
    var diff = h - _smooth;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    _smooth = (_smooth + diff * 0.2) % 360;
    if (_smooth < 0) _smooth += 360;
    setState(() => _heading = _smooth);
  }

  @override
  void dispose() {
    _acc.stop();
    _mag.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (_mag.available == false || _acc.available == false) return ToolList(children: [notAvailable(t)]);
    final h = _heading;
    final names = Ls(t, 'cardinals');
    String dir(double d) {
      const combos = [
        [0], [0, 1], [1], [2, 1], [2], [2, 3], [3], [0, 3],
      ];
      final i = (((d + 22.5) % 360) ~/ 45) % 8;
      return combos[i].map((k) => names[k]).join();
    }

    return ToolList(children: [
      Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: Stack(alignment: Alignment.center, children: [
            Transform.rotate(
              angle: -(h ?? 0) * math.pi / 180,
              child: CustomPaint(size: const Size(300, 300), painter: _DialPainter(names, AppLook.of(context).accent)),
            ),
            const Positioned(top: 0, child: Icon(Icons.arrow_drop_down_rounded, size: 48, color: Colors.redAccent)),
          ]),
        ),
      ),
      BigReadout(h == null ? '…' : '${h.round()}°', caption: h == null ? null : dir(h)),
      AppInfoCard(L(t, 'calib8'), icon: Icons.all_inclusive_rounded),
    ]);
  }
}

class _DialPainter extends CustomPainter {
  final List<String> names;
  final Color accent;
  _DialPainter(this.names, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    canvas.drawCircle(c, r, Paint()..color = Colors.white10);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    for (var d = 0; d < 360; d += 5) {
      final a = d * math.pi / 180 - math.pi / 2;
      final len = d % 30 == 0 ? 16.0 : 8.0;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * r;
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (r - len);
      canvas.drawLine(p1, p2, Paint()..color = d % 90 == 0 ? Colors.white : Colors.white54);
    }
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 - math.pi / 2;
      final tp = TextPainter(
        text: TextSpan(
          text: names[i],
          style: TextStyle(color: i == 0 ? Colors.redAccent : Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = c + Offset(math.cos(a), math.sin(a)) * (r - 40);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) => false;
}

// ------------------------------------------------------------- su terazisi

class LevelTool extends StatefulWidget {
  final ToolContext t;
  const LevelTool(this.t, {super.key});

  @override
  State<LevelTool> createState() => _LevelToolState();
}

class _LevelToolState extends State<LevelTool> {
  final _acc = SensorWatch<AccelerometerEvent>();
  double _x = 0, _y = 0;

  @override
  void initState() {
    super.initState();
    _acc.start(() => accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval), (e) {
      final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (g == 0) return;
      setState(() {
        _x = _x * 0.8 + _deg(math.asin((e.x / g).clamp(-1.0, 1.0))) * 0.2;
        _y = _y * 0.8 + _deg(math.asin((e.y / g).clamp(-1.0, 1.0))) * 0.2;
      });
    }, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _acc.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (_acc.available == false) return ToolList(children: [notAvailable(t)]);
    final level = _x.abs() < 0.5 && _y.abs() < 0.5;
    final s = AppLook.of(context);
    return ToolList(children: [
      Center(
        child: SizedBox(
          width: 280,
          height: 280,
          child: CustomPaint(painter: _BubblePainter(-_x, _y, level ? Colors.greenAccent : s.accent)),
        ),
      ),
      BigReadout(level ? L(t, 'level_ok') : '${_x.abs().toStringAsFixed(1)}° · ${_y.abs().toStringAsFixed(1)}°'),
    ]);
  }
}

class _BubblePainter extends CustomPainter {
  final double x, y;
  final Color color;
  _BubblePainter(this.x, this.y, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = Colors.white10);
    for (final f in [0.33, 0.66, 1.0]) {
      canvas.drawCircle(
          c,
          r * f - 1,
          Paint()
            ..color = Colors.white24
            ..style = PaintingStyle.stroke);
    }
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), Paint()..color = Colors.white24);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), Paint()..color = Colors.white24);
    final off = Offset(x.clamp(-20.0, 20.0) / 20 * (r - 24), y.clamp(-20.0, 20.0) / 20 * (r - 24));
    canvas.drawCircle(c + off, 22, Paint()..color = color.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(_BubblePainter old) => true;
}

// ------------------------------------------------------------------ cetvel

class RulerTool extends StatefulWidget {
  final ToolContext t;
  const RulerTool(this.t, {super.key});

  @override
  State<RulerTool> createState() => _RulerToolState();
}

class _RulerToolState extends State<RulerTool> {
  double _pxPerMm = 160 / 25.4; // mantıksal piksel ≈ 1/160 inç
  bool _calib = false;
  double? _mark;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readDouble('pxmm', _pxPerMm).then((v) {
      if (mounted) setState(() => _pxPerMm = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    return Column(children: [
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          return GestureDetector(
            onTapDown: (d) => setState(() => _mark = d.localPosition.dy),
            onVerticalDragUpdate: (d) => setState(() => _mark = d.localPosition.dy),
            child: CustomPaint(
              size: Size(c.maxWidth, c.maxHeight),
              painter: _RulerPainter(_pxPerMm, _mark, s.accent, _calib),
            ),
          );
        }),
      ),
      if (_mark != null)
        Text('${(_mark! / _pxPerMm / 10).toStringAsFixed(2)} cm  ·  ${(_mark! / _pxPerMm / 25.4).toStringAsFixed(2)} in',
            style: TextStyle(color: s.number, fontSize: 22, fontWeight: FontWeight.w800)),
      if (_calib) ...[
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(L(t, 'card_hint'))),
        Slider(
          min: 3,
          max: 12,
          value: _pxPerMm.clamp(3.0, 12.0),
          onChanged: (v) => setState(() => _pxPerMm = v),
          onChangeEnd: (v) => t.store.write('pxmm', '$v'),
        ),
      ],
      TextButton.icon(
        onPressed: () => setState(() => _calib = !_calib),
        icon: const Icon(Icons.credit_card_rounded),
        label: Text(L(t, 'calibrate')),
      ),
    ]);
  }
}

class _RulerPainter extends CustomPainter {
  final double pxmm;
  final double? mark;
  final Color accent;
  final bool card;
  _RulerPainter(this.pxmm, this.mark, this.accent, this.card);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;
    if (card) {
      // Kartın uzun kenarı (85,6 mm) ekranın üstünden başlar.
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 85.6 * pxmm), Paint()..color = accent.withValues(alpha: 0.25));
    }
    // Sol: santimetre, sağ: inç.
    for (var mm = 0; mm * pxmm < size.height; mm++) {
      final y = mm * pxmm;
      final len = mm % 10 == 0 ? 36.0 : (mm % 5 == 0 ? 24.0 : 12.0);
      canvas.drawLine(Offset(0, y), Offset(len, y), p);
      if (mm % 10 == 0 && mm > 0) {
        final tp = TextPainter(
          text: TextSpan(text: '${mm ~/ 10}', style: const TextStyle(color: Colors.white, fontSize: 14)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(40, y - tp.height / 2));
      }
    }
    final pxIn = pxmm * 25.4;
    for (var i = 0; i * pxIn / 16 < size.height; i++) {
      final y = i * pxIn / 16;
      final len = i % 16 == 0 ? 36.0 : (i % 8 == 0 ? 26.0 : (i % 4 == 0 ? 18.0 : 10.0));
      canvas.drawLine(Offset(size.width - len, y), Offset(size.width, y), p);
      if (i % 16 == 0 && i > 0) {
        final tp = TextPainter(
          text: TextSpan(text: '${i ~/ 16}"', style: const TextStyle(color: Colors.white, fontSize: 14)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(size.width - 44 - tp.width, y - tp.height / 2));
      }
    }
    if (mark != null) {
      canvas.drawLine(
          Offset(0, mark!),
          Offset(size.width, mark!),
          Paint()
            ..color = accent
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.pxmm != pxmm || old.mark != mark || old.card != card;
}

// ------------------------------------------------------- konum yardımcısı

Future<bool> _locationReady(BuildContext context, ToolContext t) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      if (!context.mounted) return false;
      if (!await rationaleOnce(context, t, 'location', Icons.location_on_rounded)) return false;
      p = await Geolocator.requestPermission();
    }
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  } catch (_) {
    return false;
  }
}

class GpsTool extends StatefulWidget {
  final ToolContext t;
  final bool altitude;
  const GpsTool(this.t, {super.key, this.altitude = false});

  @override
  State<GpsTool> createState() => _GpsToolState();
}

class _GpsToolState extends State<GpsTool> {
  StreamSubscription<Position>? _sub;
  Position? _last;
  bool? _ok;
  double _max = 0, _dist = 0, _minAlt = double.infinity, _maxAlt = -double.infinity;
  bool _mph = false;
  final List<double> _hist = [];
  final _started = DateTime.now();

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final ok = await _locationReady(context, t);
    if (!mounted) return;
    setState(() => _ok = ok);
    if (!ok) return;
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0),
    ).listen((p) {
      if (!mounted) return;
      setState(() {
        final prev = _last;
        if (prev != null && p.accuracy < 30) {
          final d = Geolocator.distanceBetween(prev.latitude, prev.longitude, p.latitude, p.longitude);
          if (d > p.accuracy / 4) _dist += d;
        }
        _last = p;
        final v = p.speed < 0 ? 0.0 : p.speed;
        _max = math.max(_max, v);
        _hist.add(widget.altitude ? p.altitude : v * 3.6);
        if (_hist.length > 120) _hist.removeAt(0);
        if (p.altitude != 0) {
          _minAlt = math.min(_minAlt, p.altitude);
          _maxAlt = math.max(_maxAlt, p.altitude);
        }
      });
    }, onError: (Object _) {
      if (mounted) setState(() => _ok = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _speed(double ms) => _mph ? (ms * 2.236936).toStringAsFixed(1) : (ms * 3.6).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    if (_ok == false) return ToolList(children: [notAvailable(t), AppInfoCard(appTx('perm_denied', t.lang))]);
    final p = _last;
    final secs = DateTime.now().difference(_started).inSeconds;
    if (widget.altitude) {
      return ToolList(children: [
        if (p == null) AppInfoCard(L(t, 'waiting_gps'), icon: Icons.satellite_alt_rounded),
        BigReadout(p == null ? '…' : p.altitude.toStringAsFixed(0), unit: 'm', caption: L(t, 'altitude')),
        if (p != null)
          AppPanel(
            child: Column(children: [
              AppResult(label: 'ft', value: (p.altitude * 3.28084).toStringAsFixed(0), lang: t.lang),
              AppResult(label: L(t, 'accuracy'), value: '± ${p.altitudeAccuracy.toStringAsFixed(0)} m', lang: t.lang),
              if (_minAlt.isFinite) AppResult(label: L(t, 'minimum'), value: '${_minAlt.toStringAsFixed(0)} m', lang: t.lang),
              if (_maxAlt.isFinite) AppResult(label: L(t, 'maximum'), value: '${_maxAlt.toStringAsFixed(0)} m', lang: t.lang),
            ]),
          ),
        if (_hist.length > 2) Sparkline(_hist),
        AppInfoCard(L(t, 'approx')),
      ]);
    }
    final unit = _mph ? 'mph' : 'km/h';
    return ToolList(children: [
      if (p == null) AppInfoCard(L(t, 'waiting_gps'), icon: Icons.satellite_alt_rounded),
      BigReadout(p == null ? '0.0' : _speed(p.speed < 0 ? 0 : p.speed), unit: unit, caption: L(t, 'c_speed')),
      Choice<bool>(values: const [false, true], labels: const ['km/h', 'mph'], selected: _mph, onChanged: (v) => setState(() => _mph = v)),
      AppPanel(
        child: Column(children: [
          AppResult(label: L(t, 'maximum'), value: '${_speed(_max)} $unit', lang: t.lang),
          AppResult(
            label: L(t, 'average'),
            value: secs == 0 ? '—' : '${_speed(_dist / secs)} $unit',
            lang: t.lang,
          ),
          AppResult(
            label: L(t, 'distance'),
            value: _mph ? '${(_dist / 1609.344).toStringAsFixed(2)} mi' : '${(_dist / 1000).toStringAsFixed(2)} km',
            lang: t.lang,
          ),
          if (p != null) AppResult(label: L(t, 'accuracy'), value: '± ${p.accuracy.toStringAsFixed(0)} m', lang: t.lang),
        ]),
      ),
      if (_hist.length > 2) Sparkline(_hist, min: 0),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: OutlinedButton(
          onPressed: () => setState(() {
            _max = 0;
            _dist = 0;
            _hist.clear();
          }),
          child: Text(L(t, 'reset')),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- barometre

class BarometerTool extends StatefulWidget {
  final ToolContext t;
  const BarometerTool(this.t, {super.key});

  @override
  State<BarometerTool> createState() => _BarometerToolState();
}

class _BarometerToolState extends State<BarometerTool> {
  final _w = SensorWatch<BarometerEvent>();
  final List<double> _hist = [];
  double _sea = 1013.25;

  @override
  void initState() {
    super.initState();
    _w.start(() => barometerEventStream(), (e) {
      setState(() {
        _hist.add(e.pressure);
        if (_hist.length > 300) _hist.removeAt(0);
      });
    }, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _w.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (_w.available == false) return ToolList(children: [notAvailable(t)]);
    final p = _w.last?.pressure;
    final alt = p == null ? null : 44330 * (1 - math.pow(p / _sea, 0.1903));
    return ToolList(children: [
      BigReadout(p == null ? '…' : p.toStringAsFixed(1), unit: 'hPa', caption: L(t, 'c_pressure')),
      if (p != null)
        AppPanel(
          child: Column(children: [
            AppResult(label: 'mmHg', value: (p * 0.750062).toStringAsFixed(1), lang: t.lang),
            AppResult(label: 'inHg', value: (p * 0.02953).toStringAsFixed(2), lang: t.lang),
            AppResult(label: 'atm', value: (p / 1013.25).toStringAsFixed(4), lang: t.lang),
            AppResult(label: '${L(t, 'altitude')} (≈)', value: '${alt!.toStringAsFixed(0)} m', lang: t.lang),
            Row(children: [
              Text('P₀ ${_sea.toStringAsFixed(1)}'),
              Expanded(child: Slider(min: 950, max: 1060, value: _sea, onChanged: (v) => setState(() => _sea = v))),
            ]),
          ]),
        ),
      if (_hist.length > 2) Sparkline(_hist),
      AppInfoCard(L(t, 'approx')),
    ]);
  }
}

// ------------------------------------------------------------ titreşim

class VibrationTool extends StatefulWidget {
  final ToolContext t;
  const VibrationTool(this.t, {super.key});

  @override
  State<VibrationTool> createState() => _VibrationToolState();
}

class _VibrationToolState extends State<VibrationTool> {
  final _w = SensorWatch<UserAccelerometerEvent>();
  final List<double> _hist = [];
  double _now = 0, _max = 0;

  @override
  void initState() {
    super.initState();
    _w.start(() => userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval), (e) {
      final v = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      setState(() {
        _now = v;
        _max = math.max(_max, v);
        _hist.add(v);
        if (_hist.length > 200) _hist.removeAt(0);
      });
    }, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _w.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (_w.available == false) return ToolList(children: [notAvailable(t)]);
    return ToolList(children: [
      BigReadout(_now.toStringAsFixed(2), unit: 'm/s²'),
      Sparkline(_hist, min: 0, height: 140),
      AppPanel(
        child: Column(children: [
          AppResult(label: L(t, 'maximum'), value: '${_max.toStringAsFixed(2)} m/s²', lang: t.lang),
          AppResult(label: 'g', value: (_now / 9.80665).toStringAsFixed(3), lang: t.lang),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: OutlinedButton(onPressed: () => setState(() => _max = 0), child: Text(L(t, 'reset'))),
      ),
      AppInfoCard(L(t, 'approx')),
    ]);
  }
}

// --------------------------------------------------------- metal dedektörü

class MetalTool extends StatefulWidget {
  final ToolContext t;
  const MetalTool(this.t, {super.key});

  @override
  State<MetalTool> createState() => _MetalToolState();
}

class _MetalToolState extends State<MetalTool> {
  final _w = SensorWatch<MagnetometerEvent>();
  final List<double> _hist = [];
  double _now = 0;
  double? _base;
  final _beep = TonePlayer();
  DateTime _lastBeep = DateTime(2000);

  @override
  void initState() {
    super.initState();
    _w.start(() => magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval), (e) {
      final v = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      _base ??= v;
      setState(() {
        _now = v;
        _hist.add(v);
        if (_hist.length > 200) _hist.removeAt(0);
      });
      final rise = v - (_base ?? v);
      if (rise > 20 && DateTime.now().difference(_lastBeep).inMilliseconds > 400) {
        _lastBeep = DateTime.now();
        _beep.play(makeWav([(1200.0 + rise * 5, 60)]));
      }
    }, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _w.stop();
    _beep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (_w.available == false) return ToolList(children: [notAvailable(t)]);
    final s = AppLook.of(context);
    final rise = _now - (_base ?? _now);
    return ToolList(children: [
      BigReadout(_now.toStringAsFixed(0), unit: 'µT'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LinearProgressIndicator(
          value: (rise / 150).clamp(0.0, 1.0),
          minHeight: 16,
          borderRadius: BorderRadius.circular(8),
          color: rise > 20 ? Colors.redAccent : s.accent,
          backgroundColor: Colors.white12,
        ),
      ),
      Sparkline(_hist, height: 120),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: OutlinedButton(onPressed: () => setState(() => _base = _now), child: Text(L(t, 'zero'))),
      ),
      AppInfoCard(L(t, 'metal_hint'), icon: Icons.info_outline_rounded),
    ]);
  }
}

// ---------------------------------------------------------------- açı ölçer

class AngleTool extends StatefulWidget {
  final ToolContext t;
  const AngleTool(this.t, {super.key});

  @override
  State<AngleTool> createState() => _AngleToolState();
}

class _AngleToolState extends State<AngleTool> {
  final _w = SensorWatch<AccelerometerEvent>();
  double _roll = 0, _pitch = 0, _zero = 0;
  bool _hold = false;
  int _mode = 0; // 0 kenar (ekrana dik), 1 yüzey eğimi

  @override
  void initState() {
    super.initState();
    _w.start(() => accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval), (e) {
      if (_hold) return;
      setState(() {
        _roll = _roll * 0.8 + _deg(math.atan2(e.x, e.y)) * 0.2;
        final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
        _pitch = _pitch * 0.8 + (g == 0 ? 0.0 : _deg(math.acos((e.z / g).clamp(-1.0, 1.0)))) * 0.2;
      });
    }, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _w.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (_w.available == false) return ToolList(children: [notAvailable(t)]);
    final v = (_mode == 0 ? _roll : _pitch) - _zero;
    final s = AppLook.of(context);
    return ToolList(children: [
      Choice<int>(
        values: const [0, 1],
        labels: ['∠ ${L(t, 'c_length')}', '∠ ${L(t, 'area')}'],
        selected: _mode,
        onChanged: (m) => setState(() {
          _mode = m;
          _zero = 0;
        }),
      ),
      Center(
        child: SizedBox(
          width: 260,
          height: 160,
          child: CustomPaint(painter: _ProtractorPainter(v, s.accent)),
        ),
      ),
      BigReadout('${v.toStringAsFixed(1)}°'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _zero = _mode == 0 ? _roll : _pitch),
              child: Text(L(t, 'zero')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: () => setState(() => _hold = !_hold),
              child: Text(_hold ? L(t, 'start') : L(t, 'hold')),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _ProtractorPainter extends CustomPainter {
  final double angle;
  final Color accent;
  _ProtractorPainter(this.angle, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 4);
    final r = size.width / 2 - 4;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), math.pi, math.pi, false,
        Paint()
          ..color = Colors.white38
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    for (var d = 0; d <= 180; d += 10) {
      final a = math.pi + d * math.pi / 180;
      final len = d % 30 == 0 ? 16.0 : 8.0;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r, c + Offset(math.cos(a), math.sin(a)) * (r - len),
          Paint()..color = Colors.white54);
    }
    final a = math.pi * 1.5 + angle * math.pi / 180;
    canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * (r - 4),
        Paint()
          ..color = accent
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_ProtractorPainter old) => old.angle != angle;
}
