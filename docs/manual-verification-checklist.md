# Manual Verification Checklist — SkillManager macOS App

This checklist walks through the end-to-end flow from source discovery to security scanning.
Run it after any significant change or before a release.

---

## Prerequisites

- macOS 13.0+
- Run `swift build --target SkillManagerApp` — build must succeed with no errors.
- Optionally create sample skill directories (see `docs/sample-data.md`).

---

## 1. First Launch

| # | Step | Expected |
|---|------|----------|
| 1.1 | Launch the app (first run, no DB) | App opens, no crash. Sources panel shows mock/seeded data. |
| 1.2 | Check `~/Library/Application Support/SkillManager/skills.db` | File exists after first launch. |
| 1.3 | Quit and re-launch | App re-loads persisted state from DB (not mock data). |

---

## 2. Source Discovery

| # | Step | Expected |
|---|------|----------|
| 2.1 | Press **Cmd+R** (Refresh All Sources) | Spinner shows; app runs `SourceDiscoveryService.detectSources()` → scans → indexes. |
| 2.2 | Create `~/.claude/skills/my-skill/skill.json` with `{"name":"my-skill","version":"1.0.0"}` | After Refresh, `my-skill` appears in skill list under Claude Code source. |
| 2.3 | Create `~/.openclaw/skills/oc-skill/skill.json` | After Refresh, `oc-skill` appears under OpenClaw source. |
| 2.4 | Add a source manually via Sources tab → **+** button | Source appears in list; Refresh indexes its skills. |
| 2.5 | Delete a source via Sources tab → swipe/right-click Delete | Source and all its skills are removed from the list. |

---

## 3. Skill Inventory

| # | Step | Expected |
|---|------|----------|
| 3.1 | Open Skills tab | All indexed skills are listed with name, version, source badge. |
| 3.2 | Type in the search box | List filters in real-time by name. |
| 3.3 | Filter by source in the sidebar | Only skills from that source are shown. |
| 3.4 | Filter by enabled/disabled | Correct subset shown. |
| 3.5 | Click a skill | Detail panel shows name, version, path, source, indexed date. |
| 3.6 | Verify detail file info block | Shows root path / primary document / last modified / file count when metadata is available. |
| 3.7 | Use quick actions in detail panel | **Open Folder**, **Open Document** (prefers `SKILL.md`), and **Open README** all open expected targets. |
| 3.8 | Remove `SKILL.md` or `README.md` from a sample skill and refresh | Detail panel shows localized fallback/empty-state text instead of broken file preview. |
| 3.9 | Shrink window width below 900 px | Skills view switches to compact pane mode (List/Detail segmented control) and remains usable. |
| 3.10 | In compact mode, switch between List/Detail | Selection is preserved and detail panel remains readable without overlap. |
| 3.11 | In compact mode, switch source filter from sidebar | Pane automatically returns to **List** view to avoid stale detail context. |

---

## 4. Skill Enable / Disable

| # | Step | Expected |
|---|------|----------|
| 4.1 | Toggle a Claude Code or Project skill on/off | `isEnabled` flag flips immediately in UI; persisted to DB. |
| 4.2 | Re-launch app | Enabled state is preserved. |
| 4.3 | Attempt to toggle an OpenClaw skill | UI should prevent or show an error (OpenClaw does not support enable/disable). |

---

## 5. Sync Plan

| # | Step | Expected |
|---|------|----------|
| 5.1 | Create a `DesiredStateProfile` via the SyncEngine API (or future sync UI) with one skill disabled | `SyncEngine.plan()` returns a `SyncAction` of kind `.disable`. |
| 5.2 | Apply the plan (`SyncEngine.apply()`) | Skill is disabled in DB; audit log entry is created with `.succeeded` outcome. |
| 5.3 | Create a profile with conflicting versions across sources | `SyncPlan.conflicts` is non-empty; `isApplicable` is `false`. |

---

## 6. Security Scan

| # | Step | Expected |
|---|------|----------|
| 6.1 | Add a skill with `rm -rf` in a `.sh` file | After Refresh (security scan runs post-index), `latestSecurityReport` contains a HIGH finding for that skill. |
| 6.2 | Add a skill with `curl ... \| sh` | MEDIUM or HIGH finding is reported. |
| 6.3 | Trust a finding (SecurityService.trustFinding) | Finding disappears from the next scan's report; remediation log records `.trusted`. |
| 6.4 | Disable a flagged skill (SecurityService.disableSkill) | Skill is disabled; remediation log records `.disabled`. |
| 6.5 | Add skill to ignore list; re-scan | That (skillId, ruleId) pair no longer appears in report. |

---

## 7. End-to-End Orchestration

| # | Step | Expected |
|---|------|----------|
| 7.1 | Press Cmd+R from a cold state (no registered sources) | App discovers default sources, indexes skills, runs security scan in one pass. |
| 7.2 | Introduce a high-severity pattern mid-session; press Cmd+R | Security report is updated; new finding appears. |
| 7.3 | Remove a skill directory from disk; press Cmd+R | Skill disappears from inventory after re-index (replaceAll for that source). |
| 7.4 | `AppStore.orchestrationWarnings` is non-nil | Any non-fatal errors during the pipeline are surfaced as warnings (check Xcode console or future warning banner). |
| 7.5 | While refresh is running, observe top overlay | Pipeline progress message appears (refresh/security stages) and clears automatically when done. |
| 7.6 | Make one source fail (invalid path), then open Sources | Failed source shows error text and Retry button; Retry Failed action is enabled in toolbar. |

### 7A. Pipeline flow visualization (stage-by-stage)

| # | Step | Expected |
|---|------|----------|
| 7A.1 | Trigger Refresh and keep the app in foreground | Stage text appears in order: `refresh` → `source-scan` → `sync-plan` → `sync-apply` → `security-scan`. |
| 7A.2 | During each stage transition | Status text updates only once per stage boundary (no random jump backwards). |
| 7A.3 | Pipeline success | Final success/idle state is shown and transient progress UI is cleared automatically. |
| 7A.4 | Pipeline partial failure (one source fails) | Global pipeline still completes; warning state is visible and contains failed source summary. |

### 7B. Retry recovery (failed source -> successful re-index)

| # | Step | Expected |
|---|------|----------|
| 7B.1 | Set one source path to a non-existent folder and run Refresh | Source enters failed state with actionable error message. |
| 7B.2 | Fix the source path to a valid folder and press Retry Failed | Source state changes from failed → running → ready. |
| 7B.3 | Confirm skills under that source | Skills are re-indexed and visible without requiring app restart. |
| 7B.4 | Re-run Retry Failed when no failed sources remain | Action is disabled or no-op with clear UI feedback (no stale error banner). |

---

## 8. Accessibility & Keyboard

| # | Step | Expected |
|---|------|----------|
| 8.1 | In Sources tab press **Cmd+N** | Add Source sheet opens. |
| 8.2 | In Sources tab with failed source press **Cmd+Shift+R** | Retry Failed is triggered (or disabled when no failed source exists). |
| 8.3 | Press **Esc** while status banner is visible | Banner dismisses. |
| 8.4 | Navigate primary actions with keyboard (Tab/Shift+Tab) | Focus moves predictably between Refresh, Retry Failed, Add Source, and row actions. |
| 8.5 | With a source row focused, press Space/Enter on Retry button | Retry action is invoked once and row state updates (no duplicate trigger). |
| 8.6 | During active refresh, traverse controls via keyboard | Disabled actions are skipped or announced as disabled; focus does not get trapped. |

---

## 9. Build Verification

```bash
# Must produce no errors (warnings are acceptable):
swift build --target SkillManagerApp

# Run unit + integration tests:
swift test
```

All tests must pass before marking the release as ready.

---

## 10. Localization & Branding Verification (zh-Hant / en)

| # | Step | Expected |
|---|------|----------|
| 10.1 | Set macOS language to Traditional Chinese and launch app | Navigation, toolbar, empty states, detail labels, and action buttons show zh-Hant text. |
| 10.2 | Switch macOS language to English and relaunch app | Same UI surfaces switch to English text with no mixed-language rows. |
| 10.3 | Open Sources + Settings + Skills pages in both locales | No visible hard-coded fallback English remains in the covered UI scope. |
| 10.4 | Build app via `scripts/build_app.sh` and open `dist/SkillManagerApp.app` | App icon is non-default (not blank white app icon) in Finder/Dock. |
| 10.5 | If Finder still shows old icon, refresh cache (`touch dist/SkillManagerApp.app`) and reopen folder | Updated icon appears after cache refresh. |

### Finder icon cache quick commands

```bash
# preferred lightweight refresh
touch dist/SkillManagerApp.app
killall Finder

# if Dock still shows stale icon
killall Dock
```

---

## Notes

- The `refreshAll()` path in `AppStore` is the primary integration point.
  It calls `OrchestrationService.runFullPipeline()` which runs all four stages.
- Sync plan computation and apply are separate from the refresh flow and must be
  triggered explicitly (no UI yet — use the `computeSyncPlan` / `applyPendingSyncPlan`
  methods on `AppStore`).
- Security scan runs automatically at the end of every `refreshAll()`.
  It can also be triggered standalone via `AppStore.runSecurityScan()`.
