# Codar Rust bridge build glue

Bu klasör, `rust/` altındaki Codar Reader Core crate'ini Flutter platformlarına
taşımak için kullanılan Cargokit/FRB yapılandırmasıdır.

- Flutter plugin paketi: `rust_lib_codar`
- Cargo crate ve native output adı: `codar_reader`
- Android minimum SDK: 24
- FRB generated loader stem'i: `codar_reader`

Uygulama API'si `flutter_rust_bridge.yaml` ile tanımlıdır. Bu klasördeki
generated/build-tool dosyaları elle değiştirilmez; platform wrapper'ları yalnızca
crate yolu ve çıktı adı tutarlılığı için proje yapılandırmasına aittir.
