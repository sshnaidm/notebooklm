# NotebookLM Link Automation

This directory contains scripts for automating the addition of links as sources to NotebookLM notebooks.

## add_links_script.py

This script automates the process of adding links as sources to a NotebookLM notebook.

### Prerequisites

- Python 3.6+
- Playwright for Python (`pip install playwright`)
- After installing Playwright, run `playwright install chromium` to install the browser

### Usage

The script supports three main modes of operation:

1. **Login only (for first-time setup)**:

   ```bash
   ./add_links_script.py --login --notebook "https://notebooklm.google.com/notebook/your-notebook-id"
   ```

   This will open a browser window for you to log in to your Google account. This is useful for initial setup without adding any links.

2. **Login and add links**:

   ```bash
   ./add_links_script.py --login --notebook "https://notebooklm.google.com/notebook/your-notebook-id" --links "https://example.com" "https://example2.com"
   ```

   This will open a browser window for you to log in to your Google account. After logging in, the script will add the specified links to the notebook.

3. **Adding links (after login)**:

   ```bash
   ./add_links_script.py --notebook "https://notebooklm.google.com/notebook/your-notebook-id" --links "https://example.com" "https://example2.com"
   ```

   Or using a file containing links (one per line):

   ```bash
   ./add_links_script.py --notebook "https://notebooklm.google.com/notebook/your-notebook-id" --links-file "path/to/links.txt"
   ```

### Command-line Arguments

- `--notebook`: (Required) URL of the NotebookLM notebook
- `--login`: (Optional) Run the login process first
- `--links`: (Optional) List of links to add as sources (mutually exclusive with `--links-file`)
- `--links-file`: (Optional) Path to a file containing links, one per line (mutually exclusive with `--links`)
- `--profile-path`: (Optional) Path to the browser profile directory (default: `~/.browser_automation`)

Note: Either `--login` or one of the links options (`--links` or `--links-file`) must be provided.

### Examples

```bash
# First run with login only (just to set up the profile)
./add_links_script.py --login --notebook "https://notebooklm.google.com/notebook/5e4bd5cb-9b98-4ff4-b0dc-4abccb02e861"

# Login and add links in one command
./add_links_script.py --login --notebook "https://notebooklm.google.com/notebook/5e4bd5cb-9b98-4ff4-b0dc-4abccb02e861" --links "https://access.redhat.com/support/policy/updates/openshift" "https://www.youtube.com/watch?v=b9BWbr_7xs8"

# Subsequent runs (no login needed)
./add_links_script.py --notebook "https://notebooklm.google.com/notebook/5e4bd5cb-9b98-4ff4-b0dc-4abccb02e861" --links-file "example_links.txt"

# Using a custom profile path
./add_links_script.py --login --notebook "https://notebooklm.google.com/notebook/5e4bd5cb-9b98-4ff4-b0dc-4abccb02e861" --profile-path "~/custom_browser_profile"
```

## Notes

- The script uses a persistent browser profile to maintain your login session (default location: `~/.browser_automation`).
- You can specify a custom profile path using the `--profile-path` argument.
- For YouTube links, the script automatically selects the "YouTube" source type.
- For other links, it selects the "Website" source type.
