# DJVU Tools

This directory contains scripts for extracting text from DJVU files and optionally converting them to PDF.

## Dependencies

### Core (always required)

- `djvutxt` - Extracts hidden text layers from DJVU files (part of djvulibre)
- `ocrodjvu` - OCRs DJVU files and embeds the text layer in place (uses tesseract internally)

### For PDF output (`-p` flag)

- `ddjvu` - Converts DJVU to PDF (part of djvulibre)
- `ocrmypdf` - Adds OCR text layer to PDF files

### For `djvu_to_txt.sh` only

- `ddjvu` - Renders DJVU pages to TIFF for OCR (part of djvulibre)
- `djvused` - Reads DJVU metadata such as page count (part of djvulibre)
- `tesseract` - OCR engine for page-by-page text extraction

Installation:

```bash
# On Fedora
sudo dnf install djvulibre tesseract tesseract-langpack-rus
pip install ocrodjvu

# On Debian/Ubuntu
sudo apt install djvulibre-bin tesseract-ocr tesseract-ocr-rus
pip install ocrodjvu

# On macOS with Homebrew
brew install djvulibre tesseract tesseract-lang
pip install ocrodjvu
```

## ocr_djvu.sh

The primary tool for processing DJVU files. It checks for an existing text layer in the DJVU; if found, extracts it directly. If not, it runs `ocrodjvu` to OCR and **embed the text layer into the DJVU file itself**, then extracts the text. This means subsequent runs on the same file will find the embedded text and skip OCR.

A `.txt` file is always saved alongside the original DJVU. An OCR'd PDF can optionally be produced with `-p`.

### Usage

```bash
./ocr_djvu.sh [-p] [-f] [file_or_directory]
```

Flags:

- `-p` - Also save an OCR'd PDF to `OUTPUT_DIR`
- `-f` - Force OCR even if the DJVU already has a text layer (replaces it)

### How it works

```
book.djvu
  |
  +-- Has text layer? (djvutxt, checked unless -f)
  |     |
  |     YES --> Extract to book.txt, done
  |     |
  |     NO  --> ocrodjvu --in-place (embeds text layer into DJVU)
  |               |
  |               +--> djvutxt --> book.txt
  |
  +-- -p flag? --> ddjvu --> ocrmypdf --> out/book.pdf
```

### Examples

Extract text from a single file:

```bash
./ocr_djvu.sh book.djvu
```

Process all DJVU files in a directory:

```bash
./ocr_djvu.sh /path/to/books
```

Also produce PDF output:

```bash
./ocr_djvu.sh -p book.djvu
```

Force re-OCR even if text layer exists:

```bash
./ocr_djvu.sh -f book.djvu
```

Set OCR language and output directory:

```bash
OCR_LANG=rus OUTPUT_DIR=pdfs ./ocr_djvu.sh -p /path/to/books
```

### Environment variables

- `OCR_LANG` - Tesseract language(s) for OCR (default: `rus+eng`). Supports multi-language with `+` syntax.
- `OUTPUT_DIR` - Directory for PDF output when `-p` is used (default: `out`)
- `MIN_WORDS` - Minimum word count to consider an existing text layer usable (default: `100`)

## djvu_to_txt.sh

A text extraction tool that converts DJVU files to plain text using a page-by-page approach. If the DJVU has an existing text layer, it extracts it directly. Otherwise it renders each page to TIFF and OCRs with Tesseract one page at a time, keeping disk usage low.

This script does **not** modify the original DJVU file (unlike `ocr_djvu.sh` which embeds the text layer back). It writes a `.txt` file next to each original and includes a progress bar for the page-by-page OCR.

### When to use which

| | `ocr_djvu.sh` | `djvu_to_txt.sh` |
|---|---|---|
| Embeds text layer into DJVU | Yes | No |
| Subsequent runs skip OCR | Yes (text layer persists) | Only if `.txt` already exists |
| Can produce PDF | Yes (`-p`) | No |
| Can force re-OCR | Yes (`-f`) | No |
| Recurse subdirectories | No | Yes (`-r`) |
| OCR method | `ocrodjvu` (in-place) | Page-by-page TIFF + tesseract |
| Requires `ocrodjvu` | Yes | No |

Use `ocr_djvu.sh` when you want the text layer permanently embedded in your DJVU files. Use `djvu_to_txt.sh` when you only need `.txt` output and don't want to modify the originals, or when `ocrodjvu` is not installed.

### Usage

```bash
./djvu_to_txt.sh [-r] [directory]
```

Flags:

- `-r` - Recurse into subdirectories

### Examples

Process all DJVU files in the current directory:

```bash
./djvu_to_txt.sh
```

Process a specific directory recursively:

```bash
./djvu_to_txt.sh -r /path/to/books
```

Set OCR language and temp directory:

```bash
OCR_LANG=eng TMPDIR=/var/tmp ./djvu_to_txt.sh -r /path/to/books
```

### Environment variables

- `OCR_LANG` - Tesseract language(s) for OCR (default: `rus+eng`)
- `TMPDIR` - Directory for temporary files (default: system default). Set to a disk-backed path like `/var/tmp` when `/tmp` is RAM-backed and space is tight.
