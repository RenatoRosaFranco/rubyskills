# ruby-skills

CLI for packaging, publishing, and installing Ruby engineering knowledge.

A published skill can be recovered on another machine **byte for byte**,
identified by `namespace/name`, version, and SHA-256.

Site and registry: [https://rubyskills.org](https://rubyskills.org)

```
Machine A                         Registry                      Machine B
─────────                         ────────                      ─────────
ruby-skills build
ruby-skills publish  ─────────►  rails/request-specs
                                 1.4.2
                                 SHA-256 = A       ─────────►  ruby-skills install

                                                               SHA-256(B) == A
```

## Requirements

- Ruby 3.2 or later
- [Thor](https://github.com/rails/thor) `~> 1.3` (pulled in by the gem)

## Install

From a checkout:

```bash
bundle install
ruby -Ilib bin/ruby-skills version
```

Once published:

```bash
gem install ruby-skills
ruby-skills version
```

## Quick start

Publish:

```bash
ruby-skills init rails/request-specs
cd request-specs
# edit skill.yml, SKILL.md, and references/
ruby-skills validate
ruby-skills build
ruby-skills login
ruby-skills publish
```

Install (no token required):

```bash
ruby-skills info rails/request-specs
ruby-skills install rails/request-specs
```

The skill lands in `.ruby-skills/rails/request-specs/<version>/`.
`install` verifies the SHA-256 of the raw `.rskill` **before** extracting
anything. A checksum mismatch writes no files.

Published versions are **immutable**. To change knowledge, bump `version`
in `skill.yml` and publish again.

## Anatomy of a skill

```
request-specs/
├── skill.yml
├── SKILL.md
└── references/
    └── http.md
```

The canonical id is `namespace/name`. The version lives in `skill.yml` and
follows RubyGems versioning. `build` writes a deterministic gzip+tar named
`namespace-name-version.rskill` (for example
`pkg/rails-request-specs-1.4.2.rskill`).

## Auth

`ruby-skills login` opens a browser (gcloud / Heroku style), you approve
the CLI, then the token is stored locally. `--token rsk_...` skips the
browser (CI, headless machines).

```bash
ruby-skills login
ruby-skills whoami
ruby-skills logout
```

```text
username: johndoe
email:    johen@doe.com
```

Credentials live under XDG, never in `config.yml`:

| File | Mode | Contents |
| --- | --- | --- |
| `~/.config/ruby-skills/config.yml` | `0600` | registry origin |
| `~/.config/ruby-skills/credentials.yml` | `0600` | token `rsk_...` |

The directory is created `0700`. Resolution order:

- Registry: `RUBY_SKILLS_REGISTRY_URL` → `config.yml` → `https://rubyskills.org`
- Token: `RUBY_SKILLS_API_TOKEN` → `credentials.yml`

`RUBY_SKILLS_NO_BROWSER=1` prints the login URL without launching a browser.
`logout` only prints `Logged out.` when a token was actually stored.

```bash
ruby-skills config registry https://staging.rubyskills.org
```

## Commands

| Command | Auth | What it does |
| --- | --- | --- |
| `help [COMMAND]` | no | List commands or describe one |
| `version` | no | Print the gem version |
| `init [NAME]` | no | Scaffold a skill (`namespace/name`) |
| `validate [PATH]` | no | Validate a local skill |
| `build [PATH]` | no | Write a `.rskill` to `pkg/` |
| `config [KEY] [VALUE]` | no | Get or set the registry origin |
| `login [--token]` | browser or token | Save `credentials.yml` |
| `logout` | — | Remove the saved token |
| `whoami [--json]` | token | Print the logged-in username and email |
| `info SKILL` | no | Public registry metadata |
| `publish [PATH]` | token | Upload an immutable version |
| `install [SKILL] [--save] [--version]` | no | Skillfile graph, or one registry skill |
| `outdated [SKILL] [--json]` | no | Report newer registry versions (read-only) |
| `sync [--agent] [--dry-run]` | no | Mirror locked skills into detected agents |
| `list [--json]` | no | Read `Skills.lock` (legacy) |
| `update [SKILL]` | — | Skillfile + registry (install ≠ update) |
| `remove SKILL` | — | Flat `.ruby-skills/NAME` or `--save` |

`help` is the default command. `-h` and `--help` are aliases.

## What is not in this cycle yet

`list` still belongs to the old Skillfile / `Skills.lock` / editor-adapter
path. It does **not** operate on the canonical
`.ruby-skills/namespace/name/version` layout that `install` writes.

`sync` reads that canonical layout and the project lockfile, then writes
disposable symlinks into detected agent directories (`.claude/skills`,
`.codex/skills`, `.cursor/skills`, `.vscode/skills`). It does not copy
credentials or rewrite unrelated agent configuration.

The VS Code extension lives in
[`rubyskills-plugins/rubyskills-vscode`](../rubyskills-plugins/rubyskills-vscode).
It still reads `ruby-skills list --json` from the legacy lockfile.

## Development

```bash
bundle install
bundle exec rspec
ruby -Ilib bin/ruby-skills help
```

Library code is under `lib/ruby_skills/`. The executable is `bin/ruby-skills`.

## Releasing

Publishing uses [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/)
(OIDC). There is no RubyGems API key in GitHub.

One-time setup:

1. Create a GitHub Environment named `release` on this repository.
2. On RubyGems.org, add a pending trusted publisher for `ruby-skills`:
   [Create pending trusted publisher](https://rubygems.org/profile/oidc/pending_trusted_publishers/new)
   - Repository owner: `renatofranco`
   - Repository name: `ruby-skills`
   - Workflow filename: `push_gem.yml`
   - Environment: `release`

Then, for each version:

1. Bump `RubySkills::VERSION` in `lib/ruby_skills/version.rb`.
2. Commit the bump.
3. Tag and push:

```bash
git tag v0.2.0
git push origin v0.2.0
```

The `Push gem` workflow builds the gem and uploads it to RubyGems.org.

## License

MIT
