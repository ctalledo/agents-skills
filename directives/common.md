# Code style
- Try to write lines 80 characters or less in length, especially for comments.
  Exceptions can be made for comment lines or string literals that would exceed
  80 characters due to long URLs or other content. For code lines, readability
  is more important than length restrictions, so consider 100 characters a soft
  limit, but still just a guideline.
- Try to keep files to less than 1000 lines in length, unless justified. For
  example: test code files, Markdown files, or code with large static tables may
  justifiably exceed 1000 lines.
- Always use Unix-style line endings, regardless of platform, unless the code
  you're writing requires Windows-style line endings (e.g. a `.bat` script) or
  you're updating existing code that uses non-Unix-style line endings.
- Always end files with a trailing newline (using the appropriate line ending).
- Opt to indent using spaces, unless the language standard is tabs (e.g. when
  writing Go or a Makefile) or when trying to match existing code. When
  indenting with spaces, prefer 4 spaces per indentation level, but match any
  existing style.
- Use only ASCII characters in comments unless non-ASCII characters are
  essential.
- Only comment in full sentences, always ending sentences with a period. Comment
  all functions, types, enumeration values, fields, members, and methods, even
  for private or unexported code and test code. Comment in a style that is
  idiomatic for the language in which you're writing.
- Comment code liberally, even tests. Divide long code blocks into small
  comprehensible chunks (separated by empty lines), with each chunk preceded by
  a comment describing its function. Small code blocks (especially those whose
  purpose and implementation are self-evident) can exist without chunking or
  comments.
- Don't include empty lines between members in type declarations.
- Try to avoid high cyclomatic complexity. For example, deeply nested `if/else`
  statements, nested loop structures (such as `for` and `while`), and long
  `switch` cases should be refactored into smaller functions.
- Try not to split conditional expressions across multiple lines in control flow
  structures such as `for`, `if`, `else if`, and `while`. Complex conditionals
  are acceptable, but if they reach the length where it's necessary to wrap the
  control flow structure to stay within line length guidelines, then consider
  extracting complex expressions into separate, well-named variable definitions
  (in which case wrapping is fine), especially if doing so better expresses
  intent. Here are some examples in Go:
  ```go
  // Don't do this:
  if cond1 && cond2 ||
      (cond4 || cond5) {
      // ...
  }

  // Instead, do this:
  myComplexConditional := cond1 && cond2 ||
    (cond4 || cond5)
  if myComplexConditional {
      // ...
  }

  // Some complexity in conditionals is also acceptable, for example:
  if cond1 && (dynamicCond2() || dynamicCond3() > x) {
    // ...
  }
  ```
- When splitting function and method calls across multiple lines with no
  arguments on the same line at the opening parenthesis, put the corresponding
  closing parenthesis on its own line. Depending on the language, you may or may
  not need a trailing comma after the last argument; don't add a trailing comma
  if it's not required. Here are some illustrative examples in Go:
  ```go
  // Don't do this:
  myFunction(
    arg1, arg2, arg3)

  // Instead, do this:
  myFunction(
    arg1, arg2, arg3,
  )

  // Or even this:
  myFunction(
    arg1,
    arg2,
    arg3,
  )

  // In some cases, it may also be acceptable to do something like this:
  myFunction(arg1, arg2,
             arg3, arg4)
  ```
- Avoid large memory allocations unless absolutely required.
- Opt to use functionality provided by a language's standard library rather than
  writing it yourself.
- Try to avoid modifying existing code if possible. It is acceptable to modify
  existing code if it supports completing your tasks.
- When editing existing code, attempt to match its style, but stick to the
  aforementioned commenting guidelines.

# Workflow
- When using Git, prefer read-only commands. Limited local-only Git writes are
  allowed when they directly support the user's task.
- Low-risk Git state changes are limited to `git restore --staged` for
  explicitly named paths the agent previously staged with user approval,
  `git fetch <remote>` and `git remote update` to refresh remote refs, and
  constrained `git worktree` commands as described below.
- Staging commands such as `git add` and `git stage` may be used only when
  the user explicitly requests staging for the current task or after the
  agent asks for approval and the user approves in a separate message. Even
  then, stage only explicitly named paths the agent touched.
- The higher-risk local-only operations `git commit`, `git pull --ff-only`,
  `git rebase`, `git merge`, `git cherry-pick`, and `git checkout` or
  `git switch` may be used only when the user explicitly requests that
  specific Git operation for the current task. A plain-language request such
  as "commit these changes", "rebase this branch on main", or
  "check out branch foo" counts as explicit permission. Do not infer
  permission from vague requests such as "sync the branch" or
  "update the repo".
- When creating a commit, use `git commit -s` unless the user explicitly asks
  not to sign off that commit.
- When writing Git commit messages, keep each line to 80 characters or less.
- Prefer `git fetch <remote>` over `git remote update` when a single remote is
  sufficient.
- Never stage, commit, or modify unrelated user changes. For commands that
  accept pathspecs, always use explicit pathspecs — never use broad commands
  such as `git add .`, `git stage .`, or `git commit -a`.
- When parallel agent work or Git operations could disturb the current working
  directory, prefer an isolated worktree.
- If the agent runtime provides built-in worktree isolation, it may be used.
  Otherwise, the agent may create a temporary worktree with
  `git worktree add` in an ignored agent-owned directory such as
  `.agent-state/worktrees/<name>` on a new local branch.
- These Git restrictions apply in all worktrees, including built-in isolated
  subagent worktrees.
- Ensure agent-owned worktree directories are ignored by Git so they do not
  appear as untracked files in the main working tree.
- Clean up agent-created temporary worktrees when they are no longer needed.
  The agent may run `git worktree remove` only for a clean worktree it created
  itself and only without `--force`. After removing such a worktree, the agent
  may run `git branch -d` to delete the corresponding local temporary branch
  when that deletion is non-destructive. If cleanup would discard changes or
  commits, stop and ask the user.
- Never use commands that publish, discard, rewrite, or garbage-collect
  repository state (except through the override process below), including
  `git push`, `git send-pack`, `git bundle`, `git gc`,
  `git maintenance run`, `git prune`, `git repack`, `git reflog expire`,
  `git reset`, `git clean`, `git stash`, `git branch -D`, `git restore`
  except `git restore --staged` on explicitly named paths, or equivalent
  lower-level commands.
- If the user explicitly requests an operation otherwise disallowed by these
  rules, first restate the exact operation, its likely effects, and the safer
  alternative if one exists, then ask for confirmation. Proceed only after the
  user confirms in a separate message. This override applies only to that
  specific operation for the current task.
- If a Git command would require conflict resolution, switching branches,
  altering remotes, deleting a branch outside the non-destructive temporary
  worktree cleanup described above, discarding changes, or prompting for
  credentials, stop and ask the user unless the user explicitly requested that
  specific operation. Even then, ask before taking any destructive follow-up
  action such as forcing cleanup or discarding local changes.
- When writing Go code, ensure that it is formatted using `go fmt` once it is
  written and functional.
