/// Kamera ve ışık araçları: el feneri, QR/barkod okuyucu, büyüteç, ayna,
/// ışık ölçer, mesafe/yükseklik, renk seçici, SOS.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../common.dart';

// --------------------------------------------------------------- el feneri

/// Flaşı açıp kapatan küçük yardımcı (kamera önizlemesi gerekmez).
class Torch {
  CameraController? _c;
  bool available = false;
  bool on = false;

  Future<void> open() async {
    if (kIsWeb) return;
    try {
      final cams = await availableCameras();
      final back = cams.where((c) => c.lensDirection == CameraLensDirection.back).toList();
      if (back.isEmpty) return;
      final c = CameraController(back.first, ResolutionPreset.low, enableAudio: false);
      await c.initialize();
      _c = c;
      available = true;
    } catch (_) {
      available = false;
    }
  }

  Future<void> set(bool v) async {
    final c = _c;
    if (c == null) return;
    try {
      await c.setFlashMode(v ? FlashMode.torch : FlashMode.off);
      on = v;
    } catch (_) {
      available = false;
    }
  }

  Future<void> close() async {
    final c = _c;
    _c = null;
    if (c == null) return;
    try {
      await c.setFlashMode(FlashMode.off);
    } catch (_) {}
    await c.dispose();
  }
}

class FlashlightTool extends StatefulWidget {
  final ToolContext t;
  const FlashlightTool(this.t, {super.key});

  @override
  State<FlashlightTool> createState() => _FlashlightToolState();
}

class _FlashlightToolState extends State<FlashlightTool> {
  final _torch = Torch();
  bool _ready = false;
  bool _screen = false;
  Color _screenColor = Colors.white;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!kIsWeb && await rationaleOnce(context, t, 'camera', Icons.flashlight_on_rounded)) {
        await _torch.open();
      }
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    unawaited(_torch.close());
    WakelockPlus.disable().catchError((Object _) {});
    super.dispose();
  }

  Future<void> _toggle() async {
    HapticFeedback.mediumImpact();
    await _torch.set(!_torch.on);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    if (_screen) {
      return GestureDetector(
        onTap: () => setState(() => _screen = false),
        child: Container(color: _screenColor, width: double.infinity, height: double.infinity),
      );
    }
    return ToolList(children: [
      if (_ready && !_torch.available) notAvailable(t),
      const SizedBox(height: 24),
      Center(
        child: GestureDetector(
          onTap: _torch.available ? _toggle : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _torch.on ? Colors.amber : Colors.white10,
              boxShadow: _torch.on ? [const BoxShadow(color: Colors.amberAccent, blurRadius: 60, spreadRadius: 6)] : null,
              border: Border.all(color: s.accent, width: 2),
            ),
            child: Icon(Icons.power_settings_new_rounded, size: 90, color: _torch.on ? Colors.black87 : Colors.white70),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Center(child: Text(L(t, _torch.on ? 'on' : 'off'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
      AppHeading(L(t, 'screen_light'), icon: Icons.light_mode_rounded),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 10, children: [
          for (final c in [Colors.white, const Color(0xFFFFE0B2), Colors.redAccent, Colors.lightBlueAccent])
            GestureDetector(
              onTap: () {
                WakelockPlus.enable().catchError((Object _) {});
                setState(() {
                  _screenColor = c;
                  _screen = true;
                });
              },
              child: CircleAvatar(radius: 26, backgroundColor: c),
            ),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------- QR okuyucu

class QrScanTool extends StatefulWidget {
  final ToolContext t;
  const QrScanTool(this.t, {super.key});

  @override
  State<QrScanTool> createState() => _QrScanToolState();
}

class _QrScanToolState extends State<QrScanTool> {
  MobileScannerController? _c;
  bool _allowed = false;
  bool _asked = false;
  String? _last;
  String? _format;
  List<String> _history = [];

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readStrings('history').then((h) {
      if (mounted) setState(() => _history = h);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await rationaleOnce(context, t, 'camera', Icons.qr_code_scanner_rounded);
      if (!mounted) return;
      setState(() {
        _asked = true;
        _allowed = ok;
        if (ok) _c = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
      });
    });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _found(BarcodeCapture cap) {
    if (cap.barcodes.isEmpty) return;
    final b = cap.barcodes.first;
    final v = b.rawValue ?? b.displayValue;
    if (v == null || v == _last) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _last = v;
      _format = b.format.name.toUpperCase();
      _history.remove(v);
      _history.insert(0, v);
      if (_history.length > 50) _history = _history.sublist(0, 50);
    });
    t.store.writeStrings('history', _history);
  }

  bool _isUrl(String v) => v.startsWith('http://') || v.startsWith('https://');

  Widget _resultCard(String v) => AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_format != null && v == _last) Text(_format!, style: const TextStyle(color: Colors.white60)),
          SelectableText(v, style: const TextStyle(fontSize: 17)),
          Row(children: [
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded),
              label: Text(t.tx('copied')),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: v));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.tx('copied'))));
              },
            ),
            if (_isUrl(v))
              TextButton.icon(
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(L(t, 'open_link')),
                onPressed: () => launchUrl(Uri.parse(v), mode: LaunchMode.externalApplication),
              ),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return ToolList(children: [
      if (_asked && !_allowed) AppInfoCard(appTx('perm_denied', t.lang)),
      if (c != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 320,
              child: MobileScanner(controller: c, onDetect: _found),
            ),
          ),
        ),
      if (_last != null) _resultCard(_last!),
      if (_history.isNotEmpty) ...[
        AppHeading(L(t, 'history'), icon: Icons.history_rounded),
        for (final h in _history.take(20))
          ListTile(
            dense: true,
            leading: Icon(_isUrl(h) ? Icons.link_rounded : Icons.qr_code_2_rounded),
            title: Text(h, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => setState(() {
              _last = h;
              _format = null;
            }),
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

// --------------------------------------------------------------- büyüteç

class MagnifierTool extends StatefulWidget {
  final ToolContext t;
  final bool mirror;
  const MagnifierTool(this.t, {super.key, this.mirror = false});

  @override
  State<MagnifierTool> createState() => _MagnifierToolState();
}

class _MagnifierToolState extends State<MagnifierTool> {
  double _zoom = 1, _min = 1, _max = 1;
  bool _light = false;
  bool _frozen = false;

  Future<void> _ready(CameraController c) async {
    try {
      final lo = await c.getMinZoomLevel(), hi = await c.getMaxZoomLevel();
      final start = widget.mirror ? lo : math.min(hi, lo * 2);
      await c.setZoomLevel(start);
      if (mounted) {
        setState(() {
          _min = lo;
          _max = hi;
          _zoom = start;
        });
      }
    } catch (_) {/* yakınlaştırma desteklenmiyor */}
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return CameraBox(
      tool: t,
      lens: widget.mirror ? CameraLensDirection.front : CameraLensDirection.back,
      preset: ResolutionPreset.high,
      onReady: _ready,
      builder: (context, c) => Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: cameraPreview(c),
          ),
        ),
        if (_max > _min)
          Row(children: [
            const SizedBox(width: 16),
            const Icon(Icons.zoom_in_rounded),
            Expanded(
              child: Slider(
                min: _min,
                max: _max,
                value: _zoom.clamp(_min, _max),
                onChanged: (v) {
                  setState(() => _zoom = v);
                  c.setZoomLevel(v).catchError((Object _) {});
                },
              ),
            ),
            Text('${_zoom.toStringAsFixed(1)}×'),
            const SizedBox(width: 16),
          ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            if (!widget.mirror && !kIsWeb)
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(_light ? Icons.flashlight_off_rounded : Icons.flashlight_on_rounded),
                  label: Text(L(t, _light ? 'off' : 'on')),
                  onPressed: () async {
                    try {
                      await c.setFlashMode(_light ? FlashMode.off : FlashMode.torch);
                      setState(() => _light = !_light);
                    } catch (_) {}
                  },
                ),
              ),
            if (!widget.mirror && !kIsWeb) const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                icon: Icon(_frozen ? Icons.play_arrow_rounded : Icons.pause_rounded),
                label: Text(L(t, _frozen ? 'start' : 'freeze')),
                onPressed: () async {
                  try {
                    if (_frozen) {
                      await c.resumePreview();
                    } else {
                      await c.pausePreview();
                    }
                    setState(() => _frozen = !_frozen);
                  } catch (_) {}
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------- ışık ölçer ve renk seçici

/// Kamera karelerini işleyen ortak gövde.
class _FrameTool extends StatefulWidget {
  final ToolContext t;
  final bool color;
  const _FrameTool(this.t, {required this.color});

  @override
  State<_FrameTool> createState() => _FrameToolState();
}

class _FrameToolState extends State<_FrameTool> {
  ({int r, int g, int b, double luma})? _s;
  bool _hold = false;
  bool _streamFailed = false;
  int _lastMs = 0;
  double _k = 4.0; // lüks tahmini için kalibrasyon çarpanı
  final List<double> _hist = [];

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readDouble('k', _k).then((v) {
      if (mounted) setState(() => _k = v);
    });
  }

  Future<void> _ready(CameraController c) async {
    if (kIsWeb) {
      setState(() => _streamFailed = true);
      return;
    }
    try {
      await c.startImageStream((img) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (_hold || now - _lastMs < 150) return;
        _lastMs = now;
        final s = sampleFrame(img);
        if (s == null || !mounted) return;
        setState(() {
          _s = s;
          _hist.add(s.luma);
          if (_hist.length > 120) _hist.removeAt(0);
        });
      });
    } catch (_) {
      if (mounted) setState(() => _streamFailed = true);
    }
  }

  String _hex(int r, int g, int b) =>
      '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return CameraBox(
      tool: t,
      preset: ResolutionPreset.low,
      onReady: _ready,
      builder: (context, c) => ToolList(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: () => setState(() => _hold = !_hold),
            child: Stack(alignment: Alignment.center, children: [
              cameraPreview(c, height: 260),
              if (widget.color)
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                ),
            ]),
          ),
        ),
        if (_streamFailed) notAvailable(t),
        if (widget.color && s != null) ...[
          AppPanel(
            child: Row(children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: Color.fromARGB(255, s.r, s.g, s.b), borderRadius: BorderRadius.circular(14)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(children: [
                  AppResult(label: 'HEX', value: _hex(s.r, s.g, s.b), lang: t.lang),
                  AppResult(label: 'RGB', value: '${s.r}, ${s.g}, ${s.b}', lang: t.lang),
                ]),
              ),
            ]),
          ),
          AppInfoCard(L(t, 'tap_color'), icon: Icons.touch_app_rounded),
        ],
        if (!widget.color && s != null) ...[
          BigReadout((s.luma * _k).toStringAsFixed(0), unit: 'lx ≈'),
          Sparkline(_hist, min: 0, max: 255),
          AppPanel(
            child: Row(children: [
              Text(L(t, 'calibration')),
              Expanded(
                child: Slider(
                  min: 0.5,
                  max: 20,
                  value: _k,
                  onChanged: (v) => setState(() => _k = v),
                  onChangeEnd: (v) => t.store.write('k', '$v'),
                ),
              ),
            ]),
          ),
          AppInfoCard(L(t, 'approx')),
          AppInfoCard(L(t, 'point_camera'), icon: Icons.light_mode_rounded),
        ],
      ]),
    );
  }
}

Widget lightMeterTool(ToolContext t) => _FrameTool(t, color: false);
Widget colorPickerTool(ToolContext t) => _FrameTool(t, color: true);

// ------------------------------------------------- mesafe ve yükseklik

class DistanceTool extends StatefulWidget {
  final ToolContext t;
  const DistanceTool(this.t, {super.key});

  @override
  State<DistanceTool> createState() => _DistanceToolState();
}

class _DistanceToolState extends State<DistanceTool> {
  final _w = SensorWatch<AccelerometerEvent>();
  final _h = TextEditingController(text: '1.5');
  double _angle = 0; // ufkun altındaki açı (derece)
  double? _dist;
  double? _height;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.read('h').then((v) {
      if (v != null && mounted) setState(() => _h.text = v);
    });
    _w.start(() => accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval), (e) {
      // Telefon dik tutulurken: y yerçekimi, z kameranın aşağı eğimi.
      final a = math.atan2(e.z, e.y) * 180 / math.pi;
      setState(() => _angle = _angle * 0.8 + a * 0.2);
    }, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _w.stop();
    _h.dispose();
    super.dispose();
  }

  void _tap() {
    final h = parseNumber(_h.text) ?? 1.5;
    HapticFeedback.mediumImpact();
    setState(() {
      if (_dist == null) {
        if (_angle <= 1) return;
        _dist = h / math.tan(_angle * math.pi / 180);
      } else {
        _height = h - _dist! * math.tan(_angle * math.pi / 180);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_w.available == false) return ToolList(children: [notAvailable(t)]);
    final s = AppLook.of(context);
    return CameraBox(
      tool: t,
      preset: ResolutionPreset.medium,
      builder: (context, c) => ToolList(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: _tap,
            child: Stack(alignment: Alignment.center, children: [
              cameraPreview(c, height: 300),
              Container(width: double.infinity, height: 2, color: s.accent),
              Container(width: 2, height: 40, color: s.accent),
              Positioned(
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  color: Colors.black54,
                  child: Text(L(t, _dist == null ? 'aim_base' : 'aim_top')),
                ),
              ),
              Positioned(bottom: 8, child: Text('${_angle.toStringAsFixed(1)}°', style: const TextStyle(fontSize: 18))),
            ]),
          ),
        ),
        AppPanel(
          child: Column(children: [
            AppNumberField(
              controller: _h,
              label: L(t, 'cam_height'),
              onChanged: (v) => t.store.write('h', v),
            ),
            AppResult(label: L(t, 'distance'), value: _dist == null ? '—' : '${_dist!.toStringAsFixed(2)} m', lang: t.lang, big: true),
            AppResult(label: L(t, 'height'), value: _height == null ? '—' : '${_height!.toStringAsFixed(2)} m', lang: t.lang, big: true),
            TextButton(
              onPressed: () => setState(() {
                _dist = null;
                _height = null;
              }),
              child: Text(L(t, 'reset')),
            ),
          ]),
        ),
        AppInfoCard(L(t, 'approx')),
      ]),
    );
  }
}

// --------------------------------------------------------------------- SOS

class SosTool extends StatefulWidget {
  final ToolContext t;
  const SosTool(this.t, {super.key});

  @override
  State<SosTool> createState() => _SosToolState();
}

class _SosToolState extends State<SosTool> {
  final _torch = Torch();
  final _siren = TonePlayer();
  final _number = TextEditingController(text: '112');
  final _note = TextEditingController();
  bool _light = false, _sound = false, _flash = false;
  int _gen = 0;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.read('number').then((v) {
      if (v != null && mounted) setState(() => _number.text = v);
    });
    t.store.read('note').then((v) {
      if (v != null && mounted) setState(() => _note.text = v);
    });
  }

  @override
  void dispose() {
    _gen++;
    unawaited(_torch.close());
    _siren.dispose();
    _number.dispose();
    _note.dispose();
    WakelockPlus.disable().catchError((Object _) {});
    super.dispose();
  }

  Future<void> _toggleLight() async {
    if (_light) {
      _gen++;
      setState(() {
        _light = false;
        _flash = false;
      });
      await _torch.set(false);
      return;
    }
    if (!_torch.available && !kIsWeb && await rationaleOnce(context, t, 'camera', Icons.sos_rounded)) {
      await _torch.open();
    }
    WakelockPlus.enable().catchError((Object _) {});
    setState(() => _light = true);
    final gen = ++_gen;
    const u = 200;
    final pattern = <(bool, int)>[
      for (var i = 0; i < 3; i++) ...[(true, u), (false, u)],
      (false, u * 2),
      for (var i = 0; i < 3; i++) ...[(true, u * 3), (false, u)],
      (false, u * 2),
      for (var i = 0; i < 3; i++) ...[(true, u), (false, u)],
      (false, u * 6),
    ];
    while (mounted && gen == _gen) {
      for (final (on, ms) in pattern) {
        if (!mounted || gen != _gen) break;
        setState(() => _flash = on);
        await _torch.set(on);
        await Future<void>.delayed(Duration(milliseconds: ms));
      }
    }
  }

  Future<void> _toggleSound() async {
    if (_sound) {
      await _siren.stop();
      setState(() => _sound = false);
      return;
    }
    final seg = <(double, int)>[for (var f = 600.0; f <= 1400; f += 40) (f, 25), for (var f = 1400.0; f >= 600; f -= 40) (f, 25)];
    await _siren.play(makeWav(seg, volume: 1), loop: true);
    setState(() => _sound = true);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      ToolList(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _light ? Colors.redAccent : Colors.white12,
                  padding: const EdgeInsets.symmetric(vertical: 22),
                ),
                icon: const Icon(Icons.sos_rounded, size: 32),
                label: Text(L(t, 'sos_light')),
                onPressed: _toggleLight,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _sound ? Colors.redAccent : Colors.white12,
                  padding: const EdgeInsets.symmetric(vertical: 22),
                ),
                icon: const Icon(Icons.campaign_rounded, size: 32),
                label: Text(L(t, 'siren')),
                onPressed: _toggleSound,
              ),
            ),
          ]),
        ),
        AppPanel(
          child: Column(children: [
            AppTextField(controller: _number, label: L(t, 'emergency_number'), onChanged: (v) => t.store.write('number', v)),
            AppButton(
              label: L(t, 'call_emergency'),
              icon: Icons.call_rounded,
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: _number.text.trim())),
            ),
          ]),
        ),
        AppPanel(
          child: AppTextField(
            controller: _note,
            label: L(t, 'medical_note'),
            maxLines: 4,
            onChanged: (v) => t.store.write('note', v),
          ),
        ),
      ]),
      if (_flash) Positioned.fill(child: IgnorePointer(child: Container(color: Colors.white))),
    ]);
  }
}
