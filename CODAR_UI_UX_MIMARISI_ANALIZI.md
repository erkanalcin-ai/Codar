# CODAR UI/UX Mimari Analizi

## Kapsam

Bu doküman, `C:\Codar` içindeki mevcut Flutter + Rust projesinin UI/UX mimarisini, ekran yapısını, veri akışını, Brand Kit kullanımını ve referans tasarımla arasındaki teknik/görsel farkları özetler.

Bu analiz sırasında uygulama kodu, dependency'ler veya mimari değiştirilmemiştir.

APK, build ve test çalıştırılmamıştır.

## Git durumu

- Branch: `master`
- HEAD: `04a0aee`
- HEAD mesajı: `Phase 2: product shell`
- Çalışma ağacı temiz değildir.
- HEAD'e göre çok sayıda Phase 3/4 değişikliği tracked ve untracked olarak bulunmaktadır.
- Mevcut UI analizi yalnızca HEAD'i değil, çalışma ağacındaki sonraki değişiklikleri de kapsar.

## Genel mimari

```text
CodarApp
 ├─ Global splash overlay
 ├─ Material 3 light/dark theme
 └─ GoRouter
     ├─ StatefulShellRoute
     │   ├─ Home
     │   ├─ Library
     │   ├─ Collections
     │   └─ Settings
     ├─ Book Detail
     ├─ Reader
     └─ Records
```

Genel veri akışı:

```text
Flutter Screen
 → Riverpod Provider
 → Repository
 → SQLite / app-private storage
```

Reader veri akışı:

```text
ReaderScreen
 → ImportService staged file
 → CodarReaderService
 → FRB generated bindings
 → Rust Reader API
 → ebook-rs
```

Ana mimari dosyaları:

- `lib/main.dart`
- `lib/src/app/router.dart`
- `lib/src/app/shell.dart`
- `lib/src/app/providers.dart`
- `lib/src/db/repositories.dart`
- `lib/src/reader/reader_service.dart`
- `flutter_rust_bridge.yaml`
- `rust/src/api/reader.rs`

## Route ve ekran yapısı

| Ekran | Mevcut yapı |
|---|---|
| Splash | `CodarApp` içinde global 2 saniyelik overlay |
| Home | Koyu navy yüzey, favoriler `PageView`, yatay kitap satırları |
| Library | Koyu yüzey, arama, favori filtresi, grid/list görünüm |
| Book Detail | Koyu yüzey, kapak, metadata, progress ve aksiyonlar |
| Reader | Dikey `PageView`, seçilebilir metin, gizlenen toolbar |
| Collections | Açık cream yüzey, rounded collection card'ları |
| Records | Açık tema, highlights/notes/bookmarks sekmeleri |
| Settings | Açık tema, gruplu ayar satırları |
| Search | Ayrı ekran yok; Library içindeki TextField kullanılıyor |
| Empty states | Ortak `CodarEmptyState` widget'ı var |

Route yapısı:

- `/` → Home
- `/library` → Library
- `/collections` → Collections
- `/settings` → Settings
- `/book/:id` → Book Detail
- `/reader/:id` → Reader
- `/records` → Records

Records birincil bottom navigation sekmesi değildir; Collections içinden açılır.

## Design system ve Brand Kit

Brand renkleri `lib/src/brand/codar_brand.dart` içinde merkezi olarak tanımlıdır:

- Navy
- Deep navy
- Navy soft
- Charcoal
- Cream
- Gold

`CodarLogo` widget'ı tema ve arka plana göre transparent `READ FURTHER` logo ailesinden uygun dosyayı seçer.

Mevcut Brand Kit assetleri:

- `assets/brand/read_further/codar_logo_horizontal_dark_transparent.png`
- `assets/brand/read_further/codar_logo_horizontal_light_transparent.png`
- `assets/brand/read_further/codar_logo_stacked_dark_transparent.png`
- `assets/brand/read_further/codar_logo_stacked_light_transparent.png`
- `assets/brand/read_further/icons/codar_app_icon_*.png`
- `assets/brand/codar_splash_background.png`

### Design system eksikleri

Renk ve logo merkezi olsa da tam bir UI design system mevcut değildir.

- Ortak spacing token'ları yok.
- Ortak typography scale yok.
- Ortak card, hero, metadata row ve action bar bileşenleri yok.
- Ekranlar kendi `Padding`, `BorderRadius`, `TextStyle`, `Card` ve `ListTile` değerlerini ayrı ayrı tanımlıyor.
- Özel rounded card sistemi ile standart Material `ListTile/Card` sistemi birlikte kullanılıyor.
- Aynı uygulama içinde koyu ve açık yüzeyler bulunmasına rağmen geçiş ve component dili tam olarak ortak değil.

Bu nedenle ekranlar tek tek çalışsa da ortak bir premium ürün sistemi gibi görünmüyor.

## Ekran bazlı analiz

### Home

Mevcut yapı:

- Favoriler üstte featured carousel olarak bulunuyor.
- Büyük kapak, kitap adı, yazar ve progress gösteriliyor.
- Kartın kendisi Reader'a yönlendiriyor.
- Tablet/geniş ekran için farklı layout var.
- Altında devam edilen, son eklenen, son okunan ve tüm kitaplar yatay listeleri bulunuyor.

Eksikler:

- Alt bölümler hâlâ tekrar eden başlık + yatay liste yapısında.
- Referanstaki güçlü içerik hiyerarşisi ve “Tümünü gör” aksiyonları yok.
- Tablet layout'u section'ları iki kolonlu grid olarak gösteriyor; kitap odaklı referans düzeniyle tam örtüşmüyor.
- Kapaksız kitap görünümü generic icon + text fallback olarak kalıyor.
- Home, Library'deki cover warmup akışını doğrudan izlemiyor.

Dosya: `lib/src/presentation/home/home_screen.dart`

### Library

Mevcut yapı:

- Grid/list görünüm değişimi.
- Başlık/yazar araması.
- Favoriler filtresi.
- Sort popup.
- Embedded veya cache cover gösterimi.
- App-private fallback cover.

Eksikler:

- Arama alanı hâlâ klasik form kutusu hissi veriyor.
- Filtre sistemi yalnızca Tümü/Favoriler düzeyinde.
- Kitap kartları görsel olarak basit.
- Grid ve list kartları farklı component dilleri kullanıyor.
- Cover loading/fallback durumu premium bir görsel sistem değil.
- Ayrı Search ekranı veya gelişmiş arama kompozisyonu bulunmuyor.

Dosyalar:

- `lib/src/presentation/library/library_screen.dart`
- `lib/src/presentation/widgets/book_widgets.dart`

### Book Detail

Mevcut yapı:

- Kapak, başlık, yazar ve metadata.
- Progress göstergesi.
- Oku, collection ve favorite aksiyonları.
- Enrichment ve metadata düzenleme.
- Kitaba ait highlight, note ve bookmark kayıtları.
- Landscape/tablet için iki kolon layout.

Eksikler:

- Büyük `FilledButton.icon` referanstaki minimal ikon/contextual action yaklaşımından uzak.
- Metadata bölümü satır listesi gibi görünüyor.
- Koyu yüzey ile standart Material bileşenleri arasında tam görsel bütünlük yok.
- Description ve records bölümleri uzun bir form/detail ekranı hissi veriyor.
- Book Detail için özel hero/header component'i yok.

Dosya: `lib/src/presentation/book_detail/book_detail_screen.dart`

### Reader

Mevcut yapı:

- Dikey `PageView` kullanılıyor.
- Toolbar dokununca görünür hale geliyor ve otomatik gizleniyor.
- Bölüm seçimi Bölümler menüsü üzerinden yapılabiliyor.
- CFI, progress, highlight, note ve bookmark akışları korunuyor.
- Üst sağda section içi sayfa numarası bulunuyor.
- Metin `SelectableRegion` ile seçilebiliyor.

Kritik mimari bulgu:

Rust tarafında `paginate_section` API'si mevcut olmasına rağmen Flutter Reader gerçek layout pagination için bu API'yi kullanmıyor.

Flutter tarafında `_paginateBlocks`, `_measureText` ve `TextPainter` ile Dart içinde tahmini block pagination yapılıyor.

Sonuçları:

- Sayfa sınırları gerçek kitap layout'una göre değil, tahmini metin yüksekliğine göre belirleniyor.
- Font, ekran yoğunluğu, accessibility font boyutu veya farklı karakter genişliklerinde sonuç değişebilir.
- Sayfa numarası bölüm bazlıdır; kitap geneli `152 / 422` mantığı bulunmuyor.
- CFI restore bölümü doğruluyor; sayfa içindeki konum sonrasında progress/offset tahminiyle seçiliyor.
- Bölüm sınırı kullanıcıya gizlense de page model hâlâ section bazlı.

Bu nokta, Reader'ın referans görseldeki gerçek kitap okuyucu deneyimine ulaşamamasının en önemli teknik nedenidir.

Dosyalar:

- `lib/src/presentation/reader/reader_screen.dart`
- `lib/src/reader/reader_service.dart`
- `lib/src/reader/locator_nav.dart`
- `rust/src/api/reader.rs`
- `rust/src/reader/content.rs`
- `rust/src/reader/locator.rs`

### Collections

Mevcut yapı:

- Açık cream yüzey.
- Favorites ve all books collection satırları.
- Kullanıcı collection oluşturma/silme.
- Collection içindeki kitapları bottom sheet ile gösterme.
- Records ekranına yönlendirme.

Eksikler:

- Standart `Card + ListTile` ağırlığı yüksek.
- Referanstaki daha rafine ikon merkezli satır düzeni tam uygulanmamış.
- Collection kitapları için ayrı cover odaklı görünüm yok.
- Collection detail bir ekran yerine bottom sheet olarak açılıyor.

Dosya: `lib/src/presentation/collections/collections_screen.dart`

### Records

Mevcut yapı:

- Highlight, note ve bookmark olmak üzere üç TabBar sekmesi.
- Her kayıt ilgili kitaba ve locator'a geri bağlanıyor.
- Açık cream tema kullanılıyor.

Eksikler:

- Records birincil navigation öğesi değil.
- Kayıt listeleri standart Card/ListTile yapısında.
- Kitap kapağı, güçlü kayıt hiyerarşisi veya referanstaki premium kayıt sunumu yok.

Dosya: `lib/src/presentation/records/records_screen.dart`

### Settings

Mevcut yapı:

- Uygulama dili.
- Reader ayarları.
- Dosya silme davranışı.
- Online enrichment.
- Backup import/export.
- Açık cream tema.

Eksikler:

- Ayarlar grupları var ancak ortak ve güçlü bir settings-row design component'i yok.
- Standart `ListTile` ve `SwitchListTile` yapısı referanstaki sade/ikon merkezli kompozisyondan uzak.
- Reader ayarları bottom sheet içinde klasik form görünümünde.
- Ekranlar arası typography ve spacing tam ortak değil.

Dosya: `lib/src/presentation/settings/settings_screen.dart`

## Cover sistemi

Mevcut zincir:

```text
Embedded cover
 → app-private cover cache
 → opt-in Open Library enrichment
 → generic fallback
```

İlgili dosyalar:

- `lib/src/presentation/widgets/book_widgets.dart`
- `lib/src/library/enrichment_service.dart`
- `lib/src/library/import_service.dart`

Teknik olarak:

- Embedded cover öncelikli.
- Cover app-private cache'e yazılıyor.
- Open Library enrichment opt-in.
- Kullanıcı düzenlemesi korunuyor.
- Orijinal kitap dosyasına yazılmıyor.

UI tarafındaki eksikler:

- Cover loading state tasarlanmamış.
- Fallback gerçek bir branded cover treatment değil.
- Enrichment tamamlandıktan sonra tüm ekranlar aynı yenilenme davranışını göstermiyor.
- Cover sonucu her kartta `FutureBuilder` ile ayrı okunuyor; ortak reactive cover provider yok.

## UI state ve veri yenileme modeli

Riverpod kullanılıyor ancak ekranların önemli bölümü `FutureBuilder` ile veri okuyor.

Güncelleme modeli çoğunlukla:

```text
Mutation
 → repository write
 → libraryRefreshProvider.bump()
 → FutureBuilder/provider yeniden çalışır
```

Bu yapı çalışır durumdadır ancak gerçek zamanlı ve merkezi bir UI state modeli değildir.

Riskler:

- Ekranların refresh davranışı birbirinden farklı olabilir.
- Aynı repository sorgusu birden fazla FutureBuilder tarafından tekrar çalıştırılabilir.
- Cover ve progress gibi alanlarda kısa süreli eski veri/fallback görüntülenebilir.
- UI tasarımının veri state'leriyle tutarlı yükleme/error/empty durumları her ekranda aynı değildir.

## Test kapsamı

Mevcut testler:

- HTML parser güvenliği.
- Türkçe karakter ve localization anahtarları.
- CFI route round-trip.
- Stabil book ID.
- Grid breakpoint fonksiyonu.
- Backup encode/decode.
- FRB/Rust locator contract testleri.
- Android üzerinde Phase 4 smoke/integration testi.

Testler ağırlıklı olarak davranışsal ve contract seviyesindedir.

Eksik UI doğrulaması:

- Referans görselle screenshot karşılaştırması yok.
- Widget golden testleri yok.
- Farklı telefon/tablet viewport'ları için görsel regression yok.
- Reader sayfalama ve gerçek cihaz gesture doğrulaması otomatik testlerle ölçülmüyor.
- Launcher icon ve status bar davranışı için fiziksel cihaz screenshot kanıtı yok.

## UI'ın referans tasarıma göre pass olmamasının root cause'ları

1. Ortak design system yalnızca renk ve logo seviyesinde mevcut.
2. Spacing, typography, card ve action component'leri ekranlara dağılmış durumda.
3. Reader, Rust paginator yerine tahmini Dart block pagination kullanıyor.
4. Sayfa numarası section içi; kitap geneli progress modeli yok.
5. Home, Library, Detail ve Collections farklı card/list/button dilleri kullanıyor.
6. Cover fallback'i premium kitap kapağı görünümü değil.
7. Search ayrı bir deneyim değil; Library TextField'ına sıkıştırılmış.
8. Records ve Settings işlevsel ancak referanstaki ikon merkezli minimal sunuma ulaşmamış.
9. Kaynak analizleri ve Flutter testleri görsel uyumluluk kanıtı değildir.
10. Önceki APK/cihaz doğrulamalarında gerçek ekran görüntüsü ile referans karşılaştırması yapılmadan görsel pass kabul edilmiştir.

## Sonuç

CODAR'ın mevcut UI/UX'i, Phase 2 product shell üzerine Phase 3/4 özellikleri eklenmiş işlevsel bir yapıdır.

Özellik akışları büyük ölçüde mevcut olsa da uygulama henüz referans görseldeki gibi tek bir premium design system ile yeniden kurulmuş değildir.

Önerilen sonraki çalışma sırası:

1. Ortak design system ve component sınırlarını tanımlamak.
2. Home, Library, Book Detail ve Reader'ı aynı visual grammar ile yeniden kurmak.
3. Reader pagination ve locator modelini kitap geneli sayfa ilerlemesiyle netleştirmek.
4. Cover loading/fallback/enrichment durumlarını ortak component'e almak.
5. Gerçek cihaz ekran görüntüleriyle ekran bazlı referans karşılaştırması yapmak.

Bu rapor oluşturulurken uygulama kodu, dependency pinleri, Rust/FRB mimarisi ve Android yapılandırması değiştirilmemiştir.
