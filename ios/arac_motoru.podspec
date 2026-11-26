#
# Araç Kutusu motoru: iOS yerel eklentisi (yalnızca Bluetooth cihaz bulucu
# için CoreBluetooth taraması). Diğer araçlar iOS'ta saf Dart'tır.
#
Pod::Spec.new do |s|
  s.name             = 'arac_motoru'
  s.version          = '1.0.0'
  s.summary          = 'Araç Kutusu motoru: Bluetooth cihaz bulucu (CoreBluetooth).'
  s.description      = 'Yakındaki BLE cihazlarının adını ve sinyal gücünü okur; bağlantı kurmaz, ağ kullanmaz.'
  s.homepage         = 'https://github.com/taktemurr-ops/arac-motoru'
  s.license          = { :type => 'Proprietary', :text => 'Tüm hakları saklıdır.' }
  s.author           = { 'Game Studio 100' => 'taktemurr-ops' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.frameworks       = 'CoreBluetooth'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
