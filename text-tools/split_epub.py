#!/usr/bin/env python3
"""
EPUB Splitter Script (split_epub.py)
Splits large EPUB files into smaller chunks based on word count.
By default, it processes all EPUB files in the current directory.

Environment variables:
  MAX_CHUNK_WORDS: Maximum words per chunk (default: 400000)
  OUTPUT_DIR:      Directory to save output files (default: out)
  OUTPUT_PREFIX:   Prefix for output files (default: '')
"""

import os
import sys
import re
import glob
import shutil
import zipfile
from html.parser import HTMLParser
from lxml import etree

# Default settings (can be overridden with environment variables)
MAX_CHUNK_WORDS = int(os.environ.get('MAX_CHUNK_WORDS', 400000))
OUTPUT_DIR = os.environ.get('OUTPUT_DIR', 'out')
OUTPUT_PREFIX = os.environ.get('OUTPUT_PREFIX', '')


class _TextExtractor(HTMLParser):
    """Simple HTML parser that extracts plain text."""
    def __init__(self):
        super().__init__()
        self._buf = []
        self._in_skip = 0
        self._skip_tags = {'script', 'style'}

    def handle_starttag(self, tag, attrs):
        if tag.lower() in self._skip_tags:
            self._in_skip += 1

    def handle_endtag(self, tag):
        if tag.lower() in self._skip_tags and self._in_skip > 0:
            self._in_skip -= 1

    def handle_data(self, data):
        if self._in_skip == 0:
            self._buf.append(data)

    def word_count(self):
        return len(' '.join(self._buf).split())


def count_words_html(content):
    """Count words in HTML/XHTML content bytes."""
    parser = _TextExtractor()
    try:
        text = content.decode('utf-8', errors='ignore') if isinstance(content, bytes) else content
        parser.feed(text)
    except Exception:
        return 0
    return parser.word_count()


def get_opf_path(epub_path):
    """Read container.xml and return the path to the OPF file inside the ZIP."""
    with zipfile.ZipFile(epub_path) as z:
        container = z.read('META-INF/container.xml').decode('utf-8', errors='ignore')
    m = re.search(r'full-path=["\']([^"\']+)["\']', container)
    if not m:
        raise ValueError(f"Cannot find OPF path in META-INF/container.xml of {epub_path}")
    return m.group(1)


def parse_spine(opf_bytes):
    """
    Parse the OPF XML and return:
      spine_idrefs  - ordered list of idref strings from <spine>
      manifest      - dict: id -> {'href': ..., 'media-type': ...}
    """
    root = etree.fromstring(opf_bytes)
    ns = {'opf': 'http://www.idpf.org/2007/opf'}

    manifest = {}
    for item in root.findall('.//opf:manifest/opf:item', ns):
        item_id = item.get('id')
        href = item.get('href', '')
        mtype = item.get('media-type', '')
        if item_id:
            manifest[item_id] = {'href': href, 'media-type': mtype}

    spine_idrefs = []
    for itemref in root.findall('.//opf:spine/opf:itemref', ns):
        idref = itemref.get('idref')
        if idref:
            spine_idrefs.append(idref)

    return spine_idrefs, manifest


def modify_opf_for_chunk(opf_bytes, chunk_idrefs, part_num, total_parts):
    """
    Return modified OPF bytes where:
      - <spine> only contains itemrefs from chunk_idrefs
      - dc:title is updated with part number
      - dc:identifier gets a part suffix
    """
    root = etree.fromstring(opf_bytes)
    ns_opf = 'http://www.idpf.org/2007/opf'
    ns_dc = 'http://purl.org/dc/elements/1.1/'

    chunk_set = set(chunk_idrefs)

    # Update spine: remove itemrefs not in this chunk
    for spine in root.iter(f'{{{ns_opf}}}spine'):
        for itemref in list(spine):
            if itemref.get('idref') not in chunk_set:
                spine.remove(itemref)

    # Update title
    for title_el in root.iter(f'{{{ns_dc}}}title'):
        if title_el.text:
            title_el.text = f"{title_el.text} (Part {part_num} of {total_parts})"
        break

    # Update identifier
    for id_el in root.iter(f'{{{ns_dc}}}identifier'):
        if id_el.text:
            id_el.text = f"{id_el.text}-part{part_num}"
        break

    return etree.tostring(root, xml_declaration=True, encoding='UTF-8', pretty_print=False)


def split_epub(file_path, output_prefix, max_words):
    """
    Split a large EPUB file into smaller chunks based on word count.
    Returns list of output file paths.
    """
    print(f"Analyzing file: {file_path}")

    opf_path = get_opf_path(file_path)
    opf_dir = os.path.dirname(opf_path)  # e.g. 'OEBPS' or ''

    with zipfile.ZipFile(file_path) as z:
        opf_bytes = z.read(opf_path)
        spine_idrefs, manifest = parse_spine(opf_bytes)

        # Count words for each spine item
        spine_items = []  # list of (idref, zip_path, word_count)
        for idref in spine_idrefs:
            if idref not in manifest:
                continue
            href = manifest[idref]['href']
            # Build the ZIP-internal path (OPF-relative href -> ZIP path)
            if opf_dir:
                zip_path = opf_dir + '/' + href
            else:
                zip_path = href
            # Normalise (remove ./ etc.)
            zip_path = os.path.normpath(zip_path).replace('\\', '/')
            try:
                content = z.read(zip_path)
                words = count_words_html(content)
            except KeyError:
                words = 0
            spine_items.append((idref, zip_path, words))

    total_words = sum(w for _, _, w in spine_items)
    print(f"Total words: {total_words}")
    print(f"Total spine items: {len(spine_items)}")

    # Small enough — just copy
    if total_words <= max_words:
        output = f"{output_prefix}.epub"
        shutil.copy2(file_path, output)
        print(f"File is small enough, copied to: {output}")
        return [output]

    print(f"Splitting large file: {file_path} ({total_words} words)")

    # Group spine items into chunks
    chunks = []
    current = []
    current_words = 0
    for item in spine_items:
        _, _, words = item
        if current_words + words > max_words and current:
            chunks.append(current)
            current = []
            current_words = 0
        current.append(item)
        current_words += words
    if current:
        chunks.append(current)

    print(f"Splitting into {len(chunks)} chunks")

    output_files = []

    for idx, chunk in enumerate(chunks, 1):
        chunk_words = sum(w for _, _, w in chunk)
        chunk_idrefs = [idref for idref, _, _ in chunk]
        output = f"{output_prefix}-{idx}.epub"

        print(f"Creating chunk {idx}/{len(chunks)} "
              f"({len(chunk)} docs, {chunk_words} words) -> {output}")

        modified_opf = modify_opf_for_chunk(opf_bytes, chunk_idrefs, idx, len(chunks))

        with zipfile.ZipFile(file_path, 'r') as src, \
             zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as dst:

            for info in src.infolist():
                data = src.read(info.filename)

                if info.filename == opf_path:
                    # Write our modified OPF
                    dst.writestr(info, modified_opf)
                elif info.filename == 'mimetype':
                    # mimetype must be first and uncompressed per EPUB spec
                    zi = zipfile.ZipInfo('mimetype')
                    zi.compress_type = zipfile.ZIP_STORED
                    dst.writestr(zi, data)
                else:
                    dst.writestr(info, data)

        print(f"  Chunk {idx}: {chunk_words} words, saved to {output}")
        output_files.append(output)

    print(f"Split into {len(output_files)} chunks:")
    for f in output_files:
        print(f"  {f}")

    return output_files


def process_file(file_path):
    """Process a single EPUB file."""
    base = os.path.splitext(os.path.basename(file_path))[0]

    if OUTPUT_PREFIX:
        output_prefix = os.path.join(OUTPUT_DIR, f"{OUTPUT_PREFIX}-{base}")
    else:
        output_prefix = os.path.join(OUTPUT_DIR, base)

    return split_epub(file_path, output_prefix, MAX_CHUNK_WORDS)


def usage():
    script = sys.argv[0]
    print(f"Usage: {script} [epub_file]")
    print()
    print("If epub_file is provided, only that file will be processed.")
    print("If no file is provided, all EPUB files in the current directory will be processed.")
    print()
    print("Environment variables:")
    print(f"  MAX_CHUNK_WORDS  Maximum words per chunk (default: {MAX_CHUNK_WORDS})")
    print(f"  OUTPUT_DIR       Directory to save output files (default: '{OUTPUT_DIR}')")
    print(f"  OUTPUT_PREFIX    Prefix for output files (default: '{OUTPUT_PREFIX}')")
    print()
    print("Examples:")
    print(f"  # Process a specific file")
    print(f"  {script} document.epub")
    print()
    print(f"  # Process all EPUB files in current directory")
    print(f"  {script}")
    print()
    print(f"  # Custom settings")
    print(f"  MAX_CHUNK_WORDS=300000 OUTPUT_DIR=/tmp/chunks OUTPUT_PREFIX=split {script} document.epub")


def main():
    if len(sys.argv) >= 2 and sys.argv[1] in ('--help', '-h'):
        usage()
        sys.exit(0)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    if len(sys.argv) >= 2:
        file_path = sys.argv[1]
        if not os.path.isfile(file_path):
            print(f"Error: File '{file_path}' not found.")
            sys.exit(1)
        process_file(file_path)
    else:
        print("Processing all EPUB files in the current directory...")
        epub_files = sorted(glob.glob('*.epub'))

        if not epub_files:
            print("No EPUB files found in the current directory.")
            sys.exit(1)

        print("Found EPUB files:")
        for f in epub_files:
            print(f"  {f}")
        print()

        for f in epub_files:
            process_file(f)
            print()

        print("All EPUB files processed.")


if __name__ == '__main__':
    main()
