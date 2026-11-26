library;

class AppFile {
  final String name;
  final String path;
  final int size;
  const AppFile(this.name, this.path, this.size);
}

class AppFiles {
  static bool get supported => false;
  static Future<List<AppFile>> list() async => const [];
  static Future<bool> copyIn(String? sourcePath, String name) async => false;
  static Future<void> delete(String path) async {}
  static Future<bool> writeUnder(String dir, String relPath, List<int> data) async => false;
}
