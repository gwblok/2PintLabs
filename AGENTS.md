# Shared PowerShell and Markdown instructions

Apply these rules to the relevant files. The maintained reference is [CodeStandards](https://github.com/gwblok/CodeStandards).

## PowerShell

- Start every new `.ps1` script and `.psm1` module with comment-based help before executable code. Separate a preceding shebang or `#Requires` directive from the help by a blank line. If a function directly follows the help, leave two blank lines before it.
- Include `.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`, `.PARAMETER` for each script-level parameter, and `.NOTES` containing `Author:`, `Created:`, and `Change History:` with a dated initial entry. Document public module functions with their own help. Use real details or `Not specified`; do not invent authors, dates, or versions.
- Add comments before meaningful phases and significant non-obvious operations to explain what will happen and any important reason or risk. Keep comments accurate; do not narrate every obvious line.
- Document prerequisites and side effects, validate inputs, surface failures, and use four-space indentation in new files.
- Preserve existing behavior and local style. Update an existing change history for meaningful changes; add a missing header when substantially revising a legacy file rather than making unrelated bulk edits. Respect script signatures.

## Markdown

- Start with a clear title and purpose. Include prerequisites, numbered steps, examples, validation, troubleshooting, and limitations when they are relevant.
- Use language-labeled code fences, descriptive links, and useful image descriptions. Keep examples safe and accurate, and do not expose credentials or invent test results.
- Update documentation alongside behavior changes. A separate changelog is optional unless the project requires one.
