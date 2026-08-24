# ruby-skills

Package manager for installing, updating, removing, and sharing AI development skills in Ruby and Rails projects.

Skills are declared in a `Skillfile`, copied into `.ruby-skills/`, recorded in `Skills.lock`, and exposed to editors through adapters (Claude, Codex, Cursor, VS Code).

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
```

## Quick start

```bash
ruby-skills init
```

That creates a `Skillfile` and a `.ruby-skills/` directory. Declare skills in the Skillfile:

```ruby
# Skillfile

skill "rails-performance",
  github: "username/rails-performance"

skill "local-review",
  path: "../skills/local-review",
  version: "0.1.0"
```

Each `skill` needs exactly one source: `github:` (`owner/repo`) or `path:`. `version:` is optional.

Then install:

```bash
ruby-skills install
ruby-skills install rails-performance
```

## Commands

| Command | Description |
| --- | --- |
| `ruby-skills init` | Create `Skillfile` and `.ruby-skills/` |
| `ruby-skills install [SKILL]` | Install one skill, or every skill in the Skillfile |
| `ruby-skills list` | Print installed skills from `Skills.lock` |
| `ruby-skills list --json` | Same data as JSON (`-j`) |
| `ruby-skills update [SKILL]` | Update one skill, or every installed skill |
| `ruby-skills remove SKILL` | Remove an installed skill |
| `ruby-skills version` | Print the gem version |
| `ruby-skills help [COMMAND]` | Command help |

Human-readable list:

```
Installed skills:

rails-performance                   0.1.0
rails-security                      0.2.0
```

Machine-readable list (`ruby-skills list --json`):

```json
{
  "skills": [
    {
      "name": "rails-performance",
      "version": "0.1.0",
      "source": "github:username/rails-performance"
    }
  ]
}
```

An empty lockfile prints `{"skills":[]}`. Editors should consume `--json` instead of parsing the table.

## Project files

| Path | Role |
| --- | --- |
| `Skillfile` | Declared skills (Ruby DSL) |
| `Skills.lock` | Installed name, version, and source |
| `.ruby-skills/` | Local copies of installed skills |

`Skillfile` and `Skills.lock` are gitignored in this repo because they are per-project workspace files created by `init` / `install`.

## Editor plugins

Install still notifies Claude, Codex, Cursor, and VS Code adapters so the skill is visible in those tools.

The VS Code extension lives in [`rubyskills-plugins/rubyskills-vscode`](../rubyskills-plugins/rubyskills-vscode). It wraps this CLI and loads the sidebar from `ruby-skills list --json`.

## Development

```bash
bundle install
ruby -Ilib bin/ruby-skills help
```

Library code is under `lib/ruby_skills/`. The executable is `bin/ruby-skills`.

## Releasing

Publishing uses [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) (OIDC). There is no RubyGems API key in GitHub.

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
