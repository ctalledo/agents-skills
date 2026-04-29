---
name: worklog-threads
description: >-
  List all active worklog threads in a Markdown table sorted by priority
  (high → medium → low).
compatibility: >-
  Requires the wl tool. Locates it via $WORKLOG_PATH/tools/wl.
---

# Worklog Threads

Run the following command:

```bash
$WORKLOG_PATH/tools/wl thread list
```

Present the results as a Markdown table with columns **ID**, **Pri**,
**Status**, **Type**, **Updated**, and **Title**, sorted by priority descending
(high → medium → low). Within the same priority level, preserve the
order returned by `wl thread list`.
