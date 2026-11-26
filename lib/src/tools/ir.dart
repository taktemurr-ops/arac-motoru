/// Kızılötesi TV kumandası. Yalnızca kızılötesi vericisi (IR blaster) olan
/// Android telefonlarda çalışır; kodlar protokol tanımlarından (NEC, 32 bit
/// Samsung, Sony SIRC, Philips RC5) cihazda üretilir. Marka adları yalnızca
/// uyumluluk listesinde geçer; logo kullanılmaz.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../platform/ir.dart';

// ------------------------------------------------------------ protokoller

/// Gönderilecek tek bir kızılötesi çerçeve: taşıyıcı frekansı (Hz) ve
/// açık/kapalı süreleri (mikrosaniye, ilk değer "açık").
class IrFrame {
  final int carrier;
  final List<int> pattern;
  const IrFrame(this.carrier, this.pattern);

  /// Toplam süre (µs).
  int get duration => pattern.fold<int>(0, (a, b) => a + b);
}

enum IrProtocol { nec, samsung, sony12, rc5 }

List<int> _bitsLsb(int value, int count) => [for (var i = 0; i < count; i++) (value >> i) & 1];

/// NEC: 9 ms başlık, adres, ters adres, komut, ters komut (LSB önce).
IrFrame irNec(int address, int command) {
  final p = <int>[9000, 4500];
  for (final b in [
    ..._bitsLsb(address & 0xFF, 8),
    ..._bitsLsb(~address & 0xFF, 8),
    ..._bitsLsb(command & 0xFF, 8),
    ..._bitsLsb(~command & 0xFF, 8),
  ]) {
    p..add(560)..add(b == 1 ? 1690 : 560);
  }
  p.add(560);
  return IrFrame(38000, p);
}

/// 32 bit Samsung: 4,5 ms başlık, adres iki kez, komut, ters komut.
IrFrame irSamsung(int address, int command) {
  final p = <int>[4500, 4500];
  for (final b in [
    ..._bitsLsb(address & 0xFF, 8),
    ..._bitsLsb(address & 0xFF, 8),
    ..._bitsLsb(command & 0xFF, 8),
    ..._bitsLsb(~command & 0xFF, 8),
  ]) {
    p..add(560)..add(b == 1 ? 1690 : 560);
  }
  p.add(560);
  return IrFrame(38000, p);
}

/// Sony SIRC 12 bit: 7 bit komut + 5 bit adres; çerçeve 45 ms aralıkla 3 kez.
IrFrame irSony12(int address, int command) {
  final one = <int>[2400, 600];
  for (final b in [..._bitsLsb(command & 0x7F, 7), ..._bitsLsb(address & 0x1F, 5)]) {
    one..add(b == 1 ? 1200 : 600)..add(600);
  }
  final busy = one.fold<int>(0, (a, b) => a + b) - one.last;
  final framed = [...one]..[one.length - 1] = 45000 - busy;
  final p = <int>[...framed, ...framed, ...one.sublist(0, one.length - 1)];
  return IrFrame(40000, p);
}

/// Philips RC5: 14 bit Manchester (889 µs yarım bit), MSB önce.
IrFrame irRc5(int address, int command, {bool toggle = false}) {
  final bits = <int>[
    1,
    command >= 64 ? 0 : 1, // RC5X: 7. komut biti ters ikinci başlangıç biti
    toggle ? 1 : 0,
    for (var i = 4; i >= 0; i--) (address >> i) & 1,
    for (var i = 5; i >= 0; i--) (command >> i) & 1,
  ];
  // Yarım bit düzeyleri: 1 = boşluk sonra işaret, 0 = işaret sonra boşluk.
  final halves = <bool>[];
  for (final b in bits) {
    halves.addAll(b == 1 ? const [false, true] : const [true, false]);
  }
  while (halves.isNotEmpty && !halves.first) {
    halves.removeAt(0);
  }
  while (halves.isNotEmpty && !halves.last) {
    halves.removeLast();
  }
  final p = <int>[];
  bool? level;
  for (final h in halves) {
    if (h == level) {
      p[p.length - 1] += 889;
    } else {
      p.add(889);
      level = h;
    }
  }
  return IrFrame(36000, p);
}

IrFrame irEncode(IrProtocol proto, int address, int command) {
  switch (proto) {
    case IrProtocol.nec:
      return irNec(address, command);
    case IrProtocol.samsung:
      return irSamsung(address, command);
    case IrProtocol.sony12:
      return irSony12(address, command);
    case IrProtocol.rc5:
      return irRc5(address, command);
  }
}

/// Protokole göre izin verilen en büyük adres ve komut.
(int, int) irLimits(IrProtocol p) => switch (p) {
      IrProtocol.nec || IrProtocol.samsung => (255, 255),
      IrProtocol.sony12 => (31, 127),
      IrProtocol.rc5 => (31, 127),
    };

/// Kumanda düğmeleri (sıra ekrandaki dizilişle aynı).
const List<String> kIrButtons = [
  'power', 'input', 'mute', 'vol_up', 'vol_down', 'ch_up', 'ch_down', 'menu', 'home', 'back',
  'up', 'down', 'left', 'right', 'ok', 'd1', 'd2', 'd3', 'd4', 'd5', 'd6', 'd7', 'd8', 'd9', 'd0',
];

/// Uyumlu televizyon aileleri: protokol, adres ve düğme → komut.
/// Kodlar protokol belgelerinden ve yaygın açık kaynak kızılötesi
/// veritabanlarından derlenmiştir; her modelde çalışmayabilir.
class IrProfile {
  final String id;
  final String name;
  final IrProtocol protocol;
  final int address;
  final Map<String, int> codes;
  const IrProfile(this.id, this.name, this.protocol, this.address, this.codes);

  IrFrame? frame(String button) {
    final c = codes[button];
    return c == null ? null : irEncode(protocol, address, c);
  }
}

const List<IrProfile> kIrProfiles = [
  IrProfile('samsung', 'Samsung', IrProtocol.samsung, 0x07, {
    'power': 0x02, 'input': 0x01, 'mute': 0x0F, 'vol_up': 0x07, 'vol_down': 0x0B, 'ch_up': 0x12, 'ch_down': 0x10,
    'menu': 0x1A, 'home': 0x79, 'back': 0x58, 'up': 0x60, 'down': 0x61, 'left': 0x65, 'right': 0x62, 'ok': 0x68,
    'd1': 0x04, 'd2': 0x05, 'd3': 0x06, 'd4': 0x08, 'd5': 0x09, 'd6': 0x0A, 'd7': 0x0C, 'd8': 0x0D, 'd9': 0x0E,
    'd0': 0x11,
  }),
  IrProfile('lg', 'LG', IrProtocol.nec, 0x04, {
    'power': 0x08, 'input': 0x0B, 'mute': 0x09, 'vol_up': 0x02, 'vol_down': 0x03, 'ch_up': 0x00, 'ch_down': 0x01,
    'menu': 0x43, 'home': 0x7C, 'back': 0x28, 'up': 0x40, 'down': 0x41, 'left': 0x07, 'right': 0x06, 'ok': 0x44,
    'd1': 0x11, 'd2': 0x12, 'd3': 0x13, 'd4': 0x14, 'd5': 0x15, 'd6': 0x16, 'd7': 0x17, 'd8': 0x18, 'd9': 0x19,
    'd0': 0x10,
  }),
  IrProfile('sony', 'Sony', IrProtocol.sony12, 0x01, {
    'power': 21, 'input': 37, 'mute': 20, 'vol_up': 18, 'vol_down': 19, 'ch_up': 16, 'ch_down': 17, 'home': 96,
    'up': 116, 'down': 117, 'left': 52, 'right': 51, 'ok': 101,
    'd1': 0, 'd2': 1, 'd3': 2, 'd4': 3, 'd5': 4, 'd6': 5, 'd7': 6, 'd8': 7, 'd9': 8, 'd0': 9,
  }),
  IrProfile('philips', 'Philips (RC5)', IrProtocol.rc5, 0x00, {
    'power': 12, 'mute': 13, 'vol_up': 16, 'vol_down': 17, 'ch_up': 32, 'ch_down': 33,
    'd1': 1, 'd2': 2, 'd3': 3, 'd4': 4, 'd5': 5, 'd6': 6, 'd7': 7, 'd8': 8, 'd9': 9, 'd0': 0,
  }),
];

// ------------------------------------------------------------------- araç

class IrRemoteTool extends StatefulWidget {
  final ToolContext t;
  const IrRemoteTool(this.t, {super.key});

  @override
  State<IrRemoteTool> createState() => _IrRemoteToolState();
}

class _IrRemoteToolState extends State<IrRemoteTool> {
  bool? _has;
  String _profile = kIrProfiles.first.id;
  String? _flash;
  Timer? _scan;
  int _scanIndex = -1;
  IrProtocol _cProto = IrProtocol.nec;
  final _cAddr = TextEditingController(text: '0');
  final _cCmd = TextEditingController(text: '0');
  final _cName = TextEditingController();
  final List<Map<String, Object?>> _custom = [];

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final has = await IrBlaster.hasEmitter();
    final p = await t.store.read('profile');
    final c = await t.store.readList('custom');
    if (!mounted) return;
    setState(() {
      _has = has;
      if (p != null && kIrProfiles.any((x) => x.id == p)) _profile = p;
      _custom.addAll(c);
    });
  }

  @override
  void dispose() {
    _scan?.cancel();
    _cAddr.dispose();
    _cCmd.dispose();
    _cName.dispose();
    super.dispose();
  }

  IrProfile get _p => kIrProfiles.firstWhere((x) => x.id == _profile);

  Future<void> _send(IrFrame? f, String key) async {
    if (f == null) return;
    unawaited(HapticFeedback.lightImpact());
    final ok = await IrBlaster.transmit(f);
    if (!mounted) return;
    setState(() => _flash = key);
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(L(t, 'ir_failed'))));
    }
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted && _flash == key) setState(() => _flash = null);
    });
  }

  void _startScan() {
    _scan?.cancel();
    setState(() => _scanIndex = 0);
    unawaited(_send(kIrProfiles[0].frame('power'), 'scan'));
    _scan = Timer.periodic(const Duration(milliseconds: 2500), (tm) {
      if (!mounted) {
        tm.cancel();
        return;
      }
      final next = _scanIndex + 1;
      if (next >= kIrProfiles.length) {
        tm.cancel();
        setState(() => _scanIndex = -1);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(L(t, 'ir_scan_none'))));
        return;
      }
      setState(() => _scanIndex = next);
      unawaited(_send(kIrProfiles[next].frame('power'), 'scan'));
    });
  }

  void _scanWorked() {
    _scan?.cancel();
    final p = kIrProfiles[_scanIndex.clamp(0, kIrProfiles.length - 1)];
    setState(() {
      _profile = p.id;
      _scanIndex = -1;
    });
    unawaited(t.store.write('profile', p.id));
  }

  IconData _icon(String b) => switch (b) {
        'power' => Icons.power_settings_new_rounded,
        'input' => Icons.input_rounded,
        'mute' => Icons.volume_off_rounded,
        'vol_up' => Icons.volume_up_rounded,
        'vol_down' => Icons.volume_down_rounded,
        'ch_up' => Icons.keyboard_arrow_up_rounded,
        'ch_down' => Icons.keyboard_arrow_down_rounded,
        'menu' => Icons.menu_rounded,
        'home' => Icons.home_rounded,
        'back' => Icons.undo_rounded,
        'up' => Icons.arrow_drop_up_rounded,
        'down' => Icons.arrow_drop_down_rounded,
        'left' => Icons.arrow_left_rounded,
        'right' => Icons.arrow_right_rounded,
        _ => Icons.circle_outlined,
      };

  /// Düğme adı (ekran okuyucu için); sıra 'ir_names' etiketiyle aynı.
  String _name(String b) {
    const keys = ['power', 'input', 'mute', 'vol_up', 'vol_down', 'ch_up', 'ch_down', 'menu', 'home', 'back', 'up',
        'down', 'left', 'right'];
    final names = Ls(t, 'ir_names');
    final i = keys.indexOf(b);
    return i >= 0 && i < names.length ? names[i].trim() : b;
  }

  Widget _btn(String b, {double size = 64, Color? color}) {
    final f = _p.frame(b);
    final s = AppLook.of(context);
    final label = b.startsWith('d') ? b.substring(1) : (b == 'ok' ? 'OK' : null);
    final on = _flash == b;
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Semantics(
        button: true,
        label: label ?? _name(b),
        child: Material(
          color: f == null ? Colors.white10 : (on ? s.accent : (color ?? s.card)),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: f == null ? null : () => _send(f, b),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: label != null
                    ? Text(label,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: f == null ? Colors.white24 : Colors.white))
                    : Icon(_icon(b), size: size * 0.5, color: f == null ? Colors.white24 : Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(List<Widget> c) => Row(mainAxisAlignment: MainAxisAlignment.center, children: c);

  @override
  Widget build(BuildContext context) {
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!android) {
      return ToolList(children: [
        AppInfoCard(L(t, 'ir_android_only'), icon: Icons.settings_remote_rounded),
        AppInfoCard(L(t, 'ir_compat'), icon: Icons.tv_rounded),
      ]);
    }
    if (_has == null) return const Center(child: CircularProgressIndicator());
    if (_has == false) {
      return ToolList(children: [
        AppInfoCard(L(t, 'ir_no_emitter'), icon: Icons.settings_remote_rounded),
        AppInfoCard(L(t, 'ir_compat'), icon: Icons.tv_rounded),
      ]);
    }
    final (maxA, maxC) = irLimits(_cProto);
    return ToolList(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Pick<String>(
          label: L(t, 'ir_tv'),
          values: [for (final p in kIrProfiles) p.id],
          text: (id) => kIrProfiles.firstWhere((p) => p.id == id).name,
          value: _profile,
          onChanged: (v) {
            setState(() => _profile = v);
            unawaited(t.store.write('profile', v));
          },
        ),
      ),
      if (_scanIndex >= 0)
        AppPanel(
          child: Column(children: [
            Text('${L(t, 'ir_scan_try')} ${kIrProfiles[_scanIndex].name} (${_scanIndex + 1}/${kIrProfiles.length})',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            AppButton(label: L(t, 'ir_scan_ok'), icon: Icons.check_rounded, onPressed: _scanWorked),
            TextButton(
              onPressed: () {
                _scan?.cancel();
                setState(() => _scanIndex = -1);
              },
              child: Text(L(t, 'stop')),
            ),
          ]),
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppButton(label: L(t, 'ir_scan'), icon: Icons.manage_search_rounded, onPressed: _startScan),
        ),
      AppPanel(
        child: Column(children: [
          _row([_btn('power', color: const Color(0xFFC62828)), _btn('input'), _btn('mute')]),
          // Dar ekranlarda (320 dp) orta blok orantılı küçülür.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: _row([
              Column(children: [_btn('vol_up'), const Text('VOL'), _btn('vol_down')]),
              const SizedBox(width: 16),
              Column(children: [_btn('up'), _row([_btn('left'), _btn('ok'), _btn('right')]), _btn('down')]),
              const SizedBox(width: 16),
              Column(children: [_btn('ch_up'), const Text('CH'), _btn('ch_down')]),
            ]),
          ),
          _row([_btn('menu'), _btn('home'), _btn('back')]),
          for (final r in const [
            ['d1', 'd2', 'd3'],
            ['d4', 'd5', 'd6'],
            ['d7', 'd8', 'd9'],
            ['d0'],
          ])
            _row([for (final b in r) _btn(b, size: 56)]),
        ]),
      ),
      AppHeading(L(t, 'ir_custom'), icon: Icons.tune_rounded),
      AppPanel(
        child: Column(children: [
          Choice<IrProtocol>(
            values: IrProtocol.values,
            labels: const ['NEC', 'Samsung32', 'SIRC-12', 'RC5'],
            selected: _cProto,
            onChanged: (v) => setState(() => _cProto = v),
          ),
          Row(children: [
            Expanded(child: AppNumberField(controller: _cAddr, label: '${L(t, 'ir_address')} (0–$maxA)', decimal: false)),
            const SizedBox(width: 12),
            Expanded(child: AppNumberField(controller: _cCmd, label: '${L(t, 'ir_command')} (0–$maxC)', decimal: false)),
          ]),
          AppTextField(controller: _cName, label: L(t, 'name')),
          Row(children: [
            Expanded(
              child: AppButton(
                label: L(t, 'ir_send'),
                icon: Icons.settings_remote_rounded,
                onPressed: () {
                  final a = (int.tryParse(_cAddr.text) ?? -1);
                  final c = (int.tryParse(_cCmd.text) ?? -1);
                  if (a < 0 || a > maxA || c < 0 || c > maxC) {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(L(t, 'invalid'))));
                    return;
                  }
                  unawaited(_send(irEncode(_cProto, a, c), 'custom'));
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: L(t, 'add'),
              icon: const Icon(Icons.bookmark_add_rounded),
              onPressed: () {
                final a = (int.tryParse(_cAddr.text) ?? -1);
                final c = (int.tryParse(_cCmd.text) ?? -1);
                if (a < 0 || a > maxA || c < 0 || c > maxC) return;
                final name = _cName.text.trim().isEmpty ? '${_cProto.name} $a/$c' : _cName.text.trim();
                setState(() => _custom.add({'n': name, 'p': _cProto.name, 'a': a, 'c': c}));
                unawaited(t.store.writeList('custom', _custom));
              },
            ),
          ]),
        ]),
      ),
      for (var i = 0; i < _custom.length; i++)
        ListTile(
          leading: const Icon(Icons.settings_remote_rounded),
          title: Text('${_custom[i]['n']}'),
          subtitle: Text('${_custom[i]['p']} · ${_custom[i]['a']} / ${_custom[i]['c']}'),
          onTap: () {
            final m = _custom[i];
            final p = IrProtocol.values.firstWhere((x) => x.name == m['p'], orElse: () => IrProtocol.nec);
            unawaited(_send(irEncode(p, (m['a'] as num?)?.toInt() ?? 0, (m['c'] as num?)?.toInt() ?? 0), 'custom'));
          },
          trailing: IconButton(
            tooltip: L(t, 'delete'),
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () {
              setState(() => _custom.removeAt(i));
              unawaited(t.store.writeList('custom', _custom));
            },
          ),
        ),
      AppInfoCard(L(t, 'ir_compat'), icon: Icons.tv_rounded),
    ]);
  }
}
