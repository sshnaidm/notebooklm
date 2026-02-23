# PDF Tools

This directory contains scripts for working with PDF files.

## Dependencies

Most scripts require:

- `pdftotext` - For extracting text and counting words (poppler-utils)
- `pdfunite` - For combining PDF files (poppler-utils)
- `pdfinfo` - For getting PDF metadata (poppler-utils)
- `qpdf` - For splitting PDF files

Additionally, `ocr_pdf.sh` requires:

- `ocrmypdf` - For adding OCR text layers to image-only PDFs

These can typically be installed via:

```bash
# On Fedora
sudo dnf install poppler-utils qpdf ocrmypdf

# On Debian/Ubuntu
sudo apt install poppler-utils qpdf ocrmypdf

# On macOS with Homebrew
brew install poppler qpdf ocrmypdf
```

## pdf_process.sh

A comprehensive script for processing multiple PDF files, combining them into chunks based on word count and generating a manifest file, splitting large files if needed. By default, it processes all PDF files in the current directory. It prepares PDFs for NotebookLM by splitting large files and combining smaller ones.

### Usage pdf_process.sh

```bash
./pdf_process.sh [output_directory]
```

The script will:

1. Find all PDF files in the current directory
2. Calculate word counts for each file
3. Split large files if needed (split chunks are saved to the output directory)
4. Combine files into chunks based on word count
5. Generate a manifest file listing which PDFs are in each chunk

All output files, including both the split chunks from large PDFs and the combined chunks, are saved to the specified output directory (default: 'out').

Environment variables:

- `MAX_CHUNK_WORDS`: Maximum words per chunk (default: 400000)

## split_pdf.sh

A standalone script for splitting large PDF files into smaller chunks based on word count. By default, it processes all PDF files in the current directory.

### Usage split_pdf.sh

```bash
./split_pdf.sh [pdf_file]
```

Parameters:

- `pdf_file`: (Optional) A specific PDF file to split. If not provided, all PDF files in the current directory will be processed.

Environment variables:

- `MAX_CHUNK_WORDS`: Maximum words per chunk (default: 400000)
- `OUTPUT_DIR`: Directory to save output files (default: 'out')
- `OUTPUT_PREFIX`: Prefix for output files (default: none)

### Examples

Process all PDF files in the current directory:

```bash
./split_pdf.sh
```

Process a specific PDF file:

```bash
./split_pdf.sh large_document.pdf
```

This will create files like:

- `out/large_document-1.pdf`
- `out/large_document-2.pdf`
- etc.

Customize output with environment variables:

```bash
MAX_CHUNK_WORDS=200000 OUTPUT_DIR=my_output OUTPUT_PREFIX=split ./split_pdf.sh
```

This will create files like:

- `my_output/split-document1-1.pdf`
- `my_output/split-document1-2.pdf`
- `my_output/split-document2-1.pdf`
- etc.

## combine_pdf.sh

A script for combining multiple PDF files into chunks based on word count. If the combined word count exceeds the maximum limit, multiple output files will be created.

### Usage combine_pdf.sh

Process all PDF files in the current directory:

```bash
./combine_pdf.sh
```

Environment variables:

- `MAX_WORDS`: Maximum words per combined chunk (default: 400000)
- `OUTDIR`: Directory to save output files (default: 'out')

This will create files like:

- `out/combined_pdf-part1.pdf`
- `out/combined_pdf-part2.pdf` (if needed)
- etc.

## ocr_pdf.sh

Adds a text layer to image-only (scanned) PDFs using `ocrmypdf`. PDFs that already contain sufficient text are skipped automatically. The OCR is done in place — the original PDF file is replaced with the OCR'd version. Includes a progress bar that tracks `ocrmypdf`'s page-by-page progress.

This script is also sourced by `prepare_all.sh` to provide OCR functionality for the document preparation pipeline.

### Usage ocr_pdf.sh

```bash
./ocr_pdf.sh [-r] [-t] [file_or_directory]
```

Flags:

- `-t` - Also save extracted text as a `.txt` file alongside each PDF
- `-r` - Recurse into subdirectories

Parameters:

- `file_or_directory`: (Optional) A single PDF file or a directory to process. If not provided, processes all PDFs in the current directory.

### How it works

1. Extracts text with `pdftotext` and counts words
2. If the PDF already has >= `MIN_WORDS` words, skips OCR
3. Otherwise, runs `ocrmypdf --skip-text` to add a text layer, replacing the original file in place
4. If `-t` is set, extracts the text to a `.txt` file (skips if `.txt` already exists)

### Examples

OCR a single file:

```bash
./ocr_pdf.sh document.pdf
```

OCR all PDFs in a directory and also extract text:

```bash
./ocr_pdf.sh -t /path/to/scanned-books
```

Recurse into subdirectories:

```bash
./ocr_pdf.sh -r -t /path/to/library
```

Set OCR language and word threshold:

```bash
OCR_LANG=deu MIN_WORDS=50 ./ocr_pdf.sh -t document.pdf
```

### Environment variables

- `OCR_LANG` - Tesseract language(s) for OCR (default: `rus+eng`). Supports multi-language with `+` syntax.
- `MIN_WORDS` - Minimum word count to consider a PDF as already having text (default: `100`)
- `TMPDIR` - Directory for temporary files (default: system default)
