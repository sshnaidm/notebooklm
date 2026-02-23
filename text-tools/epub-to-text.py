#!/usr/bin/env python3

import os
import argparse
import ebooklib
from ebooklib import epub
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

            # Extract text from the parsed HTML.
            # The .get_text() method returns all the text in a document
            # or tag, stripped of its HTML tags.
            # The 'separator' argument helps in managing whitespace.
            text = soup.get_text(separator='\n', strip=True)

            # Clean up the text by removing excessive blank lines
            cleaned_lines = [line.strip() for line in text.splitlines() if line.strip()]
            cleaned_text = '\n'.join(cleaned_lines)

            if cleaned_text:
                full_text_content.append(cleaned_text)

        # Write the extracted content to the output file
        with open(output_path, 'w', encoding='utf-8') as f:
            # Join chapters/sections with a double newline for separation
            f.write('\n\n'.join(full_text_content))

        print("Successfully converted EPUB to text.")
        print(f"Output saved to: '{output_path}'")

    except epub.EpubException as e:
        print("Error: Failed to process EPUB file. It might be corrupted or not a valid EPUB.")
        print(f"Details: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")


def main():
    """Main function to handle command-line arguments."""
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
