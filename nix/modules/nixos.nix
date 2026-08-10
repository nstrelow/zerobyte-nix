# NixOS module for Zerobyte backup management service
{ self }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.zerobyte;
in
{
  options.services.zerobyte = {
    enable = lib.mkEnableOption "Zerobyte backup management service";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.system}.zerobyte;
      defaultText = lib.literalExpression "pkgs.zerobyte";
      description = "The Zerobyte package to use.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "zerobyte";
      description = "User account under which Zerobyte runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "zerobyte";
      description = "Group under which Zerobyte runs.";
    };

    createUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to create the user and group automatically.
        Set to false if using an existing user account.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/zerobyte";
      description = "Directory to store Zerobyte data.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4096;
      description = "Port on which Zerobyte listens.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for Zerobyte.";
    };

    serverIp = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "IP address to bind the server to.";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
      description = "Timezone for scheduling backups.";
    };

    resticHostname = lib.mkOption {
      type = lib.types.str;
      default = "zerobyte";
      description = "Hostname used for restic operations.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables for Zerobyte.";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://backup.example.com";
      description = ''
        Public URL Zerobyte is reached on, including the protocol.
        Required: upstream refuses to start without it, and it is added to the
        trusted origins automatically. An https:// URL also marks session
        cookies as secure.
      '';
    };

    trustProxy = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Trust X-Forwarded-* headers from a reverse proxy.
        Enable only when Zerobyte is actually behind one, otherwise clients can
        spoof their source address.
      '';
    };

    appSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/agenix/zerobyte-app-secret";
      description = ''
        Path to a file containing the application secret (32-256 characters),
        used to encrypt credentials stored in Zerobyte's database.

        The file is passed to the service via systemd's LoadCredential, so it is
        read as root before privileges are dropped and never needs to be
        readable by the service user.

        Generate one with `openssl rand -hex 32`. Losing it makes every stored
        repository password unrecoverable.
      '';
    };

    rcloneConfigDir = lib.mkOption {
      type = lib.types.path;
      defaultText = lib.literalExpression ''"''${dataDir}/rclone"'';
      example = "/var/lib/zerobyte/rclone";
      description = ''
        Directory holding rclone.conf.

        Zerobyte *writes* this file when remotes are managed through the web UI,
        so it must be writable. To seed it with an existing configuration, copy
        the file into place before the service starts rather than pointing this
        at a read-only secret.
      '';
    };

    webhookAllowedOrigins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "http://ntfy.internal:2586" ];
      description = ''
        Origins that notification destinations and webhooks may target.

        Zerobyte refuses to create a notification destination whose origin is
        not listed here, so any self-hosted target (ntfy, gotify, a webhook
        receiver) must be added before it can be configured.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.nfs-utils ]";
      description = ''
        Extra packages to place on the service's PATH, for backends the
        bundled wrapper does not already cover.
      '';
    };

    trustedOrigins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "https://zerobyte.example.com"
        "https://backup.local"
      ];
      description = ''
        List of trusted origins for CORS.
        Required when running behind a reverse proxy.
        Each origin should include the protocol (https://).
      '';
    };

    serverIdleTimeout = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Server idle timeout in seconds.";
    };

    disableRateLimiting = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Disable rate limiting.
        Only recommended for development or testing environments.
      '';
    };

    fuse = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable FUSE mounting capabilities.
          Requires CAP_SYS_ADMIN and access to /dev/fuse.
          Enables NFS, SMB, and WebDAV volume mounts.
        '';
      };
    };

    protectHome = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable ProtectHome systemd security hardening.
        When true, /home, /root, and /run/user are inaccessible.
        Set to false if you need to backup home directories.
      '';
    };

    extraReadWritePaths = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
      default = [ ];
      example = [
        "/mnt/storage"
        "/backup"
      ];
      description = ''
        Additional paths the service can write to.
        Accepts both string paths and Nix store paths.
        Use this for custom repository locations outside of dataDir.
        Required because ProtectSystem=strict makes the filesystem read-only.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.appSecretFile != null;
        message = ''
          services.zerobyte.appSecretFile must be set: Zerobyte requires an
          APP_SECRET and exits on startup without one. Generate a secret with
          `openssl rand -hex 32` and store it outside the Nix store (e.g. with
          agenix or sops-nix).
        '';
      }
    ];

    services.zerobyte.rcloneConfigDir = lib.mkDefault "${cfg.dataDir}/rclone";

    users.users.${cfg.user} = lib.mkIf cfg.createUser {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
      description = "Zerobyte service user";
    };

    users.groups.${cfg.group} = lib.mkIf cfg.createUser { };

    # Ensure dataDir and data subdir exist with correct ownership
    # Note: Zerobyte also creates data/ via fs.mkdir, but tmpfiles ensures correct ownership
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/data 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/repositories 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/volumes 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/restic 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/restic/cache 0750 ${cfg.user} ${cfg.group} -"
      # rclone.conf holds cloud credentials in cleartext
      "d ${cfg.rcloneConfigDir} 0700 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.zerobyte = {
      description = "Zerobyte backup management service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      path = cfg.extraPackages;

      environment = {
        NODE_ENV = "production";
        PORT = toString cfg.port;
        SERVER_IP = cfg.serverIp;
        SERVER_IDLE_TIMEOUT = toString cfg.serverIdleTimeout;
        RESTIC_HOSTNAME = cfg.resticHostname;
        BASE_URL = cfg.baseUrl;
        TRUST_PROXY = lib.boolToString cfg.trustProxy;
        # systemd exposes credentials under $CREDENTIALS_DIRECTORY (%d)
        APP_SECRET_FILE = "%d/app-secret";
        ZEROBYTE_DATABASE_URL = "${cfg.dataDir}/data/zerobyte.db";
        ZEROBYTE_REPOSITORIES_DIR = "${cfg.dataDir}/repositories";
        ZEROBYTE_VOLUMES_DIR = "${cfg.dataDir}/volumes";
        RESTIC_CACHE_DIR = "${cfg.dataDir}/restic/cache";
        RCLONE_CONFIG_DIR = cfg.rcloneConfigDir;
        MIGRATIONS_PATH = "${cfg.package}/lib/zerobyte/assets/migrations";
        APP_VERSION = cfg.package.version;
        TZ = cfg.timezone;
      }
      // lib.optionalAttrs (cfg.trustedOrigins != [ ]) {
        TRUSTED_ORIGINS = lib.concatStringsSep "," cfg.trustedOrigins;
      }
      // lib.optionalAttrs (cfg.webhookAllowedOrigins != [ ]) {
        WEBHOOK_ALLOWED_ORIGINS = lib.concatStringsSep "," cfg.webhookAllowedOrigins;
      }
      // lib.optionalAttrs cfg.disableRateLimiting {
        DISABLE_RATE_LIMITING = "true";
      }
      // cfg.environment;

      serviceConfig = {
        LoadCredential = [ "app-secret:${toString cfg.appSecretFile}" ];
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${cfg.package}/bin/zerobyte";
        Restart = "on-failure";
        RestartSec = 5;

        WorkingDirectory = cfg.dataDir;

        # Capabilities
        # - CAP_SYS_ADMIN: Required for FUSE mounts
        # - CAP_DAC_READ_SEARCH: Required to read restricted directories
        # - CAP_DAC_OVERRIDE: Required to write to directories not owned by service user
        AmbientCapabilities =
          lib.optional cfg.fuse.enable "CAP_SYS_ADMIN"
          ++ lib.optional (!cfg.protectHome) "CAP_DAC_READ_SEARCH"
          ++ lib.optional (cfg.extraReadWritePaths != [ ]) "CAP_DAC_OVERRIDE";
        CapabilityBoundingSet =
          lib.optional cfg.fuse.enable "CAP_SYS_ADMIN"
          ++ lib.optional (!cfg.protectHome) "CAP_DAC_READ_SEARCH"
          ++ lib.optional (cfg.extraReadWritePaths != [ ]) "CAP_DAC_OVERRIDE";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = cfg.protectHome;
        # Disable when capabilities are needed
        NoNewPrivileges = !cfg.fuse.enable && cfg.protectHome && cfg.extraReadWritePaths == [ ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = !cfg.fuse.enable;
        LockPersonality = true;
        MemoryDenyWriteExecute = false; # Required for bun/V8
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        PrivateMounts = !cfg.fuse.enable;

        # Allow write access to data directory. rcloneConfigDir is listed
        # separately because it may be placed outside dataDir, and Zerobyte
        # rewrites rclone.conf whenever remotes change.
        ReadWritePaths = [
          cfg.dataDir
          cfg.rcloneConfigDir
        ]
        ++ (map toString cfg.extraReadWritePaths);
      }
      # State directory (only set when using default dataDir)
      // lib.optionalAttrs (cfg.dataDir == "/var/lib/zerobyte") {
        StateDirectory = "zerobyte";
        StateDirectoryMode = "0750";
      }
      # FUSE device access
      // lib.optionalAttrs cfg.fuse.enable {
        DeviceAllow = [ "/dev/fuse rw" ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
