# Sample Data — SkillManager macOS App

This document describes the sample data used in tests, Previews, and manual verification.

---

## In-App Mock / Seed Data

When the app launches for the first time (empty database), it seeds the following data:

### Sources

| ID | Type | Display Name | Root Path |
|----|------|-------------|-----------|
| `claude-code::/Users/demo/.claude` | Claude Code | Claude Code (Global) | `/Users/demo/.claude` |
| `project::/Users/demo/Projects/my-app/.claude` | Project | my-app | `/Users/demo/Projects/my-app/.claude` |
| `openclaw::/Users/demo/.openclaw` | OpenClaw | OpenClaw (Global) | `/Users/demo/.openclaw` |

### Skills

| Name | Version | Source | Enabled |
|------|---------|--------|---------|
| commit | 1.2.0 | Claude Code (Global) | ✓ |
| review-pr | 2.0.1 | Claude Code (Global) | ✓ |
| debug | 1.0.0 | Claude Code (Global) | ✗ |
| test-runner | — | Claude Code (Global) | ✓ |
| deploy | 0.3.0 | my-app | ✓ |
| seed-db | — | my-app | ✗ |
| format | 3.1.0 | OpenClaw (Global) | ✓ |
| lint | 1.5.2 | OpenClaw (Global) | ✓ |

These values live in `AppStore.swift` under the `// MARK: - Sample / Preview data` section.

---

## Creating Local Skill Directories for Manual Testing

The following shell commands create a minimal skill directory layout that the app will discover and index on the next refresh (Cmd+R).

```bash
# Claude Code global skills
mkdir -p ~/.claude/skills/commit
echo '{"name":"commit","version":"1.0.0"}' > ~/.claude/skills/commit/skill.json

mkdir -p ~/.claude/skills/review-pr
echo '{"name":"review-pr","version":"2.0.0"}' > ~/.claude/skills/review-pr/skill.json

# Project skills (adjust path as needed)
mkdir -p ~/Projects/my-app/skills/deploy
echo '{"name":"deploy","version":"0.3.0"}' > ~/Projects/my-app/skills/deploy/skill.json

# OpenClaw global skills
mkdir -p ~/.openclaw/skills/format
echo '{"name":"format","version":"3.1.0"}' > ~/.openclaw/skills/format/skill.json
```

After creating these directories, press **Cmd+R** in the app to discover and index them.

---

## Security Scan Test Skills

The following creates a skill with a high-severity pattern to exercise the security scanner:

```bash
mkdir -p ~/tmp/skills/risky-skill
echo '{"name":"risky-skill","version":"1.0.0"}' > ~/tmp/skills/risky-skill/skill.json
echo '#!/bin/bash' > ~/tmp/skills/risky-skill/run.sh
echo 'rm -rf /tmp/test-dir' >> ~/tmp/skills/risky-skill/run.sh
```

Then add `~/tmp/skills` as a new **Project** source in the Sources tab.
After Refresh, the security report should show a HIGH finding for `risky-skill` (rule: `dangerous-rm`).

---

## Skill Manifest Format

Each skill directory must contain a `skill.json` or `manifest.json` at its root:

```json
{
  "name": "my-skill",
  "version": "1.0.0"
}
```

Both `name` and `version` are optional — missing values fall back to the directory name and `nil` respectively.

---

## Test Fixtures

Integration tests create all fixtures in `FileManager.default.temporaryDirectory` and clean up after each test run. No persistent local fixtures are required.

See `Tests/SkillPersistenceTests/OrchestrationIntegrationTests.swift` for the full set of programmatic fixtures.
