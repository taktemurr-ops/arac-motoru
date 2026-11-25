/// Ses araçları: ses ölçer, akort, metronom, hoparlör temizleme.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';

/// Mikrofonu PCM olarak dinler; kaydetmez.
class MicListener {
  AudioRecorder? _rec;
  StreamSubscription<Uint8List>? _sub;
  static const rate = 44100;

  Future<bool> start(void Function(Float64List samples) onSamples) async {
    try {
      final rec = AudioRecorder();
      _rec = rec;
      if (!await rec.hasPermission()) return false;
      final stream = await rec.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: rate, numChannels: 1),
      );
      _sub = stream.listen((data) {
        final bd = ByteData.sublistView(data);
        final n = data.lengthInBytes ~/ 2;
        final out = Float64List(n);
        for (var i = 0; i < n; i++) {
          out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
        }
        onSamples(out);
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    final r = _rec;
    _rec = null;
    if (r != null) {
      try {
        await r.stop();
      } catch (_) {}
      await r.dispose();
    }
  }
}

Future<bool> _micRationale(BuildContext context, ToolContext t) => rationaleOnce(context, t, 'mic', Icons.mic_rounded);

// --------------------------------------------------------------- ses ölçer

class SoundMeterTool extends StatefulWidget {
  final ToolContext t;
  const SoundMeterTool(this.t, {super.key});

  @override
  State<SoundMeterTool> createState() => _SoundMeterToolState();
}

class _SoundMeterToolState extends State<SoundMeterTool> {
  final _mic = MicListener();
  bool? _ok;
  double _db = 0, _max = 0, _min = 200, _sum = 0;
  int _n = 0;
  double _offset = 100;
  final List<double> _hist = [];
  int _lastMs = 0;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readDouble('offset', _offset).then((v) => _offset = v);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!await _micRationale(context, t)) {
      if (mounted) setState(() => _ok = false);
      return;
    }
    final ok = await _mic.start((s) {
      var sum = 0.0;
      for (final v in s) {
        sum += v * v;
      }
      final rms = math.sqrt(sum / math.max<int>(1, s.length));
      final db = (20 * math.log(math.max(rms, 1e-7)) / math.ln10 + _offset).clamp(0.0, 140.0);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastMs < 100 || !mounted) return;
      _lastMs = now;
      setState(() {
        _db = _db * 0.6 + db * 0.4;
        _max = math.max(_max, _db);
        _min = math.min(_min, _db);
        _sum += _db;
        _n++;
        _hist.add(_db);
        if (_hist.length > 150) _hist.removeAt(0);
      });
    });
    if (mounted) setState(() => _ok = ok);
  }

  @override
  void dispose() {
    unawaited(_mic.stop());
    super.dispose();
  }

  String _label(double db) {
    if (db < 30) return '🍃';
    if (db < 50) return '📚';
    if (db < 70) return '💬';
    if (db < 85) return '🚗';
    if (db < 100) return '⚠️';
    return '⛔';
  }

  @override
  Widget build(BuildContext context) {
    if (_ok == false) return ToolList(children: [notAvailable(t), AppInfoCard(appTx('perm_denied', t.lang))]);
    return ToolList(children: [
      BigReadout(_db.toStringAsFixed(0), unit: 'dB ${_label(_db)}'),
      Sparkline(_hist, min: 20, max: 120, height: 120),
      AppPanel(
        child: Column(children: [
          AppResult(label: L(t, 'minimum'), value: _n == 0 ? '—' : '${_min.toStringAsFixed(0)} dB', lang: t.lang),
          AppResult(label: L(t, 'average'), value: _n == 0 ? '—' : '${(_sum / _n).toStringAsFixed(0)} dB', lang: t.lang),
          AppResult(label: L(t, 'maximum'), value: _n == 0 ? '—' : '${_max.toStringAsFixed(0)} dB', lang: t.lang),
          Row(children: [
            Text('${L(t, 'calibration')} ${_offset.toStringAsFixed(0)}'),
            Expanded(
              child: Slider(
                min: 70,
                max: 130,
                value: _offset,
                onChanged: (v) => setState(() => _offset = v),
                onChangeEnd: (v) => t.store.write('offset', '$v'),
              ),
            ),
          ]),
          TextButton(
            onPressed: () => setState(() {
              _max = 0;
              _min = 200;
              _sum = 0;
              _n = 0;
            }),
            child: Text(L(t, 'reset')),
          ),
        ]),
      ),
      AppInfoCard(L(t, 'approx')),
    ]);
  }
}

// ------------------------------------------------------------------- akort

const _noteNames = ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'];

/// YIN benzeri temel frekans bulucu (60–1500 Hz).
double? detectPitch(Float64List x, int rate) {
  final n = x.length;
  if (n < 2048) return null;
  var energy = 0.0;
  for (final v in x) {
    energy += v * v;
  }
  if (math.sqrt(energy / n) < 0.01) return null;
  final minLag = rate ~/ 1500, maxLag = math.min<int>(rate ~/ 60, n ~/ 2);
  final d = Float64List(maxLag + 1);
  final w = n - maxLag;
  for (var lag = 1; lag <= maxLag; lag++) {
    var s = 0.0;
    for (var i = 0; i < w; i++) {
      final diff = x[i] - x[i + lag];
      s += diff * diff;
    }
    d[lag] = s;
  }
  // Birikimli ortalamaya göre normalleştir.
  var run = 0.0;
  final cmnd = Float64List(maxLag + 1)..[0] = 1.0;
  for (var lag = 1; lag <= maxLag; lag++) {
    run += d[lag];
    cmnd[lag] = run == 0 ? 1.0 : d[lag] * lag / run;
  }
  var best = -1;
  for (var lag = minLag; lag <= maxLag; lag++) {
    if (cmnd[lag] < 0.15) {
      while (lag + 1 <= maxLag && cmnd[lag + 1] < cmnd[lag]) {
        lag++;
      }
      best = lag;
      break;
    }
  }
  if (best < 0) return null;
  // Parabolik iyileştirme.
  var lag = best.toDouble();
  if (best > 1 && best < maxLag) {
    final a = cmnd[best - 1], b = cmnd[best], c = cmnd[best + 1];
    final den = a - 2 * b + c;
    if (den != 0) lag = best + (a - c) / (2 * den);
  }
  return rate / lag;
}

class TunerTool extends StatefulWidget {
  final ToolContext t;
  const TunerTool(this.t, {super.key});

  @override
  State<TunerTool> createState() => _TunerToolState();
}

class _TunerToolState extends State<TunerTool> {
  final _mic = MicListener();
  final _ref = TonePlayer();
  bool? _ok;
  double? _freq;
  double _a4 = 440;
  final List<double> _buf = [];
  int _lastMs = 0;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!await _micRationale(context, t)) {
      if (mounted) setState(() => _ok = false);
      return;
    }
    final ok = await _mic.start((s) {
      _buf.addAll(s);
      if (_buf.length < 4096) return;
      final frame = Float64List.fromList(_buf.sublist(_buf.length - 4096));
      _buf.clear();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastMs < 80) return;
      _lastMs = now;
      final f = detectPitch(frame, MicListener.rate);
      if (mounted && f != null) setState(() => _freq = _freq == null ? f : _freq! * 0.5 + f * 0.5);
    });
    if (mounted) setState(() => _ok = ok);
  }

  @override
  void dispose() {
    unawaited(_mic.stop());
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ok == false) return ToolList(children: [notAvailable(t), AppInfoCard(appTx('perm_denied', t.lang))]);
    final s = AppLook.of(context);
    final f = _freq;
    String note = '—';
    double cents = 0;
    if (f != null) {
      final midi = 69 + 12 * math.log(f / _a4) / math.ln2;
      final r = midi.round();
      cents = (midi - r) * 100;
      note = '${_noteNames[r % 12]}${r ~/ 12 - 1}';
    }
    final inTune = f != null && cents.abs() < 5;
    final guitar = <(String, int)>[('E2', 40), ('A2', 45), ('D3', 50), ('G3', 55), ('B3', 59), ('E4', 64)];
    return ToolList(children: [
      if (f == null) AppInfoCard(L(t, 'listening'), icon: Icons.hearing_rounded),
      BigReadout(note, unit: f == null ? '' : '${f.toStringAsFixed(1)} Hz'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SizedBox(
          height: 60,
          child: CustomPaint(painter: _CentsPainter(f == null ? null : cents, inTune ? Colors.greenAccent : s.accent)),
        ),
      ),
      Center(
        child: Text(
          f == null ? '' : (inTune ? L(t, 'in_tune') : (cents < 0 ? L(t, 'tune_up') : L(t, 'tune_down'))),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: inTune ? Colors.greenAccent : Colors.white),
        ),
      ),
      AppPanel(
        child: Column(children: [
          Row(children: [
            Text('A4 = ${_a4.round()} Hz'),
            Expanded(child: Slider(min: 430, max: 450, divisions: 20, value: _a4, onChanged: (v) => setState(() => _a4 = v))),
          ]),
          Wrap(spacing: 8, children: [
            for (final (name, midi) in guitar)
              ActionChip(
                label: Text(name),
                onPressed: () {
                  final hz = _a4 * math.pow(2, (midi - 69) / 12);
                  _ref.play(makeWav([(hz.toDouble(), 1500)], volume: 0.6));
                },
              ),
          ]),
        ]),
      ),
    ]);
  }
}

class _CentsPainter extends CustomPainter {
  final double? cents;
  final Color color;
  _CentsPainter(this.cents, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    final p = Paint()..color = Colors.white38;
    for (var c = -50; c <= 50; c += 10) {
      final x = mid + c / 50 * mid;
      canvas.drawLine(Offset(x, size.height * (c == 0 ? 0.1 : 0.35)), Offset(x, size.height * 0.65), p);
    }
    final c = cents;
    if (c == null) return;
    final x = mid + c.clamp(-50.0, 50.0) / 50 * mid;
    canvas.drawCircle(Offset(x, size.height / 2), 12, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CentsPainter old) => old.cents != cents || old.color != color;
}

// ---------------------------------------------------------------- metronom

class MetronomeTool extends StatefulWidget {
  final ToolContext t;
  const MetronomeTool(this.t, {super.key});

  @override
  State<MetronomeTool> createState() => _MetronomeToolState();
}

class _MetronomeToolState extends State<MetronomeTool> {
  final _hi = TonePlayer();
  final _lo = TonePlayer();
  late final Uint8List _accent = makeWav([(1760.0, 40)], volume: 0.9);
  late final Uint8List _click = makeWav([(1100.0, 30)], volume: 0.7);
  int _bpm = 100;
  int _beats = 4;
  int _beat = -1;
  bool _running = false;
  Timer? _timer;
  final _sw = Stopwatch();
  int _count = 0;
  final List<int> _taps = [];

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readInt('bpm', 100).then((v) {
      if (mounted) setState(() => _bpm = v.clamp(30, 260));
    });
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      _sw.stop();
      setState(() {
        _running = false;
        _beat = -1;
      });
      return;
    }
    _count = 0;
    _sw
      ..reset()
      ..start();
    setState(() => _running = true);
    _tickNext();
  }

  /// Sapmayı biriktirmeden bir sonraki vuruşu planlar.
  void _tickNext() {
    if (!_running) return;
    final interval = 60000 / _bpm;
    final due = (_count * interval).round();
    final wait = math.max<int>(0, due - _sw.elapsedMilliseconds);
    _timer = Timer(Duration(milliseconds: wait), () {
      if (!mounted || !_running) return;
      final b = _count % _beats;
      (b == 0 ? _hi : _lo).play(b == 0 ? _accent : _click);
      if (b == 0) HapticFeedback.lightImpact();
      setState(() => _beat = b);
      _count++;
      _tickNext();
    });
  }

  void _setBpm(int v) {
    setState(() => _bpm = v.clamp(30, 260));
    t.store.write('bpm', '$_bpm');
    if (_running) {
      _timer?.cancel();
      _count = 0;
      _sw
        ..reset()
        ..start();
      _tickNext();
    }
  }

  void _tap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _taps.removeWhere((x) => now - x > 3000);
    _taps.add(now);
    if (_taps.length >= 2) {
      final avg = (_taps.last - _taps.first) / (_taps.length - 1);
      _setBpm((60000 / avg).round());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hi.dispose();
    _lo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    return ToolList(children: [
      BigReadout('$_bpm', unit: 'BPM'),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < _beats; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            margin: const EdgeInsets.all(6),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == _beat ? (i == 0 ? Colors.orangeAccent : s.accent) : Colors.white12,
            ),
          ),
      ]),
      Slider(min: 30, max: 260, value: _bpm.toDouble(), onChanged: (v) => _setBpm(v.round())),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final d in [-5, -1, 1, 5])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: OutlinedButton(onPressed: () => _setBpm(_bpm + d), child: Text(d > 0 ? '+$d' : '$d')),
          ),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Pick<int>(
          label: L(t, 'beats'),
          values: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 12],
          text: (v) => '$v',
          value: _beats,
          onChanged: (v) => setState(() => _beats = v),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: OutlinedButton(onPressed: _tap, child: Text(L(t, 'tap_tempo')))),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _running ? Colors.redAccent : s.play),
              icon: Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded),
              label: Text(L(t, _running ? 'stop' : 'start')),
              onPressed: _toggle,
            ),
          ),
        ]),
      ),
    ]);
  }
}

// --------------------------------------------------------- hoparlör temizleme

class SpeakerCleanTool extends StatefulWidget {
  final ToolContext t;
  const SpeakerCleanTool(this.t, {super.key});

  @override
  State<SpeakerCleanTool> createState() => _SpeakerCleanToolState();
}

class _SpeakerCleanToolState extends State<SpeakerCleanTool> {
  final _p = TonePlayer();
  bool _on = false;
  int _left = 0;
  Timer? _timer;

  ToolContext get t => widget.t;

  Future<void> _toggle() async {
    if (_on) {
      _timer?.cancel();
      await _p.stop();
      setState(() => _on = false);
      return;
    }
    // 165 Hz'lik düşük ton, kısa aralarla (titreşim suyu dışarı iter).
    final wav = makeWav([(165.0, 1800), (0.0, 200)], volume: 1);
    await _p.play(wav, loop: true);
    setState(() {
      _on = true;
      _left = 30;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (tm) async {
      if (!mounted) return;
      if (_left <= 1) {
        tm.cancel();
        await _p.stop();
        if (mounted) setState(() => _on = false);
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    return ToolList(children: [
      const SizedBox(height: 24),
      Center(
        child: GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _on ? s.accent.withValues(alpha: 0.3) : Colors.white10,
              border: Border.all(color: s.accent, width: 3),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_on ? Icons.water_drop_rounded : Icons.speaker_rounded, size: 72),
              Text(_on ? '$_left s' : L(t, 'start'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ),
      AppInfoCard(L(t, 'speaker_hint'), icon: Icons.volume_up_rounded),
    ]);
  }
}
