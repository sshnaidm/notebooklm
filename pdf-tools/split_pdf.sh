#!/bin/bash
#
# PDF Splitter Script (split_pdf.sh)
# This script splits large PDF files into smaller chunks based on word count.
# By default, it processes all PDF files in the current directory.
#

# Default settings (can be overridden with environment variables)
MAX_CHUNK_WORDS=${MAX_CHUNK_WORDS:-400000}
OUTPUT_DIR=${OUTPUT_DIR:-out}
OUTPUT_PREFIX=${OUTPUT_PREFIX:-""}
TMPDIR=$(mktemp -d)

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Cleanup function to remove temporary files
cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Dependencies check
for cmd in pdfinfo pdftotext qpdf; do
    command -v $cmd >/dev/null || { echo "$cmd not found. Install it."; exit 1; }
done

# Split a large PDF file into smaller chunks based on word count
split_pdf() {
    local file="$1"
    local output_prefix="$2"
    local max_words="$3"
    local base=$(basename "$file" .pdf)
    local output_files=()

    echo "Analyzing file: $file"

    # Get word count
    local word_count
    word_count=$(pdftotext "$file" - 2>/dev/null | wc -w)
    echo "Total words: $word_count"

    # If file is small enough, just copy it
    if (( word_count <= max_words )); then
        local output="${output_prefix}.pdf"
        cp "$file" "$output"
        echo "File is small enough, copied to: $output"
        echo "$output"
        return 0
    fi

    echo "Splitting large file: $file ($word_count words)"

    # Get page count
    local pages
    pages=$(pdfinfo "$file" | awk '/^Pages:/ {print $2}')
    echo "Total pages: $pages"

    # Calculate words per page and pages per chunk
    local words_per_page=$((word_count / pages))
    ((words_per_page == 0)) && words_per_page=1
    local pages_per_chunk=$((max_words / words_per_page))
    ((pages_per_chunk == 0)) && pages_per_chunk=1

    echo "Estimated words per page: $words_per_page"
    echo "Pages per chunk: $pages_per_chunk"

    local chunk_start=1
    local chunk_index=1

    # Split the PDF into chunks
    while [ $chunk_start -le $pages ]; do
        local chunk_end=$((chunk_start + pages_per_chunk - 1))
        ((chunk_end > pages)) && chunk_end=$pages

        local output="${output_prefix}-${chunk_index}.pdf"
        echo "Creating chunk $chunk_index (pages $chunk_start-$chunk_end) -> $output"

        # Extract pages using qpdf
        qpdf "$file" --pages "$file" $chunk_start-$chunk_end -- "$output"

        # Count words in the chunk
        local temp_txt="$TMPDIR/temp.txt"
        pdftotext "$output" "$temp_txt"
        local chunk_words=$(wc -w < "$temp_txt")
        rm -f "$temp_txt"

        echo "  Chunk $chunk_index has $chunk_words words"
        output_files+=("$output")

        chunk_start=$((chunk_end + 1))
        ((chunk_index++))
    done

    echo "Split into ${#output_files[@]} chunks:"
    printf '  %s\n' "${output_files[@]}"

    # Return the list of output files
    printf '%s\n' "${output_files[@]}"
}

# Process a single PDF file
process_file() {
    local file="$1"
    local base=$(basename "$file" .pdf)

    # Determine output prefix
    local output_prefix
    if [ -n "$OUTPUT_PREFIX" ]; then
        output_prefix="${OUTPUT_DIR}/${OUTPUT_PREFIX}-${base}"
    else
        output_prefix="${OUTPUT_DIR}/${base}"
    fi

    # Split the PDF
    split_pdf "$file" "$output_prefix" "$MAX_CHUNK_WORDS"
}

# Main function
main() {
    # Check if a specific file was provided
    if [ $# -ge 1 ]; then
        # Process the specified file
        if [ -f "$1" ]; then
            process_file "$1"
        else
            echo "Error: File '$1' not found."
            exit 1
        fi
    else
        # Process all PDF files in the current directory
        echo "Processing all PDF files in the current directory..."

        # Find all PDF files
        pdf_files=$(find . -maxdepth 1 -type f -name "*.pdf" | sort)

        if [ -z "$pdf_files" ]; then
            echo "No PDF files found in the current directory."
            exit 1
        fi

        # Process each PDF file
        echo "Found PDF files:"
        echo "$pdf_files"
        echo

        while IFS= read -r file; do
            process_file "$file"
            echo
        done <<< "$pdf_files"

        echo "All PDF files processed."
    fi
}

# Display usage information
usage() {
    echo "Usage: $0 [pdf_file]"
    echo
    echo "If pdf_file is provided, only that file will be processed."
    echo "If no file is provided, all PDF files in the current directory will be processed."
    echo
    echo "Environment variables:"
    echo "  MAX_CHUNK_WORDS: Maximum words per chunk (default: $MAX_CHUNK_WORDS)"
    echo "  OUTPUT_DIR: Directory to save output files (default: '$OUTPUT_DIR')"
    echo "  OUTPUT_PREFIX: Prefix for output files (default: '$OUTPUT_PREFIX')"
    echo
    echo "Examples:"
    echo "  # Process all PDF files in current directory"
    echo "  $0"
    echo
    echo "  # Process a specific file"
    echo "  $0 document.pdf"
    echo
    echo "  # Process all PDFs with custom settings"
    echo "  MAX_CHUNK_WORDS=500000 OUTPUT_DIR=chunks OUTPUT_PREFIX=split $0"
}

# If script is run with --help or -h, show usage
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    usage
    exit 0
fi

# If script is run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
