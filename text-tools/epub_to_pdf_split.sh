#!/bin/bash
#
# EPUB to PDF Converter and Splitter (epub_to_pdf_split.sh)
# Converts all EPUB files in a directory to PDF, then splits each PDF
# using split_pdf.sh based on word count.
#

# Resolve the directory this script lives in so we can find split_pdf.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPLIT_PDF="${SCRIPT_DIR}/../pdf-tools/split_pdf.sh"

# Default settings (can be overridden with environment variables)
MAX_CHUNK_WORDS=${MAX_CHUNK_WORDS:-400000}
OUTPUT_DIR=${OUTPUT_DIR:-out}
OUTPUT_PREFIX=${OUTPUT_PREFIX:-""}
KEEP_PDF=${KEEP_PDF:-0}      # Set to 1 to keep intermediate PDFs
INPUT_DIR="${1:-.}"          # First argument is input dir, default to current dir

TMPDIR_PDF=$(mktemp -d)

# Cleanup function
cleanup() {
    rm -rf "$TMPDIR_PDF"
}
trap cleanup EXIT

# Dependencies check
for cmd in ebook-convert pdfinfo pdftotext qpdf; do
    command -v "$cmd" >/dev/null || { echo "$cmd not found. Install it."; exit 1; }
done

if [ ! -f "$SPLIT_PDF" ]; then
    echo "Error: split_pdf.sh not found at $SPLIT_PDF"
    exit 1
fi

if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' not found."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Convert a single EPUB to PDF and split it
process_epub() {
    local epub_file="$1"
    local base
    base=$(basename "$epub_file" .epub)

    echo "=== Processing: $epub_file ==="

    # Convert EPUB -> PDF into temp dir
    local pdf_file="$TMPDIR_PDF/${base}.pdf"
    echo "  Converting to PDF..."
    if ! ebook-convert "$epub_file" "$pdf_file" 2>/dev/null; then
        echo "  ERROR: ebook-convert failed for $epub_file"
        return 1
    fi

    if [ ! -f "$pdf_file" ]; then
        echo "  ERROR: PDF not created for $epub_file"
        return 1
    fi

    echo "  Converted: $pdf_file"

    # Optionally keep a copy of the intermediate PDF alongside the chunks
    if [ "$KEEP_PDF" = "1" ]; then
        cp "$pdf_file" "${OUTPUT_DIR}/${base}.pdf"
        echo "  Kept PDF: ${OUTPUT_DIR}/${base}.pdf"
    fi

    # Split the PDF using split_pdf.sh
    echo "  Splitting PDF..."
    MAX_CHUNK_WORDS="$MAX_CHUNK_WORDS" \
    OUTPUT_DIR="$OUTPUT_DIR" \
    OUTPUT_PREFIX="$OUTPUT_PREFIX" \
    bash "$SPLIT_PDF" "$pdf_file"

    echo "  Done: $base"
    echo
}

# Display usage information
usage() {
    echo "Usage: $0 [input_dir]"
    echo
    echo "Converts all EPUB files in input_dir to PDF and splits them."
    echo "input_dir defaults to the current directory."
    echo
    echo "Environment variables:"
    echo "  MAX_CHUNK_WORDS: Maximum words per chunk (default: $MAX_CHUNK_WORDS)"
    echo "  OUTPUT_DIR:      Directory to save split PDFs (default: '$OUTPUT_DIR')"
    echo "  OUTPUT_PREFIX:   Prefix for output files (default: '$OUTPUT_PREFIX')"
    echo "  KEEP_PDF:        Set to 1 to keep intermediate PDFs (default: $KEEP_PDF)"
    echo
    echo "Examples:"
    echo "  $0 /path/to/epubs"
    echo
    echo "  MAX_CHUNK_WORDS=300000 OUTPUT_DIR=/tmp/pdfs $0 /path/to/epubs"
    echo
    echo "  # Keep intermediate PDFs and apply a prefix"
    echo "  KEEP_PDF=1 OUTPUT_PREFIX=diag OUTPUT_DIR=out $0 /path/to/epubs"
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    usage
    exit 0
fi

echo "Input directory:  $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Max chunk words:  $MAX_CHUNK_WORDS"
echo

# Collect EPUB files
mapfile -t epub_files < <(find "$INPUT_DIR" -maxdepth 1 -type f -iname "*.epub" | sort)

if [ ${#epub_files[@]} -eq 0 ]; then
    echo "No EPUB files found in '$INPUT_DIR'."
    exit 1
fi

echo "Found ${#epub_files[@]} EPUB file(s):"
for f in "${epub_files[@]}"; do
    echo "  $f"
done
echo

failed=()
for epub_file in "${epub_files[@]}"; do
    if ! process_epub "$epub_file"; then
        failed+=("$epub_file")
    fi
done

echo "All done."
if [ ${#failed[@]} -gt 0 ]; then
    echo "Failed files:"
    for f in "${failed[@]}"; do
        echo "  $f"
    done
    exit 1
fi
