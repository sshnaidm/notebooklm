# Text File Splitter (`split_text.sh`)

Splits large text files into smaller chunks based on word count.

## Features

```bash
./split_text.sh <input_file>
```

- Splits files at approximately 400,000 words per chunk
- Preserves file extensions
- Creates output files in current directory as `<filename>-part-<N>.<ext>`

## Example

```bash
./split_text.sh large_document.txt
```

Creates:

- `large_document-part-1.txt`
- `large_document-part-2.txt` (if needed)

To change the word limit, set the `MAX_WORDS` environment variable:

```bash
MAX_WORDS=200000 ./split_text.sh large_document.txt
```
