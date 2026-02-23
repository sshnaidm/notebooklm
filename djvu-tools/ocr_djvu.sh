#!/bin/bash
#
# DJVU OCR Script (ocr_djvu.sh)
# Extracts text from DJVU files, saving a .txt alongside each original.
# If the DJVU already has a text layer, extracts it directly (no OCR needed).
# Otherwise uses ocrodjvu to OCR and embed the text layer into the DJVU in
# place, then extracts it with djvutxt.
# Can optionally save an OCR'd PDF with -p.
#
# Usage: ocr_djvu.sh [-p] [-f] [file_or_directory]
#   -p             Also save OCR'd PDF output
#   -f             Force OCR even if DJVU has an existing text layer
#   file_or_dir    DJVU file or directory to process (default: current directory)
#
# Environment variables:
#   OCR_LANG       Tesseract language(s) for OCR (default: rus+eng)
#   OUTPUT_DIR     Directory for PDF output when -p is used (default: out)
#   MIN_WORDS      Minimum word count to consider text layer usable (default: 100)
#

# Default settings (can be overridden with environment variables)
OCR_LANG=${OCR_LANG:-rus+eng}
OUTPUT_DIR=${OUTPUT_DIR:-out}
MIN_WORDS=${MIN_WORDS:-100}
SAVE_PDF=0
FORCE_OCR=0
INPUT=""

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 [-p] [-f] [file_or_directory]"
    echo
    echo "Extracts text from DJVU files. Checks for an existing text layer first;"
    echo "if not found, OCRs with ocrodjvu and embeds the text layer into the DJVU."
    echo
    echo "  -p             Also save OCR'd PDF output"
    echo "  -f             Force OCR even if DJVU has an existing text layer"
    echo "  file_or_dir    DJVU file or directory to process (default: current directory)"
    echo
    echo "Environment variables:"
    echo "  OCR_LANG    Tesseract OCR language(s) (default: $OCR_LANG)"
    echo "              Examples: eng, rus, rus+eng, deu"
    echo "  OUTPUT_DIR  Directory for PDF output with -p (default: '$OUTPUT_DIR')"
    echo "  MIN_WORDS   Minimum words to accept text layer (default: $MIN_WORDS)"
    echo
    echo "Examples:"
    echo "  $0 book.djvu"
    echo "  $0 -p book.djvu"
    echo "  $0 -f -p book.djvu"
    echo "  OCR_LANG=rus+eng $0"
    echo "  OCR_LANG=rus OUTPUT_DIR=pdfs $0 -p"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -p|--pdf)
            SAVE_PDF=1
            shift
            ;;
        -f|--force)
            FORCE_OCR=1
            shift
            ;;
        -*)
            echo "Error: Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            INPUT="$1"
            shift
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------

missing=()
for cmd in ocrodjvu djvutxt; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
if [ "$SAVE_PDF" = "1" ]; then
    for cmd in ddjvu ocrmypdf; do
        command -v "$cmd" >/dev/null || missing+=("$cmd")
    done
fi
if [ ${#missing[@]} -gt 0 ]; then
    echo "Error: missing required tools: ${missing[*]}"
    echo "Install ocrodjvu (pip install ocrodjvu) and djvulibre (provides djvutxt)."
    [ "$SAVE_PDF" = "1" ] && echo "For -p flag, also install ddjvu (djvulibre) and ocrmypdf."
    exit 1
fi

# ---------------------------------------------------------------------------
# Core conversion
# ---------------------------------------------------------------------------

# Process a single DJVU file: embed text layer, extract text, optionally save PDF.
ocr_djvu_file() {
    local file="$1"
    local dir
    dir=$(dirname "$file")
    local base
    base=$(basename "$file")
    base="${base%.*}"
    local txt_out="${dir}/${base}.txt"
    local has_text=0

    # Step 1: Check for existing text layer (unless forced)
    if [ "$FORCE_OCR" != "1" ]; then
        echo "  Checking for existing text layer..."
        local djvu_text
        djvu_text=$(djvutxt "$file" 2>/dev/null)
        local word_count
        word_count=$(echo "$djvu_text" | wc -w)

        if [ "$word_count" -ge "$MIN_WORDS" ]; then
            echo "  Found existing text layer ($word_count words). Skipping OCR."
            has_text=1

            # Save text from the existing layer
            if [ -f "$txt_out" ]; then
                echo "  Skipping text extraction (${txt_out} already exists)."
            else
                echo "$djvu_text" > "$txt_out"
                echo "  Saved text: $txt_out"
            fi
        else
            echo "  No usable text layer ($word_count words)."
        fi
    fi

    # Step 2: OCR and embed text layer into DJVU (if no usable text layer)
    if [ "$has_text" = "0" ]; then
        local ocrodjvu_flags=(--in-place -l "$OCR_LANG" -e tesseract)
        if [ "$FORCE_OCR" = "1" ]; then
            ocrodjvu_flags+=(--clear-text)
        fi

        echo "  Running OCR with ocrodjvu (language: $OCR_LANG)..."
        if ! ocrodjvu "${ocrodjvu_flags[@]}" "$file"; then
            echo "  ERROR: ocrodjvu failed for $file"
            return 1
        fi
        echo "  Text layer embedded in DJVU."

        # Extract text from the now-embedded layer
        if [ -f "$txt_out" ]; then
            echo "  Skipping text extraction (${txt_out} already exists)."
        else
            djvutxt "$file" > "$txt_out" 2>/dev/null
            echo "  Saved text: $txt_out"
        fi
    fi

    # Step 3: PDF output (only if -p requested)
    if [ "$SAVE_PDF" = "1" ]; then
        local tmpdir
        tmpdir=$(mktemp -d)
        # shellcheck disable=SC2064
        trap "rm -rf '$tmpdir'" RETURN

        mkdir -p "$OUTPUT_DIR"
        local pdf_out="${OUTPUT_DIR}/${base}.pdf"

        echo "  Converting DJVU to PDF..."
        local raw_pdf="${tmpdir}/${base}_raw.pdf"
        if ! ddjvu -format=pdf -skip "$file" "$raw_pdf" 2>/dev/null; then
            echo "  ERROR: ddjvu PDF conversion failed for $file"
            return 1
        fi

        echo "  Running OCR on PDF (language: $OCR_LANG)..."
        if ocrmypdf --skip-text -l "$OCR_LANG" --output-type pdf "$raw_pdf" "$pdf_out" 2>/dev/null; then
            echo "  Saved PDF: $pdf_out"
        else
            echo "  WARNING: PDF OCR failed, saving unconverted PDF"
            cp "$raw_pdf" "$pdf_out"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [ -n "$INPUT" ]; then
    if [ -f "$INPUT" ]; then
        # Single file mode
        echo "=== Processing: $INPUT ==="
        ocr_djvu_file "$INPUT"
        exit $?
    elif [ -d "$INPUT" ]; then
        INPUT_DIR="$INPUT"
    else
        echo "Error: '$INPUT' is not a file or directory."
        exit 1
    fi
else
    INPUT_DIR="."
fi

# Directory mode
mapfile -t djvu_files < <(find "$INPUT_DIR" -maxdepth 1 -type f \( -iname "*.djvu" -o -iname "*.djv" \) | sort)

if [ ${#djvu_files[@]} -eq 0 ]; then
    echo "No DJVU files found in '$INPUT_DIR'."
    exit 1
fi

echo "Found ${#djvu_files[@]} DJVU file(s):"
for f in "${djvu_files[@]}"; do
    echo "  $f"
done
echo

failed=()
for file in "${djvu_files[@]}"; do
    echo "=== Processing: $file ==="
    if ! ocr_djvu_file "$file"; then
        failed+=("$file")
    fi
    echo
done

echo "All done."
if [ ${#failed[@]} -gt 0 ]; then
    echo "Failed files:"
    for f in "${failed[@]}"; do
        echo "  $f"
    done
    exit 1
fi
