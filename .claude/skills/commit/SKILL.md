---
name: commit
description: Use when committing in the autocc repo. Enforces Conventional Commits, splits commits that mix concerns, writes imperative subjects, and stages only the relevant files. Trigger when the user says "commit", "make a commit", "stage and commit", or right after they accept a code change and the next step is to commit it.
---

# Commit conventions for autocc

This repo uses Conventional Commits + release-please. Commit messages on `main` drive the next version bump and the changelog, so format matters.

## Procedure

**1. Inspect the diff.**

Run `git status` and `git diff` (and `git diff --staged` if anything is already staged). Identify the *single* intent of the change.

If the diff covers multiple unrelated concerns — e.g. a bug fix in `DRTracker.lua` AND a refactor in `UI.lua` — STOP. Split them into separate commits using `git add <specific files>` per commit. Don't fold.

**2. Pick the type.**

| Type | Use for | Bump |
| --- | --- | --- |
| `feat` | new user-facing capability | minor |
| `fix` | bug fix | patch |
| `perf` | performance change | patch |
| `feat!` / `fix!` (with `BREAKING CHANGE:` footer) | breaks public behavior | major |
| `refactor` | code restructure with no behavior change | none |
| `chore` | tooling / housekeeping | none |
| `docs` | documentation only | none |
| `style` | whitespace, formatting | none |
| `test` | tests only | none |
| `build` | build system / dependencies | none |
| `ci` | CI/workflow files | none |

Types that don't bump also don't appear in the changelog.

**3. Write the subject.**

- Imperative: *add*, *fix*, *rename* — never past tense (*added*, *fixed*).
- Lowercase the first word after the type prefix.
- ≤ 70 chars. No trailing period.
- Optional scope in parens after the type: `feat(rotation):`, `fix(drtracker):`, `ci(release):`.

**4. Body (only if WHY is non-obvious).**

- Blank line after the subject.
- Wrap at ~72 chars.
- Explain *why*, not *what* — the diff says what. Mention constraints, prior incidents, user feedback that motivated the change.

**5. Stage only the files for this commit.**

Don't `git add -A` or `git add .` if the working tree contains unrelated changes. List the files explicitly.

**6. Never `--no-verify`.**

Don't skip hooks. If a hook fails, fix the underlying issue.

**7. Co-author trailer.**

If you're committing on the user's behalf, append a Claude Co-Authored-By trailer to the commit body (after a blank line):

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

## Examples

**Good:**

- `feat(rotation): score knockbacks below real CCs`
- `fix(drtracker): key state by unit token to avoid Midnight secret values`
- `feat!: drop classic compatibility`
- `chore: bump packager action to v2`
- `ci(release-please): grant pull-requests:write permission`

**Bad:**

- `Added a new feature.` — capitalized, past tense, no type, vague.
- `WIP` — not a commit message.
- `fix: stuff` — vague subject; reader can't tell what was fixed.
- `feat: redo the rotation algorithm and also fix a UI bug` — two concerns, split.
- `feat: add typhoon to db` — wrong type (this is data not a feature); use `chore(db): add typhoon` or absorb it into the change that needed it.

## When in doubt

- Not sure if a change is `feat` or `fix`? Did existing behavior break and now works correctly → `fix`. Did new behavior appear that wasn't there → `feat`.
- Not sure if a change is `feat` or `refactor`? Can a user observe the difference → `feat`. No → `refactor`.
- Not sure if a change is breaking? If anyone using the old API/UI path would have to change something → breaking. Otherwise → not.
