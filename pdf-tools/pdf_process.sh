#!/bin/bash

MAX_CHUNK_WORDS=${MAX_CHUNK_WORDS:-400000}
PART=1
CURRENT_WORDS=0
CHUNK_FILES=()
TMPDIR=$(mktemp -d)
F_BASENAME="combined_pdf"

INPUT_FILE="$(mktemp)"
OUTPUT_DIR=${1:-out}
BASENAME="${OUTPUT_DIR}/${F_BASENAME}"

mkdir -p $OUTPUT_DIR
echo "Using input file $INPUT_FILE"

find . -maxdepth 1 -name "*.pdf" -print0 | while IFS= read -r -d '' file; do
  word_count=$(pdftotext "$file" - 2>/dev/null | wc -w)
  size=$(ls -sh "$file" | awk '{print $1}')
  echo "$word_count $size $file"
done | tee "$INPUT_FILE"

MANIFEST_FILE="manifest.txt"
echo "" > "$MANIFEST_FILE"
declare -A FILE_MAP

cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Dependencies check
for cmd in pdfunite pdfinfo pdfseparate pdftotext; do
    command -v $cmd >/dev/null || { echo "$cmd not found. Install it."; exit 1; }
done

# Sanitize file for temporary naming
sanitize() {
    basename "$1" | sed 's/[^a-zA-Z0-9_-]/_/g'
}

write_manifest() {
    local part=$1
    echo "${BASENAME}-part${part}.pdf:" >> "$MANIFEST_FILE"
    for f in "${CHUNK_FILES[@]}"; do
        # Try to find original filename from TMPDIR copy
        if [[ "$f" == "$TMPDIR/"* ]]; then
            base=$(basename "$f")
            original=${base%%-split*}
            echo "  - (split) $original" >> "$MANIFEST_FILE"
        else
            echo "  - $f" >> "$MANIFEST_FILE"
        fi
    done
    echo >> "$MANIFEST_FILE"
}

# Handle regular or split part file
handle_chunk_file() {
    local file="$1"
    local words="$2"

    if (( CURRENT_WORDS + words > MAX_CHUNK_WORDS )); then
        write_manifest "$PART"
        output="${BASENAME}-part${PART}.pdf"
        echo "Creating $output from:"
        printf '  %s\n' "${CHUNK_FILES[@]}"
        pdfunite "${CHUNK_FILES[@]}" "$output"
        echo

        CHUNK_FILES=()
        CURRENT_WORDS=0
        ((PART++))
    fi

    CHUNK_FILES+=("$file")
    FILE_MAP["$file"]="${FILE_MAP[$file]:-}${CURRENT_WORDS:+, }$PART"
    ((CURRENT_WORDS += words))
}

split_large_pdf() {
    local file="$1"
    local word_count="$2"
    local base=$(basename "$file" .pdf)
    local safe_name=$(sanitize "$base")

    echo "Splitting large file: $file ($word_count words)"

    local pages
    pages=$(pdfinfo "$file" | awk '/^Pages:/ {print $2}')
    local words_per_page=$((word_count / pages))
    ((words_per_page == 0)) && words_per_page=1
    local pages_per_chunk=$((MAX_CHUNK_WORDS / words_per_page))
    ((pages_per_chunk == 0)) && pages_per_chunk=1

    local chunk_start=1
    local chunk_index=1

    while [ $chunk_start -le $pages ]; do
        local chunk_end=$((chunk_start + pages_per_chunk - 1))
        ((chunk_end > pages)) && chunk_end=$pages

        # Create split chunk in temp dir for processing
        chunk_pdf="$TMPDIR/${safe_name}-split${chunk_index}.pdf"
        qpdf "$file" --pages "$file" $chunk_start-$chunk_end -- "$chunk_pdf"

        # Also save a copy to OUTPUT_DIR
        output_chunk="${OUTPUT_DIR}/${safe_name}-split${chunk_index}.pdf"
        cp "$chunk_pdf" "$output_chunk"
        echo "Saved split chunk to: $output_chunk"

        # Count words
        temp_txt="$TMPDIR/temp.txt"
        pdftotext "$chunk_pdf" "$temp_txt"
        chunk_words=$(wc -w < "$temp_txt")
        rm -f "$temp_txt"

        handle_chunk_file "$chunk_pdf" "$chunk_words"

        chunk_start=$((chunk_end + 1))
        ((chunk_index++))
    done
}

# Main loop
while IFS= read -r line || [[ -n "$line" ]]; do
    # Extract word count, size, and filename with regex
    if [[ "$line" =~ ^([0-9]+)[[:space:]]+[0-9\.]+[KMGT]?[[:space:]]+(.+)$ ]]; then
    WORDS="${BASH_REMATCH[1]}"
    FILE="${BASH_REMATCH[2]}"

    if (( WORDS > MAX_CHUNK_WORDS )); then
        split_large_pdf "$FILE" "$WORDS"
    else
        handle_chunk_file "$FILE" "$WORDS"
    fi
  fi
done < "$INPUT_FILE"

# Final flush
if (( ${#CHUNK_FILES[@]} > 0 )); then
    write_manifest "$PART"
    output="${BASENAME}-part${PART}.pdf"
    echo "Creating $output from:"
    printf '  %s\n' "${CHUNK_FILES[@]}"
    pdfunite "${CHUNK_FILES[@]}" "$output"
    echo
fi

find  ${OUTPUT_DIR} -maxdepth 1 -name "*.pdf" -print0 | while IFS= read -r -d '' file; do
  word_count=$(pdftotext "$file" - 2>/dev/null | wc -w)
  size=$(ls -sh "$file" | awk '{print $1}')
  echo "$word_count $size $file"
done

echo "Manifest written to $MANIFEST_FILE"
