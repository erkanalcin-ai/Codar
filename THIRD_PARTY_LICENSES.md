# Codar — Third-Party Licenses (Phase 1)

Generated/audited: 2026-09-16. Toolchain: Flutter 3.47.1 / Dart 3.13.1 /
Rust 1.98.1 / cargo-deny 0.20.2 (`cargo deny check licenses` → **ok**).

Policy (`deny.toml`): allow MIT, Apache-2.0, BSD-2/3-Clause, ISC, Unlicense,
Zlib, CC0-1.0, Unicode-DFS-2016, Unicode-3.0. No copyleft in tree
(sole LGPL mention is `r-efi` triple-licensed MIT/Apache/LGPL — permissive
choice applies). No paid SDKs, no analytics, no ads.

Known watch items (do not silently upgrade past these without re-audit):

- `ttf-parser 0.25.1` (via pdf_oxide): RUSTSEC-2026-0192 **unmaintained**,
  no safe upgrade available. Non-blocking for Phase 1 spike; revisit on
  pdf_oxide/skrifa migration.
- `allo-isolate 0.1.27` (via flutter_rust_bridge): license via LICENSE file
  (Apache-2.0, verified by reading the file), not the manifest field.
- Duplicate versions in tree (warn-level, accepted): `zip` 7.2.0 + 8.6.0,
  `getrandom` 0.3.4 + 0.4.3, `bitflags` 1.x + 2.x, `weezl` 0.1 + 0.2.
- `uniffi` (MPL-2.0) is NOT in the tree (feature disabled). Never enable it
  without a license review.

## A. Direct Dart/Flutter dependencies (pubspec.lock — verified)

| Package | Version | License | Publisher/Source | Purpose |
|---|---|---|---|---|
| flutter_riverpod (+riverpod) | 3.4.3 | MIT | dash-overflow / pub.dev | State management |
| go_router | 18.0.1 | BSD-3-Clause | flutter.dev / pub.dev | Navigation |
| sqflite | 2.4.3 | BSD-2-Clause | tekartik / pub.dev | SQLite |
| path_provider | 2.1.6 | BSD-3-Clause | flutter.dev / pub.dev | App dirs |
| file_picker | 12.2.0 | MIT | victorcarreras.dev / pub.dev | SAF import picker |
| shared_preferences | 2.5.5 | BSD-3-Clause | flutter.dev / pub.dev | Settings KV |
| intl | 0.20.3 | BSD-3-Clause | dart.dev / pub.dev | Localization (TR/EN later) |
| flutter_rust_bridge | 2.13.0 | MIT | cjycode / pub.dev | Dart↔Rust bridge (exact pin with Rust crate + codegen) |
| freezed_annotation | 3.1.0 | MIT | remi / pub.dev | FRB generated DTOs |
| path | 1.9.1 | BSD-3-Clause | dart.dev / pub.dev | Path join |
| cupertino_icons | 1.0.9 | MIT | flutter.dev / pub.dev | iOS-style icons |
| freezed (dev) | 4.0.1 | MIT | remi / pub.dev | Codegen for FRB freezed DTOs |
| build_runner (dev) | 2.16.1 | BSD-3-Clause | dart.dev / pub.dev | Codegen runner |
| rust_lib_codar | path | — (own code) | local rust_builder | cargokit build glue |

Note: Phase 0 pinned `intl 0.20.2`; `go_router 18.0.1` requires `intl ^0.20.3`
via flutter_localizations, so `intl 0.20.3` is the documented minimal
substitution (same BSD-3 license, same publisher).

## B. Direct Rust dependencies (rust/Cargo.toml — verified)

| Crate | Version | License | Repo | Purpose |
|---|---|---|---|---|
| ebook-rs | =0.16.6 | MIT | github.com/SV-stark/ebook-rs | Ebook engine (default-features=false, features=["pdf"]) |
| flutter_rust_bridge | =2.13.0 | MIT | github.com/fzyzcjy/flutter_rust_bridge | Bridge runtime (exact pin) |
| serde | 1 | MIT OR Apache-2.0 | github.com/serde-rs/serde | DTO serialization |
| serde_json | 1 | MIT OR Apache-2.0 | github.com/serde-rs/json | Readium locator JSON |

Confirmed ABSENT from the tree (disabled ebook-rs features): tiny_http,
url (as ebook dep), rayon (ebook `parallel`), memmap2, zstd, tokio (ebook
`async`), pyo3, uniffi, wasm-bindgen (ebook `wasm`), mimalloc, opds/server
modules. Present-but-legitimate lookalikes: `tokio` via flutter_rust_bridge
runtime, `rayon` via pdf_oxide→jpeg-decoder (PDF subtree), `getrandom` via
ahash/pdf_oxide, `wasm-bindgen` wasm-target-only (absent from Android tree).

## C. Transitive Rust dependency licenses (Cargo.lock — generated from local registry manifests)

| Crate | Version | License |
|---|---|---|
| addr2line | 0.25.1 | Apache-2.0 OR MIT |
| adler2 | 2.0.1 | 0BSD OR MIT OR Apache-2.0 |
| aes | 0.9.3 | MIT OR Apache-2.0 |
| ahash | 0.8.12 | MIT OR Apache-2.0 |
| aho-corasick | 1.1.5 | Unlicense OR MIT |
| allocator-api2 | 0.2.21 | MIT OR Apache-2.0 |
| alloc-no-stdlib | 3.0.0 | BSD-3-Clause |
| alloc-stdlib | 0.3.0 | BSD-3-Clause |
| allo-isolate | 0.1.27 | see LICENSE |
| android_logger | 0.15.1 | MIT OR Apache-2.0 |
| android_log-sys | 0.3.2 | MIT OR Apache-2.0 |
| android_system_properties | 0.1.6 | MIT OR Apache-2.0 |
| anstream | 1.0.0 | MIT OR Apache-2.0 |
| anstyle | 1.0.14 | MIT OR Apache-2.0 |
| anstyle-parse | 1.0.0 | MIT OR Apache-2.0 |
| anstyle-query | 1.1.5 | MIT OR Apache-2.0 |
| anstyle-wincon | 3.0.11 | MIT OR Apache-2.0 |
| anyhow | 1.0.104 | MIT OR Apache-2.0 |
| arrayvec | 0.7.8 | MIT OR Apache-2.0 |
| atoi_simd | 0.18.1 | MIT OR Apache-2.0 |
| atomic | 0.5.3 | Apache-2.0/MIT |
| autocfg | 1.5.1 | Apache-2.0 OR MIT |
| backtrace | 0.3.76 | MIT OR Apache-2.0 |
| base64 | 0.23.1 | MIT OR Apache-2.0 |
| bitflags | 1.3.2 | MIT/Apache-2.0 |
| bitflags | 2.13.2 | MIT OR Apache-2.0 |
| block-buffer | 0.10.4 | MIT OR Apache-2.0 |
| block-buffer | 0.12.1 | MIT OR Apache-2.0 |
| block-padding | 0.4.2 | MIT OR Apache-2.0 |
| brotli | 9.0.0 | BSD-3-Clause AND MIT |
| brotli-decompressor | 6.0.0 | BSD-3-Clause/MIT |
| build-target | 0.4.0 | MIT |
| bumpalo | 3.20.3 | MIT OR Apache-2.0 |
| bytemuck | 1.25.2 | Zlib OR Apache-2.0 OR MIT |
| bytemuck_derive | 1.12.1 | Zlib OR Apache-2.0 OR MIT |
| byteorder | 1.5.0 | Unlicense OR MIT |
| byteorder-lite | 0.1.0 | Unlicense OR MIT |
| bytes | 1.12.1 | MIT |
| castaway | 0.2.4 | MIT |
| cbc | 0.2.1 | MIT OR Apache-2.0 |
| cc | 1.4.6 | MIT OR Apache-2.0 |
| cfg-if | 1.0.5 | MIT OR Apache-2.0 |
| chrono | 0.4.45 | MIT OR Apache-2.0 |
| cipher | 0.5.2 | MIT OR Apache-2.0 |
| colorchoice | 1.0.5 | MIT OR Apache-2.0 |
| compact_str | 0.10.0 | MIT |
| console_error_panic_hook | 0.1.7 | Apache-2.0/MIT |
| const-oid | 0.10.2 | Apache-2.0 OR MIT |
| core_detect | 1.0.0 | MIT/Apache-2.0 |
| core-foundation-sys | 0.8.7 | MIT OR Apache-2.0 |
| cpubits | 0.1.1 | MIT OR Apache-2.0 |
| cpufeatures | 0.3.1 | MIT OR Apache-2.0 |
| crc32fast | 1.5.2 | MIT OR Apache-2.0 |
| crossbeam-deque | 0.8.8 | MIT OR Apache-2.0 |
| crossbeam-epoch | 0.9.21 | MIT OR Apache-2.0 |
| crossbeam-utils | 0.8.23 | MIT OR Apache-2.0 |
| crunchy | 0.2.4 | MIT |
| crypto-common | 0.1.7 | MIT OR Apache-2.0 |
| crypto-common | 0.2.2 | MIT OR Apache-2.0 |
| dart-sys | 4.1.5 | MIT OR Apache-2.0 |
| dashmap | 5.5.3 | MIT |
| debug_unsafe | 0.1.4 | MIT OR Apache-2.0 |
| defmt | 1.1.1 | MIT OR Apache-2.0 |
| defmt-macros | 1.1.1 | MIT OR Apache-2.0 |
| defmt-parser | 1.0.0 | MIT OR Apache-2.0 |
| delegate-attr | 0.3.1 | MIT |
| digest | 0.10.7 | MIT OR Apache-2.0 |
| digest | 0.11.3 | MIT OR Apache-2.0 |
| ebook-rs | 0.16.6 | MIT |
| either | 1.18.0 | MIT OR Apache-2.0 |
| encoding_rs | 0.8.41 | (Apache-2.0 OR MIT) AND BSD-3-Clause |
| env_filter | 0.1.4 | MIT OR Apache-2.0 |
| env_filter | 2.0.0 | MIT OR Apache-2.0 |
| env_logger | 0.11.11 | MIT OR Apache-2.0 |
| equivalent | 1.0.2 | Apache-2.0 OR MIT |
| euclid | 0.22.14 | MIT OR Apache-2.0 |
| fast-float2 | 0.2.4 | MIT OR Apache-2.0 |
| fastrand | 2.5.0 | Apache-2.0 OR MIT |
| fax | 0.2.7 | MIT |
| fax | 0.3.0 | MIT |
| fdeflate | 0.3.7 | MIT OR Apache-2.0 |
| find-msvc-tools | 0.1.12 | MIT OR Apache-2.0 |
| flate2 | 1.1.10 | MIT OR Apache-2.0 |
| flutter_rust_bridge | 2.13.0 | MIT |
| flutter_rust_bridge_macros | 2.13.0 | MIT |
| foldhash | 0.1.5 | Zlib |
| font-types | 0.11.3 | MIT OR Apache-2.0 |
| futures | 0.3.34 | MIT OR Apache-2.0 |
| futures-channel | 0.3.34 | MIT OR Apache-2.0 |
| futures-core | 0.3.34 | MIT OR Apache-2.0 |
| futures-executor | 0.3.34 | MIT OR Apache-2.0 |
| futures-io | 0.3.34 | MIT OR Apache-2.0 |
| futures-macro | 0.3.34 | MIT OR Apache-2.0 |
| futures-sink | 0.3.34 | MIT OR Apache-2.0 |
| futures-task | 0.3.34 | MIT OR Apache-2.0 |
| futures-util | 0.3.34 | MIT OR Apache-2.0 |
| generic-array | 0.14.7 | MIT |
| getrandom | 0.3.4 | MIT OR Apache-2.0 |
| getrandom | 0.4.3 | MIT OR Apache-2.0 |
| gimli | 0.32.3 | MIT OR Apache-2.0 |
| half | 2.7.1 | MIT OR Apache-2.0 |
| hashbrown | 0.14.5 | MIT OR Apache-2.0 |
| hashbrown | 0.15.5 | MIT OR Apache-2.0 |
| hashbrown | 0.17.1 | MIT OR Apache-2.0 |
| hermit-abi | 0.5.3 | MIT OR Apache-2.0 |
| hex | 0.4.3 | MIT OR Apache-2.0 |
| hybrid-array | 0.4.15 | MIT OR Apache-2.0 |
| iana-time-zone | 0.1.65 | MIT OR Apache-2.0 |
| iana-time-zone-haiku | 0.1.2 | MIT OR Apache-2.0 |
| image | 0.25.10 | MIT OR Apache-2.0 |
| indexmap | 2.14.2 | Apache-2.0 OR MIT |
| inout | 0.2.2 | MIT OR Apache-2.0 |
| is_terminal_polyfill | 1.70.2 | MIT OR Apache-2.0 |
| itoa | 1.0.18 | MIT OR Apache-2.0 |
| jiff | 0.2.37 | Unlicense OR MIT |
| jiff-core | 0.1.1 | Unlicense OR MIT |
| jiff-static | 0.2.37 | Unlicense OR MIT |
| jpeg-decoder | 0.3.2 | MIT OR Apache-2.0 |
| js-sys | 0.3.105 | MIT OR Apache-2.0 |
| kurbo | 0.13.1 | Apache-2.0 OR MIT |
| lazy_static | 1.5.0 | MIT OR Apache-2.0 |
| libc | 0.2.189 | MIT OR Apache-2.0 |
| lock_api | 0.4.14 | MIT OR Apache-2.0 |
| log | 0.4.34 | MIT OR Apache-2.0 |
| md-5 | 0.10.6 | MIT OR Apache-2.0 |
| md-5 | 0.11.0 | MIT OR Apache-2.0 |
| memchr | 2.8.3 | Unlicense OR MIT |
| miniz_oxide | 0.8.9 | MIT OR Zlib OR Apache-2.0 |
| miniz_oxide | 0.9.1 | MIT OR Zlib OR Apache-2.0 |
| moxcms | 0.8.1 | BSD-3-Clause OR Apache-2.0 |
| multiversion | 0.9.0 | MIT OR Apache-2.0 |
| multiversion_no_op | 1.0.0 | Apache-2.0 OR MIT |
| multiversion-macros | 0.9.0 | MIT OR Apache-2.0 |
| nom | 8.0.0 | MIT |
| num_cpus | 1.17.0 | MIT OR Apache-2.0 |
| num-traits | 0.2.19 | MIT OR Apache-2.0 |
| object | 0.37.3 | Apache-2.0 OR MIT |
| office_oxide | 0.1.11 | MIT OR Apache-2.0 |
| once_cell | 1.21.4 | MIT OR Apache-2.0 |
| once_cell_polyfill | 1.70.2 | MIT OR Apache-2.0 |
| oslog | 0.2.0 | MIT |
| parking_lot | 0.12.5 | MIT OR Apache-2.0 |
| parking_lot_core | 0.9.12 | MIT OR Apache-2.0 |
| pdf_oxide | 0.3.78 | MIT OR Apache-2.0 |
| percent-encoding | 2.3.2 | MIT OR Apache-2.0 |
| phf | 0.14.0 | MIT |
| phf_generator | 0.14.0 | MIT |
| phf_macros | 0.14.0 | MIT |
| phf_shared | 0.14.0 | MIT |
| pin-project-lite | 0.2.17 | Apache-2.0 OR MIT |
| png | 0.18.1 | MIT OR Apache-2.0 |
| polycool | 0.4.0 | MIT OR Apache-2.0 |
| portable-atomic | 1.15.0 | Apache-2.0 OR MIT |
| portable-atomic-util | 0.2.8 | Apache-2.0 OR MIT |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 |
| pxfm | 0.1.30 | BSD-3-Clause OR Apache-2.0 |
| qcms | 0.3.0 | MIT |
| quick-error | 2.0.1 | MIT/Apache-2.0 |
| quick-xml | 0.41.0 | MIT |
| quick-xml | 0.42.0 | MIT |
| quote | 1.0.47 | MIT OR Apache-2.0 |
| rayon | 1.12.0 | MIT OR Apache-2.0 |
| rayon-core | 1.13.0 | MIT OR Apache-2.0 |
| read-fonts | 0.39.2 | MIT OR Apache-2.0 |
| redox_syscall | 0.5.18 | MIT |
| r-efi | 5.3.0 | MIT OR Apache-2.0 OR LGPL-2.1-or-later |
| r-efi | 6.0.0 | MIT OR Apache-2.0 OR LGPL-2.1-or-later |
| regex | 1.13.1 | MIT OR Apache-2.0 |
| regex-automata | 0.4.18 | MIT OR Apache-2.0 |
| regex-syntax | 0.8.11 | MIT OR Apache-2.0 |
| roxmltree | 0.21.1 | MIT OR Apache-2.0 |
| rustc-demangle | 0.1.28 | MIT/Apache-2.0 |
| rustc-hash | 2.1.3 | Apache-2.0 OR MIT |
| rustversion | 1.0.23 | MIT OR Apache-2.0 |
| scopeguard | 1.2.0 | MIT OR Apache-2.0 |
| serde | 1.0.229 | MIT OR Apache-2.0 |
| serde_core | 1.0.229 | MIT OR Apache-2.0 |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 |
| serde_json | 1.0.151 | MIT OR Apache-2.0 |
| sha1_smol | 1.0.1 | BSD-3-Clause |
| sha2 | 0.11.0 | MIT OR Apache-2.0 |
| shlex | 2.0.1 | MIT OR Apache-2.0 |
| simd-adler32 | 0.3.10 | MIT |
| simdutf8 | 0.1.5 | MIT OR Apache-2.0 |
| siphasher | 1.0.3 | MIT/Apache-2.0 |
| skrifa | 0.42.1 | MIT OR Apache-2.0 |
| slab | 0.4.12 | MIT |
| slotmap | 1.1.1 | Zlib |
| smallvec | 1.16.1 | MIT OR Apache-2.0 |
| static_assertions | 1.1.0 | MIT OR Apache-2.0 |
| stringprep | 0.1.5 | MIT/Apache-2.0 |
| subsetter | 0.2.6 | MIT OR Apache-2.0 |
| syn | 2.0.119 | MIT OR Apache-2.0 |
| syn | 3.0.5 | MIT OR Apache-2.0 |
| taffy | 0.14.0 | MIT |
| thiserror | 2.0.20 | MIT OR Apache-2.0 |
| thiserror-impl | 2.0.20 | MIT OR Apache-2.0 |
| threadpool | 1.8.1 | MIT/Apache-2.0 |
| tiff | 0.11.3 | MIT |
| tinyvec | 1.13.3 | Zlib OR Apache-2.0 OR MIT |
| tokio | 1.53.1 | MIT |
| ttf-parser | 0.25.1 | MIT OR Apache-2.0 |
| typed-path | 0.12.3 | MIT OR Apache-2.0 |
| typenum | 1.20.1 | MIT OR Apache-2.0 |
| unicode-bidi | 0.3.18 | MIT OR Apache-2.0 |
| unicode-ident | 1.0.24 | (MIT OR Apache-2.0) AND Unicode-3.0 |
| unicode-linebreak | 0.1.5 | Apache-2.0 |
| unicode-normalization | 0.1.25 | MIT OR Apache-2.0 |
| unicode-properties | 0.1.4 | MIT/Apache-2.0 |
| utf8parse | 0.2.2 | Apache-2.0 OR MIT |
| uuid | 1.26.1 | Apache-2.0 OR MIT |
| version_check | 0.9.5 | MIT/Apache-2.0 |
| wasip2 | 1.0.4+wasi-0.2.12 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT |
| wasm-bindgen | 0.2.128 | MIT OR Apache-2.0 |
| wasm-bindgen-futures | 0.4.78 | MIT OR Apache-2.0 |
| wasm-bindgen-macro | 0.2.128 | MIT OR Apache-2.0 |
| wasm-bindgen-macro-support | 0.2.128 | MIT OR Apache-2.0 |
| wasm-bindgen-shared | 0.2.128 | MIT OR Apache-2.0 |
| web-sys | 0.3.105 | MIT OR Apache-2.0 |
| weezl | 0.1.12 | MIT OR Apache-2.0 |
| weezl | 0.2.1 | MIT OR Apache-2.0 |
| whatlang | 0.18.0 | MIT |
| windows-core | 0.62.2 | MIT OR Apache-2.0 |
| windows-implement | 0.60.2 | MIT OR Apache-2.0 |
| windows-interface | 0.59.3 | MIT OR Apache-2.0 |
| windows-link | 0.2.1 | MIT OR Apache-2.0 |
| windows-result | 0.4.1 | MIT OR Apache-2.0 |
| windows-strings | 0.5.1 | MIT OR Apache-2.0 |
| windows-sys | 0.61.2 | MIT OR Apache-2.0 |
| wit-bindgen | 0.57.1 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT |
| write-fonts | 0.48.1 | MIT OR Apache-2.0 |
| zerocopy | 0.8.57 | BSD-2-Clause OR Apache-2.0 OR MIT |
| zerocopy-derive | 0.8.57 | BSD-2-Clause OR Apache-2.0 OR MIT |
| zip | 7.2.0 | MIT |
| zip | 8.6.0 | MIT |
| zlib-rs | 0.6.8 | Zlib |
| zmij | 1.0.23 | MIT |
| zopfli | 0.8.3 | Apache-2.0 |
| zune-core | 0.5.3 | MIT OR Apache-2.0 OR Zlib |
| zune-jpeg | 0.5.15 | MIT OR Apache-2.0 OR Zlib |

(codar_reader itself: MIT, see rust/Cargo.toml.)
