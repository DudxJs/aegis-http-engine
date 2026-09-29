# Aegis HTTP Engine

**HTTP spy protection for Roblox executors.** Detects, neutralizes and monitors HTTP spies (request loggers) so your scripts' network traffic stays private.

![version](https://img.shields.io/badge/version-1.1.0-blue) ![license](https://img.shields.io/badge/license-MIT-green) ![platform](https://img.shields.io/badge/platform-Roblox-red)

---

## Quick start

One line. Protection is active as soon as it loads.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DudxJs/aegis-http-engine/refs/heads/main/Loader.lua"))()
```

Then, whenever you want:

```lua
Aegis:HttpSpy(false) -- disable
Aegis:HttpSpy(true)  -- enable
```

> Load Aegis **first**, before any other script, so no spy gets a chance to hook in ahead of it.

### Pin a version (recommended for production)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DudxJs/aegis-http-engine/refs/tags/v1.1.0/Loader.lua"))()
```

---

## Features

- Detects Lua-closure hooks and hooks made through `hookfunction` / `hookmetamethod`
- Detects hooks disguised with `newcclosure()` to evade `islclosure()`-based checks
- Recovers the original HTTP functions and neutralizes the spy
- Continuous integrity checks: catches spies loaded **after** Aegis
- Blocks attempts to hook protected HTTP functions (including `replaceclosure`, `hookfunc`, `detour_function`)
- Routes HTTP `__namecall` methods to the original functions, even if other scripts hook `__namecall`
- Cleans spy logs from memory
- Heuristic deep scan for spy-like functions (HTTP, hook-related and spy-GUI constant matching)
- Safe request helpers that bypass hooks
- Event system, configurable actions, runtime on/off

Covered: `game:HttpGet`, `game:HttpPost`, `game:GetObjects`, `HttpService:GetAsync`, `HttpService:PostAsync`, `HttpService:RequestAsync`, `request`, `http_request`, `http.request`, `syn.request`.

---

## API

Every method works with `:` or `.` (`Aegis:HttpSpy(true)` and `Aegis.HttpSpy(true)`).

| Method | Description |
|---|---|
| `Aegis:HttpSpy(state?)` | `true`/`false` enables/disables. Without an argument, returns the current state. |
| `Aegis:Toggle()` | Flips the state and returns it. |
| `Aegis:IsEnabled()` | Returns `true` if protection is active. |
| `Aegis:IsDetected()` | Returns `true` if a spy was ever detected. |
| `Aegis:GetStatus()` | Table with `Version`, `Enabled`, `Detected`, `Detections`. |
| `Aegis:GetDetections()` | List of detection records (`Target`, `Reason`, `Time`). |
| `Aegis:OnDetect(fn, replay?)` | Registers a callback. Returns `{ Disconnect }`. Past detections are replayed unless `replay == false`. |
| `Aegis:Configure(tbl)` | Updates settings at runtime. |
| `Aegis:Scan()` | Runs an integrity check now. Returns `true` if something was found. |
| `Aegis:DeepScan()` | Runs the GC heuristic scan. Returns the number of suspicious functions. |
| `Aegis:Restore()` | Re-applies the original HTTP functions. |
| `Aegis.Safe.Get(url, headers?)` | Hook-proof GET. Returns `body, statusCode`. |
| `Aegis.Safe.Post(url, body, headers?)` | Hook-proof POST. Returns `body, statusCode`. |
| `Aegis.Version` | Version string. |

### Example

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DudxJs/aegis-http-engine/refs/heads/main/Loader.lua"))()

Aegis:OnDetect(function(info)
    warn("Spy detected:", info.Target, "-", info.Reason)
end)

local body, status = Aegis.Safe.Get("https://example.com/api")
print(status, body)

Aegis:HttpSpy(false)
```

More in [`examples/`](examples).

---

## Configuration

Set `getgenv().AegisConfig` **before** loading (or use `Aegis:Configure`):

```lua
getgenv().AegisConfig = {
    Action = "Kick",              -- "Notify" (default) | "Kick" | function(info)
    KickMessage = "Spy detected.",
    Silent = false,
    ToggleKey = Enum.KeyCode.RightControl,
}
loadstring(game:HttpGet("https://raw.githubusercontent.com/DudxJs/aegis-http-engine/refs/heads/main/Loader.lua"))()
```

| Option | Default | Description |
|---|---|---|
| `Action` | `"Notify"` | What to do on detection: log/event only, kick the player, or run your own function. |
| `KickMessage` | `"Aegis: HTTP spy detected."` | Message used with `Action = "Kick"`. |
| `Silent` | `false` | Disables console output. |
| `OnDetect` | `nil` | Callback `function(info)` registered at load time. |
| `RecheckInterval` | `2` | Seconds between integrity checks. |
| `CleanupInterval` | `3` | Seconds between spy-log cleanups. |
| `TrustOriginalFunctionCheck` | `true` | Treat a `getoriginalfunction()` mismatch as a hook. |
| `TrustExecutorClosureCheck` | `true` | Treat `isexecutorclosure()`/`checkclosure() == true` as a hook. Catches hooks disguised with `newcclosure()`. Disable only if your executor false-positives on this. |
| `ReportOnMetaMismatch` | `false` | Report when `__namecall` is replaced outside Aegis wrappers. |
| `DeepScan` | `true` | Heuristic GC scan. |
| `DeepScanInterval` | `20` | Seconds between deep scans. |
| `DeepScanReport` | `false` | `false` = console warning only (other legitimate scripts can match the heuristic). |
| `ToggleKey` | `nil` | Optional hotkey to toggle protection. |

---

## Requirements

Executor functions: `clonefunction`, `hookfunction`, `hookmetamethod`, `newcclosure`, `getrawmetatable`.
Optional (extra detection): `getgc`, `getconstants`, `getupvalues`, `getoriginalfunction`, `isexecutorclosure`.

If a required function is missing, Aegis loads a harmless stub (`Aegis.Supported == false`) and your script keeps running.

## Compatibility

| Executor | Status |
|---|---|
| _To be filled after testing_ | |

## Privacy & security

- Aegis does **not** download or execute any other code.
- No telemetry, no external requests. The only network activity is your own calls to `Aegis.Safe.*`.
- Single file, readable source.

## Limitations

No Lua-level protection is absolute. Anyone with executor-level access can eventually bypass client-side defenses. Aegis raises the cost of doing so, but it is not a guarantee. Use it as one layer of your defense.

## Versioning

[Semantic Versioning](https://semver.org). See [CHANGELOG.md](CHANGELOG.md). Pin a tag in production; `main` may change.

## License

[MIT](LICENSE)
