#!/usr/bin/env python3
import asyncio
import argparse
import os
from playwright.async_api import async_playwright


async def login(profile_path):
    """
    Open a browser for the user to log in to their Google account and save the profile.

    Args:
        profile_path (str): Path to the browser profile directory
    """
    profile_path = os.path.expanduser(profile_path)

    async with async_playwright() as p:
        # This is where your cookies and login sessions will be stored
        browser = await p.chromium.launch_persistent_context(
            user_data_dir=profile_path,
            headless=False,
        )
        page = await browser.new_page()
        await page.goto("https://accounts.google.com")

        print("Please log in manually and then close the browser window when done.")
        try:
            await page.wait_for_timeout(60000 * 10)  # 10 minutes to log in
        except Exception as e:
            print(f"Finished with {e}")


async def add_links(notebook_url, links, profile_path):
    """
    Add links as sources to a NotebookLM notebook.

    Args:
        notebook_url (str): URL of the NotebookLM notebook
        links (list): List of links to add as sources
        profile_path (str): Path to the browser profile directory
    """
    profile_path = os.path.expanduser(profile_path)

    async with async_playwright() as p:
        # This is where your cookies and login sessions will be stored
        browser = await p.chromium.launch_persistent_context(
            user_data_dir=profile_path,
            executable_path="/usr/bin/chromium-browser",
            headless=False,  # Set to True if you want to run in the background
        )
        page = await browser.new_page()
        await page.goto(notebook_url)

        for link in links:
            # Wait for the page to load and the "Add source" button to be visible
            # Using text content as a locator can be robust to some UI changes
            await page.locator("text='Add'").wait_for(state="visible")

            # Click the "Add source" button
            await page.locator("text='Add'").click()

            # Wait for the source options to appear and click "Webpage" or "Youtube"
            # Again, using text content
            if "youtube.com" in link:
                text_to_click = "YouTube"
            else:
                text_to_click = "Website"
            await page.locator(f"text='{text_to_click}'").wait_for(state="visible")
            await page.locator(f"text='{text_to_click}'").click()

            # Selector for the modal container based on the provided HTML
            modal_selector = ".mat-mdc-dialog-inner-container"

            # Wait for the modal container to be visible
            await page.locator(modal_selector).wait_for(state="visible", timeout=15000)

            # Now, locate the input field within this modal by finding the label
            # and navigating to the associated input within its form field container.
            # This chain finds the modal, then the mat-label with specific text,
            # goes up to its ancestor mat-form-field, and finds the input inside.
            if "youtube.com" in link:
                text_to_fill = "Paste YouTube URL"
            else:
                text_to_fill = "Paste URL"
            url_input_locator = (
                page.locator(modal_selector)
                .locator(f"mat-label:text('{text_to_fill}')")
                .locator("xpath=ancestor::mat-form-field")
                .locator("input")
            )

            # Fill the input field. Playwright's fill() waits for the element to be actionable.
            # Use a robust timeout for the fill action itself
            await url_input_locator.fill(link, timeout=20000)

            # Locate the "Insert" button *within* the modal
            # We find the button that contains the text "Insert"
            insert_button_selector = f"{modal_selector} button:has-text('Insert')"

            # Click the "Insert" button.
            # Playwright's click() waits for the element to be actionable (including enabled).
            await page.locator(insert_button_selector).click(timeout=20000)

            print(f"Added source: {link}")

            # Wait for the source to be processed
            await page.wait_for_timeout(2000)  # Wait for 2 seconds

        await browser.close()


def read_links_from_file(file_path):
    """
    Read links from a file, one link per line.

    Args:
        file_path (str): Path to the file containing links

    Returns:
        list: List of links
    """
    with open(file_path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def main():
    parser = argparse.ArgumentParser(description="Add links as sources to a NotebookLM notebook.")
    parser.add_argument("--notebook", required=True, help="URL of the NotebookLM notebook")
    parser.add_argument("--login", action="store_true", help="Run login process first")
    parser.add_argument(
        "--profile-path",
        default="~/.browser_automation",
        help="Path to the browser profile directory (default: ~/.browser_automation)",
    )

    # Group for links input (either from command line or file)
    group = parser.add_mutually_exclusive_group(required=False)
    group.add_argument("-l", "--links", nargs="+", help="Links to add as sources")
    group.add_argument("-f", "--links-file", help="Path to a file containing links (one per line)")

    args = parser.parse_args()

    # Run login process if requested
    if args.login:
        asyncio.run(login(args.profile_path))

    # Only add links if they are provided
    if args.links or args.links_file:
        # Get links from command line or file
        if args.links:
            links = args.links
        else:
            links = read_links_from_file(args.links_file)

        # Add links to the notebook
        asyncio.run(add_links(args.notebook, links, args.profile_path))
    elif not args.login:
        # If no links are provided and not in login mode, show an error
        parser.error("Either --links, --links-file, or --login must be provided")


if __name__ == "__main__":
    main()
