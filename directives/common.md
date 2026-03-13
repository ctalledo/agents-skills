# Code style
- Try to write lines less than 80 characters in length, especially for comments.
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
- When using Git, don't use any commands that would change the state of the
  repository or any associated remote repository.
- When writing Go code, ensure that it is formatted using `go fmt` once it is
  written and functional.
