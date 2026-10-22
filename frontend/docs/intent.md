# What We're Building: the Strata Website

## The short version

A simple, one-page website for **Strata** where anyone can learn what the app does and **download it for their Mac in one click**.

## Who it's for

People who found Strata (from a link, a post or a search) and want to know:
1. What is this?
2. Will it work on my Mac?
3. How do I get it, and how do I open it?

Most of them are **not developers**. Many are people who moved from Windows to a Mac. They have never visited a GitHub releases page and shouldn't have to.

## The problem it solves

Today the only way to get Strata is the GitHub releases page. That page is confusing for normal people: they have to find the **Assets** list, pick the right file, and then work out on their own why macOS blocks the app the first time it opens.

The website replaces that with a clean page, a big **Download for Mac** button, and plain-language install steps.

## What the website will do

### 1. Explain Strata at a glance
- A headline that says what Strata is: *a Windows-style taskbar for your Mac*.
- A picture of the bar, so people get it without reading.
- A short list of the main features: one button per window, Start button, pinned apps, snapping, custom zones, multiple monitors.

### 2. Download in one click
- A big **Download for Mac** button near the top, and again at the bottom.
- The button always downloads **the newest version**, without us editing the website each time we release.
- Next to it: the version number, the file size, and "macOS 14 or newer · Apple silicon and Intel · Free".
- If the newest version can't be looked up for some reason, the button still works: it opens the GitHub releases page instead.

### 3. Walk people through installing
The same three steps as the README, written for non-technical people:
1. Unzip it and drag Strata into Applications.
2. Open it the first time (macOS blocks it because it isn't registered with Apple; here's how to click **Open Anyway**).
3. Give it Accessibility permission.

### 4. Answer the usual questions
- The snap keyboard shortcuts.
- How to update and how to uninstall.
- Is it safe? Is it free? Why does macOS warn me?
- Where to report a bug.

## What it will look like

- **Clean and white**, with lots of space, like a modern Mac app's website.
- Works well on phones too (people often find it on their phone first, then download on their Mac).
- Fast. No pop-ups, no cookie banners, no tracking.

## What it won't do (for now)

- No accounts, sign-ups, payments or newsletter.
- No blog or changelog pages. The "What's new" details stay on GitHub.
- No analytics or tracking of any kind.
- No other languages besides English.

## Where it lives

The website is part of the Strata project itself, in the `frontend/` folder, so the app and its website are kept in one place. It's published for free on GitHub Pages.
