# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com), versioning follows [SemVer](https://semver.org).

## [1.1.0]

### Added
- Protection for `game:GetObjects()`, another method that fetches content over the network.
- `TrustExecutorClosureCheck` config option: detects hooks disguised with `newcclosure()` so they read as native C-closures to `islclosure()`/`iscclosure()`. Uses `isexecutorclosure()`/`checkclosure()` instead, which is not fooled by that disguise on most executors.
- Deep scan now checks three independent constant categories (HTTP methods, hook-related globals, spy GUI strings) and flags a function when at least two categories match, catching GUI-based spies that deep scan previously missed.
- Deep scan no longer skips functions that already look like C-closures, so `newcclosure()`-disguised hooks are scanned too.

### Changed
- Renamed `StrictOriginalCheck` to `TrustOriginalFunctionCheck`, now **enabled by default**. A mismatch from `getoriginalfunction()` is treated as a hook unconditionally, since on essentially every executor that implements it, a mismatch only happens when something hooked the target.
- `pickOriginal()` (used to recover the real function from a hook's upvalues) now also excludes executor-generated closures from its candidates, so it can no longer mistakenly pick another disguised hook as "the original."

### Fixed
- Hooks wrapped in `newcclosure()` (a known evasion technique against `islclosure()`-based detection) are now detected and recovered, instead of being silently reinstalled as if they were legitimate.

## [1.0.0]

### Added
- Public API: `Aegis:HttpSpy(state)`, `Toggle`, `IsEnabled`, `IsDetected`, `GetStatus`, `GetDetections`, `OnDetect`, `Configure`, `Scan`, `DeepScan`, `Restore`, `Safe.Get`, `Safe.Post`.
- Runtime enable/disable without reloading.
- Continuous integrity checks (catches late-loaded spies).
- Snapshot-based detection (closure type, source, identity), including `newcclosure` hooks.
- Detection of global replacement (e.g. `request = function ...`).
- Original recovery filtered by function name.
- Protection for `replaceclosure`, `hookfunc`, `detour_function`.
- Heuristic GC deep scan.
- Configurable `Action` (`Notify`, `Kick`, custom function) and event callbacks with replay.
- Executor support check with a harmless stub fallback.

### Changed
- Removed the remote `punish.lua` execution. Aegis no longer downloads or runs external code.
