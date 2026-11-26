/// Alkışla / ıslıkla telefonu bul. Mikrofon yalnızca cihazda işlenir; ses
/// kaydedilmez ve gönderilmez. Android'de arka planda (bildirimli ön plan
/// hizmeti) dinler; iPhone'da uygulama açıkken çalışır.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../common.dart';
import '../platform/finder.dart';
import '../platform/notify.dart';
import 'audio.dart' show MicListener;

// ------------------------------------------------------------------- FFT

/// Gerçek girişli, 2'nin kuvveti uzunlukta hızlı Fourier dönüşümü (Hann
/// pencereli genlik spektrumu).
class SpectrumFft {
  final int n;
  final Float64List _cos, _sin, _win;
  final Int32List _rev;
  final Float64List _re, _im;

  SpectrumFft(this.n)
      : _cos = Float64List(n ~/ 2),
        _sin = Float64List(n ~/ 2),
        _win = Float64List(n),
        _rev = Int32List(n),
        _re = Float64List(n),
        _im = Float64List(n) {
    assert(n > 1 && (n & (n - 1)) == 0);
    for (var i = 0; i < n ~/ 2; i++) {
      _cos[i] = math.cos(2 * math.pi * i / n);
      _sin[i] = -math.sin(2 * math.pi * i / n);
    }
    for (var i = 0; i < n; i++) {
      _win[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
    }
    var bits = 0;
    while ((1 << bits) < n) {
      bits++;
    }
    for (var i = 0; i < n; i++) {
      var r = 0;
      for (var b = 0; b < bits; b++) {
        if ((i >> b) & 1 == 1) r |= 1 << (bits - 1 - b);
      }
      _rev[i] = r;
    }
  }

  /// [x] (uzunluk n) için n/2 genlik değeri.
  Float64List magnitudes(Float64List x) {
    for (var i = 0; i < n; i++) {
      _re[_rev[i]] = x[i] * _win[i];
      _im[_rev[i]] = 0;
    }
    for (var size = 2; size <= n; size <<= 1) {
      final half = size >> 1;
      final step = n ~/ size;
      for (var start = 0; start < n; start += size) {
        for (var k = 0; k < half; k++) {
          final c = _cos[k * step], s = _sin[k * step];
          final a = start + k, b = a + half;
          final tr = _re[b] * c - _im[b] * s;
          final ti = _re[b] * s + _im[b] * c;
          _re[b] = _re[a] - tr;
          _im[b] = _im[a] - ti;
          _re[a] += tr;
          _im[a] += ti;
        }
      }
    }
    final out = Float64List(n ~/ 2);
    for (var i = 0; i < n ~/ 2; i++) {
      out[i] = math.sqrt(_re[i] * _re[i] + _im[i] * _im[i]);
    }
    return out;
  }
}

// -------------------------------------------------------------- algılayıcı

/// Alkış (iki kısa, geniş bantlı vuruş) ve ıslık (0,9–4 kHz arası sürekli,
/// tek frekanslı ses) algılayıcısı. Android hizmetindeki Java sürümü
/// (FinderService.java) aynı eşikleri kullanır.
class SoundFinderDetector {
  static const int frame = 1024;
  final int sampleRate;

  /// 0 (az hassas) – 1 (çok hassas).
  double sensitivity;
  bool claps;
  bool whistle;

  final Float64List _buf = Float64List(frame);
  final SpectrumFft _fft = SpectrumFft(frame);
  int _fill = 0;
  int _frameNo = 0;
  double _floor = 0.01;
  double _prev = 0;
  bool _pending = false;
  int _onsetAt = -100000;
  double _peak = 0;
  double _flat = 0;
  final List<int> _clapFrames = [];
  int _tonal = 0;
  int _miss = 0;
  double _lastHz = 0;
  int _cooldownUntil = 0;

  /// Son çerçevenin düzeyi (0–1) ve ıslık frekansı (Hz); arayüz için.
  double level = 0;
  double pitch = 0;

  SoundFinderDetector({this.sampleRate = 44100, this.sensitivity = 0.5, this.claps = true, this.whistle = true});

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  int _frames(double ms) => (ms * sampleRate / 1000 / frame).round();

  /// Örnekleri ekler; tetiklenirse 'clap' ya da 'whistle' döndürür.
  String? add(List<double> samples) {
    String? hit;
    for (final v in samples) {
      _buf[_fill++] = v;
      if (_fill == frame) {
        _fill = 0;
        final h = _process();
        if (h != null) hit = h;
      }
    }
    return hit;
  }

  /// Algılayıcıyı sıfırlar (ör. alarm çaldıktan sonra).
  void reset() {
    _pending = false;
    _clapFrames.clear();
    _tonal = 0;
    _miss = 0;
  }

  String? _process() {
    _frameNo++;
    var sum = 0.0;
    for (final v in _buf) {
      sum += v * v;
    }
    final rms = math.sqrt(sum / frame);
    level = rms;
    final mag = _fft.magnitudes(_buf);
    final s = sensitivity.clamp(0.0, 1.0);
    if (!_pending) {
      _floor = rms < _floor * 3 ? _floor * 0.97 + rms * 0.03 : _floor * 0.999 + rms * 0.001;
      _floor = _floor.clamp(0.0005, 0.2);
    }
    String? hit;
    if (_frameNo >= _cooldownUntil) {
      if (claps) hit = _clap(rms, s, mag);
      if (hit == null && whistle) hit = _whistle(rms, s, mag);
      if (hit != null) {
        reset();
        _cooldownUntil = _frameNo + _frames(2500);
      }
    }
    _prev = rms;
    return hit;
  }

  /// 300 Hz–8 kHz arası spektral düzlük (alkış geniş bantlı, konuşma değil).
  double _flatness(Float64List mag) {
    final lo = math.max<int>(1, (300 * frame / sampleRate).floor());
    final hi = math.min<int>(mag.length - 1, (8000 * frame / sampleRate).ceil());
    var logSum = 0.0, sum = 0.0;
    for (var i = lo; i <= hi; i++) {
      final p = mag[i] * mag[i] + 1e-12;
      logSum += math.log(p);
      sum += p;
    }
    final n = hi - lo + 1;
    return math.exp(logSum / n) / (sum / n);
  }

  String? _clap(double rms, double s, Float64List mag) {
    final k = _lerp(12, 4, s);
    final absMin = _lerp(0.15, 0.03, s);
    if (_pending) {
      if (rms > _peak) {
        _peak = rms;
        _flat = math.max(_flat, _flatness(mag));
      }
      if (rms < _peak * 0.35) {
        _pending = false;
        if (_flat < 0.2) return null; // tonlu ses: alkış değil
        _clapFrames.add(_onsetAt);
        _clapFrames.removeWhere((f) => _frameNo - f > _frames(1500));
        if (_clapFrames.length >= 2) {
          final gap = _clapFrames[_clapFrames.length - 1] - _clapFrames[_clapFrames.length - 2];
          if (gap >= _frames(120) && gap <= _frames(900)) return 'clap';
        }
      } else if (_frameNo - _onsetAt > _frames(250)) {
        _pending = false; // uzun süren ses: alkış değil
        _clapFrames.clear();
      }
      return null;
    }
    if (rms > absMin && rms > _floor * k && rms > _prev * 2.5 && _frameNo - _onsetAt > _frames(100)) {
      _pending = true;
      _onsetAt = _frameNo;
      _peak = rms;
      _flat = _flatness(mag);
    }
    return null;
  }

  String? _whistle(double rms, double s, Float64List mag) {
    final lo = (900 * frame / sampleRate).floor();
    final hi = math.min<int>(mag.length - 1, (4000 * frame / sampleRate).ceil());
    var pk = lo;
    var pm = 0.0;
    for (var i = lo; i <= hi; i++) {
      if (mag[i] > pm) {
        pm = mag[i];
        pk = i;
      }
    }
    var side = 0.0;
    var n = 0;
    for (var i = lo; i <= hi; i++) {
      if ((i - pk).abs() > 2) {
        side += mag[i];
        n++;
      }
    }
    final ratio = pm / math.max(1e-12, side / math.max<int>(1, n));
    final hz = pk * sampleRate / frame;
    final tonal = ratio > _lerp(28, 10, s) && rms > _floor * 2.5 && rms > _lerp(0.02, 0.004, s);
    if (tonal && (_tonal == 0 || (hz - _lastHz).abs() <= _lastHz * 0.15)) {
      _tonal++;
      _miss = 0;
      _lastHz = hz;
      pitch = hz;
      if (_tonal >= _frames(_lerp(700, 350, s))) return 'whistle';
    } else if (_tonal > 0) {
      _miss++;
      if (_miss > 2) {
        _tonal = 0;
        _miss = 0;
      }
    }
    return null;
  }
}

/// Alarm sesi: iki tonlu siren (1 sn), döngüde çalınır.
Uint8List finderAlarmWav() => makeWav([
      for (var i = 0; i < 4; i++) ...[(1760.0, 120), (2350.0, 120)],
      (0.0, 40),
    ], volume: 1.0, square: true);

// ------------------------------------------------------------------- araç

class SoundFinderTool extends StatefulWidget {
  final ToolContext t;
  const SoundFinderTool(this.t, {super.key});

  @override
  State<SoundFinderTool> createState() => _SoundFinderToolState();
}

class _SoundFinderToolState extends State<SoundFinderTool> {
  int _mode = 2; // 0 alkış, 1 ıslık, 2 ikisi
  double _sens = 0.5;
  bool _sound = true, _flash = true, _vibrate = true;
  bool _running = false;
  bool _ringing = false;
  final _mic = MicListener();
  SoundFinderDetector? _det;
  final _alarm = TonePlayer();
  double _level = 0;
  int _lastUi = 0;

  ToolContext get t => widget.t;
  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final m = await t.store.readMap('prefs');
    final running = _android && await SoundFinderService.running();
    if (!mounted) return;
    setState(() {
      _mode = (m['mode'] as num?)?.toInt() ?? _mode;
      _sens = (m['sens'] as num?)?.toDouble() ?? _sens;
      _sound = m['sound'] as bool? ?? _sound;
      _flash = m['flash'] as bool? ?? _flash;
      _vibrate = m['vib'] as bool? ?? _vibrate;
      _running = running;
    });
  }

  Future<void> _save() => t.store.writeMap('prefs', {
        'mode': _mode,
        'sens': _sens,
        'sound': _sound,
        'flash': _flash,
        'vib': _vibrate,
      });

  @override
  void dispose() {
    unawaited(_stopLocal());
    _alarm.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await rationaleOnce(context, t, 'mic', Icons.mic_rounded)) return;
    // Mikrofon izni (sistem penceresi) burada istenir; kayıt başlatılmaz.
    final rec = AudioRecorder();
    final granted = await rec.hasPermission();
    await rec.dispose();
    if (!granted) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(appTx('perm_denied', t.lang))));
      return;
    }
    if (_android) {
      await Notify.requestPermission();
      final ok = await SoundFinderService.start(
        claps: _mode != 1,
        whistle: _mode != 0,
        sensitivity: _sens,
        sound: _sound,
        flash: _flash,
        vibrate: _vibrate,
        title: L(t, 'finder_listening'),
        body: L(t, 'finder_bg_note'),
        alertTitle: L(t, 'finder_found'),
        stopLabel: L(t, 'finder_stop_alarm'),
        stopListen: L(t, 'stop'),
      );
      if (mounted) setState(() => _running = ok);
      if (!ok && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.tx('not_available'))));
      }
      return;
    }
    // iPhone: uygulama açıkken dinler; ekran kapanmasın.
    final det = SoundFinderDetector(sensitivity: _sens, claps: _mode != 1, whistle: _mode != 0);
    _det = det;
    final ok = await _mic.start((s) {
      final hit = det.add(s);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (hit != null) unawaited(_ring());
      if (now - _lastUi > 120 && mounted) {
        _lastUi = now;
        setState(() => _level = det.level);
      }
    });
    if (ok) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
    if (mounted) setState(() => _running = ok);
  }

  Future<void> _ring() async {
    if (_ringing) return;
    setState(() => _ringing = true);
    if (_sound) await _alarm.play(finderAlarmWav(), loop: true);
    if (_vibrate) {
      for (var i = 0; i < 3; i++) {
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  Future<void> _silence() async {
    await _alarm.stop();
    _det?.reset();
    if (mounted) setState(() => _ringing = false);
  }

  Future<void> _stopLocal() async {
    await _mic.stop();
    await _alarm.stop();
    _det = null;
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  Future<void> _stop() async {
    if (_android) {
      await SoundFinderService.stop();
    } else {
      await _stopLocal();
    }
    if (mounted) {
      setState(() {
        _running = false;
        _ringing = false;
        _level = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_android && !_ios) return ToolList(children: [notAvailable(t), AppInfoCard(L(t, 'finder_ios_note'))]);
    final s = AppLook.of(context);
    return ToolList(children: [
      if (_ringing)
        AppPanel(
          child: Column(children: [
            const Icon(Icons.notifications_active_rounded, size: 56, color: Colors.amber),
            Text(L(t, 'finder_found'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            AppButton(label: L(t, 'finder_stop_alarm'), icon: Icons.check_circle_rounded, onPressed: _silence),
          ]),
        ),
      AppPanel(
        child: Column(children: [
          Icon(_running ? Icons.hearing_rounded : Icons.hearing_disabled_rounded,
              size: 72, color: _running ? s.accent : Colors.white38),
          const SizedBox(height: 8),
          Text(_running ? L(t, 'finder_listening') : L(t, 'finder_idle'),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (_running && !_android) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: (_level * 4).clamp(0.0, 1.0), minHeight: 10),
            ),
          ],
          const SizedBox(height: 12),
          AppButton(
            label: _running ? L(t, 'stop') : L(t, 'start'),
            icon: _running ? Icons.stop_rounded : Icons.play_arrow_rounded,
            onPressed: _running ? _stop : _start,
          ),
        ]),
      ),
      Choice<int>(
        values: const [0, 1, 2],
        labels: Ls(t, 'finder_modes'),
        selected: _mode,
        onChanged: (v) {
          if (_running) return;
          setState(() => _mode = v);
          unawaited(_save());
        },
      ),
      AppPanel(
        child: Column(children: [
          Row(children: [
            Text(L(t, 'finder_sensitivity')),
            Expanded(
              child: Slider(
                value: _sens,
                divisions: 10,
                onChanged: _running ? null : (v) => setState(() => _sens = v),
                onChangeEnd: (_) => _save(),
              ),
            ),
          ]),
          SwitchListTile(
            title: Text(L(t, 'play_sound')),
            value: _sound,
            onChanged: _running
                ? null
                : (v) {
                    setState(() => _sound = v);
                    unawaited(_save());
                  },
          ),
          if (_android)
            SwitchListTile(
              title: Text(L(t, 'play_light')),
              value: _flash,
              onChanged: _running
                  ? null
                  : (v) {
                      setState(() => _flash = v);
                      unawaited(_save());
                    },
            ),
          SwitchListTile(
            title: Text(L(t, 'finder_vibrate')),
            value: _vibrate,
            onChanged: _running
                ? null
                : (v) {
                    setState(() => _vibrate = v);
                    unawaited(_save());
                  },
          ),
        ]),
      ),
      AppInfoCard(L(t, 'finder_how'), icon: Icons.tips_and_updates_rounded),
      AppInfoCard(_android ? L(t, 'finder_bg_note') : L(t, 'finder_ios_note'), icon: Icons.battery_alert_rounded),
      AppInfoCard(L(t, 'perm_mic'), icon: Icons.lock_rounded),
    ]);
  }
}
