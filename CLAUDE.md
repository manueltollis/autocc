# autocc

WoW addon — Mythic+ AoE CC rotation helper. Single package, Lua only, no external dependencies.

## Releases

Automated via [release-please](https://github.com/googleapis/release-please).

- Push or merge to `main` → release-please updates an open *Release PR* with the cumulative changelog and the next proposed version.
- Merging that Release PR → release-please creates a `vX.Y.Z` tag, publishes a GitHub Release, and the BigWigs packager attaches the built zip.
- The current version lives in `.release-please-manifest.json` — that's the source of truth, not the `## Version:` line in `autocc.toc` (the packager substitutes the git tag at build time).
- Manual `git tag vX.Y.Z && git push --tags` still works as a hotfix fallback via `.github/workflows/release.yml`.

## Commit messages

Every commit on `main` **must** follow [Conventional Commits](https://www.conventionalcommits.org). release-please reads them to pick the next bump and to build the changelog.

```
<type>(<optional scope>): <subject>

<optional body>

<optional footer>
```

| Type | Use for | Version bump |
| --- | --- | --- |
| `feat` | new user-facing feature | minor |
| `fix` | bug fix | patch |
| `perf` | performance improvement | patch |
| `feat!` / `fix!` / `BREAKING CHANGE:` footer | breaking change | major |
| `refactor`, `chore`, `docs`, `style`, `test`, `build`, `ci` | internal-only | none |

Subject:

- Imperative — *add party tracker*, not *added party tracker*.
- Lowercase after the type prefix.
- ≤ 70 chars, no trailing period.
- One change per commit. Don't fold a fix and an unrelated refactor into one.

Examples:

- `feat(rotation): score knockbacks below real CCs`
- `fix(drtracker): key state by unit token to avoid Midnight secret values`
- `feat!: drop classic compatibility`
- `chore: bump packager action to v2`

## Branches and tags

- Work on feature branches; merge into `main` via squash so a clean Conventional Commit ends up on `main`.
- Don't tag manually unless cutting a hotfix that bypasses release-please. Tag format is `vX.Y.Z`. Prereleases: `vX.Y.Z-alpha.N` / `-beta.N` / `-rc.N` (packager marks them as prerelease automatically).

## Code layout

- `Core.lua` — bootstrap, pub/sub, slash commands, SavedVariables defaults.
- `Database.lua` — canonical AoE CC spell list with DR category, duration, cooldown.
- `PartyTracker.lua` — per-member cooldowns via `UNIT_SPELLCAST_SUCCEEDED`.
- `DRTracker.lua` — per-unit-token DR state via `UNIT_AURA` snapshots.
- `Rotation.lua` — greedy scoring algorithm that picks the next N CCs.
- `UI.lua` — the in-game icon row.
- `Config.lua` — the management window.

## WoW Midnight (12.0+) gotchas

These three patterns will silently break in M+ / boss encounters — avoid them:

- `COMBAT_LOG_EVENT_UNFILTERED` is forbidden in restricted contexts. Use `UNIT_SPELLCAST_SUCCEEDED` and `UNIT_AURA` instead.
- `UnitGUID()` for hostile units returns an opaque *secret value* that can't be used as a Lua table key. Key per-target state by unit token (`target`, `nameplate3`).
- `GetSpellInfo` / `GetSpellTexture` globals were removed in 11.0 — use `C_Spell.GetSpellTexture` / `C_Spell.GetSpellInfo` (the latter returns a table now).
