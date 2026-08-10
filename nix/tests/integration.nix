# NixOS VM integration test for Zerobyte
{ pkgs, self }:

pkgs.testers.nixosTest {
  name = "zerobyte-integration";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ self.nixosModules.default ];

      # A store path is fine here because this is a throwaway test VM; in real
      # deployments the secret must come from agenix/sops-nix instead.
      services.zerobyte = {
        enable = true;
        openFirewall = true;
        baseUrl = "http://localhost:4096";
        appSecretFile = pkgs.writeText "zerobyte-test-secret" "0123456789abcdef0123456789abcdef0123456789abcdef";
      };

      # Add curl for healthcheck test
      environment.systemPackages = [ pkgs.curl ];

      # Ensure the test VM has enough resources
      virtualisation = {
        memorySize = 1024;
        diskSize = 2048;
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("zerobyte.service")
    machine.wait_for_open_port(4096)

    # v0.41 moved the healthcheck under /api (returns {"status":"ok"}).
    # Retry rather than hitting it once: the listener opens before the router
    # is ready, which a KVM-less (TCG-emulated) runner reliably loses the race
    # against, yielding an empty reply.
    machine.wait_until_succeeds("curl -sf http://localhost:4096/api/healthcheck", timeout=120)
    result = machine.succeed("curl -s http://localhost:4096/api/healthcheck")
    assert '"status":"ok"' in result or '"ok"' in result, f"Healthcheck failed: {result}"

    # The secret must reach the service via systemd credentials, not the unit
    # environment (which is world-readable in the store). systemd redacts the
    # LoadCredential value itself, so assert on the environment instead: the
    # service must reference the credential path and never a literal secret.
    # systemd expands %d before exposing Environment, so this asserts on the
    # resolved credentials directory rather than the literal specifier.
    env = machine.succeed("systemctl show zerobyte.service -p Environment")
    assert "APP_SECRET_FILE=/run/credentials/zerobyte.service/app-secret" in env, (
        f"credential not wired: {env}"
    )
    assert "APP_SECRET=" not in env.replace("APP_SECRET_FILE=", ""), (
        f"secret leaked into the unit environment: {env}"
    )

    # Reaching this point at all proves the secret was readable: upstream
    # calls process.exit(1) at startup when APP_SECRET is missing or invalid.

    # Migrations must resolve to the packaged assets/migrations directory
    machine.succeed("test -f /var/lib/zerobyte/data/zerobyte.db")

    machine.log("Zerobyte integration test passed!")
  '';
}
