# Contributing

PRs welcome for distro support and config improvements.

## Development

```sh
git clone https://github.com/.../opencode-podman-setup.git
cd opencode-podman-setup
```

Run tests:

```sh
bats bats/
```

Run linting:

```sh
shellcheck opencode-pod install.sh lib/*.sh
```

## Release Checklist

- [ ] All tests pass: `bats bats/`
- [ ] shellcheck clean
- [ ] Manual test on Arch, Fedora, Ubuntu 24.04
- [ ] Tag release: `git tag v1.0.0 && git push --tags`
