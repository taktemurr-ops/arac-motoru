/// Ton / frekans üreteci: sinüs, kare, üçgen ve testere dalgası; sabit ton
/// ya da logaritmik frekans taraması. Ses cihazda üretilir, kaydedilmez.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';

/// Dalga biçimleri (etiket sırası: Sinüs, Kare, Üçgen, Testere).
enum Wave { sine, square, triangle, saw }

const int kToneRate = 44100;

/// Bir dönem içindeki konum [p] (0–1) için dalga değeri (-1…1).
double waveSample(Wave w, double p) {
  switch (w) {
    case Wave.sine:
      return math.sin(2 * math.pi * p);
    case Wave.square:
      return p < 0.5 ? 1.0 : -1.0;
    case Wave.triangle:
      return 1 - 4 * (p - 0.5).abs();
    case Wave.saw:
      return 2 * p - 1;
  }
}

Uint8List _wav(Float64List s, int rate) {
  final data = ByteData(44 + s.length * 2);
  void str(int o, String v) {
    for (var i = 0; i < v.length; i++) {
      data.setUint8(o + i, v.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + s.length * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, s.length * 2, Endian.little);
  for (var i = 0; i < s.length; i++) {
    data.setInt16(44 + i * 2, (s[i] * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Kesintisiz döngü için tam sayıda dönem içeren (~1 sn) örnekler.
/// Dönüş: (örnekler, gerçek frekans).
(Float64List, double) toneSamples(double freq, Wave wave, {double volume = 0.5, int rate = kToneRate}) {
  final f = freq.clamp(1.0, rate / 2 - 50);
  final cycles = math.max(1, f.round());
  final n = math.max(2, (cycles * rate / f).round());
  final actual = cycles * rate / n;
  final out = Float64List(n);
  final amp = 0.9 * volume.clamp(0.0, 1.0);
  for (var i = 0; i < n; i++) {
    final p = (i * cycles / n) % 1.0;
    out[i] = waveSample(wave, p) * amp;
  }
  return (out, actual);
}

/// Döngüde çalınacak WAV.
Uint8List toneWav(double freq, Wave wave, {double volume = 0.5}) => _wav(toneSamples(freq, wave, volume: volume).$1, kToneRate);

/// [from]'dan [to]'ya [seconds] sürede logaritmik tarama (yumuşak giriş/çıkış).
Float64List sweepSamples(double from, double to, double seconds, Wave wave, {double volume = 0.5, int rate = kToneRate}) {
  final f1 = from.clamp(1.0, rate / 2 - 50), f2 = to.clamp(1.0, rate / 2 - 50);
  final n = math.max(1, (seconds.clamp(0.5, 60.0) * rate).round());
  final out = Float64List(n);
  final amp = 0.9 * volume.clamp(0.0, 1.0);
  final fade = math.min(n ~/ 2, (rate * 0.01).round());
  var phase = 0.0;
  final ratio = f2 / f1;
  for (var i = 0; i < n; i++) {
    final f = f1 * math.pow(ratio, i / n);
    phase = (phase + f / rate) % 1.0;
    var env = 1.0;
    if (i < fade) env = i / fade;
    if (n - i < fade) env = (n - i) / fade;
    out[i] = waveSample(wave, phase) * amp * env;
  }
  return out;
}

Uint8List sweepWav(double from, double to, double seconds, Wave wave, {double volume = 0.5}) =>
    _wav(sweepSamples(from, to, seconds, wave, volume: volume), kToneRate);

/// Frekansın en yakın nota adı (A4 = 440 Hz), ör. "A4 +0¢".
String noteName(double hz) {
  if (hz <= 0) return '—';
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  final midi = 69 + 12 * math.log(hz / 440) / math.ln2;
  final m = midi.round();
  final cents = ((midi - m) * 100).round();
  return '${names[((m % 12) + 12) % 12]}${(m ~/ 12) - 1} ${cents >= 0 ? '+' : ''}$cents¢';
}

// ---------------------------------------------------------------- araç

class ToneGenTool extends StatefulWidget {
  final ToolContext t;
  const ToneGenTool(this.t, {super.key});

  @override
  State<ToneGenTool> createState() => _ToneGenToolState();
}

class _ToneGenToolState extends State<ToneGenTool> {
  static const double _minF = 20, _maxF = 20000;
  final _player = TonePlayer();
  final _freqCtl = TextEditingController();
  final _fromCtl = TextEditingController(text: '20');
  final _toCtl = TextEditingController(text: '20000');
  final _secCtl = TextEditingController(text: '10');
  double _freq = 440;
  double _vol = 0.3;
  Wave _wave = Wave.sine;
  bool _sweep = false;
  bool _playing = false;
  Timer? _debounce;
  Timer? _sweepEnd;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _freqCtl.text = '440';
    unawaited(_load());
  }

  Future<void> _load() async {
    final f = await t.store.readDouble('freq', 440);
    final v = await t.store.readDouble('vol', 0.3);
    final w = await t.store.readInt('wave', 0);
    if (!mounted) return;
    setState(() {
      _freq = f.clamp(1.0, 22000.0);
      _vol = v.clamp(0.0, 1.0);
      _wave = Wave.values[w.clamp(0, Wave.values.length - 1)];
      _freqCtl.text = _fmt(_freq);
    });
  }

  String _fmt(double f) => f >= 100 ? f.round().toString() : f.toStringAsFixed(1);

  double get _slider => (math.log(_freq.clamp(_minF, _maxF) / _minF) / math.log(_maxF / _minF)).clamp(0.0, 1.0);

  void _setFreq(double f, {bool text = true}) {
    setState(() {
      _freq = f.clamp(1.0, 22000.0);
      if (text) _freqCtl.text = _fmt(_freq);
    });
    unawaited(t.store.write('freq', '$_freq'));
    _restart();
  }

  void _restart() {
    if (!_playing || _sweep) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () => _player.play(toneWav(_freq, _wave, volume: _vol), loop: true));
  }

  Future<void> _toggle() async {
    if (_playing) {
      _sweepEnd?.cancel();
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _playing = true);
    if (_sweep) {
      final a = parseNumber(_fromCtl.text) ?? 20, b = parseNumber(_toCtl.text) ?? 20000;
      final s = (parseNumber(_secCtl.text) ?? 10).clamp(0.5, 60.0);
      await _player.play(sweepWav(a, b, s, _wave, volume: _vol));
      _sweepEnd?.cancel();
      _sweepEnd = Timer(Duration(milliseconds: (s * 1000).round() + 200), () {
        if (mounted) setState(() => _playing = false);
      });
    } else {
      await _player.play(toneWav(_freq, _wave, volume: _vol), loop: true);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sweepEnd?.cancel();
    _player.dispose();
    _freqCtl.dispose();
    _fromCtl.dispose();
    _toCtl.dispose();
    _secCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waves = Ls(t, 'waves');
    final s = AppLook.of(context);
    return ToolList(children: [
      AppInfoCard(L(t, 'tone_hint'), icon: Icons.hearing_rounded),
      Choice<bool>(
        values: const [false, true],
        labels: [L(t, 'frequency'), L(t, 'sweep')],
        selected: _sweep,
        onChanged: (v) async {
          if (_playing) await _toggle();
          setState(() => _sweep = v);
        },
      ),
      Choice<Wave>(
        values: Wave.values,
        labels: [for (var i = 0; i < Wave.values.length; i++) i < waves.length ? waves[i] : Wave.values[i].name],
        selected: _wave,
        onChanged: (w) {
          setState(() => _wave = w);
          unawaited(t.store.write('wave', '${w.index}'));
          _restart();
        },
      ),
      if (!_sweep) ...[
        BigReadout(_fmt(_freq), unit: 'Hz', caption: noteName(_freq)),
        AppPanel(
          child: Column(children: [
            Slider(value: _slider, onChanged: (v) => _setFreq(_minF * math.pow(_maxF / _minF, v))),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
              for (final (lbl, f) in [('÷2', 0.5), ('−10', -10.0), ('−1', -1.0), ('+1', 1.0), ('+10', 10.0), ('×2', 2.0)])
                OutlinedButton(
                  onPressed: () => _setFreq(lbl.startsWith('÷') || lbl.startsWith('×') ? _freq * f : _freq + f),
                  child: Text(lbl),
                ),
            ]),
            AppNumberField(
              controller: _freqCtl,
              label: L(t, 'frequency'),
              suffix: 'Hz',
              onChanged: (v) {
                final f = parseNumber(v);
                if (f != null && f >= 1 && f <= 22000) _setFreq(f, text: false);
              },
            ),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final f in [50.0, 100.0, 261.63, 440.0, 1000.0, 5000.0, 10000.0, 15000.0])
                ActionChip(label: Text('${_fmt(f)} Hz'), onPressed: () => _setFreq(f)),
            ]),
          ]),
        ),
      ] else
        AppPanel(
          child: Column(children: [
            AppNumberField(controller: _fromCtl, label: L(t, 'from'), suffix: 'Hz'),
            AppNumberField(controller: _toCtl, label: L(t, 'to'), suffix: 'Hz'),
            AppNumberField(controller: _secCtl, label: L(t, 'c_time'), suffix: 's'),
          ]),
        ),
      AppPanel(
        child: Row(children: [
          const Icon(Icons.volume_up_rounded, color: Colors.white70),
          const SizedBox(width: 8),
          Text(L(t, 'volume')),
          Expanded(
            child: Slider(
              value: _vol,
              onChanged: (v) => setState(() => _vol = v),
              onChangeEnd: (v) {
                unawaited(t.store.write('vol', '$v'));
                _restart();
              },
            ),
          ),
          Text('${(_vol * 100).round()}%', style: TextStyle(color: s.number)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppButton(
          label: _playing ? L(t, 'stop') : L(t, 'start'),
          icon: _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
          onPressed: _toggle,
        ),
      ),
    ]);
  }
}
