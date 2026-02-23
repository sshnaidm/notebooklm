#!/usr/bin/env python3

import os
import argparse
from ebooklib import epub
import ebooklib
from bs4 import BeautifulSoup
import sys


def epub_to_text(epub_path, output_path):
    """
    Converts an EPUB file to a clean text file.

    Args:
        epub_path (str): The file path for the input EPUB file.
        output_path (str): The file path for the output text file.
    """
    try:
        # Check if the input file exists
        if not os.path.exists(epub_path):
            print(f"Error: Input file not found at '{epub_path}'")
            return

        # Read the EPUB file
        book = epub.read_epub(epub_path)

        print(f"Processing '{os.path.basename(epub_path)}'...")

        full_text_content = []

        # The 'spine' defines the linear reading order of the book.
        # We iterate through the spine to get the content in the correct order.
        for item in book.get_items_of_type(ebooklib.ITEM_DOCUMENT):
            # Get the content of the document (which is HTML)
            html_content = item.get_content()

            # Parse the HTML using BeautifulSoup
            soup = BeautifulSoup(html_content, 'html.parser')

            content_blocks = []
            # Define the tags that we consider to be content blocks.
            # We include 'div' as it's often used for paragraphs instead of 'p'.
            target_tags = ['p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6']

            for tag in soup.find_all(target_tags):
                # This is the key logic: we process a tag only if it doesn't contain
                # another block-level tag. This prevents us from duplicating text by
                # processing both a container <div> and the <p> tags inside it.
                # We check if the tag contains any other target tags within it.
                # If the only one found is the tag itself, it's a "leaf" block.
                if len(tag.find_all(target_tags)) == 1:
                    # Extract text from the block.
                    text = tag.get_text(separator=' ', strip=True)
                    if text:
                        content_blocks.append(text)

            # Join the extracted text blocks with double newlines to preserve paragraph breaks.
            cleaned_text = '\n\n'.join(content_blocks)

            if cleaned_text:
                full_text_content.append(cleaned_text)

        # Write the extracted content to the output file
        with open(output_path, 'w', encoding='utf-8') as f:
            # Join chapters/sections with three newlines for better visual separation.
            f.write('\n\n\n'.join(full_text_content))

        print(f"Successfully converted EPUB to text.")
        print(f"Output saved to: '{output_path}'")

    except epub.EpubException as e:
        print(f"Error: Failed to process EPUB file. It might be corrupted or not a valid EPUB.")
        print(f"Details: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")


def main():
    """Main function to handle command-line-arguments."""
    parser = argparse.ArgumentParser(
        description="Convert an EPUB file to a plain text file.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "input_file",
        help="Path to the input .epub file."
    )
    parser.add_argument(
        "-o", "--output",
        dest="output_file",
        help="Path for the output .txt file.\n(default: same name as input file with .txt extension)"
    )

    # If no arguments are provided, print help message
    if len(sys.argv) == 1:
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args()

    # Determine the output file path if not provided
    if args.output_file:
        output_path = args.output_file
    else:
        # Get the base name of the input file and change the extension to .txt
        base_name = os.path.splitext(os.path.basename(args.input_file))[0]
        output_path = f"{base_name}.txt"

    epub_to_text(args.input_file, output_path)


if __name__ == "__main__":
    main()
