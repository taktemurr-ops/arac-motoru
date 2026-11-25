/// Uygulamanın kendi klasörü: yalnızca kullanıcının seçip "kopyasını
/// sakla" dediği dosyalar buraya gelir. Geniş depolama izni gerekmez.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppFile {
  final String name;
  final String path;
  final int size;
  const AppFile(this.name, this.path, this.size);
}

class AppFiles {
  static bool get supported => true;

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}files');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<List<AppFile>> list() async {
    try {
      final d = await _dir();
      final out = <AppFile>[];
      await for (final e in d.list()) {
        if (e is File) {
          final name = e.uri.pathSegments.isEmpty ? e.path : e.uri.pathSegments.last;
          out.add(AppFile(name, e.path, await e.length()));
        }
      }
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> copyIn(String? sourcePath, String name) async {
    if (sourcePath == null) return false;
    try {
      final d = await _dir();
      final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      await File(sourcePath).copy('${d.path}${Platform.pathSeparator}$safe');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> delete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
