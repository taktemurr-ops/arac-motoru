/// Ağ bilgisi: Wi-Fi adı, yerel IP, ağ geçidi, alt ağ maskesi, ağ
/// arabirimleri; çevrimdışı alt ağ (CIDR) hesaplayıcı ve yaygın portlar.
/// Hiçbir veri dışarı gönderilmez.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../platform/net.dart';

// ------------------------------------------------------------ alt ağ

int? parseIpv4(String s) {
  final p = s.trim().split('.');
  if (p.length != 4) return null;
  var v = 0;
  for (final x in p) {
    final n = int.tryParse(x);
    if (n == null || n < 0 || n > 255 || x.isEmpty || x.length > 3) return null;
    v = (v << 8) | n;
  }
  return v;
}

String ipv4(int v) => '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}';

/// IPv4 alt ağı: "192.168.1.10/24" ya da "192.168.1.10 255.255.255.0".
class Subnet {
  final int ip;
  final int prefix;
  const Subnet(this.ip, this.prefix);

  static Subnet? parse(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    String a;
    String b;
    if (s.contains('/')) {
      final i = s.indexOf('/');
      a = s.substring(0, i);
      b = s.substring(i + 1);
    } else if (s.contains(' ')) {
      final i = s.indexOf(' ');
      a = s.substring(0, i);
      b = s.substring(i + 1);
    } else {
      a = s;
      b = '32';
    }
    final ip = parseIpv4(a);
    if (ip == null) return null;
    int? prefix = int.tryParse(b.trim());
    if (prefix == null) {
      final m = parseIpv4(b);
      if (m == null) return null;
      prefix = maskToPrefix(m);
      if (prefix == null) return null;
    }
    if (prefix < 0 || prefix > 32) return null;
    return Subnet(ip, prefix);
  }

  /// Geçerli (bitişik) maske ise önek uzunluğu.
  static int? maskToPrefix(int m) {
    var n = 0;
    var seenZero = false;
    for (var i = 31; i >= 0; i--) {
      final bit = (m >> i) & 1;
      if (bit == 1) {
        if (seenZero) return null;
        n++;
      } else {
        seenZero = true;
      }
    }
    return n;
  }

  int get mask => prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  int get wildcard => ~mask & 0xFFFFFFFF;
  int get network => ip & mask;
  int get broadcast => network | wildcard;
  int get total => prefix == 0 ? 4294967296 : 1 << (32 - prefix);

  /// Kullanılabilir ana bilgisayar sayısı (/31 ve /32 için RFC 3021).
  int get hosts => prefix >= 31 ? total : total - 2;
  int get first => prefix >= 31 ? network : network + 1;
  int get last => prefix >= 31 ? broadcast : broadcast - 1;

  String get ipClass {
    final o = (ip >> 24) & 255;
    if (o < 128) return 'A';
    if (o < 192) return 'B';
    if (o < 224) return 'C';
    if (o < 240) return 'D';
    return 'E';
  }

  /// Özel (RFC 1918), CGNAT, döngü ya da yerel bağlantı adresi mi?
  String get scope {
    final o1 = (ip >> 24) & 255, o2 = (ip >> 16) & 255;
    if (o1 == 10 || (o1 == 172 && o2 >= 16 && o2 <= 31) || (o1 == 192 && o2 == 168)) return 'RFC 1918';
    if (o1 == 100 && o2 >= 64 && o2 <= 127) return 'CGNAT';
    if (o1 == 127) return 'Loopback';
    if (o1 == 169 && o2 == 254) return 'Link-local';
    if (o1 >= 224 && o1 <= 239) return 'Multicast';
    return 'Public';
  }
}

const List<(int, String, String)> kPorts = [
  (20, 'TCP', 'FTP data'), (21, 'TCP', 'FTP'), (22, 'TCP', 'SSH / SFTP'), (23, 'TCP', 'Telnet'),
  (25, 'TCP', 'SMTP'), (53, 'TCP/UDP', 'DNS'), (67, 'UDP', 'DHCP'), (69, 'UDP', 'TFTP'), (80, 'TCP', 'HTTP'),
  (110, 'TCP', 'POP3'), (123, 'UDP', 'NTP'), (143, 'TCP', 'IMAP'), (161, 'UDP', 'SNMP'), (389, 'TCP', 'LDAP'),
  (443, 'TCP/UDP', 'HTTPS / QUIC'), (445, 'TCP', 'SMB'), (465, 'TCP', 'SMTPS'), (514, 'UDP', 'Syslog'),
  (587, 'TCP', 'SMTP submission'), (853, 'TCP', 'DNS over TLS'), (993, 'TCP', 'IMAPS'), (995, 'TCP', 'POP3S'),
  (1194, 'UDP', 'OpenVPN'), (1883, 'TCP', 'MQTT'), (3306, 'TCP', 'MySQL'), (3389, 'TCP', 'RDP'),
  (5060, 'TCP/UDP', 'SIP'), (5353, 'UDP', 'mDNS'), (5432, 'TCP', 'PostgreSQL'), (5900, 'TCP', 'VNC'),
  (6379, 'TCP', 'Redis'), (8080, 'TCP', 'HTTP alt'), (8443, 'TCP', 'HTTPS alt'), (51820, 'UDP', 'WireGuard'),
];

// ------------------------------------------------------------------ araç

class NetworkTool extends StatefulWidget {
  final ToolContext t;
  const NetworkTool(this.t, {super.key});

  @override
  State<NetworkTool> createState() => _NetworkToolState();
}

class _NetworkToolState extends State<NetworkTool> {
  int _tab = 0;
  bool _loading = false;
  Map<String, String?> _wifi = {};
  List<NetIface> _ifaces = [];
  final _cidr = TextEditingController(text: '192.168.1.10/24');
  final _portQ = TextEditingController();

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<String?> _safe(Future<String?> Function() f) async {
    try {
      final v = await f();
      if (v == null || v.isEmpty) return null;
      return v.replaceAll('"', '');
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh({bool askName = false}) async {
    setState(() => _loading = true);
    if (askName && !kIsWeb) {
      if (await rationaleOnce(context, t, 'wifi', Icons.wifi_rounded)) {
        try {
          await Geolocator.requestPermission();
        } catch (_) {}
      }
    }
    final m = <String, String?>{};
    if (!kIsWeb) {
      final n = NetworkInfo();
      m['wifi_name'] = await _safe(n.getWifiName);
      m['bssid'] = await _safe(n.getWifiBSSID);
      m['ip'] = await _safe(n.getWifiIP);
      m['ip6'] = await _safe(n.getWifiIPv6);
      m['mask'] = await _safe(n.getWifiSubmask);
      m['gw'] = await _safe(n.getWifiGatewayIP);
      m['bc'] = await _safe(n.getWifiBroadcast);
    }
    final ifs = await NetInfoIo.interfaces();
    if (!mounted) return;
    setState(() {
      _wifi = m;
      _ifaces = ifs;
      _loading = false;
      if (m['ip'] != null && m['mask'] != null) {
        final mk = parseIpv4(m['mask']!);
        final p = mk == null ? null : Subnet.maskToPrefix(mk);
        if (p != null) _cidr.text = '${m['ip']}/$p';
      }
    });
  }

  @override
  void dispose() {
    _cidr.dispose();
    _portQ.dispose();
    super.dispose();
  }

  Widget _row(String label, String? v) => AppResult(label: label, value: v ?? '—', lang: t.lang);

  List<Widget> _info() {
    if (kIsWeb) return [notAvailable(t)];
    final conn = _ifaces.isEmpty
        ? '—'
        : _ifaces.any((i) => i.name.startsWith('wlan') || i.name.startsWith('en0') || i.name.startsWith('wl'))
            ? 'Wi-Fi'
            : _ifaces.any((i) => i.name.startsWith('rmnet') || i.name.startsWith('pdp_ip') || i.name.startsWith('ccmni'))
                ? L(t, 'mobile_data')
                : _ifaces.first.name;
    return [
      AppPanel(
        child: Column(children: [
          _row(L(t, 'connection'), conn),
          _row(L(t, 'wifi_name'), _wifi['wifi_name']),
          _row('BSSID', _wifi['bssid']),
          _row(L(t, 'ip_local'), _wifi['ip']),
          _row('IPv6', _wifi['ip6']),
          _row(L(t, 'subnet'), _wifi['mask']),
          _row(L(t, 'gateway'), _wifi['gw']),
          _row(L(t, 'broadcast'), _wifi['bc']),
        ]),
      ),
      if (_wifi['wifi_name'] == null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.wifi_find_rounded),
            label: Text(L(t, 'show_wifi_name')),
            onPressed: () => _refresh(askName: true),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppButton(label: L(t, 'refresh'), icon: Icons.refresh_rounded, onPressed: _loading ? null : _refresh),
      ),
      if (_ifaces.isNotEmpty) ...[
        AppHeading(L(t, 'interfaces'), icon: Icons.lan_rounded),
        for (final i in _ifaces)
          AppPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              for (final a in i.v4) SelectableText('IPv4  $a'),
              for (final a in i.v6) SelectableText('IPv6  $a', style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ]),
          ),
      ],
    ];
  }

  List<Widget> _calc() {
    final s = Subnet.parse(_cidr.text);
    return [
      AppPanel(
        child: Column(children: [
          AppTextField(controller: _cidr, label: L(t, 'cidr_hint'), onChanged: (_) => setState(() {})),
          if (s == null)
            Text(L(t, 'invalid'), style: const TextStyle(color: Colors.orangeAccent))
          else ...[
            _row(L(t, 'network_addr'), '${ipv4(s.network)}/${s.prefix}'),
            _row(L(t, 'subnet'), ipv4(s.mask)),
            _row('Wildcard', ipv4(s.wildcard)),
            _row(L(t, 'broadcast'), ipv4(s.broadcast)),
            _row(L(t, 'host_range'), '${ipv4(s.first)} – ${ipv4(s.last)}'),
            _row(L(t, 'host_count'), '${s.hosts}'),
            _row(L(t, 'ip_class'), '${s.ipClass} · ${s.scope}'),
          ],
        ]),
      ),
    ];
  }

  List<Widget> _ports() {
    final q = _portQ.text.trim().toLowerCase();
    final l = kPorts.where((p) => q.isEmpty || '${p.$1}'.contains(q) || p.$3.toLowerCase().contains(q)).toList();
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppTextField(controller: _portQ, label: '${L(t, 'ports')} · 443, DNS…', onChanged: (_) => setState(() {})),
      ),
      if (l.isEmpty) AppInfoCard(t.tx('no_results')),
      for (final p in l)
        ListTile(
          dense: true,
          leading: SizedBox(
            width: 64,
            child: Text('${p.$1}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          title: Text(p.$3),
          trailing: Text(p.$2, style: const TextStyle(color: Colors.white70)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ToolList(children: [
      Choice<int>(
        values: const [0, 1, 2],
        labels: [L(t, 'connection'), L(t, 'subnet_calc'), L(t, 'ports')],
        selected: _tab,
        onChanged: (v) => setState(() => _tab = v),
      ),
      if (_loading) const LinearProgressIndicator(),
      ...switch (_tab) { 0 => _info(), 1 => _calc(), _ => _ports() },
    ]);
  }
}
