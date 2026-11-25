/// Araçların ortak yardımcıları: çeviri, liste düzeni, ses üretimi,
/// sensör bekleme ve kamera kutusu.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import 'tx.dart';

/// Araç etiketi (33 dil).
String L(ToolContext t, String key) => t.t(kAracL[key] ?? [key]);

/// Virgülle ayrılmış etiket listesi.
List<String> Ls(ToolContext t, String key) => L(t, key).split(',');

/// Aracın gövdesi: kaydırılabilir sütun.
class ToolList extends StatelessWidget {
  final List<Widget> children;
  const ToolList({super.key, required this.children});

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.only(top: 8, bottom: 32), children: children);
}

/// "Bu cihazda yok" bilgisi.
Widget notAvailable(ToolContext t) =>
    AppInfoCard(t.tx(kIsWeb ? 'web_unavailable' : 'not_available'), icon: Icons.sensors_off_rounded);

/// Büyük sayı göstergesi.
class BigReadout extends StatelessWidget {
  final String value;
  final String unit;
  final String? caption;
  const BigReadout(this.value, {super.key, this.unit = '', this.caption});

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    return AppPanel(
      child: Column(children: [
        if (caption != null) Text(caption!, style: const TextStyle(color: Colors.white70, fontSize: 15)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(value, style: TextStyle(color: s.number, fontSize: 64, fontWeight: FontWeight.w900)),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(unit, style: const TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Seçenek düğmeleri (SegmentedButton) için kısa yol.
class Choice<T> extends StatelessWidget {
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;
  const Choice({super.key, required this.values, required this.labels, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [
            for (var i = 0; i < values.length; i++) ButtonSegment<T>(value: values[i], label: Text(labels[i])),
          ],
          selected: {selected},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    );
  }
}

/// Açılır liste.
class Pick<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final String Function(T) text;
  final T value;
  final ValueChanged<T> onChanged;
  const Pick({
    super.key,
    required this.label,
    required this.values,
    required this.text,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        items: [for (final v in values) DropdownMenuItem<T>(value: v, child: Text(text(v), overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// Düz metin alanı.
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool obscure;
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.onChanged,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        obscureText: obscure,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 17),
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: maxLines > 1,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

/// Tarih seçme satırı.
class DateRow extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? first;
  final DateTime? last;
  const DateRow({super.key, required this.label, required this.value, required this.onChanged, this.first, this.last});

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_rounded),
      title: Text(label),
      subtitle: Text(loc.formatFullDate(value)),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: first ?? DateTime(1800),
          lastDate: last ?? DateTime(2300),
        );
        if (d != null) onChanged(d);
      },
    );
  }
}

// ------------------------------------------------------------------ ses

/// 16 bit mono WAV üretir. [segments]: (frekans Hz, süre ms); frekans 0 sessizliktir.
Uint8List makeWav(List<(double, int)> segments, {int rate = 22050, double volume = 0.8, bool square = false}) {
  var total = 0;
  for (final s in segments) {
    total += (rate * s.$2 / 1000).round();
  }
  final data = ByteData(44 + total * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + total * 2, Endian.little);
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
  data.setUint32(40, total * 2, Endian.little);
  var o = 44;
  for (final s in segments) {
    final n = (rate * s.$2 / 1000).round();
    final fade = math.min<int>(n ~/ 2, (rate * 0.005).round());
    for (var i = 0; i < n; i++) {
      var v = 0.0;
      if (s.$1 > 0) {
        final ph = math.sin(2 * math.pi * s.$1 * i / rate);
        v = square ? (ph >= 0 ? 1.0 : -1.0) : ph;
        var env = 1.0;
        if (i < fade) env = i / fade;
        if (n - i < fade) env = (n - i) / fade;
        v *= env * volume;
      }
      data.setInt16(o, (v * 32767).round().clamp(-32768, 32767), Endian.little);
      o += 2;
    }
  }
  return data.buffer.asUint8List();
}

/// Tek bir ses çalar; kapanınca kaynakları bırakır.
class TonePlayer {
  final AudioPlayer _p = AudioPlayer();

  Future<void> play(Uint8List wav, {bool loop = false}) async {
    try {
      await _p.stop();
      await _p.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
      await _p.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (_) {/* ses yoksa sessiz geç */}
  }

  Future<void> stop() async {
    try {
      await _p.stop();
    } catch (_) {}
  }

  void dispose() {
    unawaited(_p.dispose());
  }
}

// --------------------------------------------------------------- sensör

/// Bir sensör akışını dinler; [timeout] içinde veri gelmezse ya da hata
/// olursa [available] false olur.
class SensorWatch<T> {
  StreamSubscription<T>? _sub;
  Timer? _timer;
  bool? available;
  T? last;

  void start(Stream<T> Function() open, void Function(T) onData, VoidCallback onState,
      {Duration timeout = const Duration(seconds: 3)}) {
    try {
      _sub = open().listen((e) {
        last = e;
        if (available != true) {
          available = true;
          onState();
        }
        onData(e);
      }, onError: (Object _) {
        available = false;
        onState();
      }, cancelOnError: true);
    } catch (_) {
      available = false;
      onState();
      return;
    }
    _timer = Timer(timeout, () {
      if (available == null) {
        available = false;
        onState();
      }
    });
  }

  void stop() {
    _timer?.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
  }
}

// --------------------------------------------------------------- kamera

/// İzin açıklaması bir kez gösterildi mi?
Future<bool> rationaleOnce(BuildContext context, ToolContext t, String perm, IconData icon) async {
  if (await t.store.readBool('perm.$perm')) return true;
  if (!context.mounted) return false;
  final ok = await explainPermission(context, lang: t.lang, icon: icon, reason: L(t, 'perm_$perm'));
  if (ok) await t.store.writeBool('perm.$perm', true);
  return ok;
}

/// Kamerayı açıp önizlemeyi çizen kutu. [builder] hazır denetleyiciyle
/// çağrılır; kamera yoksa ya da izin verilmezse bilgi gösterilir.
class CameraBox extends StatefulWidget {
  final ToolContext tool;
  final CameraLensDirection lens;
  final ResolutionPreset preset;
  final Widget Function(BuildContext context, CameraController c) builder;
  final void Function(CameraController c)? onReady;
  const CameraBox({
    super.key,
    required this.tool,
    required this.builder,
    this.lens = CameraLensDirection.back,
    this.preset = ResolutionPreset.medium,
    this.onReady,
  });

  @override
  State<CameraBox> createState() => _CameraBoxState();
}

class _CameraBoxState extends State<CameraBox> with WidgetsBindingObserver {
  CameraController? _c;
  String? _error;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (!_asked) {
      _asked = true;
      final ok = await rationaleOnce(context, widget.tool, 'camera', Icons.photo_camera_rounded);
      if (!ok) {
        if (mounted) setState(() => _error = appTx('perm_denied', widget.tool.lang));
        return;
      }
    }
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'none');
      final cam = cams.firstWhere((c) => c.lensDirection == widget.lens, orElse: () => cams.first);
      final c = CameraController(cam, widget.preset, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
      widget.onReady?.call(c);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code.toLowerCase().contains('denied')
          ? appTx('perm_denied', widget.tool.lang)
          : appTx(kIsWeb ? 'web_unavailable' : 'not_available', widget.tool.lang));
    } catch (_) {
      if (mounted) setState(() => _error = appTx('not_available', widget.tool.lang));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _c;
    if (c == null) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _c = null;
      unawaited(c.dispose());
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _error == null) {
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final c = _c;
    _c = null;
    if (c != null) unawaited(c.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return AppInfoCard(_error!, icon: Icons.no_photography_rounded);
    final c = _c;
    if (c == null || !c.value.isInitialized) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    return widget.builder(context, c);
  }
}

/// Önizlemeyi kutuya sığdırır.
Widget cameraPreview(CameraController c, {double? height}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: SizedBox(
      height: height,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: c.value.previewSize?.height ?? 480,
          height: c.value.previewSize?.width ?? 640,
          child: CameraPreview(c),
        ),
      ),
    ),
  );
}

/// Kamera karesinden ortadaki rengi ve ortalama parlaklığı çıkarır.
/// Android YUV420 ve iOS BGRA8888 biçimlerini anlar.
({int r, int g, int b, double luma})? sampleFrame(CameraImage img) {
  try {
    final w = img.width, h = img.height;
    final cx = w ~/ 2, cy = h ~/ 2;
    if (img.format.group == ImageFormatGroup.bgra8888) {
      final p = img.planes.first;
      int px(int x, int y, int ch) => p.bytes[y * p.bytesPerRow + x * 4 + ch];
      var sum = 0.0, n = 0;
      for (var y = 0; y < h; y += h ~/ 16 + 1) {
        for (var x = 0; x < w; x += w ~/ 16 + 1) {
          sum += 0.299 * px(x, y, 2) + 0.587 * px(x, y, 1) + 0.114 * px(x, y, 0);
          n++;
        }
      }
      return (r: px(cx, cy, 2), g: px(cx, cy, 1), b: px(cx, cy, 0), luma: sum / math.max<int>(1, n));
    }
    final yp = img.planes[0];
    var sum = 0.0, n = 0;
    for (var y = 0; y < h; y += h ~/ 16 + 1) {
      for (var x = 0; x < w; x += w ~/ 16 + 1) {
        sum += yp.bytes[y * yp.bytesPerRow + x];
        n++;
      }
    }
    final yv = yp.bytes[cy * yp.bytesPerRow + cx].toDouble();
    var u = 128.0, v = 128.0;
    if (img.planes.length >= 3) {
      final up = img.planes[1], vp = img.planes[2];
      final ps = up.bytesPerPixel ?? 1;
      final ui = (cy ~/ 2) * up.bytesPerRow + (cx ~/ 2) * ps;
      final vi = (cy ~/ 2) * vp.bytesPerRow + (cx ~/ 2) * (vp.bytesPerPixel ?? 1);
      if (ui < up.bytes.length && vi < vp.bytes.length) {
        u = up.bytes[ui].toDouble();
        v = vp.bytes[vi].toDouble();
      }
    }
    int c(double x) => x.round().clamp(0, 255);
    return (
      r: c(yv + 1.402 * (v - 128)),
      g: c(yv - 0.344136 * (u - 128) - 0.714136 * (v - 128)),
      b: c(yv + 1.772 * (u - 128)),
      luma: sum / math.max<int>(1, n),
    );
  } catch (_) {
    return null;
  }
}

/// Basit çizgi grafik (son değerler).
class Sparkline extends StatelessWidget {
  final List<double> values;
  final double? min;
  final double? max;
  final double height;
  const Sparkline(this.values, {super.key, this.min, this.max, this.height = 90});

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    return AppPanel(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _SparkPainter(values, min, max, s.accent)),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> v;
  final double? lo, hi;
  final Color color;
  _SparkPainter(this.v, this.lo, this.hi, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final a = lo ?? v.reduce(math.min);
    var b = hi ?? v.reduce(math.max);
    if (b - a < 1e-9) b = a + 1;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height * (1 - ((v[i] - a) / (b - a)).clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}
