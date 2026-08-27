# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

When releasing, rename the `Unreleased` section to `[x.y.z] - YYYY-MM-DD`; the
release workflow uses that section as the GitHub Release notes.

## [Unreleased]

### Added

- `ruby-skills` CLI: `init`, `install`, `list`, `remove`, `update`, `outdated`,
  `sync`, `validate`, `build`, `info`, `publish`, `config`, `login`, `logout`,
  `whoami` and `version`.
- `Skillfile` / `Skillfile.lock` with dependency resolution, including
  transitive dependencies.
- Registry client with browser-based login and API token storage.

### Changed

- Minimum supported Ruby version is now 3.2 (required by Bundler 4).
