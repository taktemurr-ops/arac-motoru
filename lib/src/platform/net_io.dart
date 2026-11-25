library;

import 'dart:io';

/// Bir ağ arabirimi ve adresleri.
class NetIface {
  final String name;
  final List<String> v4;
  final List<String> v6;
  const NetIface(this.name, this.v4, this.v6);
}

class NetInfoIo {
  static bool get supported => true;

  static Future<List<NetIface>> interfaces() async {
    try {
      final l = await NetworkInterface.list(includeLoopback: false, includeLinkLocal: true, type: InternetAddressType.any);
      return [
        for (final i in l)
          NetIface(
            i.name,
            [for (final a in i.addresses) if (a.type == InternetAddressType.IPv4) a.address],
            [for (final a in i.addresses) if (a.type == InternetAddressType.IPv6) a.address],
          ),
      ];
    } catch (_) {
      return const [];
    }
  }
}
