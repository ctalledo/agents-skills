---
name: open-browser
description: >-
  Open one or more URLs in Google Chrome. Use when Jacob needs to open a PR,
  issue, Slack thread, or any other link in the browser. Accepts a
  space-separated or newline-separated list of URLs.
argument-hint: "<url> [url...]"
compatibility: >-
  Requires macOS with Google Chrome installed. Uses the macOS `open` command.
---

# Open Browser

Open one or more URLs in Google Chrome on macOS.

## Procedure

Parse `$ARGUMENTS` as a whitespace-separated list of URLs. For each URL,
run:

```bash
open -a "Google Chrome" "<url>"
```

When multiple URLs are provided, open all of them — it is fine to run the
`open` commands in rapid succession.

Report which URLs were opened. If any `open` call fails, report the error
and continue with the remaining URLs.

## Tips

- This is safe to invoke without asking for confirmation — opening a URL
  in the browser is non-destructive and easily dismissed by the user.
- When the concierge or sitrep presents a set of PRs that need review,
  offer to open them all at once rather than one at a time.

## Constraints

- Only open URLs that Jacob explicitly referenced or that appear in worklog
  threads and notifications. Do not open arbitrary URLs.
- Do not open more than 10 URLs in a single invocation without confirming
  with Jacob first.

## Target

$ARGUMENTS
