---
name: read-doc
description: >-
  Read a Google Doc by document ID or URL. Use this to fetch the content of
  design docs, RFCs, meeting notes, or any other Google Docs document referenced
  in work threads or conversations.
argument-hint: <document-id-or-url>
compatibility: >-
  Requires the gws CLI tool configured with read-only access to Google Docs.
---

# Read Google Doc

Fetch and present the content of a Google Doc. Jacob has read-only access to
Google Docs via the `gws` CLI tool.

The command examples below are recommended starting points. Adapt field
selections and output handling to the document's size and the task at hand.

## Procedure

### 1. Resolve the document ID

Parse `$ARGUMENTS` to extract a Google Docs document ID. Supported formats:

- **Full URL**: `https://docs.google.com/document/d/DOCUMENT_ID/edit...`
  Extract the string between `/d/` and the next `/`.
- **Bare ID**: A string with no slashes or `docs.google.com` in it.

If the argument does not match either format, report the problem and ask the
user for clarification.

### 2. Fetch the document

Start with title and body content:

```
gws docs documents get \
    --params '{"documentId": "<ID>"}' \
    --fields "title,body"
```

If the command fails with a 404 or permission error, report the issue to the
user — it likely means the document is not shared with Jacob's account. Do not
retry automatically.

If the response is very large and threatens to overwhelm the context window,
re-fetch with a narrower field mask to get document structure first:

```
gws docs documents get \
    --params '{"documentId": "<ID>"}' \
    --fields "title,body(content(paragraph(elements(textRun(content)))))"
```

Other useful field combinations:

- **With revision info**: `"title,body,revisionId"`
- **Title only** (to verify access before fetching body): `"title"`

Always use `--fields` to avoid pulling the full unmasked API response, which
can be enormous.

### 3. Present the content

The Google Docs API returns structured JSON with nested paragraph and text-run
objects. Extract the readable text content from the structural elements and
present it clearly:

1. Show the document title.
2. If the document is long, summarize its structure (headings and sections)
   first and ask the user which sections are relevant before dumping the full
   text.
3. For shorter documents, present the full content in a readable format.

### 4. Schema discovery

If you need to explore available response fields:

```
gws schema docs.documents.get
```

This is useful when Jacob asks for specific metadata (revision history,
suggested changes, comments, etc.) that is not covered by the default field
mask.

## Tips

- Prefer the minimal field mask that answers the question. `"title,body"` is
  sufficient for most reads.
- For very long documents (design docs, RFCs), read the structure first and
  let Jacob direct which sections to focus on rather than loading everything.
- If the document contains inline images or drawings, note their presence but
  do not attempt to render them.

## Constraints

- Jacob has **read-only** access to Google Docs via `gws`. Do not attempt any
  write operations (creating, editing, or commenting on documents).
- All `gws` interaction must go through the `gws` CLI. There is no MCP server
  for Google Workspace.
- Always use `--fields` to limit response size. Omitting it can produce
  responses that exceed useful context limits.

## Target

$ARGUMENTS
