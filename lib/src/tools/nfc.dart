/// NFC etiket okuyucu / yazıcı. Android'de NDEF okuma ve yazma (metin,
/// bağlantı), iOS'ta okuma. Etiket içeriği cihazdan çıkmaz.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ndef_record/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common.dart';

// ------------------------------------------------------------- NDEF kodlama

const List<String> _uriPrefixes = [
  '', 'http://www.', 'https://www.', 'http://', 'https://', 'tel:', 'mailto:', 'ftp://anonymous:anonymous@',
  'ftp://ftp.', 'ftps://', 'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://', 'news:', 'telnet://', 'imap:',
  'rtsp://', 'urn:', 'pop:', 'sip:', 'sips:', 'tftp:', 'btspp://', 'btl2cap://', 'btgoep://', 'tcpobex://',
  'irdaobex://', 'file://', 'urn:epc:id:', 'urn:epc:tag:', 'urn:epc:pat:', 'urn:epc:raw:', 'urn:epc:', 'urn:nfc:',
];

/// Bir NDEF kaydının çözülmüş hâli.
class NdefItem {
  /// 'text', 'uri', 'mime' ya da 'other'.
  final String kind;
  final String value;
  final String? lang;
  const NdefItem(this.kind, this.value, {this.lang});
}

/// Metin kaydı (RTD "T") yükü.
Uint8List ndefTextPayload(String text, {String lang = 'en'}) {
  final l = utf8.encode(lang);
  return Uint8List.fromList([l.length & 0x3F, ...l, ...utf8.encode(text)]);
}

/// Bağlantı kaydı (RTD "U") yükü; bilinen önek tek baytla kısaltılır.
Uint8List ndefUriPayload(String uri) {
  var code = 0;
  var best = 0;
  for (var i = 1; i < _uriPrefixes.length; i++) {
    final p = _uriPrefixes[i];
    if (uri.startsWith(p) && p.length > best) {
      best = p.length;
      code = i;
    }
  }
  return Uint8List.fromList([code, ...utf8.encode(uri.substring(best))]);
}

/// Bir kaydı (TNF, tür, yük) okunur hâle getirir.
NdefItem decodeNdef(int tnf, Uint8List type, Uint8List payload) {
  final ty = ascii.decode(type, allowInvalid: true);
  if (tnf == 1 && ty == 'T' && payload.isNotEmpty) {
    final status = payload[0];
    final ll = status & 0x3F;
    final utf16 = (status & 0x80) != 0;
    final lang = ascii.decode(payload.sublist(1, (1 + ll).clamp(1, payload.length)), allowInvalid: true);
    final body = payload.sublist((1 + ll).clamp(1, payload.length));
    String text;
    if (utf16) {
      final units = <int>[];
      for (var i = 0; i + 1 < body.length; i += 2) {
        units.add((body[i] << 8) | body[i + 1]);
      }
      text = String.fromCharCodes(units);
    } else {
      text = utf8.decode(body, allowMalformed: true);
    }
    return NdefItem('text', text, lang: lang);
  }
  if (tnf == 1 && ty == 'U' && payload.isNotEmpty) {
    final pre = payload[0] < _uriPrefixes.length ? _uriPrefixes[payload[0]] : '';
    return NdefItem('uri', pre + utf8.decode(payload.sublist(1), allowMalformed: true));
  }
  if (tnf == 3) return NdefItem('uri', ty);
  if (tnf == 2) return NdefItem('mime', '$ty · ${utf8.decode(payload, allowMalformed: true)}');
  return NdefItem('other', '${ty.isEmpty ? '?' : ty} · ${payload.length} B');
}

String hexId(Uint8List id) => id.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');

// ------------------------------------------------------------------- araç

class _TagInfo {
  String id = '';
  List<String> tech = [];
  String type = '';
  int capacity = 0;
  bool? writable;
  List<NdefItem> items = [];
  bool ndef = false;
}

class NfcTool extends StatefulWidget {
  final ToolContext t;
  const NfcTool(this.t, {super.key});

  @override
  State<NfcTool> createState() => _NfcToolState();
}

class _NfcToolState extends State<NfcTool> {
  NfcAvailability? _avail;
  bool _scanning = false;
  bool _writeMode = false;
  bool _uri = false;
  String? _status;
  _TagInfo? _info;
  final _textCtl = TextEditingController();
  final List<Map<String, Object?>> _history = [];

  ToolContext get t => widget.t;
  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  bool get _supportedPlatform =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    unawaited(_check());
    t.store.readList('history').then((l) {
      if (mounted) setState(() => _history.addAll(l));
    });
  }

  Future<void> _check() async {
    if (!_supportedPlatform) {
      setState(() => _avail = NfcAvailability.unsupported);
      return;
    }
    try {
      final a = await NfcManager.instance.checkAvailability();
      if (mounted) setState(() => _avail = a);
    } catch (_) {
      if (mounted) setState(() => _avail = NfcAvailability.unsupported);
    }
  }

  Future<void> _stop() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _scan() async {
    if (_scanning) return _stop();
    final writing = _writeMode && _android;
    final payload = _textCtl.text.trim();
    if (writing && payload.isEmpty) return;
    setState(() {
      _scanning = true;
      _status = L(t, 'nfc_scan');
    });
    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693, if (_android) NfcPollingOption.iso18092},
        alertMessageIos: L(t, 'nfc_scan'),
        onDiscovered: (tag) async {
          try {
            if (writing) {
              await _write(tag, payload);
            } else {
              await _read(tag);
            }
          } catch (_) {
            if (mounted) setState(() => _status = L(t, 'nfc_fail'));
          }
          await _stop();
        },
        onSessionErrorIos: (_) {
          if (mounted) setState(() => _scanning = false);
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _status = L(t, 'nfc_fail');
        });
      }
    }
  }

  List<NdefItem> _decode(NdefMessage? m) => [
        for (final r in m?.records ?? const <NdefRecord>[]) decodeNdef(r.typeNameFormat.index, r.type, r.payload),
      ];

  Future<void> _read(NfcTag tag) async {
    final info = _TagInfo();
    if (_android) {
      final a = NfcTagAndroid.from(tag);
      if (a != null) {
        info.id = hexId(a.id);
        info.tech = [for (final s in a.techList) s.split('.').last];
      }
      final n = NdefAndroid.from(tag);
      if (n != null) {
        info.ndef = true;
        info.type = n.type.split('.').last;
        info.capacity = n.maxSize;
        info.writable = n.isWritable;
        info.items = _decode(n.cachedNdefMessage ?? await n.getNdefMessage());
      }
    } else {
      final mi = MiFareIos.from(tag);
      final iso = Iso7816Ios.from(tag);
      final v = Iso15693Ios.from(tag);
      final fe = FeliCaIos.from(tag);
      if (mi != null) {
        info.id = hexId(mi.identifier);
        info.tech.add('MiFare');
      } else if (iso != null) {
        info.id = hexId(iso.identifier);
        info.tech.add('ISO 7816');
      } else if (v != null) {
        info.id = hexId(v.identifier);
        info.tech.add('ISO 15693');
      } else if (fe != null) {
        info.id = hexId(fe.currentIDm);
        info.tech.add('FeliCa');
      }
      final n = NdefIos.from(tag);
      if (n != null) {
        info.ndef = true;
        info.capacity = n.capacity;
        info.writable = n.status == NdefStatusIos.readWrite;
        info.items = _decode(n.cachedNdefMessage ?? await n.readNdef());
      }
    }
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _info = info;
      _status = info.ndef ? null : L(t, 'no_ndef');
    });
    if (info.items.isNotEmpty || info.id.isNotEmpty) {
      _history.insert(0, {
        'at': DateTime.now().toIso8601String(),
        'id': info.id,
        'v': info.items.isEmpty ? '' : info.items.first.value,
      });
      if (_history.length > 30) _history.removeLast();
      await t.store.writeList('history', _history);
      if (mounted) setState(() {});
    }
  }

  Future<void> _write(NfcTag tag, String value) async {
    final n = NdefAndroid.from(tag);
    if (n == null) {
      if (mounted) setState(() => _status = L(t, 'no_ndef'));
      return;
    }
    if (!n.isWritable) {
      if (mounted) setState(() => _status = L(t, 'read_only'));
      return;
    }
    final rec = _uri
        ? NdefRecord(
            typeNameFormat: TypeNameFormat.wellKnown,
            type: Uint8List.fromList([0x55]),
            identifier: Uint8List(0),
            payload: ndefUriPayload(value))
        : NdefRecord(
            typeNameFormat: TypeNameFormat.wellKnown,
            type: Uint8List.fromList([0x54]),
            identifier: Uint8List(0),
            payload: ndefTextPayload(value, lang: t.lang));
    final size = rec.payload.length + 8;
    if (n.maxSize > 0 && size > n.maxSize) {
      if (mounted) setState(() => _status = '${L(t, 'nfc_fail')} (${n.maxSize} B)');
      return;
    }
    await n.writeNdefMessage(NdefMessage(records: [rec]));
    await HapticFeedback.mediumImpact();
    if (mounted) setState(() => _status = L(t, 'written'));
  }

  @override
  void dispose() {
    if (_scanning) unawaited(NfcManager.instance.stopSession().catchError((_) {}));
    _textCtl.dispose();
    super.dispose();
  }

  Widget _infoPanel(_TagInfo i) {
    final loc = MaterialLocalizations.of(context);
    return AppPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (i.id.isNotEmpty) AppResult(label: L(t, 'tag_id'), value: i.id, lang: t.lang),
        if (i.tech.isNotEmpty) AppResult(label: L(t, 'tag_type'), value: i.tech.join(', '), lang: t.lang),
        if (i.type.isNotEmpty) AppResult(label: 'NDEF', value: i.type, lang: t.lang),
        if (i.capacity > 0) AppResult(label: L(t, 'capacity'), value: '${i.capacity} B', lang: t.lang),
        if (i.writable != null)
          AppResult(label: L(t, 'writable'), value: i.writable! ? loc.okButtonLabel : '—', lang: t.lang),
        if (i.items.isNotEmpty) ...[
          const Divider(),
          Text(L(t, 'records'), style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final r in i.items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(r.kind == 'uri'
                  ? Icons.link_rounded
                  : r.kind == 'text'
                      ? Icons.notes_rounded
                      : Icons.data_object_rounded),
              title: SelectableText(r.value),
              subtitle: r.lang == null ? null : Text(r.lang!),
              trailing: r.kind == 'uri' && (r.value.startsWith('http') || r.value.startsWith('tel:') || r.value.startsWith('mailto:'))
                  ? IconButton(
                      tooltip: L(t, 'open_link'),
                      icon: const Icon(Icons.open_in_new_rounded),
                      onPressed: () => launchUrl(Uri.parse(r.value), mode: LaunchMode.externalApplication),
                    )
                  : IconButton(
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () => Clipboard.setData(ClipboardData(text: r.value)),
                    ),
            ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_avail == null) return const Center(child: CircularProgressIndicator());
    if (_avail == NfcAvailability.unsupported) return ToolList(children: [notAvailable(t)]);
    if (_avail == NfcAvailability.disabled) {
      return ToolList(children: [
        AppInfoCard(L(t, 'nfc_off'), icon: Icons.nfc_rounded),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppButton(label: L(t, 'refresh'), icon: Icons.refresh_rounded, onPressed: _check),
        ),
      ]);
    }
    return ToolList(children: [
      if (_android)
        Choice<bool>(
          values: const [false, true],
          labels: [L(t, 'read_tag'), L(t, 'write_tag')],
          selected: _writeMode,
          onChanged: (v) => setState(() => _writeMode = v),
        )
      else
        AppInfoCard(L(t, 'nfc_ios_read'), icon: Icons.info_outline_rounded),
      if (_writeMode && _android)
        AppPanel(
          child: Column(children: [
            Choice<bool>(
              values: const [false, true],
              labels: [L(t, 'text'), L(t, 'link')],
              selected: _uri,
              onChanged: (v) => setState(() => _uri = v),
            ),
            AppTextField(controller: _textCtl, label: _uri ? 'https://…' : L(t, 'text'), maxLines: _uri ? 1 : 3),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppButton(
          label: _scanning ? L(t, 'stop') : (_writeMode && _android ? L(t, 'write_tag') : L(t, 'read_tag')),
          icon: _scanning ? Icons.stop_rounded : Icons.nfc_rounded,
          onPressed: _scan,
        ),
      ),
      if (_scanning) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      if (_status != null) AppInfoCard(_status!, icon: Icons.contactless_rounded),
      if (_info != null && !_writeMode) _infoPanel(_info!),
      if (_history.isNotEmpty && !_writeMode) ...[
        AppHeading(L(t, 'history'), icon: Icons.history_rounded),
        for (final h in _history)
          ListTile(
            dense: true,
            leading: const Icon(Icons.contactless_outlined),
            title: Text('${h['v'] ?? ''}'.isEmpty ? '${h['id']}' : '${h['v']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${h['id']} · ${'${h['at']}'.replaceFirst('T', ' ').split('.').first}'),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.delete_sweep_rounded),
            label: Text(L(t, 'clear')),
            onPressed: () async {
              setState(_history.clear);
              await t.store.writeList('history', _history);
            },
          ),
        ),
      ],
    ]);
  }
}
