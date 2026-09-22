# Codar

Codar, kitap dosyalarını cihazda tutan Flutter + Rust tabanlı bir okuma
uygulamasıdır. Kitap dosyaları ve uygulama verisi ayrıdır; orijinal kitap
dosyaları metadata veya annotation yazımıyla değiştirilmez.

Android application ID `com.codar.codar`; current app version is `1.0.0+1`.

## Mimari

- `lib/`: Flutter UI, Riverpod provider'ları, SQLite repository'leri ve yerel
  import/backup akışları.
- `lib/src/db/`: Uygulamanın belgeler klasöründeki `codar.db`. Şema 13 tablo
  içerir ve `onUpgrade` üzerinden sürümlü migration akışına sahiptir.
- `lib/src/storage/` ve `android/app/src/main/kotlin/`: Android API 29+
  cihazlarda `Downloads/CodarLib/` için scoped MediaStore; API 24–28'de
  storage permission gerektirmeyen app-specific fallback.
- `lib/src/rust/` → `rust/src/api/`: Flutter ile Rust Reader Core arasındaki
  flutter_rust_bridge 2.13.0 sınırı.
- `rust/`: ebook-rs 0.16.6 kullanan format, locator, search ve pagination
  çekirdeği. Flutter ebook-rs tiplerini doğrudan görmez.
- `rust_builder/`: Cargokit tabanlı platform çıktıları. Rust crate ve FRB
  loader adı `codar_reader`; Flutter plugin paketi `rust_lib_codar` olarak
  kalır.

## Geliştirme

Bağımlılık sürümleri `pubspec.yaml` ve `rust/Cargo.toml` içinde sabittir.

```text
flutter pub get
flutter analyze
flutter test
cargo fmt --check
cargo check
cargo clippy
cargo test -- --test-threads=1
```

Rust komutları `rust/` klasöründe çalıştırılır. FRB yapılandırması
`flutter_rust_bridge.yaml` içindedir; generated dosyalar elle düzenlenmez.

## Android release

`android/key.properties` yalnızca yerel production signing kurulumu içindir
ve repoya alınmaz. Signing anahtarı yokken yapılan release çıktısı yalnızca
yerel doğrulama için açıkça `-Pcodar.debugReleaseSigning=true` verilerek
oluşturulabilir; bu production upload kanıtı değildir. Gerçek release build'i
doğrulanabilir bir keystore ve `android/key.properties` olmadan başlamaz.

```text
cd android
gradlew.bat assembleRelease "-Pcodar.debugReleaseSigning=true"
# PowerShell Flutter CLI: $env:CODAR_DEBUG_RELEASE_SIGNING='true'; flutter build apk --release
```

## Kapsam sınırı

Codar; WebView, AI/TTS, backend/account, reklam, OPDS/WebDAV/Calibre veya DRM
bypass içermez. Kitap dosyası importu SAF/MediaStore ve app-private staging
üzerinden yapılır.
