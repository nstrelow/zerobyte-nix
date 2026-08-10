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

    # v0.41 moved the healthcheck under /api (returns {"status":"ok"})
    result = machine.succeed("curl -s http://localhost:4096/api/healthcheck")
    assert '"status":"ok"' in result or '"ok"' in result, f"Healthcheck failed: {result}"

    # The secret must reach the service via systemd credentials, not the store
    machine.succeed("systemctl show zerobyte.service -p LoadCredential | grep -q app-secret")

    # Migrations must resolve to the packaged assets/migrations directory
    machine.succeed("test -f /var/lib/zerobyte/data/zerobyte.db")

    machine.log("Zerobyte integration test passed!")
  '';
}
