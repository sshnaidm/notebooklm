# NotebookLM scripts and tools

This repository contains various scripts and tools related to NotebookLM

## Automation

The `automation` directory contains scripts for automating various tasks related to NotebookLM.

## Install Playwright

For Fedora:

```bash
sudo dnf install -y chromium
sudo dnf install -y libicu libjpeg-turbo libwebp flite pcre libffi
python -m pip install playwright
python -m playwright install
```

## PDF Tools

The `pdf-tools` directory contains scripts for working with PDF files and preparing them for NotebookLM.

* `split_pdf.sh` - splits large PDF files into smaller chunks based on word count.
* `combine_pdf.sh` - combines multiple PDF files into chunks based on word count.
* `pdf_process.sh` - is a comprehensive script for processing multiple PDF files, combining them into chunks based on word count and generating a manifest file, splitting large files if needed.

[PDF tools README](pdf-tools/README.md)
