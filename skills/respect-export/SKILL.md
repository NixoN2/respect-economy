---
name: respect-export
description: This skill should be used when the user types "/respect-export", asks to "export learnings", "export preferences", "generate CLAUDE.md from feedback", or wants to create portable AI preferences from their respect economy data.
---

# Respect Export

Exports all learnings from the respect economy into a portable CLAUDE.md section that works without the plugin installed. This lets users share their "training" with teammates or carry it to other projects.

## Usage

1. Read the feedback file from auto-memory: find `respect-feedback.md` in `~/.claude/projects/[encoded-cwd]/memory/`
   - Encoded CWD: replace `/` and `.` in the current working directory with `-`
2. Read the wallet file at `~/.claude/respect/wallet.json` for stats context
3. Extract all sections:
   - Learnings (under `## Learnings`)
   - Mistakes to Avoid (under `## Mistakes to Avoid`)
   - Patterns (under `## Patterns`)
4. Generate a CLAUDE.md compatible section in this format:

```markdown
# AI Preferences (exported from respect plugin)

## Do

[Convert each learning's **Lesson** into a directive, e.g.:]
- Push repository changes before version bumping when publishing plugins
- Run tests before claiming work is complete

## Don't

[Convert each mistake's **Lesson** into a negative directive, e.g.:]
- Don't commit without running tests first
- Don't skip version bumps when updating plugins

## Patterns the user values

[Copy from the Patterns section, e.g.:]
- Systematic workflows and proper git practices
- Attention to detail in configuration files
```

5. Show the generated output in a code block so the user can copy it
6. Tell the user: "Paste this into any project's CLAUDE.md to carry your preferences without the plugin."
7. Offer to write it directly to `./CLAUDE.md` if the user wants (append, don't overwrite)
