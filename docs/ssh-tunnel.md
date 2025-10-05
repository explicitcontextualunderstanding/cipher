# Reverse SSH Tunnels and autossh

This guide describes how to create a persistent reverse SSH tunnel from a
device (e.g. macOS) to a remote host (e.g. Jetson) and how to manage it using
`autossh` and macOS `launchd` (or systemd on Linux).

Quick recipe (macOS):

1. Create a basic reverse forward using `ssh`:

   ```bash
   ssh -N -R 127.0.0.1:3001:127.0.0.1:3000 user@jetson
   ```

2. Use `autossh` to maintain the tunnel (reconnect on failure):

   ```bash
   autossh -M 0 -N -o ExitOnForwardFailure=yes -R 127.0.0.1:3001:127.0.0.1:3000 user@jetson
   ```

3. On macOS, create a LaunchAgent plist to manage `autossh` automatically
   (see `scripts/com.cipher.autossh.plist` for an example).

Health checks and diagnostics

- Check `/tmp/autossh.log` or your LaunchAgent logs.

- On the remote Jetson, monitor `ss -ltnp | grep :3001` and `journalctl -u sshd`.

Security note: prefer key-based SSH authentication and restrict allowed
commands in `authorized_keys` where feasible.
