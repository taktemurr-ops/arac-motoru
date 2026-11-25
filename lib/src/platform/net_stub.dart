library;

/// Bir ağ arabirimi ve adresleri.
class NetIface {
  final String name;
  final List<String> v4;
  final List<String> v6;
  const NetIface(this.name, this.v4, this.v6);
}

class NetInfoIo {
  static bool get supported => false;
  static Future<List<NetIface>> interfaces() async => const [];
}
