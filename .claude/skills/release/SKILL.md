---
name: release
description: Use for autocc release work — managing the open release-please PR, deciding the next version bump, cutting a hotfix release, or diagnosing a failed packager run. Trigger when the user says "release", "cut a release", "bump version", "tag", "ship it", or asks about the open release PR.
---

# Releases in autocc

autocc uses [release-please](https://github.com/googleapis/release-please) for automated versioning + [BigWigs packager](https://github.com/BigWigsMods/packager) for the zip build.

## Normal release flow

1. Conventional commits accumulate on `main` over a series of merges.
2. The `release-please` workflow (`.github/workflows/release-please.yml`) keeps an open PR titled `chore(main): release X.Y.Z` containing:
   - The proposed next version (computed from commit types since the last release).
   - The cumulative changelog (only `feat`, `fix`, `perf`, breaking-change commits appear).
3. When ready to ship: merge that PR. release-please will tag `vX.Y.Z`, publish a GitHub Release, and the `package` job in the same workflow runs the BigWigs packager which attaches `autocc-vX.Y.Z.zip` to the Release.

## Deciding the bump

Don't pick the bump manually — let conventional commits decide:

- Only `chore`, `docs`, `style`, `test`, `build`, `ci`, `refactor` since last release → no release PR opens (no user-visible change).
- One or more `fix` / `perf` → patch bump (`0.1.0` → `0.1.1`).
- Any `feat` → minor bump (`0.1.0` → `0.2.0`), even if there are also fixes.
- Any `feat!` / `fix!` / `BREAKING CHANGE:` footer → major bump (`0.1.0` → `1.0.0`).

If the proposed version in the release PR is wrong, the fix is upstream — the commits weren't typed correctly. Either amend them or push a follow-up that escalates with a `feat!` to force a major bump.

## Hotfix release (bypass the PR)

Only for emergencies where you can't wait for the normal flow:

```bash
git tag v0.1.5
git push --tags
```

This triggers the standalone `release.yml` workflow (BigWigs packager only) and skips release-please entirely.

**Important:** after a manual tag, update `.release-please-manifest.json` to match (`"." : "0.1.5"`) and commit. Otherwise release-please will propose the wrong next version on its next run.

## Source of truth

- `.release-please-manifest.json` — current released version.
- `## Version:` in `autocc.toc` — **not** authoritative. The packager rewrites it from the git tag during build. Leave the toc's version at any placeholder value (`0.1.0` is fine forever).

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Packager exits with `403 Resource not accessible by integration` | Workflow job missing `permissions: contents: write` | Add to the job |
| Release PR doesn't open after merging conventional commits | Either no qualifying commits (only `chore`/`docs`/etc.) or release-please config is broken | Check `release-please-config.json` and last commit types |
| Tag created but no zip on the Release | Packager job didn't trigger | Likely a `GITHUB_TOKEN` recursive-trigger issue. The `release-please.yml` workflow runs the packager in the same workflow specifically to avoid this — confirm you're not relying on a separate workflow firing |
| Release-please proposes wrong version | Manifest is out of sync (e.g. after a manual hotfix) | Edit `.release-please-manifest.json` and commit |
| Two PRs open at once after force-pushing | release-please got confused about state | Close both, let it reopen one on the next push |

## Don't

- Don't tag manually if release-please is running normally — it'll cause version drift.
- Don't edit the release PR body manually — release-please overwrites it on every run.
- Don't merge the release PR without checking the proposed version matches your expectation.
