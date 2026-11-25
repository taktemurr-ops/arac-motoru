/// Cihaz araçları: dosya yöneticisi (yalnızca kullanıcının seçtiği
/// dosyalar), pil ve cihaz bilgisi, ekran/ölü piksel testi, dokunmatik ve
/// tuş testi.
library;

import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../platform/files.dart';

String bytes(int b) {
  if (b < 1024) return '$b B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${u[i]}';
}

// ---------------------------------------------------------- dosya yöneticisi

class FilesTool extends StatefulWidget {
  final ToolContext t;
  const FilesTool(this.t, {super.key});

  @override
  State<FilesTool> createState() => _FilesToolState();
}

class _FilesToolState extends State<FilesTool> {
  List<PlatformFile> _picked = [];
  List<AppFile> _mine = [];

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final l = await AppFiles.list();
    if (mounted) setState(() => _mine = l);
  }

  Future<void> _pick() async {
    try {
      // Sistem dosya seçicisi (Android'de SAF): tüm depolama izni gerekmez.
      final r = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
      if (r != null && mounted) setState(() => _picked = r.files);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.tx('not_available'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _picked.fold<int>(0, (a, f) => a + f.size);
    return ToolList(children: [
      AppInfoCard(L(t, 'saf_note'), icon: Icons.lock_rounded),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppButton(label: L(t, 'pick_files'), icon: Icons.folder_open_rounded, onPressed: _pick),
      ),
      if (_picked.isNotEmpty) ...[
        AppHeading('${_picked.length} · ${bytes(total)}', icon: Icons.description_rounded),
        for (final f in _picked)
          ListTile(
            leading: Icon(_iconFor(f.extension)),
            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${bytes(f.size)} · ${(f.extension ?? '?').toUpperCase()}'),
            trailing: AppFiles.supported && f.path != null
                ? IconButton(
                    tooltip: L(t, 'save_copy'),
                    icon: const Icon(Icons.save_alt_rounded),
                    onPressed: () async {
                      final ok = await AppFiles.copyIn(f.path, f.name);
                      if (!mounted) return;
                      ScaffoldMessenger.maybeOf(context)
                          ?.showSnackBar(SnackBar(content: Text(ok ? '✓ ${f.name}' : t.tx('not_available'))));
                      await _reload();
                    },
                  )
                : null,
          ),
      ],
      if (AppFiles.supported) ...[
        AppHeading('${L(t, 'app_files')} · ${_mine.length}', icon: Icons.folder_special_rounded),
        if (_mine.isEmpty) AppInfoCard(L(t, 'empty')),
        for (final f in _mine)
          ListTile(
            leading: Icon(_iconFor(f.name.contains('.') ? f.name.split('.').last : null)),
            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(bytes(f.size)),
            trailing: IconButton(
              tooltip: L(t, 'delete'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(L(t, 'delete')),
                    content: Text(f.name),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.core('cancel'))),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.core('delete'))),
                    ],
                  ),
                );
                if (ok == true) {
                  await AppFiles.delete(f.path);
                  await _reload();
                }
              },
            ),
          ),
      ],
    ]);
  }

  IconData _iconFor(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'heic':
        return Icons.image_rounded;
      case 'mp4':
      case 'mov':
      case 'mkv':
      case 'webm':
        return Icons.movie_rounded;
      case 'mp3':
      case 'm4a':
      case 'wav':
      case 'ogg':
      case 'flac':
        return Icons.audiotrack_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      case 'txt':
      case 'md':
      case 'doc':
      case 'docx':
        return Icons.article_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}

// --------------------------------------------------- pil ve cihaz bilgisi

class DeviceInfoTool extends StatefulWidget {
  final ToolContext t;
  const DeviceInfoTool(this.t, {super.key});

  @override
  State<DeviceInfoTool> createState() => _DeviceInfoToolState();
}

class _DeviceInfoToolState extends State<DeviceInfoTool> {
  final _battery = Battery();
  int? _level;
  BatteryState? _state;
  StreamSubscription<BatteryState>? _sub;
  Map<String, Object?> _info = {};

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _level = await _battery.batteryLevel;
      _state = await _battery.batteryState;
      _sub = _battery.onBatteryStateChanged.listen((s) async {
        final l = await _battery.batteryLevel;
        if (mounted) {
          setState(() {
            _state = s;
            _level = l;
          });
        }
      });
    } catch (_) {/* pil bilgisi yok */}
    try {
      final d = await DeviceInfoPlugin().deviceInfo;
      _info = d.data;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Platformlar arası anlamlı alanlar.
  List<(String, String)> _rows() {
    const keys = [
      'manufacturer', 'brand', 'model', 'name', 'device', 'product', 'systemName', 'systemVersion', 'browserName',
      'platform', 'hardware', 'isPhysicalDevice', 'numberOfCores', 'computerName', 'osRelease', 'majorVersion',
    ];
    final out = <(String, String)>[];
    for (final k in keys) {
      final v = _info[k];
      if (v == null || '$v'.isEmpty) continue;
      out.add((k, '$v'.split('.').last));
    }
    final ver = _info['version'];
    if (ver is Map) {
      if (ver['release'] != null) out.add(('Android', '${ver['release']}'));
      if (ver['sdkInt'] != null) out.add(('SDK', '${ver['sdkInt']}'));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final s = AppLook.of(context);
    final size = mq.size;
    final dpr = mq.devicePixelRatio;
    final charging = _state == BatteryState.charging || _state == BatteryState.full;
    return ToolList(children: [
      if (_level != null && _level! >= 0) ...[
        BigReadout('$_level', unit: '%', caption: L(t, 'battery')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LinearProgressIndicator(
            value: _level! / 100,
            minHeight: 14,
            borderRadius: BorderRadius.circular(8),
            color: _level! < 20 ? Colors.redAccent : s.accent,
            backgroundColor: Colors.white12,
          ),
        ),
        if (charging)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Center(child: Text('⚡ ${L(t, 'charging')}', style: const TextStyle(fontSize: 17))),
          ),
      ] else
        notAvailable(t),
      AppHeading(L(t, 'screen'), icon: Icons.smartphone_rounded),
      AppPanel(
        child: Column(children: [
          AppResult(label: 'dp', value: '${size.width.round()} × ${size.height.round()}', lang: t.lang),
          AppResult(
              label: 'px', value: '${(size.width * dpr).round()} × ${(size.height * dpr).round()}', lang: t.lang),
          AppResult(label: 'DPR', value: dpr.toStringAsFixed(2), lang: t.lang),
          AppResult(label: 'Aa', value: mq.textScaler.scale(1).toStringAsFixed(2), lang: t.lang),
        ]),
      ),
      AppHeading(L(t, 'device'), icon: Icons.memory_rounded),
      AppPanel(
        child: Column(children: [
          AppResult(label: L(t, 'system'), value: kIsWeb ? 'Web' : defaultTargetPlatform.name, lang: t.lang),
          for (final (k, v) in _rows()) AppResult(label: k, value: v, lang: t.lang),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------ ekran testi

class ScreenTestTool extends StatelessWidget {
  final ToolContext t;
  const ScreenTestTool(this.t, {super.key});

  @override
  Widget build(BuildContext context) {
    return ToolList(children: [
      AppInfoCard(L(t, 'tap_next'), icon: Icons.touch_app_rounded),
      Padding(
        padding: const EdgeInsets.all(16),
        child: AppButton(
          label: L(t, 'start'),
          icon: Icons.fullscreen_rounded,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _ColorCycle())),
        ),
      ),
    ]);
  }
}

class _ColorCycle extends StatefulWidget {
  const _ColorCycle();

  @override
  State<_ColorCycle> createState() => _ColorCycleState();
}

class _ColorCycleState extends State<_ColorCycle> {
  static const _colors = [
    Colors.black, Colors.white, Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFF0000FF),
    Color(0xFF808080), Color(0xFFFFFF00), Color(0xFF00FFFF), Color(0xFFFF00FF),
  ];
  int _i = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _i = (_i + 1) % (_colors.length + 1)),
      onLongPress: () => Navigator.of(context).pop(),
      child: _i < _colors.length
          ? Container(color: _colors[_i])
          : CustomPaint(painter: _GradientPainter(), child: const SizedBox.expand()),
    );
  }
}

class _GradientPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const bands = [Colors.white, Colors.red, Colors.green, Colors.blue];
    final h = size.height / bands.length;
    for (var i = 0; i < bands.length; i++) {
      final r = Rect.fromLTWH(0, i * h, size.width, h);
      canvas.drawRect(r, Paint()..shader = LinearGradient(colors: [Colors.black, bands[i]]).createShader(r));
    }
  }

  @override
  bool shouldRepaint(_GradientPainter old) => false;
}

// ----------------------------------------------------- dokunmatik ve tuş

class TouchTestTool extends StatefulWidget {
  final ToolContext t;
  const TouchTestTool(this.t, {super.key});

  @override
  State<TouchTestTool> createState() => _TouchTestToolState();
}

class _TouchTestToolState extends State<TouchTestTool> {
  static const _cols = 10, _rows = 18;
  final Set<int> _hit = {};
  final List<String> _keys = [];
  final _focus = FocusNode();
  int _pointers = 0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _mark(Offset p, Size size) {
    final c = (p.dx / size.width * _cols).floor(), r = (p.dy / size.height * _rows).floor();
    if (c < 0 || r < 0 || c >= _cols || r >= _rows) return;
    if (_hit.add(r * _cols + c)) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final s = AppLook.of(context);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent) {
          setState(() {
            _keys.insert(0, e.logicalKey.keyLabel.isEmpty ? e.logicalKey.debugName ?? '?' : e.logicalKey.keyLabel);
            if (_keys.length > 12) _keys.removeLast();
          });
        }
        return KeyEventResult.ignored;
      },
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('${(_hit.length * 100 / (_cols * _rows)).round()}% · ✋ $_pointers',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final size = Size(c.maxWidth, c.maxHeight);
            return Listener(
              onPointerDown: (e) {
                setState(() => _pointers++);
                _mark(e.localPosition, size);
              },
              onPointerMove: (e) => _mark(e.localPosition, size),
              onPointerUp: (_) => setState(() => _pointers = (_pointers - 1).clamp(0, 99)),
              onPointerCancel: (_) => setState(() => _pointers = (_pointers - 1).clamp(0, 99)),
              child: CustomPaint(size: size, painter: _GridPainter(_hit, _cols, _rows, s.accent)),
            );
          }),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(_keys.isEmpty ? L(t, 'keys_hint') : _keys.join('  '),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(child: Text(L(t, 'touch_hint'), style: const TextStyle(color: Colors.white60, fontSize: 12))),
          TextButton(
            onPressed: () => setState(() {
              _hit.clear();
              _keys.clear();
            }),
            child: Text(L(t, 'reset')),
          ),
        ]),
      ]),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Set<int> hit;
  final int cols, rows;
  final Color color;
  _GridPainter(this.hit, this.cols, this.rows, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / cols, h = size.height / rows;
    final line = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = color.withValues(alpha: 0.6);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final rect = Rect.fromLTWH(c * w, r * h, w, h);
        if (hit.contains(r * cols + c)) canvas.drawRect(rect, fill);
        canvas.drawRect(rect, line);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => true;
}
