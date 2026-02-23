#!/bin/bash
#
# prepare_all.sh
# Converts and splits documents of various formats into word-count-limited PDF chunks.
#
# Supported formats:
#   PDF              - split directly (OCR if no text layer detected)
#   DJVU / DJV       - extract text layer or page-by-page OCR, then split as text
#   EPUB, FB2, MOBI, AZW, AZW3, DOC, DOCX, RTF, ODT,
#   HTML, HTM, LIT, PDB, LRF      - convert via ebook-convert, then split
#   TXT                            - split directly as text (no PDF conversion)
#
# Usage: prepare_all.sh [input_dir]
#   input_dir defaults to the current directory.
#
# Environment variables:
#   MAX_CHUNK_WORDS  Maximum words per output chunk (default: 400000)
#   OUTPUT_DIR       Directory for split PDFs (default: out)
#   OUTPUT_PREFIX    Prefix added to output filenames (default: "")
#   KEEP_PDF         Set to 1 to keep intermediate PDFs (default: 0)
#   OCR_LANG         Tesseract language(s) for OCR (default: eng)
#                    Examples: eng, rus, rus+eng
#   SKIP_OCR         Set to 1 to disable OCR for all formats (default: 0)
#

# Resolve the directory this script lives in
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPLIT_PDF="${SCRIPT_DIR}/pdf-tools/split_pdf.sh"
SPLIT_TEXT="${SCRIPT_DIR}/text-tools/split_text.sh"
OCR_PDF="${SCRIPT_DIR}/pdf-tools/ocr_pdf.sh"

# Default settings
MAX_CHUNK_WORDS=${MAX_CHUNK_WORDS:-400000}
OUTPUT_DIR=${OUTPUT_DIR:-out}
OUTPUT_PREFIX=${OUTPUT_PREFIX:-""}
KEEP_PDF=${KEEP_PDF:-0}
OCR_LANG=${OCR_LANG:-rus+eng}
SKIP_OCR=${SKIP_OCR:-0}
INPUT_DIR="${1:-.}"

TMPDIR_WORK=$(mktemp -d)

cleanup() {
    rm -rf "$TMPDIR_WORK"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Progress bar
# ---------------------------------------------------------------------------

# Print an in-place progress bar.  Usage: show_progress CURRENT TOTAL
show_progress() {
    local current=$1 total=$2 width=40
    local pct=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    local bar_f="" bar_e=""
    [ "$filled" -gt 0 ] && bar_f=$(printf '%*s' "$filled" '' | tr ' ' '#')
    [ "$empty"  -gt 0 ] && bar_e=$(printf '%*s' "$empty"  '' | tr ' ' '.')
    printf "\r  OCR: [%s%s] %3d%% (%d/%d)" "$bar_f" "$bar_e" "$pct" "$current" "$total"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Check required scripts
check_scripts() {
    for script in "$SPLIT_PDF" "$SPLIT_TEXT" "$OCR_PDF"; do
        if [ ! -f "$script" ]; then
            echo "Error: required script not found: $script"
            exit 1
        fi
    done
}

# Check required tools
check_deps() {
    local missing=()
    for cmd in pdftotext qpdf pdfinfo; do
        command -v "$cmd" >/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: missing required tools: ${missing[*]}"
        echo "Install them (e.g. poppler-utils, qpdf) and try again."
        exit 1
    fi
}

# Source ocr_pdf.sh for its ocr_single_pdf() function
# shellcheck source=pdf-tools/ocr_pdf.sh
source "$OCR_PDF"

# Call split_pdf.sh to split a PDF into word-count-limited chunks
split_to_chunks() {
    local pdf_file="$1"
    MAX_CHUNK_WORDS="$MAX_CHUNK_WORDS" \
    OUTPUT_DIR="$OUTPUT_DIR" \
    OUTPUT_PREFIX="$OUTPUT_PREFIX" \
    bash "$SPLIT_PDF" "$pdf_file"
}

# ---------------------------------------------------------------------------
# Per-format processors
# ---------------------------------------------------------------------------

# PDF: optionally OCR if no text layer (in place), then split
process_pdf() {
    local file="$1"
    local base="$2"

    if [ "$SKIP_OCR" != "1" ]; then
        # ocr_single_pdf OCRs in place if needed; on failure we still split
        ocr_single_pdf "$file" || true
    fi

    split_to_chunks "$file"
}

# DJVU: extract text layer or page-by-page OCR, then split as text.
# If KEEP_PDF is set, also produce a raw PDF via ddjvu.
process_djvu() {
    local file="$1"
    local base="$2"

    if ! command -v ddjvu >/dev/null; then
        echo "  ERROR: ddjvu not found. Install djvulibre to handle DJVU files."
        return 1
    fi

    # Produce a kept PDF if requested (independent of text extraction)
    if [ "$KEEP_PDF" = "1" ]; then
        echo "  Converting DJVU to PDF (KEEP_PDF)..."
        local kept_pdf="${TMPDIR_WORK}/${base}_raw.pdf"
        if ddjvu -format=pdf -skip "$file" "$kept_pdf" 2>/dev/null; then
            cp "$kept_pdf" "${OUTPUT_DIR}/${base}.pdf"
            echo "  Kept intermediate PDF: ${OUTPUT_DIR}/${base}.pdf"
            rm -f "$kept_pdf"
        else
            echo "  WARNING: ddjvu PDF conversion failed, skipping KEEP_PDF."
        fi
    fi

    # Step 1: Try extracting the existing hidden text layer
    if command -v djvutxt >/dev/null; then
        echo "  Checking for existing text layer..."
        local djvu_text
        djvu_text=$(djvutxt "$file" 2>/dev/null)
        local word_count
        word_count=$(echo "$djvu_text" | wc -w)

        if [ "$word_count" -gt 100 ]; then
            echo "  Found existing text layer ($word_count words). Skipping OCR."
            local txt_out="${TMPDIR_WORK}/${base}.txt"
            echo "$djvu_text" > "$txt_out"
            echo "  Splitting text..."
            local abs_txt
            abs_txt=$(realpath "$txt_out")
            (
                cd "$OUTPUT_DIR"
                MAX_WORDS="$MAX_CHUNK_WORDS" bash "$SPLIT_TEXT" "$abs_txt"
            )
            return $?
        fi
        echo "  No usable text layer ($word_count words)."
    fi

    # Step 2: Page-by-page TIFF → Tesseract OCR
    if [ "$SKIP_OCR" = "1" ]; then
        echo "  OCR skipped (SKIP_OCR=1). No text to extract."
        return 1
    fi

    for cmd in djvused tesseract; do
        if ! command -v "$cmd" >/dev/null; then
            echo "  ERROR: $cmd not found. Install djvulibre / tesseract-ocr."
            return 1
        fi
    done

    local num_pages
    num_pages=$(djvused "$file" -e 'n' 2>/dev/null)
    if [ -z "$num_pages" ] || [ "$num_pages" -le 0 ]; then
        echo "  ERROR: Could not determine page count."
        return 1
    fi

    echo "  Running page-by-page OCR ($num_pages pages, language: $OCR_LANG)..."

    local txt_out="${TMPDIR_WORK}/${base}.txt"
    > "$txt_out"

    local i errors=()
    for (( i = 1; i <= num_pages; i++ )); do
        show_progress "$i" "$num_pages"

        local page_tif="${TMPDIR_WORK}/page.tif"
        local page_txt="${TMPDIR_WORK}/page"

        if ! ddjvu -format=tiff -page="$i" "$file" "$page_tif" 2>/dev/null; then
            errors+=("page $i: ddjvu failed")
            rm -f "$page_tif"
            continue
        fi

        if ! tesseract "$page_tif" "$page_txt" -l "$OCR_LANG" 2>/dev/null; then
            errors+=("page $i: tesseract failed")
            rm -f "$page_tif" "${page_txt}.txt"
            continue
        fi

        cat "${page_txt}.txt" >> "$txt_out"
        echo "" >> "$txt_out"
        rm -f "$page_tif" "${page_txt}.txt"
    done
    echo ""

    for err in "${errors[@]}"; do
        echo "  WARNING: $err"
    done

    echo "  Splitting text..."
    local abs_txt
    abs_txt=$(realpath "$txt_out")
    (
        cd "$OUTPUT_DIR"
        MAX_WORDS="$MAX_CHUNK_WORDS" bash "$SPLIT_TEXT" "$abs_txt"
    )
}

# EPUB, FB2, MOBI, DOC, etc.: convert to PDF via ebook-convert, then split
process_ebook() {
    local file="$1"
    local base="$2"
    local ext="$3"

    if ! command -v ebook-convert >/dev/null; then
        echo "  ERROR: ebook-convert not found. Install Calibre to handle .$ext files."
        return 1
    fi

    echo "  Converting .$ext to PDF via ebook-convert..."
    local pdf_out="${TMPDIR_WORK}/${base}.pdf"
    if ! ebook-convert "$file" "$pdf_out" 2>/dev/null; then
        echo "  ERROR: ebook-convert failed for $file"
        return 1
    fi

    if [ ! -f "$pdf_out" ]; then
        echo "  ERROR: PDF not created for $file"
        return 1
    fi

    if [ "$KEEP_PDF" = "1" ]; then
        cp "$pdf_out" "${OUTPUT_DIR}/${base}.pdf"
        echo "  Kept intermediate PDF: ${OUTPUT_DIR}/${base}.pdf"
    fi

    split_to_chunks "$pdf_out"
}

# TXT: split directly as text chunks into OUTPUT_DIR (no PDF conversion)
# split_text.sh writes output relative to CWD, so we cd into OUTPUT_DIR first.
process_txt() {
    local file="$1"
    local abs_file
    abs_file=$(realpath "$file")

    echo "  Splitting text file..."
    (
        cd "$OUTPUT_DIR"
        MAX_WORDS="$MAX_CHUNK_WORDS" bash "$SPLIT_TEXT" "$abs_file"
    )
}

# Route a file to the correct processor based on its extension
process_file() {
    local file="$1"
    local filename
    filename=$(basename "$file")
    local ext="${filename##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    local base="${filename%.*}"

    echo "=== Processing: $file ==="

    case "$ext" in
        pdf)
            process_pdf "$file" "$base"
            ;;
        djvu|djv)
            process_djvu "$file" "$base"
            ;;
        txt)
            process_txt "$file"
            ;;
        epub|fb2|mobi|azw|azw3|doc|docx|rtf|odt|html|htm|lit|pdb|lrf)
            process_ebook "$file" "$base" "$ext"
            ;;
        *)
            echo "  WARNING: Unsupported format '.$ext', skipping."
            return 1
            ;;
    esac

    local rc=$?
    echo
    return $rc
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 [input_dir]"
    echo
    echo "Converts and splits documents into word-count-limited chunks."
    echo "Supports: PDF, EPUB, FB2, MOBI, AZW, AZW3, DOC, DOCX, RTF,"
    echo "          ODT, HTML, HTM, LIT, PDB, LRF  (-> split PDF chunks)"
    echo "          DJVU, TXT                       (-> split text chunks)"
    echo
    echo "input_dir defaults to the current directory."
    echo
    echo "Environment variables:"
    echo "  MAX_CHUNK_WORDS  Maximum words per chunk        (default: $MAX_CHUNK_WORDS)"
    echo "  OUTPUT_DIR       Directory for output files     (default: '$OUTPUT_DIR')"
    echo "  OUTPUT_PREFIX    Prefix for output filenames    (default: '$OUTPUT_PREFIX')"
    echo "  KEEP_PDF         Keep intermediate PDFs (0/1)   (default: $KEEP_PDF)"
    echo "  OCR_LANG         Tesseract OCR language(s)      (default: $OCR_LANG)"
    echo "  SKIP_OCR         Skip OCR entirely (0/1)        (default: $SKIP_OCR)"
    echo
    echo "Examples:"
    echo "  $0"
    echo "  $0 /path/to/books"
    echo "  MAX_CHUNK_WORDS=300000 OUTPUT_DIR=chunks $0 /path/to/books"
    echo "  OCR_LANG=rus+eng KEEP_PDF=1 $0 /path/to/books"
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    usage
    exit 0
fi

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

check_scripts
check_deps

if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' not found."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Input directory:  $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Max chunk words:  $MAX_CHUNK_WORDS"
echo "OCR language:     $OCR_LANG"
echo "Keep PDF:         $KEEP_PDF"
echo "Skip OCR:         $SKIP_OCR"
echo

# Collect all supported files in input_dir (case-insensitive)
mapfile -t all_files < <(
    find "$INPUT_DIR" -maxdepth 1 -type f \
    | grep -iE '\.(pdf|djvu?|epub|fb2|mobi|azw3?|doc|docx|rtf|odt|html?|txt|lit|pdb|lrf)$' \
    | sort
)

if [ ${#all_files[@]} -eq 0 ]; then
    echo "No supported files found in '$INPUT_DIR'."
    exit 1
fi

echo "Found ${#all_files[@]} file(s):"
for f in "${all_files[@]}"; do
    echo "  $f"
done
echo

failed=()
for file in "${all_files[@]}"; do
    if ! process_file "$file"; then
        failed+=("$file")
    fi
done

echo "All done."
if [ ${#failed[@]} -gt 0 ]; then
    echo
    echo "Failed files:"
    for f in "${failed[@]}"; do
        echo "  $f"
    done
    exit 1
fi
