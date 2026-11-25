/// Android ekran filtresi köprüsü (arac_motoru/filter). Diğer platformlarda
/// [ScreenFilter.supported] false döner.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenFilter {
  static const _ch = MethodChannel('arac_motoru/filter');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<T?> _call<T>(String m, [Map<String, Object?>? a]) async {
    if (!supported) return null;
    try {
      return await _ch.invokeMethod<T>(m, a);
    } catch (_) {
      return null;
    }
  }

  /// "Diğer uygulamaların üzerinde göster" izni var mı?
  static Future<bool> canDraw() async => await _call<bool>('canDraw') ?? false;

  /// Sistem izin ekranını açar.
  static Future<bool> requestPermission() async => await _call<bool>('requestPermission') ?? false;

  /// Filtreyi açar ya da günceller. [color] opak RGB, [alpha] 0–0.8.
  static Future<bool> start(int color, double alpha) async =>
      await _call<bool>('start', {'color': color, 'alpha': alpha}) ?? false;

  static Future<void> stop() => _call<bool>('stop');

  static Future<bool> running() async => await _call<bool>('running') ?? false;
}
