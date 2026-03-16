---
name: respect-setup
description: This skill should be used when the user types "/respect-setup", asks to "configure respect", "set up the economy", "customize tiers", or wants to configure tier names, thresholds, and tip sizes for the respect economy.
---

# Respect Setup Wizard

Onboarding wizard for configuring the respect economy.

## On invocation

1. Check if `~/.claude/respect/config.json` exists
2. If it exists, show current settings summary, then ask:
   - "1. Modify a specific setting"
   - "2. Reconfigure from scratch"
   - "3. Cancel (keep current config)"
   - If cancel: stop
   - If modify: show numbered list of settings (tiers, thresholds, emoji, tip sizes, status line format). Let user pick one, change just that setting, write config atomically, done.
   - If reconfigure: proceed to step 3
3. Ask questions one at a time:
   a. Tier count and names — accept defaults (lurker/contributor/trusted/veteran/partner) or enter custom names (3-6 tiers)
   b. Tier thresholds — balance required for each tier (defaults: 0/20/60/150/300)
   c. Tier emoji — emoji for each tier (defaults: 👤/🌱/⚡/🔥/🤝)
   d. Tip sizes — values for small/medium/large (defaults: 1/3/5)
   e. Status line format — format string for status line display
4. Build config.json from answers
5. Write atomically: `tmp=$(mktemp "$HOME/.claude/respect/config.json.XXXXXX") && echo "$CONFIG" > "$tmp" && mv "$tmp" "$HOME/.claude/respect/config.json"`
6. Report what was configured and how to edit it later

## Notes

- Use `$HOME/.claude/respect/config.json` as the config path
- The config.example.json in the plugin root shows the full schema
- Tell the user to restart Claude Code for the new config to take effect
