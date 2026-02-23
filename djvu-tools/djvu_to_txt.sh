#!/bin/bash
#
# djvu_to_txt.sh
# Converts DJVU files to plain text (.txt) files saved alongside the originals.
#
# If the DJVU already contains a hidden text layer (from prior OCR), that text
# is extracted directly with djvutxt — no re-OCR needed.  Otherwise each page
# is rendered to TIFF and OCR'd with Tesseract one at a time, keeping disk
# usage bounded to a single page regardless of file size.
#
# Usage: djvu_to_txt.sh [-r] [directory]
#   directory  defaults to the current directory
#   -r         recurse into subdirectories
#
# Environment variables:
#   OCR_LANG   Tesseract language(s) for OCR (default: rus+eng)
#              Examples: eng, rus, rus+eng
#   TMPDIR     Directory for temporary files (default: system default, usually
#              /tmp).  Set this to a disk-backed path (e.g. /var/tmp) when
#              /tmp is RAM-backed and space is tight.
#

OCR_LANG=${OCR_LANG:-rus+eng}
RECURSIVE=0
INPUT_DIR="."

# Minimum word count in djvutxt output to accept as usable text
MIN_WORDS=100

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 [-r] [directory]"
    echo
    echo "Converts DJVU files to plain text (.txt) saved next to each original."
    echo "Existing text layers are extracted directly; image-only pages are OCR'd."
    echo
    echo "  -r            Recurse into subdirectories"
    echo "  directory     Directory to search (default: current directory)"
    echo
    echo "Environment variables:"
    echo "  OCR_LANG   Tesseract OCR language(s) (default: $OCR_LANG)"
    echo "             Examples: eng, rus, rus+eng"
    echo "  TMPDIR     Temporary directory (default: system default)"
    echo "             Use a disk-backed path when /tmp is RAM-backed."
    echo
    echo "Examples:"
    echo "  $0"
    echo "  $0 /path/to/books"
    echo "  $0 -r /path/to/books"
    echo "  OCR_LANG=rus+eng $0 -r"
    echo "  TMPDIR=/var/tmp $0 -r /path/to/books"
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
        -*)
            echo "Error: Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            INPUT_DIR="$1"
            shift
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------

check_deps() {
    local missing=()
    for cmd in ddjvu djvutxt djvused tesseract; do
        command -v "$cmd" >/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: missing required tools: ${missing[*]}"
        echo "Install djvulibre (provides ddjvu, djvutxt, djvused) and tesseract-ocr."
        exit 1
    fi
}

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
# Core conversion
# ---------------------------------------------------------------------------

# Convert a single DJVU file to a .txt file in the same directory
convert_djvu_to_txt() {
    local file="$1"
    local dir
    dir=$(dirname "$file")
    local base
    base=$(basename "$file")
    base="${base%.*}"
    local txt_out="${dir}/${base}.txt"

    if [ -f "$txt_out" ]; then
        echo "=== Skipping: $file (${txt_out} already exists) ==="
        return 0
    fi

    echo "=== Processing: $file ==="

    # --- Step 1: Try extracting the existing hidden text layer ---------------
    echo "  Checking for existing text layer..."
    local djvu_text
    djvu_text=$(djvutxt "$file" 2>/dev/null)
    local word_count
    word_count=$(echo "$djvu_text" | wc -w)

    if [ "$word_count" -ge "$MIN_WORDS" ]; then
        echo "  Found existing text layer ($word_count words). Skipping OCR."
        echo "$djvu_text" > "$txt_out"
        echo "  Saved: $txt_out"
        return 0
    fi

    echo "  No usable text layer ($word_count words). Running page-by-page OCR..."

    # --- Step 2: Page-by-page TIFF → Tesseract OCR --------------------------
    local tmpdir
    tmpdir=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" RETURN

    local num_pages
    num_pages=$(djvused "$file" -e 'n' 2>/dev/null)
    if [ -z "$num_pages" ] || [ "$num_pages" -le 0 ]; then
        echo "  ERROR: Could not determine page count."
        return 1
    fi

    echo "  Pages: $num_pages  |  Language: $OCR_LANG"

    # Truncate output file
    > "$txt_out"

    local i
    local errors=()
    for (( i = 1; i <= num_pages; i++ )); do
        show_progress "$i" "$num_pages"

        local page_tif="${tmpdir}/page.tif"
        local page_txt="${tmpdir}/page"

        # Extract single page as TIFF
        if ! ddjvu -format=tiff -page="$i" "$file" "$page_tif" 2>/dev/null; then
            errors+=("page $i: ddjvu failed")
            rm -f "$page_tif"
            continue
        fi

        # OCR with Tesseract (writes page.txt)
        if ! tesseract "$page_tif" "$page_txt" -l "$OCR_LANG" 2>/dev/null; then
            errors+=("page $i: tesseract failed")
            rm -f "$page_tif" "${page_txt}.txt"
            continue
        fi

        # Append to output and clean up
        cat "${page_txt}.txt" >> "$txt_out"
        echo "" >> "$txt_out"
        rm -f "$page_tif" "${page_txt}.txt"
    done
    echo ""

    for err in "${errors[@]}"; do
        echo "  WARNING: $err"
    done

    echo "  Saved: $txt_out"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

check_deps

if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Directory '$INPUT_DIR' not found."
    exit 1
fi

if [ "$RECURSIVE" = "1" ]; then
    depth_flag=""
else
    depth_flag="-maxdepth 1"
fi

# shellcheck disable=SC2086
mapfile -t djvu_files < <(
    find "$INPUT_DIR" $depth_flag -type f \( -iname "*.djvu" -o -iname "*.djv" \) | sort
)

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
    if ! convert_djvu_to_txt "$file"; then
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
