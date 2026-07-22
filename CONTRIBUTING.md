# Contributing

PRs welcome for distro support and config improvements.

## Commit Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(cli): add --json flag to status command
fix(profile): ralph setup.sh fails on Podman 6.0.1
docs: add FAQ entry for multi-profile usage
ci: add stale-tarball check on PR
```

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `ci`, `chore`, `style`.
Scopes: `cli`, `profile`, `security`, `installer`, `docs`, `ci`.

## Development

```sh
git clone https://github.com/CountElqyd/opencode-pod.git
cd opencode-pod
```

Run tests:

```sh
bats bats/
```

Run linting:

```sh
shellcheck opencode-pod install.sh lib/*.sh
```

Validate version consistency:

```sh
bash scripts/validate-version.sh
```

## Release Process

1. Ensure all tests pass and shellcheck is clean
2. Run `bash scripts/release.sh <version>` (e.g. `bash scripts/release.sh 0.3.0`)
3. Curate the auto-generated changelog entry when prompted
4. Push: `git push && git push --tags`
5. CI automatically creates the GitHub Release
