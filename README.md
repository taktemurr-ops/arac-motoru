# arac-motoru

Araç Kutusu ailesinin motoru: 64 aracın gerçek uygulamaları, 33 dilde metinleri ve
merkez görünümü (onaylı oyun merkezi tasarımının deniz mavisi tonu).

- Çatı: `studio_core/apps` (AppTool, AppHubShell, reklam/satın alma, gizlilik, favoriler).
- Her araç kendi ince deposunda (`uyg-*`) yayımlanır; merkez uygulama `merkez-arac-kutusu`.
- Çevrimdışı çalışır. Yalnızca Döviz Çevirici internetten kur indirir (Avrupa Merkez Bankası
  referans kurları, frankfurter.dev üzerinden, anahtarsız) ve son kurları tarihiyle saklar.
- Sensör/kamera/mikrofon olmayan cihazlarda ve web'de araç "bu cihazda yok" der, çökmez.
- Dosya yöneticisi tüm dosyalara erişim (MANAGE_EXTERNAL_STORAGE) istemez; yalnızca sistem
  seçicisiyle (SAF) kullanıcının seçtiği dosyaları açar.
- Ton Üreteci sesi cihazda üretir (sinüs/kare/üçgen/testere, 1 Hz–22 kHz, logaritmik tarama).
- NFC Etiket Okuyucu: Android'de NDEF okuma/yazma (metin, bağlantı), iOS'ta okuma (`nfc_manager`).
  Merkez uygulamada `android.permission.NFC` ve iOS `NFCReaderUsageDescription` gerekir.
- Ağ Bilgisi: Wi-Fi/IP/ağ geçidi (`network_info_plus`), arabirimler, çevrimdışı alt ağ (CIDR)
  hesaplayıcı ve port listesi; hiçbir veri dışarı gönderilmez.
- Göz Koruma Filtresi: Android'de yerleşik servis (`android/`, `ScreenFilterService`) diğer
  uygulamaların üstüne dokunmaları geçiren renk katmanı çizer (SYSTEM_ALERT_WINDOW, saydamlık
  ≤ 0,8); iOS ve web'de sistem gece modu anlatılır, uygulama içi önizleme gösterilir.
- Maaş ve kıdem hesapları Türkiye 2026 parametreleriyle gelir; kaynak ve güncelleme tarihi
  ekranda yazar, kullanıcı değiştirebilir. Her yıl güncellenmelidir (`lib/src/tools/money.dart`).

Metinler `proto/apps/arac_titles.py` ve `arac_labels.py` dosyalarından
`proto/apps/arac/mkengine.py` ile üretilir (`lib/src/tx.dart`, `lib/src/registry.dart`).
