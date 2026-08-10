# zerobyte-nix

[![CI](https://github.com/utensils/zerobyte-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/utensils/zerobyte-nix/actions/workflows/ci.yml)
[![FlakeHub](https://img.shields.io/endpoint?url=https://flakehub.com/f/utensils/zerobyte/badge)](https://flakehub.com/flake/utensils/zerobyte)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Nix Flake](https://img.shields.io/badge/Nix-Flake-blue?logo=nixos&logoColor=white)](https://nixos.wiki/wiki/Flakes)
[![NixOS](https://img.shields.io/badge/NixOS-Module-5277C3?logo=nixos&logoColor=white)](https://nixos.org/)

Nix flake for [Zerobyte](https://github.com/nicotsx/zerobyte) - a self-hosted backup automation and management application powered by [Restic](https://restic.net/).

## Features

- Pure Nix flake packaging of Zerobyte
- NixOS module with systemd service
- Includes [shoutrrr](https://github.com/nicholas-fedor/shoutrrr) for notifications
- FUSE mount support on Linux

## Usage

### Add to your flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zerobyte-nix.url = "github:utensils/zerobyte-nix";
  };

  outputs = { self, nixpkgs, zerobyte-nix, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        zerobyte-nix.nixosModules.default
        {
          services.zerobyte = {
            enable = true;
            port = 4096;
            openFirewall = true;

            # Required. Zerobyte refuses to start without these.
            baseUrl = "https://backup.example.com";
            appSecretFile = "/run/agenix/zerobyte-app-secret";
          };
        }
      ];
    };
  };
}
```

### Use the overlay

```nix
{
  nixpkgs.overlays = [ zerobyte-nix.overlays.default ];
}
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Zerobyte service |
| `baseUrl` | string | *(required)* | Public URL including protocol; also sets cookie security |
| `appSecretFile` | path | *(required)* | File holding the 32–256 char `APP_SECRET`, loaded via systemd credentials |
| `package` | package | this flake's `zerobyte` | Package to use |
| `port` | int | `4096` | Port to listen on |
| `dataDir` | path | `/var/lib/zerobyte` | Data directory |
| `rcloneConfigDir` | path | `${dataDir}/rclone` | Writable directory for `rclone.conf` |
| `user` | string | `"zerobyte"` | User to run as |
| `group` | string | `"zerobyte"` | Group to run as |
| `createUser` | bool | `true` | Create the user/group automatically |
| `openFirewall` | bool | `false` | Open firewall port |
| `serverIp` | string | `"0.0.0.0"` | Bind address |
| `timezone` | string | `"UTC"` | Timezone used for schedules |
| `resticHostname` | string | `"zerobyte"` | Hostname recorded in restic snapshots |
| `trustProxy` | bool | `false` | Trust `X-Forwarded-*` headers (reverse proxy only) |
| `trustedOrigins` | list | `[]` | Additional trusted origins for CORS |
| `serverIdleTimeout` | int | `60` | Server idle timeout in seconds |
| `disableRateLimiting` | bool | `false` | Disable rate limiting (dev/testing only) |
| `fuse.enable` | bool | `true` | Enable FUSE support (Linux only) |
| `protectHome` | bool | `true` | Enable ProtectHome hardening |
| `extraReadWritePaths` | list | `[]` | Additional writable paths |
| `webhookAllowedOrigins` | list | `[]` | Origins notification destinations/webhooks may target |
| `extraPackages` | list | `[]` | Extra packages on the service PATH |
| `environment` | attrs | `{}` | Extra environment variables (merged last) |

> **Note:** values set via `environment` land in the world-readable Nix store.
> Use `appSecretFile` for the application secret, and let Zerobyte manage
> repository and cloud credentials in its own database.

## Development

```bash
# Enter development shell
nix develop

# Build the package
nix build

# Run integration tests (NixOS only)
nix build .#checks.x86_64-linux.integration
```

## Updating

This flake follows upstream releases (tags). To update to a new version:

```bash
# 1. Update version in flake.nix (both zerobyte-src URL and config.version)
#    zerobyte-src.url = "github:nicotsx/zerobyte/v0.42.0"
#    version = "0.42.0"

# 2. Update flake.lock
nix flake update zerobyte-src

# 3. Regenerate bun.nix (in devshell)
nix develop
update-bun-nix

# 4. Test and commit
nix build
git add flake.nix flake.lock bun.nix
git commit -m "chore: update to v0.42.0"
```

The `bun.nix` file must always match the upstream release referenced in `flake.lock`.

## License

This Nix flake packaging is licensed under the MIT License - see [LICENSE](LICENSE) for details.

Zerobyte itself is licensed under the [GNU Affero General Public License v3.0 (AGPL-3.0)](https://github.com/nicotsx/zerobyte/blob/main/LICENSE).

## Credits

- [Zerobyte](https://github.com/nicotsx/zerobyte) by nicotsx
- [Restic](https://restic.net/) backup program
- [shoutrrr](https://github.com/nicholas-fedor/shoutrrr) notification library (maintained fork of containrrr/shoutrrr)
