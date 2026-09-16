# Codar Phase 1 spike fixtures

## Committed (small, reproducible)

Hand-made in `src/` + assembled scripts (see Phase 1 report):

- `min.epub` — minimal EPUB 2 (2 chapters, known searchable phrase
  `CodarSpikePhrase`, full Turkish glyph set).
- `spike.pdf` — hand-built 2-page PDF (valid stream objects).
- `spike.cbz` — 3 PNG pages (`page1/2/10` for natural-sort proof) plus
  `__MACOSX/`, `.DS_Store`, `notes.txt` decoys.
- `spike_tr.txt` — UTF-8 Turkish fixture.
- `spike.fb2` — minimal FictionBook 2.
- `hostile_script.epub` / `hostile_badxml.epub` / `hostile_traversal.epub` —
  security fixtures (script content, malformed XML, `../` entry names).
- `big.epub` — ~570 KB single-chapter stress file.
- `alice.epub` / `alice.mobi` — Project Gutenberg #11 (public domain):
  `https://www.gutenberg.org/ebooks/11.epub.noimages`,
  `https://www.gutenberg.org/ebooks/11.kindle.noimages`.

## Git-ignored (`vendor/`, large binaries with documented provenance)

Re-fetch with:

```powershell
$g = "https://www.gutenberg.org"
curl.exe -sL "$g/ebooks/1342.epub.images" -o spike/fixtures/vendor/pride.epub
git clone --depth 1 --filter=blob:none --sparse https://github.com/SV-stark/ebook-rs.git /tmp/ebook-rs-ref
git -C /tmp/ebook-rs-ref sparse-checkout set samples
cp "/tmp/ebook-rs-ref/samples/Alice in Wonderland - Lewis Carroll.azw3" spike/fixtures/vendor/alice.azw3
cp "/tmp/ebook-rs-ref/samples/Alice in Wonderland - Lewis Carroll.pdf"  spike/fixtures/vendor/alice_vendor.pdf
cp "/tmp/ebook-rs-ref/samples/Alice in Wonderland - Lewis Carroll.lit"  spike/fixtures/vendor/alice.lit
cp "/tmp/ebook-rs-ref/samples/Jumbo Comics 099.cbz" spike/fixtures/vendor/jumbo099.cbz
cp "/tmp/ebook-rs-ref/samples/Jumbo Comics 082.cbr" spike/fixtures/vendor/jumbo082.cbr
```

Tests using absent vendor files SKIP gracefully (never fail a fresh clone).
