#!/bin/bash

# Set max words per chunk
MAX_WORDS=${MAX_WORDS:-400000}
PART=1
CURRENT_WORDS=0
CHUNK_FILES=()
OUTDIR=${OUTDIR:-out}

# Read from stdin or from a file
INPUT_FILE=$(mktemp)
echo "Using input file $INPUT_FILE"
find . -maxdepth 1 -name "*.pdf" -print0 | while IFS= read -r -d '' i; do echo "$(pdftotext "$i" - | wc -w) $(ls -sh "$i")"; done | tee $INPUT_FILE

# Ensure pdfunite is installed
command -v pdfunite >/dev/null || { echo "pdfunite not found. Install poppler-utils."; exit 1; }

# Base name for output
BASENAME1="combined_pdf"
BASENAME=${OUTDIR}/${BASENAME1}
mkdir -p ${OUTDIR}

# Read lines
while IFS= read -r line; do
    # Extract word count and file path
    WORDS=$(echo "$line" | awk '{print $1}')
    FILE=$(echo "$line" | sed -E 's/^[0-9]+\s+[0-9\.]+[KMGT]?\s+//')

    # If adding this file exceeds the limit, flush current chunk
    if (( CURRENT_WORDS + WORDS > MAX_WORDS )); then
        OUTPUT="${BASENAME}-part${PART}.pdf"
        echo "Creating $OUTPUT from:"
        printf '  %s\n' "${CHUNK_FILES[@]}"
        pdfunite "${CHUNK_FILES[@]}" "$OUTPUT"

        # Reset
        ((PART++))
        CURRENT_WORDS=0
        CHUNK_FILES=()
    fi

    # Add current file to chunk
    CHUNK_FILES+=("$FILE")
    ((CURRENT_WORDS += WORDS))
done < "$INPUT_FILE"


# Handle last chunk
if (( ${#CHUNK_FILES[@]} > 0 )); then
    OUTPUT="${BASENAME}-part${PART}.pdf"
    echo "Creating $OUTPUT from:"
    printf '  %s\n' "${CHUNK_FILES[@]}"
    pdfunite "${CHUNK_FILES[@]}" "$OUTPUT"
fi

find ${OUTDIR} -maxdepth 1 -name "*.pdf" -print0 | while IFS= read -r -d '' i; do echo "$(pdftotext "$i" - | wc -w) $(ls -sh "$i")"; done
