# arac-motoru

Araç Kutusu ailesinin motoru: 60 aracın gerçek uygulamaları, 33 dilde metinleri ve
merkez görünümü (onaylı oyun merkezi tasarımının deniz mavisi tonu).

- Çatı: `studio_core/apps` (AppTool, AppHubShell, reklam/satın alma, gizlilik, favoriler).
- Her araç kendi ince deposunda (`uyg-*`) yayımlanır; merkez uygulama `merkez-arac-kutusu`.
- Çevrimdışı çalışır. Yalnızca Döviz Çevirici internetten kur indirir (Avrupa Merkez Bankası
  referans kurları, frankfurter.dev üzerinden, anahtarsız) ve son kurları tarihiyle saklar.
- Sensör/kamera/mikrofon olmayan cihazlarda ve web'de araç "bu cihazda yok" der, çökmez.
- Dosya yöneticisi tüm dosyalara erişim (MANAGE_EXTERNAL_STORAGE) istemez; yalnızca sistem
  seçicisiyle (SAF) kullanıcının seçtiği dosyaları açar.
- Maaş ve kıdem hesapları Türkiye 2026 parametreleriyle gelir; kaynak ve güncelleme tarihi
  ekranda yazar, kullanıcı değiştirebilir. Her yıl güncellenmelidir (`lib/src/tools/money.dart`).

Metinler `proto/apps/arac_titles.py` ve `arac_labels.py` dosyalarından
`proto/apps/arac/mkengine.py` ile üretilir (`lib/src/tx.dart`, `lib/src/registry.dart`).
