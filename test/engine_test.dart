import 'package:arac_motoru/arac_motoru.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:studio_core/app/services/ads.dart';
import 'package:studio_core/app/services/purchases.dart';
import 'package:studio_core/core/save_store.dart';

void main() {
  test('60 araç, 33 dilde ad ve açıklama, benzersiz kimlik', () {
    expect(aracTools.length, 60);
    expect(aracTools.map((t) => t.id).toSet().length, 60);
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

  for (final t in [
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
