import 'dart:typed_data';

import 'package:arac_motoru/arac_motoru.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:studio_core/app/services/ads.dart';
import 'package:studio_core/app/services/purchases.dart';
import 'package:studio_core/core/save_store.dart';

void main() {
  test('64 araç, 33 dilde ad ve açıklama, benzersiz kimlik', () {
    expect(aracTools.length, 64);
    expect(aracTools.map((t) => t.id).toSet().length, 64);
    for (final t in aracTools) {
      expect(t.title.length, 33, reason: t.id);
      expect(t.tagline.length, 33, reason: t.id);
      expect(t.id.startsWith('uyg-'), isTrue);
      expect(aracCategories.any((c) => c.id == t.category), isTrue, reason: t.id);
    }
    expect(aracHubTitle.length, 33);
  });

  test('ifade çözücü', () {
    expect(Expr('2+3*4').eval(), 14);
    expect(Expr('2^3^2').eval(), 512);
    expect(Expr('-2^2').eval(), -4);
    expect(Expr('2π').eval(), closeTo(6.2832, 1e-4));
    expect(Expr('sin(90)', degrees: true).eval(), closeTo(1, 1e-12));
    expect(Expr('5!').eval(), 120);
    expect(Expr('50%').eval(), 0.5);
    expect(Expr('x^2+1').eval(3), 10);
    expect(Expr.tryEval('2+'), isNull);
  });

  test('Roma rakamı, Mors, tarih farkı', () {
    expect(toRoman(2026), 'MMXXVI');
    expect(fromRoman('MCMXCIV'), 1994);
    expect(fromRoman('IIII'), isNull);
    expect(toMorse('SOS'), '... --- ...');
    expect(fromMorse('... --- ...'), 'SOS');
    expect(dateDiff(DateTime(2000, 2, 29), DateTime(2026, 11, 25)), (26, 8, 27));
  });

  test('2026 bordro: asgari ücretlinin neti 28.075,50 ₺', () {
    final p = TrPayroll();
    final m = p.year(33030)[0];
    expect(m.net, closeTo(28075.50, 0.01));
    // Brüt 100.000 ₺: SGK %14, işsizlik %1, istisna düşülür.
    final y = p.year(100000);
    expect(y[0].sgk, closeTo(14000, 0.01));
    expect(y[0].unemp, closeTo(1000, 0.01));
    expect(y[11].net, lessThan(y[0].net)); // yıl içinde dilim yükselir
    final g = p.grossFor(y[0].net, 1);
    expect(g, closeTo(100000, 0.5));
  });

  test('ton üreteci: kesintisiz döngü, doğru frekans, tarama', () {
    final (s, f) = toneSamples(440, Wave.sine);
    expect(f, closeTo(440, 0.05));
    expect(s.length, closeTo(44100, 200));
    // Döngü başı ve sonu sürekli (ilk örnek 0, son örnek 0'a yakın).
    expect(s.first.abs(), lessThan(1e-9));
    expect(s.last.abs(), lessThan(0.1));
    final (q, _) = toneSamples(1000, Wave.square, volume: 1);
    expect(q.reduce((a, b) => a > b ? a : b), closeTo(0.9, 1e-9));
    expect(waveSample(Wave.triangle, 0.5), closeTo(1, 1e-9));
    expect(waveSample(Wave.saw, 0), -1);
    expect(sweepSamples(20, 20000, 2, Wave.sine).length, 88200);
    expect(toneWav(440, Wave.sine).length, 44 + s.length * 2);
    expect(noteName(440), 'A4 +0¢');
    expect(noteName(261.63), startsWith('C4'));
  });

  test('NFC: NDEF metin ve bağlantı kaydı kodla/çöz', () {
    final tp = ndefTextPayload('Merhaba ş', lang: 'tr');
    expect(tp[0], 2);
    final t = decodeNdef(1, Uint8List.fromList([0x54]), tp);
    expect(t.kind, 'text');
    expect(t.value, 'Merhaba ş');
    expect(t.lang, 'tr');
    final up = ndefUriPayload('https://www.example.org/a');
    expect(up[0], 2);
    final u = decodeNdef(1, Uint8List.fromList([0x55]), up);
    expect(u.kind, 'uri');
    expect(u.value, 'https://www.example.org/a');
    expect(decodeNdef(1, Uint8List.fromList([0x55]), ndefUriPayload('tel:+905551112233')).value, 'tel:+905551112233');
    expect(hexId(Uint8List.fromList([4, 0xA2, 0x1F])), '04:A2:1F');
  });

  test('alt ağ hesabı', () {
    final s = Subnet.parse('192.168.1.10/24')!;
    expect(ipv4(s.network), '192.168.1.0');
    expect(ipv4(s.broadcast), '192.168.1.255');
    expect(ipv4(s.mask), '255.255.255.0');
    expect(s.hosts, 254);
    expect(ipv4(s.first), '192.168.1.1');
    expect(s.scope, 'RFC 1918');
    final m = Subnet.parse('10.20.30.40 255.255.240.0')!;
    expect(m.prefix, 20);
    expect(ipv4(m.network), '10.20.16.0');
    expect(ipv4(m.broadcast), '10.20.31.255');
    expect(Subnet.parse('10.0.0.1/31')!.hosts, 2);
    expect(Subnet.parse('300.1.1.1/24'), isNull);
    expect(Subnet.parse('10.0.0.1 255.0.255.0'), isNull);
    expect(parseIpv4('8.8.8.8'), 0x08080808);
    expect(kPorts.any((p) => p.$1 == 443), isTrue);
  });

  test('göz filtresi rengi', () {
    final warm = kelvinColor(1800);
    final cool = kelvinColor(6500);
    expect(warm.r, closeTo(1, 1e-9));
    expect(warm.b, lessThan(cool.b));
    expect(filterAlpha(1), closeTo(0.8, 1e-9));
    expect(filterAlpha(2), closeTo(0.8, 1e-9));
    expect(filterColor(2700, 1).r, closeTo(0, 1e-9));
  });

  for (final t in [
    'uyg-nfc-okuyucu', 'uyg-ag-bilgisi', 'uyg-goz-koruma-filtresi',
    'uyg-hesap-makinesi', 'uyg-birim-cevirici', 'uyg-yuzde-ve-kesir-hesaplayici', 'uyg-denklem-cozucu',
    'uyg-roma-rakami-cevirici', 'uyg-sayi-tabani-cevirici', 'uyg-takvim-cevirici', 'uyg-sifre-uretici',
    'uyg-mors-kodu', 'uyg-maas-net-brut-hesaplayici', 'uyg-kidem-ve-ihbar-tazminati-hesaplayici',
    'uyg-zar-yazi-tura-rastgele-sayi', 'uyg-matris-ve-istatistik-hesaplayici', 'uyg-kronometre',
  ]) {
    testWidgets('araç ekranı açılır: $t', (tester) async {
      final s = AppServices(hubId: 'm', backend: MemoryBackend(), ads: NoAdsService(), purchases: NoPurchaseService());
      final tool = aracTool(t);
      final ctx = ToolContext(toolId: t, lang: 'tr', store: s.storeFor(t), services: s);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: AppLook(style: aracHubStyle, child: Scaffold(body: Builder(builder: (c) => tool.builder(c, ctx)))),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  }
}
