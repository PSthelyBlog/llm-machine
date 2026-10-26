# The tty1 session's sign-in hand-over and the Claude Code policy: the phone page answers
# only at its secret address, accepts only a code for the sign-in on screen, and types it
# into Claude's window. Run with: nix build .#checks.x86_64-linux.session
{ pkgs, machine }:
pkgs.testers.runNixOSTest {
  name = "session";

  node.specialArgs = { inherit (machine) inputs; };
  node.pkgsReadOnly = false;

  nodes.machine = {
    imports = [ machine.nixosModules.core ];
    llm-machine.user = "dev";
    # The session's programs, without starting it on tty1 (there is no internet here).
    llm-machine.session.autologin = false;
    boot.loader.grub.enable = false;
  };

  testScript = ''
    import re

    machine.wait_for_unit("multi-user.target")
    # The relay asks the routing table for its own address; give it a route to ask.
    machine.succeed("ip route replace default dev eth1")

    state = "S7aTe_-x"
    url = f"https://claude.com/cai/oauth/authorize?code=true&client_id=x&state={state}"
    # Claude's window, standing in: every line typed into it lands in /tmp/typed.
    machine.succeed("su - dev -c 'tmux new-session -d -s main -n claude \"cat > /tmp/typed\"'")
    machine.succeed(f"su - dev -c 'echo \"{url}\" > /tmp/url'")
    machine.succeed("su - dev -c 'setsid llm-login-relay 8765 /tmp/url /tmp/relay > /dev/null 2>&1 &'")
    machine.wait_until_succeeds("test -s /tmp/relay")
    address = machine.succeed("cat /tmp/relay").strip()
    assert re.fullmatch(r"http://[0-9.]+:8765/[0-9a-f]{32}", address), address

    def http(args):
        return machine.succeed(f"curl -s -o /tmp/body -w '%{{http_code}}' {args}")

    with subtest("the page is only at its secret address"):
        assert http("http://127.0.0.1:8765/") == "404"
        assert http("http://127.0.0.1:8765/" + "0" * 32) == "404"
        assert http(address) == "200"
        machine.succeed(f"grep -F 'state={state}' /tmp/body")

    with subtest("codes that don't belong to this sign-in are refused"):
        assert http(f"-d code=hello%20world%21 {address}") == "400"
        assert http(f"-d code=abc%23earlier {address}") == "400"
        # A code is typed before the reply is sent, so nothing has been typed.
        machine.succeed("test ! -s /tmp/typed")

    with subtest("a code is typed into Claude's window, with the state filled in"):
        assert http(f"-d code=abc123%23{state} {address}") == "200"
        machine.wait_until_succeeds(f"grep -qx 'abc123#{state}' /tmp/typed")
        assert http(f"-d code=+def456+ {address}") == "200"
        machine.wait_until_succeeds(f"grep -qx 'def456#{state}' /tmp/typed")

    with subtest("the secret address goes away with the relay"):
        machine.succeed("pkill -TERM -f '[l]lm-login-relay'")
        machine.wait_until_fails("test -e /tmp/relay")

    with subtest("the Claude policy gates osctl and core edits in every mode"):
        policy = "/etc/claude-code/managed-settings.json"
        machine.succeed(f"jq -e '.permissions.defaultMode == \"auto\"' {policy}")
        machine.succeed(f"jq -e '.permissions.ask | index(\"Bash(osctl try *)\")' {policy}")
        machine.succeed(f"jq -e '.permissions.ask | index(\"Bash(osctl upgrade *)\")' {policy}")
        machine.succeed(f"jq -e '.permissions.ask | index(\"Edit(//etc/llm-machine/core/**)\")' {policy}")
  '';
}
