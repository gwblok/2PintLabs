---
description: "Use when creating or modifying PowerShell scripts or modules; applies shared help-header, change-history, and commenting rules."
applyTo: "**/*.{ps1,psm1}"
---

# PowerShell instructions

- Start each new `.ps1` and `.psm1` with comment-based help before executable code. Separate a preceding shebang or `#Requires` directive from the help by a blank line; leave two blank lines before a function that directly follows the help.
- Include `.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`, `.PARAMETER` for each script-level parameter, and `.NOTES` with `Author:`, `Created:`, and `Change History:`. Add a dated initial entry and document public module functions with their own help; never invent authors, dates, or versions.
- Place comments before meaningful phases and significant non-obvious operations to explain what will happen and important reasons or risks. Keep comments current without narrating every obvious line.
- Describe prerequisites and side effects, validate inputs, and surface errors. Use four spaces for indentation in new files.
- Preserve existing behavior and local conventions. Update an existing history for meaningful changes and add a missing header when substantially revising a legacy file. Respect script signatures.

The maintained reference is [CodeStandards](https://github.com/gwblok/CodeStandards).
