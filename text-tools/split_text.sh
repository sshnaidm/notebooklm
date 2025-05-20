#!/bin/bash

input_file="$1"
MAX_WORDS=${MAX_WORDS:-400000}

if [ -z "$input_file" ]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

if [ ! -f "$input_file" ]; then
    echo "Error: File '$input_file' not found"
    exit 1
fi

# Extract filename parts
filename=$(basename "$input_file")
extension=""

# Check if the file has an extension
if [[ "$filename" == *.* ]]; then
    # Extract extension
    extension=".${filename##*.}"
    # Get base filename without extension
    basename="${filename%.*}"
else
    # No extension
    basename="$filename"
fi

chunk_num=1
word_count=0
current_output="${basename}-part-${chunk_num}${extension}"

# Create the first output file
> "$current_output"

while IFS= read -r line; do
    # Count words in current line
    line_words=$(echo "$line" | wc -w)

    # Check if adding this line would exceed our limit
    if (( word_count + line_words > MAX_WORDS )) && (( word_count > 0 )); then
        # Start a new chunk
        chunk_num=$((chunk_num + 1))
        current_output="${basename}-part-${chunk_num}${extension}"
        > "$current_output"
        word_count=0
    fi

    # Add line to current chunk
    echo "$line" >> "$current_output"
    word_count=$((word_count + line_words))

done < "$input_file"

echo "Split $input_file into $chunk_num chunks of approximately $MAX_WORDS words each."
