# AGENTS.md

Operational notes for AI coding agents working on this repo. Follows the
[agents.md](https://agents.md) convention. Humans should read
[README.md](README.md) first.

## TL;DR

- Distribution that packages **mieru** (SOCKS5 transport) + **sing-box**
  (routing engine) + a thin shell CLI (`mkeen`) for **Keenetic routers
  with Entware**. Inspired by [xkeen](https://github.com/Skrill0/XKeen).
- Binaries are cross-compiled in CI (GitHub Actions). The repo itself is
  pure shell + JSON + YAML; **never commit prebuilt binaries**.
- Target hardware: Keenetic Titan (KN-1810), MT7621 → `linux/mipsle`
  with `GOMIPS=softfloat`. CI also builds `linux/arm64`.

## Repo layout

```
opt/                                  # mirrors /opt on the router
  sbin/mkeen                          # main shell CLI
  etc/
    init.d/S99mkeen                   # Entware init script (POSIX sh)
    ndm/netfilter.d/mierukeen.sh      # NDMS post-rebuild iptables hook
    mkeen/profiles/default/
      mieru.json                      # client config template
      singbox.json                    # routing rules template
scripts/install.sh                    # curl|sh installer (POSIX sh)
build/versions.env                    # pinned mieru + sing-box versions
.github/workflows/release.yml         # cross-build + release pipeline
README.md, README.ru.md               # user docs (EN + RU)
```

Files outside this tree are documentation or CI scaffolding.

## Setup

Nothing local is required to **change shell/JSON/YAML** — the toolchain
lives in CI. To verify your changes:

```sh
sh -n opt/sbin/mkeen
sh -n opt/etc/init.d/S99mkeen
sh -n opt/etc/ndm/netfilter.d/mierukeen.sh
sh -n scripts/install.sh
python -c "import json; json.load(open('opt/etc/mkeen/profiles/default/mieru.json'))"
python -c "import json; json.load(open('opt/etc/mkeen/profiles/default/singbox.json'))"
python -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"
```

These four `sh -n` + JSON/YAML loads are the de-facto test suite.

## Release flow

1. Edit + commit on `main`. Push triggers a build-only CI run.
2. Tag `vX.Y.Z` and push the tag. CI cross-builds, packs
   `mierukeen-vX.Y.Z-<arch>.tar.gz`, and publishes them as a GitHub
   Release. `scripts/install.sh` resolves the latest release via the
   GitHub REST API and downloads the tarball directly.
3. **Do not** bump upstream versions in `.github/workflows/release.yml`
   — only in `build/versions.env`. CI reads it.

## Deploying to the live router

The repo's project owner runs one Keenetic Titan at `192.168.1.1`, and
the GitHub repo is reachable over the open internet, so end users (and
the owner) install/update with:

```sh
mkeen update                              # on the router itself
# or
curl -fsSL https://raw.githubusercontent.com/adobrotvorskiy/mierukeen/main/scripts/install.sh | sh
```

For agent-driven live diagnostics there's an SSH path via the Linux VM
at `192.168.1.91` (jumphost; the router refuses scp because it has no
`sftp-server`). Pipe-via-ssh works:

```sh
# Push a single patched file to the router from a workstation:
cat localfile | ssh aleks@192.168.1.91 \
  'sshpass -p "$ROUTER_PASS" ssh -o StrictHostKeyChecking=no root@192.168.1.1 \
   "cat > /opt/sbin/mkeen && chmod +x /opt/sbin/mkeen"'
```

Never hard-code credentials in committed files. The router root password
and the GitHub token live in the project owner's `.env.personal`.

## Hard constraints

- **POSIX `sh` only** in `opt/`, `scripts/`, `.github/`. The router runs
  BusyBox `ash`. No `bash`-isms — no `[[ ... ]]`, no `<<<`, no arrays,
  no `pipefail`. CI lint with `sh -n`.
- **LF line endings.** A `.gitattributes` enforces this; if you generate
  new script files on Windows, verify `git diff` doesn't show a sea of
  `^M`. CRLF scripts silently fail on the router.
- **No binaries in git.** mieru and sing-box are fetched and cross-built
  by CI from pinned upstream tags. Test artifacts live in `out/` and are
  `.gitignore`d.
- **Never weaken router security.** The Clash API default secret is a
  placeholder — keep it placeholder in committed configs. Do not change
  the default to bind on `0.0.0.0` without an explicit secret.

## Coding conventions

- Indentation: 4 spaces in shell, 2 spaces in JSON / YAML.
- Function naming in shell: `snake_case`. CLI subcommands map to
  `cmd_<name>` functions inside `opt/sbin/mkeen`.
- Comments in user-facing scripts: **Russian** (audience is RU-speaking
  router admins). Comments in CI YAML and AGENTS.md: **English**.
- Log lines from the runtime always start with `[mkeen] ` so they're
  greppable in mixed Entware logs.
- iptables additions go through `iptables -C ... 2>/dev/null || iptables
  -A ...` so the init script is idempotent on re-run.

## NDMS / Keenetic quirks (won't bite you again if you remember them)

- `/root` is **read-only** on Keenetic. mieru wants `$HOME/.config/...`
  → the init script exports `HOME=/opt/etc/mkeen/.mieru-state` first.
- NDMS rebuilds iptables on every UI change. Without
  `/opt/etc/ndm/netfilter.d/mierukeen.sh`, our chain silently disappears
  after the next interface flap.
- **TPROXY for TCP doesn't work on Linux 4.9** (Keenetic kernel) —
  packets are marked but never delivered to the local socket. xkeen
  works around this with "Mixed_1": TCP through `nat REDIRECT`, UDP
  through `mangle TPROXY`. We do the same. Don't try to "simplify" back
  to pure TPROXY — it will break on real hardware.
- An NDMS Policy with **no internet connection ticked** causes NDMS to
  reply `Refused` to DNS for devices in that policy. README + installer
  both warn about this; don't drop the warning.

## Out of scope for agents

- Touching `mieru` or `sing-box` upstream sources. Bump
  `build/versions.env` only.
- Changing the GitLab mirror or pushing tags there — GitLab is a passive
  mirror. All real releases happen on GitHub.

## PR / commit conventions

- Single-purpose commits. Subject line: imperative, present tense,
  ≤ 72 chars (`fix: …`, `ci: …`, `docs: …` prefixes optional).
- Reference the live-debug evidence in the body when fixing
  router-specific bugs ("found via tcpdump on br0: …"). This is how the
  Linux-4.9 TPROXY fix and the DNS-Refused finding were captured.
