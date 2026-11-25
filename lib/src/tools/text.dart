/// Metin ve kod araçları: QR oluşturucu, Mors kodu, şifre üretici.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';

// ------------------------------------------------------------ QR oluşturucu

class QrMakeTool extends StatefulWidget {
  final ToolContext t;
  const QrMakeTool(this.t, {super.key});

  @override
  State<QrMakeTool> createState() => _QrMakeToolState();
}

class _QrMakeToolState extends State<QrMakeTool> {
  int _mode = 0;
  final _text = TextEditingController(text: 'https://');
  final _ssid = TextEditingController();
  final _pass = TextEditingController();
  bool _hidePass = true;

  @override
  void dispose() {
    _text.dispose();
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  static String _wifiEsc(String s) => s.replaceAllMapped(RegExp(r'([\\;,:"])'), (m) => '\\${m[1]}');

  String get _data => _mode == 2
      ? 'WIFI:T:${_pass.text.isEmpty ? 'nopass' : 'WPA'};S:${_wifiEsc(_ssid.text)};P:${_wifiEsc(_pass.text)};;'
      : _text.text;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final data = _data;
    final ok = data.trim().isNotEmpty && (_mode != 2 || _ssid.text.isNotEmpty);
    return ToolList(children: [
      Choice<int>(
        values: const [0, 1, 2],
        labels: [L(t, 'text'), 'URL', 'Wi-Fi'],
        selected: _mode,
        onChanged: (v) => setState(() {
          _mode = v;
          if (v == 1 && !_text.text.startsWith('http')) _text.text = 'https://';
        }),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          if (_mode < 2)
            AppTextField(controller: _text, label: _mode == 0 ? L(t, 'text') : 'URL', maxLines: _mode == 0 ? 4 : 1, onChanged: (_) => setState(() {})),
          if (_mode == 2) ...[
            AppTextField(controller: _ssid, label: L(t, 'wifi_name'), onChanged: (_) => setState(() {})),
            Row(children: [
              Expanded(child: AppTextField(controller: _pass, label: L(t, 'password'), obscure: _hidePass, onChanged: (_) => setState(() {}))),
              IconButton(
                onPressed: () => setState(() => _hidePass = !_hidePass),
                icon: Icon(_hidePass ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              ),
            ]),
          ],
        ]),
      ),
      if (ok)
        Center(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: QrImageView(data: data, size: 240, backgroundColor: Colors.white),
          ),
        ),
      if (ok && _mode != 2)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.copy_rounded),
            label: Text(t.tx('copied')),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: data));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.tx('copied'))));
            },
          ),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ Mors

const Map<String, String> kMorse = {
  'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.', 'F': '..-.', 'G': '--.', 'H': '....', 'I': '..',
  'J': '.---', 'K': '-.-', 'L': '.-..', 'M': '--', 'N': '-.', 'O': '---', 'P': '.--.', 'Q': '--.-', 'R': '.-.',
  'S': '...', 'T': '-', 'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-', 'Y': '-.--', 'Z': '--..',
  '0': '-----', '1': '.----', '2': '..---', '3': '...--', '4': '....-', '5': '.....', '6': '-....', '7': '--...',
  '8': '---..', '9': '----.', '.': '.-.-.-', ',': '--..--', '?': '..--..', "'": '.----.', '!': '-.-.--',
  '/': '-..-.', '(': '-.--.', ')': '-.--.-', '&': '.-...', ':': '---...', ';': '-.-.-.', '=': '-...-',
  '+': '.-.-.', '-': '-....-', '"': '.-..-.', '@': '.--.-.',
};

const Map<String, String> _fold = {
  'Ç': 'C', 'Ğ': 'G', 'İ': 'I', 'I': 'I', 'Ö': 'O', 'Ş': 'S', 'Ü': 'U', 'Â': 'A', 'Î': 'I', 'Û': 'U',
  'Ä': 'A', 'Å': 'A', 'À': 'A', 'Á': 'A', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Ñ': 'N', 'Ø': 'O', 'Ó': 'O', 'Ò': 'O',
  'Ú': 'U', 'Ù': 'U', 'ß': 'SS', 'Ł': 'L', 'Ż': 'Z', 'Ź': 'Z', 'Ś': 'S', 'Ć': 'C', 'Ń': 'N', 'Ę': 'E', 'Ą': 'A',
};

String toMorse(String text) {
  final words = <String>[];
  for (final w in text.toUpperCase().split(RegExp(r'\s+'))) {
    if (w.isEmpty) continue;
    final letters = <String>[];
    for (final ch in w.split('')) {
      final f = _fold[ch] ?? ch;
      for (final c in f.split('')) {
        final m = kMorse[c];
        if (m != null) letters.add(m);
      }
    }
    if (letters.isNotEmpty) words.add(letters.join(' '));
  }
  return words.join(' / ');
}

String fromMorse(String code) {
  final rev = {for (final e in kMorse.entries) e.value: e.key};
  return code
      .trim()
      .split(RegExp(r'\s*/\s*|\s{3,}'))
      .map((w) => w.trim().split(RegExp(r'\s+')).map((l) => rev[l.replaceAll('·', '.').replaceAll('−', '-')] ?? '').join())
      .join(' ');
}

bool looksLikeMorse(String s) => s.trim().isNotEmpty && RegExp(r'^[\s.\-/·−]+$').hasMatch(s);

/// Mors dizisini (tonu açık, süre ms) adımlarına böler. Birim 80 ms.
List<(bool, int)> morseTimeline(String code, {int unit = 80}) {
  final out = <(bool, int)>[];
  for (final ch in code.split('')) {
    switch (ch) {
      case '.':
        out..add((true, unit))..add((false, unit));
      case '-':
        out..add((true, unit * 3))..add((false, unit));
      case ' ':
        out.add((false, unit * 2));
      case '/':
        out.add((false, unit * 2));
    }
  }
  return out;
}

class MorseTool extends StatefulWidget {
  final ToolContext t;
  const MorseTool(this.t, {super.key});

  @override
  State<MorseTool> createState() => _MorseToolState();
}

class _MorseToolState extends State<MorseTool> {
  final _in = TextEditingController(text: 'SOS');
  final _tone = TonePlayer();
  bool _flash = false;
  bool _playing = false;

  @override
  void dispose() {
    _in.dispose();
    _tone.dispose();
    _playing = false;
    super.dispose();
  }

  String get _code => looksLikeMorse(_in.text) ? _in.text.trim() : toMorse(_in.text);

  Future<void> _sound() async {
    final tl = morseTimeline(_code);
    if (tl.isEmpty) return;
    await _tone.play(makeWav([for (final (on, ms) in tl) (on ? 700.0 : 0.0, ms)]));
  }

  Future<void> _light() async {
    if (_playing) return;
    setState(() => _playing = true);
    for (final (on, ms) in morseTimeline(_code, unit: 160)) {
      if (!mounted || !_playing) break;
      setState(() => _flash = on);
      await Future<void>.delayed(Duration(milliseconds: ms));
    }
    if (mounted) {
      setState(() {
        _flash = false;
        _playing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final isCode = looksLikeMorse(_in.text);
    final out = isCode ? fromMorse(_in.text) : toMorse(_in.text);
    return Stack(children: [
      ToolList(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppTextField(
            controller: _in,
            label: '${L(t, 'text')} ⇄ ${L(t, 'morse')}',
            maxLines: 4,
            onChanged: (_) => setState(() {}),
          ),
        ),
        AppPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isCode ? L(t, 'text') : L(t, 'morse'), style: const TextStyle(color: Colors.white60)),
            SelectableText(out.isEmpty ? '—' : out,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.volume_up_rounded),
                label: Text(L(t, 'play_sound')),
                onPressed: _sound,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(_playing ? Icons.stop_rounded : Icons.flashlight_on_rounded),
                label: Text(L(t, _playing ? 'stop' : 'play_light')),
                onPressed: _playing ? () => setState(() => _playing = false) : _light,
              ),
            ),
          ]),
        ),
        AppHeading('A–Z · 0–9'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 14, runSpacing: 6, children: [
            for (final e in kMorse.entries.take(36))
              Text('${e.key} ${e.value}', style: const TextStyle(fontFamily: 'monospace', color: Colors.white70)),
          ]),
        ),
      ]),
      if (_flash) Positioned.fill(child: IgnorePointer(child: Container(color: Colors.white))),
    ]);
  }
}

// ------------------------------------------------------------ şifre üretici

class PasswordTool extends StatefulWidget {
  final ToolContext t;
  const PasswordTool(this.t, {super.key});

  @override
  State<PasswordTool> createState() => _PasswordToolState();
}

class _PasswordToolState extends State<PasswordTool> {
  static const _sets = ['ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!@#\$%^&*()-_=+[]{};:,.?'];
  final _on = [true, true, true, true];
  double _len = 16;
  String _pw = '';
  late final math.Random _r = _rng();

  static math.Random _rng() {
    try {
      return math.Random.secure();
    } catch (_) {
      return math.Random();
    }
  }

  @override
  void initState() {
    super.initState();
    _make();
  }

  void _make() {
    final pools = [for (var i = 0; i < 4; i++) if (_on[i]) _sets[i]];
    if (pools.isEmpty) {
      setState(() => _pw = '');
      return;
    }
    final n = _len.round();
    final chars = <String>[for (final p in pools) p[_r.nextInt(p.length)]];
    final all = pools.join();
    while (chars.length < n) {
      chars.add(all[_r.nextInt(all.length)]);
    }
    chars.shuffle(_r);
    setState(() => _pw = chars.take(n).join());
  }

  double get _bits {
    final size = [for (var i = 0; i < 4; i++) if (_on[i]) _sets[i].length].fold(0, (a, b) => a + b);
    return size == 0 ? 0.0 : _len.round() * math.log(size) / math.ln2;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final bits = _bits;
    final (label, color) = bits < 50
        ? ('●○○', Colors.redAccent)
        : bits < 80
            ? ('●●○', Colors.orangeAccent)
            : ('●●●', Colors.greenAccent);
    final names = [L(t, 'uppercase'), L(t, 'lowercase'), L(t, 'digits'), L(t, 'symbols')];
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          SelectableText(_pw, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: 22)),
          const SizedBox(height: 8),
          Text('${L(t, 'strength')}: $label  ${bits.round()} bit', style: TextStyle(color: color)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: AppButton(label: L(t, 'generate'), icon: Icons.autorenew_rounded, onPressed: _make)),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: t.tx('copied'),
            icon: const Icon(Icons.copy_rounded),
            onPressed: _pw.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _pw));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.tx('copied'))));
                    // Panoda kalmasın: 60 sn sonra temizle.
                    final copied = _pw;
                    Timer(const Duration(seconds: 60), () async {
                      final cur = await Clipboard.getData(Clipboard.kTextPlain);
                      if (cur?.text == copied) await Clipboard.setData(const ClipboardData(text: ''));
                    });
                  },
          ),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          Row(children: [
            Text('${L(t, 'length')}: ${_len.round()}'),
            Expanded(
              child: Slider(
                min: 6,
                max: 64,
                divisions: 58,
                value: _len,
                onChanged: (v) => setState(() => _len = v),
                onChangeEnd: (_) => _make(),
              ),
            ),
          ]),
          for (var i = 0; i < 4; i++)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(names[i]),
              subtitle: Text(_sets[i], maxLines: 1, overflow: TextOverflow.ellipsis),
              value: _on[i],
              onChanged: (v) {
                setState(() => _on[i] = v);
                _make();
              },
            ),
        ]),
      ),
    ]);
  }
}
