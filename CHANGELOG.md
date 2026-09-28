# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com), versioning follows [SemVer](https://semver.org).

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
