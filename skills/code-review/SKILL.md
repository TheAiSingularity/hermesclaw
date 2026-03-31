---
name: code-review
description: Local code review — analyzes a file, function, or git diff for bugs, security issues, edge cases, and style using your project's conventions from memory
license: MIT
compatibility: [macOS, Linux, Windows]
user-invocable: true
metadata:
  version: 0.1.0
  author: TheAiSingularity
  tags: [development, code-review, security, debugging]
  requires_tools: [terminal, file, memory]
---

# code-review

This skill performs a thorough local code review, using your codebase conventions from MEMORY.md to give context-aware feedback.

## When to invoke

- When the user provides a file path, function name, or git diff to review
- When the user says "review this", "check this code", or "find bugs in"
- When triggered from VS Code via the ACP integration

## Steps to execute

1. **Load codebase context from memory**
   - Check MEMORY.md for recorded codebase conventions (language, framework, testing patterns, style guide)
   - Note any previously flagged patterns to watch for in this project

2. **Read the target**
   - If a file path is given: read the full file
   - If a function is highlighted (via ACP): read only that function plus its immediate callers/callees
   - If reviewing a diff: read the diff plus surrounding context (±20 lines)

3. **Analyze for issues** — check all of the following:
   - **Correctness**: logic errors, off-by-one errors, incorrect conditionals
   - **Edge cases**: null/undefined inputs, empty collections, type mismatches, integer overflow
   - **Security**: injection risks (SQL, command, path traversal), unvalidated inputs, hardcoded secrets, insecure defaults
   - **Error handling**: unhandled exceptions, missing error propagation, silent failures
   - **Performance**: O(n²) loops, missing indexes, repeated expensive operations, memory leaks
   - **Style**: naming conventions, function length, unnecessary complexity (check against MEMORY.md conventions)
   - **Tests**: missing test coverage for edge cases identified above

4. **Prioritize findings**
   - P0: bugs that will cause failures in production (fix immediately)
   - P1: security or correctness issues that need fixing before merge
   - P2: code quality issues that should be addressed
   - P3: suggestions (optional improvements)

5. **Write a structured review**
   - Start with a one-line verdict: "Looks good — 2 minor issues" or "Needs changes — 1 security issue"
   - List findings by priority (P0 first)
   - For each finding: file:line, description, concrete fix
   - End with a code block showing the corrected version (for P0/P1 only)

6. **Update memory if patterns are notable**
   - If a recurring bug pattern is found (e.g., "always uses bare except in this codebase"), note it in MEMORY.md
   - This makes future reviews more accurate

## Output format

```
Code Review — [filename or description]
Verdict: [one-line summary]

P0 — Must fix:
1. [file:line] [description]
   Fix: [concrete fix or code block]

P1 — Should fix:
...

P2 — Consider:
...

Overall: [1-2 sentence summary]
```

## Notes

- This skill works best after the user has oriented Hermes to the codebase (language, framework, conventions)
- For large files (>500 lines), ask which section to focus on first
- The review respects project conventions from memory — it won't flag valid patterns just because they look unusual
