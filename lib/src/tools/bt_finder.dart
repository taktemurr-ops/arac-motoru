/// Bluetooth cihaz bulucu: kayıp kulaklık, saat ya da bileklik için sinyal
/// gücüne göre "sıcak–soğuk" yol gösterir. Bağlantı kurulmaz; konum
/// alınmaz ve gönderilmez.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../platform/bt.dart';

/// Yaklaşık uzaklık (m): yol kaybı modeli (1 m'de −59 dBm, üs 2,5).
/// Duvarlar ve vücut sinyali zayıflatır; yalnızca yön göstermek içindir.
double btDistance(int rssi, {int txPower = -59, double n = 2.5}) =>
    math.pow(10, (txPower - rssi) / (10 * n)).toDouble();

/// 0 (soğuk, −100 dBm) – 1 (çok sıcak, −40 dBm).
double btWarmth(double rssi) => ((rssi + 100) / 60).clamp(0.0, 1.0);

/// Sinyal gücünü yumuşatır ve yaklaşma/uzaklaşma eğilimini verir.
class RssiSmoother {
  double? value;
  final List<(int, double)> _hist = [];

  /// [ms] zaman damgasıyla yeni ölçüm ekler.
  double add(int rssi, int ms) {
    final v = value;
    value = v == null ? rssi.toDouble() : v * 0.7 + rssi * 0.3;
    _hist.add((ms, value!));
    _hist.removeWhere((e) => ms - e.$1 > 4000);
    return value!;
  }

  void reset() {
    value = null;
    _hist.clear();
  }

  /// Son ~3 saniyedeki değişim (dBm); artı = yaklaşıyor.
  double get trend {
    if (_hist.length < 2) return 0;
    final last = _hist.last;
    final old = _hist.firstWhere((e) => last.$1 - e.$1 <= 3000, orElse: () => _hist.first);
    return last.$2 - old.$2;
  }
}

class BtFinderTool extends StatefulWidget {
  final ToolContext t;
  const BtFinderTool(this.t, {super.key});

  @override
  State<BtFinderTool> createState() => _BtFinderToolState();
}

class _BtFinderToolState extends State<BtFinderTool> {
  String _state = 'unknown';
  StreamSubscription<BtSeen>? _sub;
  final Map<String, BtSeen> _seen = {};
  final Map<String, int> _lastSeen = {};
  String? _track;
  final _smooth = RssiSmoother();
  bool _namedOnly = true;
  bool _beep = true;
  final _player = TonePlayer();
  Timer? _tick;
  int _lastBeep = 0;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _tick?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<bool> _permissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    var sdk = 31;
    try {
      sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (_) {}
    final perms = sdk >= 31
        ? [Permission.bluetoothScan, Permission.bluetoothConnect]
        : [Permission.locationWhenInUse];
    final r = await perms.request();
    return r.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> _begin() async {
    if (!BtScanner.supported) {
      setState(() => _state = 'unsupported');
      return;
    }
    if (!await rationaleOnce(context, t, 'bt', Icons.bluetooth_searching_rounded)) {
      if (mounted) setState(() => _state = 'unauthorized');
      return;
    }
    if (!await _permissions()) {
      if (mounted) setState(() => _state = 'unauthorized');
      return;
    }
    final st = await BtScanner.state();
    if (!mounted) return;
    setState(() => _state = st);
    if (st == 'on' || st == 'unknown') _scan();
  }

  void _scan() {
    unawaited(_sub?.cancel());
    _sub = BtScanner.scan().listen((d) {
      if (!mounted) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        final old = _seen[d.id];
        _seen[d.id] = BtSeen(d.id, d.name.isEmpty ? (old?.name ?? '') : d.name, d.rssi, d.type, d.bonded || (old?.bonded ?? false));
        _lastSeen[d.id] = now;
        if (d.id == _track) _smooth.add(d.rssi, now);
        _state = 'on';
      });
    }, onError: (Object e) {
      if (!mounted) return;
      final msg = '$e';
      setState(() => _state = msg.contains('off') ? 'off' : (msg.contains('auth') ? 'unauthorized' : _state));
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 400), (_) => _onTick());
  }

  void _onTick() {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 30 sn görülmeyen cihazlar listeden düşer (izlenen hariç).
    final stale = [for (final e in _lastSeen.entries) if (now - e.value > 30000 && e.key != _track) e.key];
    if (stale.isNotEmpty) {
      setState(() {
        for (final k in stale) {
          _seen.remove(k);
          _lastSeen.remove(k);
        }
      });
    }
    final v = _smooth.value;
    if (_track != null && _beep && v != null && now - (_lastSeen[_track] ?? 0) < 5000) {
      // Yaklaştıkça daha sık "bip" (Geiger sayacı gibi).
      final gap = (1600 - 1400 * btWarmth(v)).round();
      if (now - _lastBeep >= gap) {
        _lastBeep = now;
        unawaited(_player.play(makeWav([(1200 + 800 * btWarmth(v), 45)], volume: 0.6)));
      }
    }
  }

  String _name(BtSeen d) => d.name.isNotEmpty ? d.name : '${L(t, 'bt_unknown')} · ${d.id.length > 5 ? d.id.substring(d.id.length - 5) : d.id}';

  Widget _bars(int rssi) {
    final n = rssi >= -60 ? 4 : rssi >= -70 ? 3 : rssi >= -80 ? 2 : rssi >= -90 ? 1 : 0;
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 0; i < 4; i++)
        Container(
          width: 5,
          height: 6.0 + i * 4,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(color: i < n ? Colors.lightGreenAccent : Colors.white24, borderRadius: BorderRadius.circular(2)),
        ),
    ]);
  }

  Widget _tracker() {
    final d = _seen[_track];
    final v = _smooth.value;
    final now = DateTime.now().millisecondsSinceEpoch;
    final lost = now - (_lastSeen[_track] ?? 0) > 8000;
    final w = v == null ? 0.0 : btWarmth(v);
    final color = Color.lerp(const Color(0xFF42A5F5), const Color(0xFFFF5252), w)!;
    final words = Ls(t, 'bt_levels');
    final word = words[(w * (words.length - 1)).round().clamp(0, words.length - 1)].trim();
    final tr = _smooth.trend;
    return Column(children: [
      AppPanel(
        child: Column(children: [
          Text(d == null ? '' : _name(d), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [color, color.withValues(alpha: 0.15)]),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 30 * w + 6)],
            ),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(lost ? '—' : word,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                if (v != null && !lost) Text('${v.round()} dBm', style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (lost)
            Text(L(t, 'bt_lost'), textAlign: TextAlign.center)
          else if (tr.abs() >= 3)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(tr > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: tr > 0 ? Colors.lightGreenAccent : Colors.orangeAccent),
              const SizedBox(width: 6),
              Text(tr > 0 ? L(t, 'bt_closer') : L(t, 'bt_farther')),
            ]),
          if (v != null && !lost)
            Text('≈ ${btDistance(v.round()).toStringAsFixed(1)} m', style: const TextStyle(color: Colors.white70)),
          SwitchListTile(
            title: Text(L(t, 'bt_beep')),
            value: _beep,
            onChanged: (x) => setState(() => _beep = x),
          ),
          AppButton(
            label: L(t, 'bt_back'),
            icon: Icons.list_rounded,
            onPressed: () => setState(() => _track = null),
          ),
        ]),
      ),
      AppInfoCard(L(t, 'bt_tips'), icon: Icons.tips_and_updates_rounded),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_state == 'unsupported') return ToolList(children: [notAvailable(t), AppInfoCard(L(t, 'bt_web'))]);
    if (_state == 'unauthorized') {
      return ToolList(children: [
        AppInfoCard(appTx('perm_denied', t.lang), icon: Icons.bluetooth_disabled_rounded),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppButton(label: L(t, 'refresh'), icon: Icons.refresh_rounded, onPressed: _begin),
        ),
      ]);
    }
    if (_state == 'off') {
      return ToolList(children: [
        AppInfoCard(L(t, 'bt_off'), icon: Icons.bluetooth_disabled_rounded),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            AppButton(label: L(t, 'bt_settings'), icon: Icons.settings_bluetooth_rounded, onPressed: BtScanner.openSettings),
            const SizedBox(height: 8),
            AppButton(label: L(t, 'refresh'), icon: Icons.refresh_rounded, onPressed: _begin),
          ]),
        ),
      ]);
    }
    if (_track != null) return ToolList(children: [_tracker()]);
    final list = _seen.values.where((d) => !_namedOnly || d.name.isNotEmpty).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return ToolList(children: [
      AppInfoCard(L(t, 'bt_intro'), icon: Icons.bluetooth_searching_rounded),
      SwitchListTile(
        title: Text(L(t, 'bt_named_only')),
        value: _namedOnly,
        onChanged: (v) => setState(() => _namedOnly = v),
      ),
      if (list.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else
        for (final d in list)
          ListTile(
            leading: Icon(d.bonded ? Icons.headphones_rounded : Icons.bluetooth_rounded),
            title: Text(_name(d), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${d.rssi} dBm · ≈ ${btDistance(d.rssi).toStringAsFixed(1)} m${d.bonded ? ' · ${L(t, 'bt_paired')}' : ''}'),
            trailing: _bars(d.rssi),
            onTap: () {
              setState(() {
                _track = d.id;
                _smooth.reset();
              });
            },
          ),
    ]);
  }
}
