# AGENTS.md

Repository conventions for coding agents. Human-facing contributor docs live in
[docs/contributing.md](docs/contributing.md).

## Renovate configuration

Changes to `.github/renovate.json` go on a branch named **`renovate/reconfigure`**.

Renovate validates that branch on its next scheduled run and posts a status to it
([config validation](https://docs.renovatebot.com/config-validation/)). That is the
only automated check this file gets: no workflow reads `.github/renovate.json`, and
`gx.yml`'s `paths:` filter does not cover it. A bad edit merged to `main` is
otherwise invisible until Renovate silently stops maintaining something.

Validate locally before pushing:

```sh
sh script/renovate_validate.sh
```

Know what it does and does not catch. It rejects unknown options
(`Invalid configuration option: …`) and wrong types (`packageRules` not a list),
which is worth having. It does **not** check enum values — `"mode": "bogus"`
validates cleanly — and it cannot check whether a config is *correct*: a
`packageRules` entry pointing at the wrong Debian suite passes. Both times this
repo's deb pins silently went stale (#486, #532) the config was schema-valid.

So when changing which suites a pin resolves against, verify the resulting
`registryUrls` against the apt sources the image actually enables —
`debian:13-slim`'s own sources and `config/debian_12_bookworm.sources` — rather
than treating a green validator as confirmation.

## Renovate operating mode

`.github/renovate.json` sets `"mode": "full"`. Mend's hosted app injects
`mode=silent` as global config; the repository value overrides it, because `mode`
is a normal repository-level option merged after global config.

Do not remove it. Under `mode=silent` Renovate computes updates and then discards
them — no PRs, no branches, and no Dependency Dashboard. Lookup failures are
recorded but only ever rendered into a dashboard or PR body, so silent mode makes
them structurally unreachable: the failure surfaces as *nothing happening*.
Combined with `"automerge": true`, the two settings compose into "changes merge
with no PR trail", which reviewing either setting alone would not reveal.
