[Русская версия →](README.ru.md) · [AGENTS.md →](AGENTS.md)

# mierukeen

**mieru + sing-box for Keenetic routers with Entware.**

An [xkeen](https://github.com/Skrill0/XKeen)-style distribution but with a different stack:
- **[mieru](https://github.com/enfein/mieru)** — obfuscated SOCKS5 transport (client)
- **[sing-box](https://github.com/SagerNet/sing-box)** — routing engine: REDIRECT/TPROXY inbounds, geoip/geosite, domain & CIDR rules, Clash API
- **`mkeen`** — CLI on top of both: lifecycle + profiles + routes + NDMS policy binding

Target hardware: **Keenetic Titan (KN-1810)** and any MT7621-based Keenetic (mipsel softfloat). CI also builds an arm64 tarball for other models.

## Install

On the router (Entware already installed):

```sh
curl -fsSL https://raw.githubusercontent.com/adobrotvorskiy/mierukeen/main/scripts/install.sh | sh
```

**Before starting**:

1. In the Keenetic web UI, open **Network rules → Policies** (or **Access profiles** on newer firmware) and create a policy named `Mierukeen`.
2. **Inside that policy, tick at least one internet connection** (usually your main WAN). Without this, NDMS answers `Refused` to DNS queries from devices in the policy and they never get any internet — sing-box is never reached. Traffic itself will still flow through mieru thanks to our iptables rules; this ticked WAN only makes Keenetic allow DNS.
3. Attach the devices that should go through mieru to this policy (My Networks & Wi-Fi → device → pin to policy).
4. Edit the mieru profile on the router: `vi /opt/etc/mkeen/profiles/default/mieru.json` — fill in your mieru server (`REPLACE_ME_*` fields).
5. Bind mkeen to the policy (the installer tries this automatically):

```sh
mkeen ndms detect       # look up the policy named Mierukeen, save its mark
mkeen ndms status       # show current binding
```

6. Start:

```sh
mkeen -start
mkeen -status
mkeen -log
```

Verify from a device pinned to the policy in the UI:

```
curl https://ifconfig.me   # should print the mieru server's IP
```

Devices **not** in the policy keep using your normal WAN unchanged — that's the point of the `xkeen`-style integration.

## Profiles

```sh
mkeen profile list           # active one is marked with *
mkeen profile add work       # cloned from default
mkeen profile use work
mkeen profile show           # current config
mkeen profile rm work
```

Each profile is a directory under `/opt/etc/mkeen/profiles/<name>/` containing `mieru.json` and `singbox.json`. The active one is a symlink `/opt/etc/mkeen/active`.

## NDMS policy

```sh
mkeen ndms detect [name]   # resolve mark by policy name (default: Mierukeen)
mkeen ndms bind <mark>     # set manually if auto-detect didn't work
mkeen ndms unbind          # unhook (mkeen stops intercepting)
mkeen ndms status          # current binding
```

The policy name is stored in `/opt/etc/mkeen/policy_name`, the mark in `/opt/etc/mkeen/policy_mark`. After any change — `mkeen -restart`.

## Routes

```sh
mkeen route add youtube.com       proxy   # domain -> mieru
mkeen route add 1.2.3.0/24        direct  # subnet -> direct
mkeen route add ads.example.com   block   # -> dropped

mkeen route list
mkeen route del youtube.com
mkeen route reload                         # = mkeen -restart
```

Rules are written straight into the active profile's `singbox.json` and tagged with `"_mkeen_user": true` so they can be removed later. They are prepended to `route.rules`, so they take priority over the bundled `geoip-ru` / `geosite-category-ru` defaults.

For anything more complex, edit `singbox.json` by hand — see the [sing-box docs](https://sing-box.sagernet.org/configuration/route/).

## Remote control via Karing / yacd

The default `singbox.json` ships with Clash API enabled on `127.0.0.1:9090` with placeholder secret `CHANGE_ME_CLASH_SECRET`. Expose it on the LAN interface, set your own secret, and point Karing / yacd / metacubexd at it as if it were a local client. Routes can be flipped live without editing configs.

```json
"experimental": {
  "clash_api": {
    "external_controller": "192.168.1.1:9090",
    "secret": "YOUR_LONG_SECRET"
  }
}
```

## How it works

```
LAN-client -> Keenetic
  -> NDMS sets fwmark $POLICY_MARK on packets from devices in policy Mierukeen
  -> TCP: nat    PREROUTING -m connmark --mark $POLICY_MARK -p tcp -j MIERUKEEN
                  MIERUKEEN: bypass private nets + REDIRECT --to-ports 7895
  -> UDP: mangle PREROUTING -m connmark --mark $POLICY_MARK -p udp -j MIERUKEEN
                  MIERUKEEN: bypass private nets + TPROXY --on-port 7896
                                                       |
                                                  sing-box
                                                       |
                                            +----------+----------+
                                            v          v          v
                                       mieru-out    direct      block
                                       (SOCKS5
                                        :1080)
                                            |
                                            v
                                       mieru server
```

- **NDMS Policy integration (xkeen-style):** Keenetic itself attaches a policy-specific fwmark to packets from devices in the policy. `mkeen ndms detect` pulls the mark from the local NDMS REST API at `http://localhost:79/rci/show/ip/policy` (the same source the web UI uses) and persists it to `/opt/etc/mkeen/policy_mark`.
- Only traffic with that mark is intercepted — other LAN devices are untouched.
- TCP path uses `nat REDIRECT` and UDP path uses `mangle TPROXY` on separate ports. The split is deliberate: on Linux 4.9 (Keenetic) TPROXY for TCP doesn't reliably deliver packets to a local listener, so we mirror xkeen's "Mixed_1" pattern.
- sing-box decides per-rule: RU geoip/geosite → direct, ads → block, everything else → SOCKS5 to mieru.
- mieru obfuscates the SOCKS traffic and forwards it to your server.

Coexists with xkeen: you can keep both policies active in parallel (XKeen → xray, Mierukeen → mieru) and shuffle devices between them from the UI.

## Repository layout

```
opt/
  etc/
    init.d/S99mkeen                # Entware init
    ndm/netfilter.d/mierukeen.sh   # re-applies iptables after NDMS rebuilds
    mkeen/profiles/default/        # default profile
      mieru.json
      singbox.json
  sbin/mkeen                       # CLI
scripts/
  install.sh                       # installer
build/
  versions.env                     # pinned mieru / sing-box versions
.github/workflows/release.yml      # cross-build -> GitHub Release
```

## Releases

GitHub Actions cross-builds for every `vX.Y.Z` tag and publishes two assets per release: `mierukeen-vX.Y.Z-mipsle-softfloat.tar.gz` and `…-arm64.tar.gz`. They are reachable at [GitHub Releases](https://github.com/adobrotvorskiy/mierukeen/releases) and pulled by `install.sh` via `releases/download/vX.Y.Z/…`.

## License

MIT (mierukeen sources). The bundled mieru and sing-box binaries are governed by their own licenses.
