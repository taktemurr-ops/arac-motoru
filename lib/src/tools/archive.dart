/// Arşiv açıcı: ZIP (parolalı dahil), TAR, GZ/TGZ, BZ2, XZ dosyalarını
/// cihazda açar, içindekileri gösterir ve kaydeder; seçilen dosyalardan ZIP
/// oluşturur. 7z ve RAR açılmaz (bilgi verilir). Dosyalar cihazdan çıkmaz.
/// Kod çözücüler: "archive" paketi (MIT lisansı, saf Dart).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../platform/files.dart';
import 'device.dart' show bytes;

enum ArcKind { zip, tar, gzip, bzip2, xz, sevenZip, rar, unknown }

bool _at(Uint8List b, int o, List<int> sig) {
  if (b.length < o + sig.length) return false;
  for (var i = 0; i < sig.length; i++) {
    if (b[o + i] != sig[i]) return false;
  }
  return true;
}

/// Baytların başına (sihirli sayı) ve ada bakarak biçimi bulur.
ArcKind sniffArchive(Uint8List b, String name) {
  if (_at(b, 0, const [0x50, 0x4B, 0x03, 0x04]) || _at(b, 0, const [0x50, 0x4B, 0x05, 0x06])) return ArcKind.zip;
  if (_at(b, 0, const [0x1F, 0x8B])) return ArcKind.gzip;
  if (_at(b, 0, const [0x42, 0x5A, 0x68])) return ArcKind.bzip2;
  if (_at(b, 0, const [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])) return ArcKind.xz;
  if (_at(b, 0, const [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) return ArcKind.sevenZip;
  if (_at(b, 0, const [0x52, 0x61, 0x72, 0x21])) return ArcKind.rar;
  if (_at(b, 257, ascii.encode('ustar'))) return ArcKind.tar;
  final n = name.toLowerCase();
  if (n.endsWith('.tar')) return ArcKind.tar;
  if (n.endsWith('.zip')) return ArcKind.zip;
  return ArcKind.unknown;
}

/// Arşivdeki yolu güvenli hâle getirir ("..", baştaki "/" ve sürücü harfi
/// atılır): arşiv, seçilen klasörün dışına yazamaz.
String safeArchivePath(String p) {
  final parts = p.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty && s != '.' && s != '..').toList();
  if (parts.isNotEmpty && RegExp(r'^[A-Za-z]:$').hasMatch(parts.first)) parts.removeAt(0);
  return parts.join('/');
}

class ArcEntry {
  final String path;
  final int size;
  final Uint8List Function() read;
  const ArcEntry(this.path, this.size, this.read);
}

/// Parola gerekiyor ya da parola yanlış.
class ArcPasswordNeeded implements Exception {
  const ArcPasswordNeeded();
}

/// Desteklenmeyen biçim (7z, RAR ya da tanınmayan).
class ArcUnsupported implements Exception {
  final ArcKind kind;
  const ArcUnsupported(this.kind);
}

List<ArcEntry> _fromArchive(Archive a) => [
      for (final f in a)
        if (f.isFile && safeArchivePath(f.name).isNotEmpty)
          ArcEntry(safeArchivePath(f.name), f.size, () => f.readBytes() ?? Uint8List(0)),
    ];

String _strip(String name, List<String> exts) {
  final l = name.toLowerCase();
  for (final e in exts) {
    if (l.endsWith(e)) return name.substring(0, name.length - e.length);
  }
  return name;
}

/// Arşivi açar ve dosyalarını döndürür.
List<ArcEntry> openArchive(Uint8List bytes, String name, {String? password}) {
  final kind = sniffArchive(bytes, name);
  switch (kind) {
    case ArcKind.zip:
      try {
        final a = ZipDecoder().decodeBytes(bytes, password: password);
        final out = _fromArchive(a);
        // Parolalı girişler okunurken hata verir: ilkini deneyerek erken yakala.
        if (out.isNotEmpty) out.first.read();
        return out;
      } catch (e) {
        if ('$e'.toLowerCase().contains('password') || '$e'.toLowerCase().contains('encrypt')) {
          throw const ArcPasswordNeeded();
        }
        rethrow;
      }
    case ArcKind.tar:
      return _fromArchive(TarDecoder().decodeBytes(bytes));
    case ArcKind.gzip:
    case ArcKind.bzip2:
    case ArcKind.xz:
      {
      final Uint8List inner = kind == ArcKind.gzip
          ? GZipDecoder().decodeBytes(bytes)
          : kind == ArcKind.bzip2
              ? BZip2Decoder().decodeBytes(bytes)
              : XZDecoder().decodeBytes(bytes);
      final innerName = _strip(name, const ['.tgz', '.tbz2', '.tbz', '.txz', '.gz', '.bz2', '.xz']);
      if (sniffArchive(inner, innerName) == ArcKind.tar || RegExp(r'\.t(gz|bz2?|xz)$').hasMatch(name.toLowerCase())) {
        return _fromArchive(TarDecoder().decodeBytes(inner));
      }
      final single = safeArchivePath(innerName.split('/').last);
      return [ArcEntry(single.isEmpty ? 'file' : single, inner.length, () => inner)];
      }
    case ArcKind.sevenZip:
    case ArcKind.rar:
    case ArcKind.unknown:
      throw ArcUnsupported(kind);
  }
}

/// Verilen dosyalardan ZIP üretir.
Uint8List makeZip(List<(String, Uint8List)> files) {
  final a = Archive();
  final used = <String>{};
  for (final f in files) {
    var n = safeArchivePath(f.$1);
    if (n.isEmpty) n = 'file';
    var k = 2;
    final base = n;
    while (used.contains(n)) {
      final dot = base.lastIndexOf('.');
      n = dot > 0 ? '${base.substring(0, dot)} ($k)${base.substring(dot)}' : '$base ($k)';
      k++;
    }
    used.add(n);
    a.add(ArchiveFile.bytes(n, f.$2));
  }
  return ZipEncoder().encodeBytes(a);
}

// ------------------------------------------------------------------- araç

class ArchiveTool extends StatefulWidget {
  final ToolContext t;
  const ArchiveTool(this.t, {super.key});

  @override
  State<ArchiveTool> createState() => _ArchiveToolState();
}

class _ArchiveToolState extends State<ArchiveTool> {
  static const int _maxBytes = 300 * 1024 * 1024;
  String? _name;
  Uint8List? _bytes;
  List<ArcEntry> _entries = [];
  bool _busy = false;
  String? _error;
  String _filter = '';

  ToolContext get t => widget.t;

  void _snack(String s) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s)));

  Future<void> _open() async {
    FilePickerResult? r;
    try {
      r = await FilePicker.platform.pickFiles(withData: true);
    } catch (_) {
      if (mounted) _snack(t.tx('not_available'));
      return;
    }
    final f = r?.files.single;
    if (f == null || !mounted) return;
    if (f.size > _maxBytes) {
      setState(() => _error = L(t, 'arc_too_big'));
      return;
    }
    final b = f.bytes;
    if (b == null) {
      setState(() => _error = t.tx('not_available'));
      return;
    }
    _name = f.name;
    _bytes = b;
    await _decode(null);
  }

  Future<void> _decode(String? password) async {
    final b = _bytes, n = _name;
    if (b == null || n == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _entries = [];
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    try {
      final e = openArchive(b, n, password: password);
      if (mounted) setState(() => _entries = e);
    } on ArcPasswordNeeded {
      if (!mounted) return;
      setState(() => _busy = false);
      final pw = await _askPassword(password != null);
      if (pw != null) await _decode(pw);
      return;
    } on ArcUnsupported catch (u) {
      if (mounted) {
        setState(() => _error = u.kind == ArcKind.sevenZip || u.kind == ArcKind.rar ? L(t, 'arc_7z') : L(t, 'arc_unknown'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = L(t, 'arc_broken'));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<String?> _askPassword(bool wrong) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_rounded),
        title: Text(L(t, 'password')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (wrong) Text(L(t, 'arc_wrong_pw'), style: const TextStyle(color: Colors.orangeAccent)),
          TextField(controller: c, obscureText: true, autofocus: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.core('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(t.core('ok'))),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _saveOne(ArcEntry e) async {
    Uint8List data;
    try {
      data = e.read();
    } catch (_) {
      _snack(L(t, 'arc_broken'));
      return;
    }
    try {
      final p = await FilePicker.platform.saveFile(fileName: e.path.split('/').last, bytes: data);
      if (mounted && p != null) _snack('✓ ${e.path.split('/').last}');
    } catch (_) {
      if (mounted) _snack(t.tx('not_available'));
    }
  }

  Future<void> _saveAll() async {
    String? dir;
    try {
      dir = await FilePicker.platform.getDirectoryPath();
    } catch (_) {
      dir = null;
    }
    if (dir == null || !mounted) return;
    setState(() => _busy = true);
    final base = _strip(_name ?? 'arsiv', const ['.tar.gz', '.tar.bz2', '.tar.xz', '.tgz', '.zip', '.tar', '.gz']);
    var ok = 0, bad = 0;
    for (final e in _entries) {
      try {
        if (await AppFiles.writeUnder(dir, '${safeArchivePath(base)}/${e.path}', e.read())) {
          ok++;
        } else {
          bad++;
        }
      } catch (_) {
        bad++;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(bad == 0 ? '✓ $ok · $dir/${safeArchivePath(base)}' : '${L(t, 'arc_partial')} ($ok/${ok + bad})');
  }

  Future<void> _preview(ArcEntry e) async {
    Uint8List data;
    try {
      data = e.read();
    } catch (_) {
      _snack(L(t, 'arc_broken'));
      return;
    }
    final l = e.path.toLowerCase();
    final image = RegExp(r'\.(png|jpe?g|gif|webp|bmp)$').hasMatch(l);
    final text = !image && data.length < 400000 && !data.take(2000).contains(0);
    if (!image && !text) {
      _snack(L(t, 'arc_no_preview'));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.path.split('/').last, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 520,
          height: 420,
          child: image
              ? InteractiveViewer(
                  child: Image.memory(data, errorBuilder: (_, __, ___) => Text(L(t, 'arc_no_preview'))))
              : SingleChildScrollView(
                  child: SelectableText(utf8.decode(data, allowMalformed: true),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.core('ok')))],
      ),
    );
  }

  Future<void> _makeZip() async {
    FilePickerResult? r;
    try {
      r = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    } catch (_) {
      if (mounted) _snack(t.tx('not_available'));
      return;
    }
    if (r == null || r.files.isEmpty || !mounted) return;
    final files = [for (final f in r.files) if (f.bytes != null) (f.name, f.bytes!)];
    final total = files.fold<int>(0, (a, f) => a + f.$2.length);
    if (total > _maxBytes) {
      _snack(L(t, 'arc_too_big'));
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    Uint8List zip;
    try {
      zip = makeZip(files);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(L(t, 'arc_broken'));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(RegExp(r'[^0-9]'), '');
    try {
      final p = await FilePicker.platform.saveFile(fileName: 'arsiv_$stamp.zip', bytes: zip);
      if (mounted && p != null) _snack('✓ ${files.length} · ${bytes(zip.length)}');
    } catch (_) {
      if (mounted) _snack(t.tx('not_available'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filter.isEmpty
        ? _entries
        : _entries.where((e) => e.path.toLowerCase().contains(_filter.toLowerCase())).toList();
    final total = _entries.fold<int>(0, (a, e) => a + e.size);
    return ToolList(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: AppButton(label: L(t, 'arc_open'), icon: Icons.folder_zip_rounded, onPressed: _busy ? null : _open)),
          const SizedBox(width: 8),
          Expanded(child: AppButton(label: L(t, 'arc_make'), icon: Icons.archive_rounded, onPressed: _busy ? null : _makeZip)),
        ]),
      ),
      if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      if (_error != null) AppInfoCard(_error!, icon: Icons.error_outline_rounded),
      if (_entries.isNotEmpty) ...[
        AppHeading('${_name ?? ''} · ${_entries.length} · ${bytes(total)}', icon: Icons.inventory_2_rounded),
        if (AppFiles.supported)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppButton(label: L(t, 'arc_extract_all'), icon: Icons.unarchive_rounded, onPressed: _busy ? null : _saveAll),
          ),
        if (_entries.length > 12)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        for (final e in shown.take(500))
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(e.path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${e.path.contains('/') ? '${e.path.substring(0, e.path.lastIndexOf('/'))} · ' : ''}${bytes(e.size)}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _preview(e),
            trailing: IconButton(
              tooltip: L(t, 'save_copy'),
              icon: const Icon(Icons.save_alt_rounded),
              onPressed: () => _saveOne(e),
            ),
          ),
        if (shown.length > 500) AppInfoCard('+${shown.length - 500}'),
      ] else if (!_busy && _error == null)
        AppInfoCard(L(t, 'arc_intro'), icon: Icons.folder_zip_rounded),
      AppInfoCard(L(t, 'arc_formats'), icon: Icons.info_outline_rounded),
    ]);
  }
}
