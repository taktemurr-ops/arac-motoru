import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:arac_motoru/arac_motoru.dart';
import 'package:flutter_test/flutter_test.dart';

const int _rate = 44100;

List<double> _silence(double sec, math.Random r) =>
    [for (var i = 0; i < (sec * _rate).round(); i++) (r.nextDouble() * 2 - 1) * 0.001];

/// Kısa, geniş bantlı vuruş (alkış benzeri): 20 ms, hızla sönen gürültü.
List<double> _clap(math.Random r) =>
    [for (var i = 0; i < 882; i++) (r.nextDouble() * 2 - 1) * 0.7 * math.exp(-i / 250)];

List<double> _tone(double hz, double sec, double amp) =>
    [for (var i = 0; i < (sec * _rate).round(); i++) amp * math.sin(2 * math.pi * hz * i / _rate)];

String? _run(SoundFinderDetector d, List<double> s) {
  String? hit;
  for (var i = 0; i < s.length; i += 512) {
    final h = d.add(s.sublist(i, math.min(i + 512, s.length)));
    if (h != null) hit = h;
  }
  return hit;
}

void main() {
  group('kızılötesi kodlama', () {
    test('NEC: 9 ms başlık, 32 bit, LSB önce (LG aç/kapa 0x04/0x08)', () {
      final f = irNec(0x04, 0x08);
      expect(f.carrier, 38000);
      expect(f.pattern.length, 2 + 64 + 1);
      expect(f.pattern.sublist(0, 2), [9000, 4500]);
      // Adres 0x04 = 00100000 (LSB önce): üçüncü bit 1.
      expect(f.pattern[2 + 2 * 2 + 1], 1690);
      expect(f.pattern[2 + 2 * 0 + 1], 560);
      // Ters adres baytının üçüncü biti 0.
      expect(f.pattern[2 + 2 * (8 + 2) + 1], 560);
      expect(f.duration, lessThan(80000));
    });

    test('Samsung32: adres iki kez, 4,5 ms başlık', () {
      final f = irSamsung(0x07, 0x02);
      expect(f.pattern.sublist(0, 2), [4500, 4500]);
      final bits = [for (var i = 0; i < 32; i++) f.pattern[3 + 2 * i] == 1690 ? 1 : 0];
      int byte(int k) => [for (var i = 0; i < 8; i++) bits[k * 8 + i] << i].reduce((a, b) => a | b);
      expect(byte(0), 0x07);
      expect(byte(1), 0x07);
      expect(byte(2), 0x02);
      expect(byte(3), 0xFD);
    });

    test('Sony SIRC: üç çerçeve, 40 kHz, çerçeve 45 ms', () {
      final f = irSony12(1, 21);
      expect(f.carrier, 40000);
      expect(f.pattern.length, 26 * 3 - 1);
      expect(f.pattern.sublist(0, 26).fold<int>(0, (a, b) => a + b), 45000);
      expect(f.pattern.length.isOdd, isTrue); // işaretle biter
    });

    test('RC5: işaretle başlar ve biter, 889 µs katları', () {
      final f = irRc5(0, 12);
      expect(f.carrier, 36000);
      expect(f.pattern.length.isOdd, isTrue);
      for (final v in f.pattern) {
        expect(v % 889, 0);
      }
      // 14 bit × 2 yarım bit − baştaki boşluk − sondaki boşluk (komut 12'nin son biti 0).
      expect(f.duration, 889 * 26);
    });

    test('profiller: her kod protokol sınırında, aç/kapa her profilde var', () {
      for (final p in kIrProfiles) {
        final (maxA, maxC) = irLimits(p.protocol);
        expect(p.address, inInclusiveRange(0, maxA));
        expect(p.codes.containsKey('power'), isTrue, reason: p.id);
        for (final e in p.codes.entries) {
          expect(kIrButtons.contains(e.key), isTrue, reason: '${p.id} ${e.key}');
          expect(e.value, inInclusiveRange(0, maxC), reason: '${p.id} ${e.key}');
          expect(p.frame(e.key)!.duration, lessThan(2000000));
        }
      }
    });
  });

  group('alkış / ıslık algılayıcı', () {
    test('FFT: 2 kHz sinüsün tepe noktası doğru kutuda', () {
      final fft = SpectrumFft(1024);
      final x = Float64List.fromList(_tone(2000, 1024 / _rate, 0.5));
      final m = fft.magnitudes(x);
      var pk = 0;
      for (var i = 1; i < m.length; i++) {
        if (m[i] > m[pk]) pk = i;
      }
      expect(pk * _rate / 1024, closeTo(2000, 44));
    });

    test('iki alkış tetikler, tek alkış tetiklemez', () {
      final r = math.Random(7);
      final two = [..._silence(1.0, r), ..._clap(r), ..._silence(0.4, r), ..._clap(r), ..._silence(0.6, r)];
      expect(_run(SoundFinderDetector(whistle: false), two), 'clap');
      final one = [..._silence(1.0, r), ..._clap(r), ..._silence(1.5, r)];
      expect(_run(SoundFinderDetector(whistle: false), one), isNull);
    });

    test('ıslık (sürekli 2 kHz) tetikler', () {
      final r = math.Random(3);
      final s = [..._silence(0.6, r), ..._tone(2000, 1.2, 0.3), ..._silence(0.3, r)];
      expect(_run(SoundFinderDetector(claps: false), s), 'whistle');
      expect(_run(SoundFinderDetector(), s), 'whistle');
    });

    test('sürekli gürültü ve kısa tonlar tetiklemez', () {
      final r = math.Random(11);
      final noise = [..._silence(0.5, r), for (var i = 0; i < 2 * _rate; i++) (r.nextDouble() * 2 - 1) * 0.2];
      expect(_run(SoundFinderDetector(), noise), isNull);
      final beep = [..._silence(0.5, r), ..._tone(1500, 0.15, 0.3), ..._silence(0.5, r)];
      expect(_run(SoundFinderDetector(claps: false), beep), isNull);
    });

    test('alarm sesi geçerli WAV', () {
      final w = finderAlarmWav();
      expect(ascii.decode(w.sublist(0, 4)), 'RIFF');
      expect(w.length, greaterThan(20000));
    });
  });

  group('Bluetooth', () {
    test('uzaklık ve sıcaklık', () {
      expect(btDistance(-59), closeTo(1, 1e-9));
      expect(btDistance(-84), closeTo(10, 0.01));
      expect(btWarmth(-100), 0);
      expect(btWarmth(-40), 1);
      expect(btWarmth(-70), closeTo(0.5, 1e-9));
    });

    test('yumuşatma ve eğilim', () {
      final s = RssiSmoother();
      for (var i = 0; i < 10; i++) {
        s.add(-90 + i * 3, i * 300);
      }
      expect(s.trend, greaterThan(3));
      s.reset();
      expect(s.value, isNull);
    });
  });

  group('arşiv', () {
    test('biçim tanıma ve güvenli yol', () {
      expect(sniffArchive(Uint8List.fromList([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0, 4]), 'a.7z'), ArcKind.sevenZip);
      expect(sniffArchive(Uint8List.fromList(ascii.encode('Rar!xx')), 'a.rar'), ArcKind.rar);
      expect(sniffArchive(Uint8List.fromList([1, 2, 3]), 'a.bin'), ArcKind.unknown);
      expect(safeArchivePath('../../etc/passwd'), 'etc/passwd');
      expect(safeArchivePath('/abs/./x.txt'), 'abs/x.txt');
      expect(safeArchivePath(r'C:\win\a.txt'), 'win/a.txt');
      expect(() => openArchive(Uint8List.fromList([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]), 'x.7z'),
          throwsA(isA<ArcUnsupported>()));
    });

    test('ZIP oluştur ve aç (aynı ad iki kez)', () {
      final zip = makeZip([
        ('a.txt', Uint8List.fromList(utf8.encode('merhaba'))),
        ('a.txt', Uint8List.fromList(utf8.encode('ikinci'))),
        ('../kacak.txt', Uint8List.fromList(utf8.encode('x'))),
      ]);
      expect(sniffArchive(zip, 'x.zip'), ArcKind.zip);
      final e = openArchive(zip, 'x.zip');
      expect(e.map((x) => x.path).toList(), ['a.txt', 'a (2).txt', 'kacak.txt']);
      expect(utf8.decode(e[1].read()), 'ikinci');
    });

    test('tar.gz ve tek .gz dosyası', () {
      final a = Archive()
        ..add(ArchiveFile.bytes('klasor/b.txt', utf8.encode('tar ici')))
        ..add(ArchiveFile.bytes('c.txt', utf8.encode('uc')));
      final tgz = GZipEncoder().encodeBytes(TarEncoder().encodeBytes(a));
      final e = openArchive(tgz, 'paket.tar.gz');
      expect(e.map((x) => x.path).toSet(), {'klasor/b.txt', 'c.txt'});
      expect(utf8.decode(e.firstWhere((x) => x.path == 'c.txt').read()), 'uc');
      final gz = GZipEncoder().encodeBytes(utf8.encode('tek dosya'));
      final g = openArchive(gz, 'not.txt.gz');
      expect(g.single.path, 'not.txt');
      expect(utf8.decode(g.single.read()), 'tek dosya');
    });
  });
}
