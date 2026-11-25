/// Göz koruma / gece filtresi. Android'de diğer uygulamaların üstünde
/// dokunmaları geçiren sıcak renkli bir katman (yerleşik servis); iOS ve
/// web'de sistemin kendi gece modu açıklanır ve uygulama içi önizleme
/// gösterilir.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../platform/filter.dart';

/// Renk sıcaklığından (Kelvin) yaklaşık RGB (siyah cisim, 1000–6600 K).
Color kelvinColor(double k) {
  final t = k.clamp(1000.0, 6600.0) / 100;
  double r, g, b;
  if (t <= 66) {
    r = 255;
    g = 99.4708025861 * math.log(t) - 161.1195681661;
    b = t <= 19 ? 0 : 138.5177312231 * math.log(t - 10) - 305.0447927307;
  } else {
    r = 329.698727446 * math.pow(t - 60, -0.1332047592);
    g = 288.1221695283 * math.pow(t - 60, -0.0755148492);
    b = 255;
  }
  int c(double v) => v.clamp(0, 255).round();
  return Color.fromARGB(255, c(r), c(g), c(b));
}

/// Filtre katmanı rengi: sıcaklık rengi [dim] (0–1) oranında karartılır.
Color filterColor(double kelvin, double dim) => Color.lerp(kelvinColor(kelvin), Colors.black, dim.clamp(0.0, 1.0))!;

/// Saydamlık (Android 12+ dokunma güvenliği için en fazla 0,8).
double filterAlpha(double intensity) => (intensity.clamp(0.0, 1.0) * 0.8);

int _rgb(Color c) =>
    ((c.r * 255).round() & 0xFF) << 16 | ((c.g * 255).round() & 0xFF) << 8 | ((c.b * 255).round() & 0xFF);

class EyeFilterTool extends StatefulWidget {
  final ToolContext t;
  const EyeFilterTool(this.t, {super.key});

  @override
  State<EyeFilterTool> createState() => _EyeFilterToolState();
}

class _EyeFilterToolState extends State<EyeFilterTool> with WidgetsBindingObserver {
  double _kelvin = 2700;
  double _intensity = 0.35;
  double _dim = 0.1;
  bool _on = false;
  bool _perm = false;
  bool _preview = true;
  Timer? _push;

  ToolContext get t => widget.t;

  static const _presets = [(1800.0, 0.45, 0.15), (2700.0, 0.35, 0.1), (3400.0, 0.25, 0.0), (4500.0, 0.15, 0.0)];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    final k = await t.store.readDouble('kelvin', _kelvin);
    final i = await t.store.readDouble('intensity', _intensity);
    final d = await t.store.readDouble('dim', _dim);
    final on = await ScreenFilter.running();
    final perm = await ScreenFilter.canDraw();
    if (!mounted) return;
    setState(() {
      _kelvin = k;
      _intensity = i;
      _dim = d;
      _on = on;
      _perm = perm;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ScreenFilter.canDraw().then((v) {
        if (mounted) setState(() => _perm = v);
      });
    }
  }

  void _save() {
    unawaited(t.store.write('kelvin', '$_kelvin'));
    unawaited(t.store.write('intensity', '$_intensity'));
    unawaited(t.store.write('dim', '$_dim'));
    if (_on) {
      _push?.cancel();
      _push = Timer(const Duration(milliseconds: 80),
          () => ScreenFilter.start(_rgb(filterColor(_kelvin, _dim)), filterAlpha(_intensity)));
    }
  }

  Future<void> _toggle(bool v) async {
    if (!v) {
      await ScreenFilter.stop();
      if (mounted) setState(() => _on = false);
      return;
    }
    if (!await ScreenFilter.canDraw()) {
      if (!mounted) return;
      final go = await explainPermission(context, lang: t.lang, icon: Icons.layers_rounded, reason: L(t, 'overlay_perm'));
      if (go) await ScreenFilter.requestPermission();
      return;
    }
    final ok = await ScreenFilter.start(_rgb(filterColor(_kelvin, _dim)), filterAlpha(_intensity));
    if (mounted) setState(() => _on = ok);
  }

  @override
  void dispose() {
    _push?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _slider(String label, String value, double v, double min, double max, ValueChanged<double> f) {
    return Row(children: [
      SizedBox(width: 110, child: Text(label)),
      Expanded(child: Slider(min: min, max: max, value: v.clamp(min, max), onChanged: f, onChangeEnd: (_) => _save())),
      SizedBox(width: 56, child: Text(value, textAlign: TextAlign.end)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final android = ScreenFilter.supported;
    final color = filterColor(_kelvin, _dim);
    final names = Ls(t, 'filter_presets');
    return Stack(children: [
      ToolList(children: [
        if (!android)
          AppInfoCard(
            L(t, !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? 'filter_ios' : 'filter_web'),
            icon: Icons.nightlight_round,
          ),
        if (android)
          AppPanel(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(_on ? Icons.nightlight_round : Icons.nightlight_outlined, color: color),
              title: Text(L(t, 'eye_filter'), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(_on ? L(t, 'on') : L(t, 'off')),
              value: _on,
              onChanged: _toggle,
            ),
          ),
        if (android && !_perm) AppInfoCard(L(t, 'overlay_perm'), icon: Icons.layers_rounded),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            for (var i = 0; i < _presets.length; i++)
              ChoiceChip(
                label: Text(i < names.length ? names[i] : '${_presets[i].$1.round()} K'),
                selected: _kelvin == _presets[i].$1 && _intensity == _presets[i].$2 && _dim == _presets[i].$3,
                onSelected: (_) {
                  setState(() {
                    _kelvin = _presets[i].$1;
                    _intensity = _presets[i].$2;
                    _dim = _presets[i].$3;
                  });
                  _save();
                },
              ),
          ]),
        ),
        AppPanel(
          child: Column(children: [
            _slider(L(t, 'warmth'), '${_kelvin.round()} K', _kelvin, 1000, 6500, (v) => setState(() => _kelvin = v)),
            _slider(L(t, 'intensity'), '${(_intensity * 100).round()}%', _intensity, 0, 1,
                (v) => setState(() => _intensity = v)),
            _slider(L(t, 'dim'), '${(_dim * 100).round()}%', _dim, 0, 0.9, (v) => setState(() => _dim = v)),
          ]),
        ),
        AppPanel(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(L(t, 'preview')),
            value: _preview,
            onChanged: (v) => setState(() => _preview = v),
          ),
        ),
        AppPanel(
          child: Container(
            height: 90,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [Colors.white, Color(0xFF90CAF9), Color(0xFF3949AB)]),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: color.withValues(alpha: filterAlpha(_intensity)),
            ),
          ),
        ),
      ]),
      // Uygulama içi önizleme (Android'de filtre açıkken çift katman olmasın).
      if (_preview && !_on)
        Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: color.withValues(alpha: filterAlpha(_intensity) * 0.6))),
        ),
    ]);
  }
}
