# QShare control API + `qshare` CLI

A guide for humans **and agents** to drive QShare (send/receive files with nearby
Android devices) from the command line or over HTTP.

## Prerequisites
- The **QShare.app must be running** (it hosts the API). It's a menu-bar app;
  launching it once is enough — it keeps running in the background.
- The API is **localhost-only** (`http://127.0.0.1:47821`), bound to `127.0.0.1`.
- Every request needs a bearer token, read from `~/.config/qshare/token`
  (created by the app on first launch; file mode `0600`).

## CLI (recommended for agents)

```bash
qshare list [--json]                 # devices currently visible for sending
qshare send <file>... --to <name>    # send file(s); blocks until done
qshare status [--json]               # active/recent transfers
qshare --help
```

- `--json` prints raw JSON (parse this). Without it, output is human-formatted.
- `--to` takes a device **name** (from `qshare list`) or its `id`.
- `qshare send` **blocks until the transfer completes**, exits **0** on success,
  non-zero on failure (prints `✗ Failed: <reason>` to stderr).
- Paths may be relative or use `~`; they're resolved to absolute before sending.

### Agent recipe
1. `qshare list --json` → parse the array, pick a device by `name`.
2. `qshare send /abs/path/file.jpg --to "<name>" --json` → check `.ok == true`.
   The response also includes `.pin` (the verification code shown on the phone).

## HTTP API (for other languages / direct use)

Base URL `http://127.0.0.1:47821`. Header on every request:
`Authorization: Bearer $(cat ~/.config/qshare/token)`

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/health` | — | `{"ok":true}` |
| GET | `/devices` | — | `[{"name","id","type","trusted"}]` |
| GET | `/transfers` | — | `[{"title","device","percent","phase"}]` |
| POST | `/send` | `{"paths":["/abs/f1",…],"to":"<name|id>"}` (or `"path":"/abs/f"`) | blocks, then `{"ok":bool,"pin":string?,"error":string?}` |

`type` is one of `phone` / `tablet` / `computer` / `unknown`.

### Examples
```bash
TOKEN=$(cat ~/.config/qshare/token)
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:47821/devices

curl -s -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{"paths":["/Users/me/pic.jpg"],"to":"Noise'\''s phone"}' \
     http://127.0.0.1:47821/send
# → {"ok":true,"pin":"8374","error":null}
```

### Status codes & errors
- `200` success · `400` bad request body · `401` missing/invalid token ·
  `403` bad `Host` header · `404` unknown path · `502` send failed.
- `/send` error strings: `device_not_found`, `no_readable_files`, `timeout`,
  or an engine message (e.g. `Declined`, `Connection lost`).

## Behaviour notes
- **Sending needs the receiver to accept** (a PIN prompt on the phone) unless the
  device is in QShare's *trusted* list — then it auto-accepts.
- Device `id`s can change between sessions; prefer matching by `name`.
- `/send` reuses the app's send flow, so an in-progress CLI send also shows in
  the app window.
- If `qshare` reports it can't reach the app, launch QShare.app and retry.
