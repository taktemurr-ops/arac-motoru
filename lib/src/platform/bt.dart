/// Bluetooth tarama köprüsü (arac_motoru/bt, arac_motoru/bt_scan): Android'de
/// BLE + klasik keşif, iPhone'da CoreBluetooth (BLE). Web'de yok.
/// Yalnızca yakındaki cihazların adı, kimliği ve sinyal gücü okunur;
/// bağlantı kurulmaz, konum gönderilmez.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Taramada görülen bir cihaz.
class BtSeen {
  final String id;
  final String name;
  final int rssi;

  /// 'le' ya da 'classic'.
  final String type;
  final bool bonded;
  const BtSeen(this.id, this.name, this.rssi, this.type, this.bonded);

  static BtSeen? fromMap(Object? o) {
    if (o is! Map) return null;
    final id = o['id'];
    final rssi = o['rssi'];
    if (id is! String || rssi is! num) return null;
    return BtSeen(id, (o['name'] as String?) ?? '', rssi.toInt(), (o['type'] as String?) ?? 'le', o['bonded'] == true);
  }
}

class BtScanner {
  static const _ch = MethodChannel('arac_motoru/bt');
  static const _ev = EventChannel('arac_motoru/bt_scan');

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// 'on', 'off', 'unauthorized', 'unsupported' ya da 'unknown'.
  static Future<String> state() async {
    if (!supported) return 'unsupported';
    try {
      return await _ch.invokeMethod<String>('state') ?? 'unknown';
    } catch (_) {
      return 'unsupported';
    }
  }

  /// Sistem Bluetooth ayarlarını açar.
  static Future<void> openSettings() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<bool>('settings');
    } catch (_) {}
  }

  /// Tarama akışı; dinleme bitince tarama durur.
  static Stream<BtSeen> scan() =>
      _ev.receiveBroadcastStream().map(BtSeen.fromMap).where((e) => e != null).cast<BtSeen>();
}
