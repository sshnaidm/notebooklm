# NotebookLM Tools

Scripts and tools for preparing documents of various formats for [NotebookLM](https://notebooklm.google.com). Handles PDF, DJVU, EPUB, FB2, MOBI, DOC/DOCX, and many other formats -- converting, OCR-ing, and splitting them into word-count-limited chunks suitable for upload.

## prepare_all.sh

The main entry point. Converts and splits documents of various formats into word-count-limited chunks ready for NotebookLM.

### Supported formats

| Format | Processing |
|---|---|
| PDF | OCR if no text layer, then split into chunks |
| DJVU, DJV | Extract text layer or page-by-page OCR, then split as text |
| EPUB, FB2, MOBI, AZW, AZW3, DOC, DOCX, RTF, ODT, HTML, HTM, LIT, PDB, LRF | Convert to PDF via `ebook-convert`, then split |
| TXT | Split directly as text (no PDF conversion) |

### Usage

```bash
./prepare_all.sh [input_dir]
```

`input_dir` defaults to the current directory. The script finds all supported files, converts/OCRs as needed, and splits them into chunks in the output directory.

### Examples

```bash
# Process all documents in the current directory
./prepare_all.sh

# Process a specific directory
./prepare_all.sh /path/to/books

# Customize chunk size and output
MAX_CHUNK_WORDS=300000 OUTPUT_DIR=chunks ./prepare_all.sh /path/to/books

# Set OCR language and keep intermediate PDFs
OCR_LANG=rus+eng KEEP_PDF=1 ./prepare_all.sh /path/to/books

# Skip OCR entirely
SKIP_OCR=1 ./prepare_all.sh /path/to/books
```

### Environment variables

- `MAX_CHUNK_WORDS` - Maximum words per output chunk (default: `400000`)
- `OUTPUT_DIR` - Directory for output files (default: `out`)
- `OUTPUT_PREFIX` - Prefix added to output filenames (default: none)
- `KEEP_PDF` - Set to `1` to keep intermediate PDFs from format conversions (default: `0`)
- `OCR_LANG` - Tesseract language(s) for OCR (default: `rus+eng`). Supports `+` syntax for multiple languages.
- `SKIP_OCR` - Set to `1` to disable OCR for all formats (default: `0`)

### Dependencies

`prepare_all.sh` relies on scripts from the subdirectories below, plus:

- `pdftotext`, `pdfinfo`, `qpdf` - PDF manipulation (poppler-utils, qpdf)
- `ocrmypdf` - PDF OCR
- `ebook-convert` - Format conversion (install [Calibre](https://calibre-ebook.com/))

For DJVU support: `ddjvu`, `djvutxt`, `djvused`, `tesseract` (djvulibre, tesseract-ocr).

## Tool directories

### [pdf-tools/](pdf-tools/README.md)

Scripts for working with PDF files -- splitting, combining, OCR-ing.

- `ocr_pdf.sh` - Adds OCR text layer to image-only PDFs in place, with progress bar
- `split_pdf.sh` - Splits large PDFs into word-count-limited chunks
- `combine_pdf.sh` - Combines multiple PDFs into chunks by word count
- `pdf_process.sh` - All-in-one: split, combine, and generate a manifest

### [djvu-tools/](djvu-tools/README.md)

Scripts for extracting text from DJVU files and optionally converting to PDF.

- `ocr_djvu.sh` - OCRs DJVU files with `ocrodjvu`, embeds text layer in place, extracts `.txt`
- `djvu_to_txt.sh` - Extracts text from DJVU via page-by-page tesseract (does not modify originals)

### [text-tools/](text-tools/README.md)

Scripts for working with text and ebook formats.

- `split_text.sh` - Splits large text files into word-count-limited chunks
- `split_epub.py` - Splits EPUB files into smaller parts
- `epub-to-text.py` / `epub-to-text2.py` - Converts EPUB to plain text

### [automation/](automation/README.md)

Browser automation for NotebookLM.

- `add_links_script.py` - Automates adding links as sources to a NotebookLM notebook via Playwright

## Installation

### System packages

```bash
# Fedora
sudo dnf install poppler-utils qpdf ocrmypdf djvulibre tesseract tesseract-langpack-rus calibre

# Debian/Ubuntu
sudo apt install poppler-utils qpdf ocrmypdf djvulibre-bin tesseract-ocr tesseract-ocr-rus calibre

# macOS
brew install poppler qpdf ocrmypdf djvulibre tesseract calibre
```

### Python packages

```bash
pip install -r text-tools/requirements.txt
```

For browser automation, also run:

```bash
playwright install chromium
```
