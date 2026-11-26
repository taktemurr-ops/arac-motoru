/// Android kızılötesi verici köprüsü (arac_motoru/ir, ConsumerIrManager).
/// Diğer platformlarda verici yoktur.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../tools/ir.dart' show IrFrame;

class IrBlaster {
  static const _ch = MethodChannel('arac_motoru/ir');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Telefonda kızılötesi verici var mı?
  static Future<bool> hasEmitter() async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('has') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Çerçeveyi gönderir; başarılıysa true.
  static Future<bool> transmit(IrFrame f) async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('transmit', {'carrier': f.carrier, 'pattern': f.pattern}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
