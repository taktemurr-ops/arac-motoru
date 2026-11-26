/// Android "alkışla/ıslıkla bul" ön plan hizmeti köprüsü
/// (arac_motoru/finder → FinderService.java). Diğer platformlarda yok.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SoundFinderService {
  static const _ch = MethodChannel('arac_motoru/finder');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Arka planda dinlemeyi başlatır (kalıcı bildirimle). Başlarsa true.
  static Future<bool> start({
    required bool claps,
    required bool whistle,
    required double sensitivity,
    required bool sound,
    required bool flash,
    required bool vibrate,
    required String title,
    required String body,
    required String alertTitle,
    required String stopLabel,
    required String stopListen,
  }) async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('start', {
            'claps': claps,
            'whistle': whistle,
            'sensitivity': sensitivity,
            'sound': sound,
            'flash': flash,
            'vibrate': vibrate,
            'title': title,
            'body': body,
            'alertTitle': alertTitle,
            'stopLabel': stopLabel,
            'stopListen': stopListen,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<bool>('stop');
    } catch (_) {}
  }

  static Future<bool> running() async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('running') ?? false;
    } catch (_) {
      return false;
    }
  }
}
