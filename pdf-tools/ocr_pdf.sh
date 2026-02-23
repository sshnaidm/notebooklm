#!/bin/bash
#
# ocr_pdf.sh
# Adds a text layer to image-only PDFs using ocrmypdf.
# Can process a single file or all PDF files in a directory.
#
# Usage: ocr_pdf.sh [-r] [-t] [file_or_directory]
#   -t             Also save extracted text as .txt alongside each PDF
#   -r             Recurse into subdirectories
#   file_or_dir    PDF file or directory to process (default: current directory)
#
# Environment variables:
#   OCR_LANG       Tesseract language(s) for OCR (default: rus+eng)
#                  Examples: eng, rus, rus+eng
#   MIN_WORDS      Minimum word count to consider text usable (default: 100)
#   TMPDIR         Temp directory (default: system default)
#

OCR_LANG=${OCR_LANG:-rus+eng}
MIN_WORDS=${MIN_WORDS:-100}

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------

check_ocr_deps() {
    local missing=()
    for cmd in ocrmypdf pdftotext; do
        command -v "$cmd" >/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: missing required tools: ${missing[*]}"
        echo "Install ocrmypdf and poppler-utils (provides pdftotext)."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Progress bar
# ---------------------------------------------------------------------------

# Print an in-place progress bar.  Usage: show_progress CURRENT TOTAL
if ! declare -f show_progress >/dev/null 2>&1; then
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
fi

# ---------------------------------------------------------------------------
# Core OCR
# ---------------------------------------------------------------------------

# OCR a single PDF file, replacing it in place if needed.
# If SAVE_TEXT is set, also extract text to a .txt file alongside.
ocr_single_pdf() {
    local file="$1"
    local dir
    dir=$(dirname "$file")
    local base
    base=$(basename "$file")
    base="${base%.*}"

    # Step 1: Check for existing text
    local word_count
    word_count=$(pdftotext "$file" - 2>/dev/null | wc -w)

    if [ "$word_count" -ge "$MIN_WORDS" ]; then
        echo "  Already has text ($word_count words), skipping OCR."
    else
        # Get total page count for progress tracking
        local total_pages=0
        if command -v pdfinfo >/dev/null; then
            total_pages=$(pdfinfo "$file" 2>/dev/null | awk '/^Pages:/{print $2}')
            total_pages=${total_pages:-0}
        fi

        echo "  No usable text ($word_count words). Running OCR (language: $OCR_LANG)..."
        if [ "$total_pages" -gt 0 ]; then
            echo "  Pages: $total_pages"
        fi

        local tmpfile
        tmpfile=$(mktemp)
        # shellcheck disable=SC2064
        trap "rm -f '$tmpfile'" RETURN

        local ocr_rc
        if [ "$total_pages" -gt 0 ]; then
            # Create a timestamp marker to identify our ocrmypdf working dir
            local marker
            marker=$(mktemp)

            ocrmypdf --skip-text -l "$OCR_LANG" --output-type pdf "$file" "$tmpfile" 2>/dev/null &
            local ocr_pid=$!

            # Wait for ocrmypdf to create its temp dir, then find it
            sleep 2
            local work_dir
            work_dir=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'ocrmypdf.io.*' -newer "$marker" -type d 2>/dev/null | head -1)
            rm -f "$marker"

            if [ -n "$work_dir" ] && [ -d "$work_dir" ]; then
                # Monitor progress while ocrmypdf runs
                while kill -0 "$ocr_pid" 2>/dev/null; do
                    local done_pages
                    done_pages=$(find "$work_dir" -name '*_ocr_hocr.hocr' 2>/dev/null | wc -l)
                    if [ "$done_pages" -gt "$total_pages" ]; then
                        done_pages=$total_pages
                    fi
                    show_progress "$done_pages" "$total_pages"
                    sleep 2
                done
                show_progress "$total_pages" "$total_pages"
                echo ""
            fi

            wait "$ocr_pid"
            ocr_rc=$?
        else
            # No page count available, run without progress bar
            ocrmypdf --skip-text -l "$OCR_LANG" --output-type pdf "$file" "$tmpfile" 2>/dev/null
            ocr_rc=$?
        fi

        if [ "$ocr_rc" -eq 0 ]; then
            mv "$tmpfile" "$file"
            echo "  OCR complete."
        else
            rm -f "$tmpfile"
            echo "  ERROR: OCR failed for $file"
            return 1
        fi
    fi

    # Step 2: Optionally save text
    if [ "$SAVE_TEXT" = "1" ]; then
        local txt_out="${dir}/${base}.txt"
        if [ -f "$txt_out" ]; then
            echo "  Skipping text extraction (${txt_out} already exists)."
        else
            pdftotext "$file" "$txt_out" 2>/dev/null
            echo "  Saved: $txt_out"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Main (only when executed directly, not when sourced)
# ---------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

RECURSIVE=0
SAVE_TEXT=0
INPUT=""

usage() {
    echo "Usage: $0 [-r] [-t] [file_or_directory]"
    echo
    echo "Adds a text layer to image-only PDFs using ocrmypdf."
    echo "PDFs that already contain sufficient text are skipped."
    echo
    echo "  -t             Also save extracted text as .txt alongside each PDF"
    echo "  -r             Recurse into subdirectories"
    echo "  file_or_dir    PDF file or directory to process (default: current directory)"
    echo
    echo "Environment variables:"
    echo "  OCR_LANG    Tesseract language(s) for OCR (default: $OCR_LANG)"
    echo "              Examples: eng, rus, rus+eng"
    echo "  MIN_WORDS   Minimum word count to consider text usable (default: $MIN_WORDS)"
    echo "  TMPDIR      Temporary directory (default: system default)"
    echo
    echo "Examples:"
    echo "  $0 document.pdf"
    echo "  $0 -t document.pdf"
    echo "  $0 -r /path/to/books"
    echo "  $0 -r -t /path/to/books"
    echo "  OCR_LANG=rus+eng $0 -r"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -r|--recursive)
            RECURSIVE=1
            shift
            ;;
        -t|--text)
            SAVE_TEXT=1
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

check_ocr_deps

# Determine what to process
if [ -n "$INPUT" ]; then
    if [ -f "$INPUT" ]; then
        # Single file mode
        echo "=== Processing: $INPUT ==="
        ocr_single_pdf "$INPUT"
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
if [ "$RECURSIVE" = "1" ]; then
    depth_flag=""
else
    depth_flag="-maxdepth 1"
fi

# shellcheck disable=SC2086
mapfile -t pdf_files < <(
    find "$INPUT_DIR" $depth_flag -type f -iname "*.pdf" | sort
)

if [ ${#pdf_files[@]} -eq 0 ]; then
    echo "No PDF files found in '$INPUT_DIR'."
    exit 1
fi

echo "Found ${#pdf_files[@]} PDF file(s):"
for f in "${pdf_files[@]}"; do
    echo "  $f"
done
echo

failed=()
for file in "${pdf_files[@]}"; do
    echo "=== Processing: $file ==="
    if ! ocr_single_pdf "$file"; then
        failed+=("$file")
    fi
    echo
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

fi # end BASH_SOURCE guard
