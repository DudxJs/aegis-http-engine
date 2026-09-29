--[[
    Aegis HTTP Engine
    Version : 1.1.0
    License : MIT
    Repo    : https://github.com/DudxJs/aegis-http-engine

    Detects and neutralizes HTTP spies (request loggers) in Roblox executors.

    Usage:
        loadstring(game:HttpGet("https://raw.githubusercontent.com/DudxJs/aegis-http-engine/refs/heads/main/Loader.lua"))()

        Aegis:HttpSpy(false)   -- disable
        Aegis:HttpSpy(true)    -- enable

    Optional: set getgenv().AegisConfig = { ... } BEFORE loading to customize.
]]

if getgenv().Aegis then return getgenv().Aegis end

local VERSION = "1.1.0"

----------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------
local DEFAULTS = {
    Action = "Notify",            -- "Notify" | "Kick" | function(info)
    KickMessage = "Aegis: HTTP spy detected.",
    Silent = false,               -- true = no console output
    OnDetect = nil,               -- optional callback function(info)

    RecheckInterval = 2,          -- seconds between integrity checks
    CleanupInterval = 3,          -- seconds between spy-log cleanups

    -- Detection tuning. Both default to true: a hook disguised with newcclosure()
    -- (so islclosure() reports false) is still caught by these two checks.
    TrustOriginalFunctionCheck = true, -- treat any getoriginalfunction() mismatch as a hook
    TrustExecutorClosureCheck = true,  -- treat isexecutorclosure()/checkclosure() == true as a hook
    ReportOnMetaMismatch = false,      -- report when __namecall is replaced outside Aegis wrappers

    DeepScan = true,              -- heuristic GC scan for spy-like functions
    DeepScanInterval = 20,
    DeepScanReport = false,       -- false = console warning only

    ToggleKey = nil,              -- e.g. Enum.KeyCode.RightControl
}

local cfg = {}
for k, v in pairs(DEFAULTS) do cfg[k] = v end
do
    local user = getgenv().AegisConfig
    if type(user) == "table" then
        for k, v in pairs(user) do cfg[k] = v end
    end
end

local function log(msg)
    if not cfg.Silent then warn("[Aegis] " .. msg) end
end

----------------------------------------------------------------------
-- EXECUTOR SUPPORT CHECK
----------------------------------------------------------------------
do
    local env, genv = getfenv(), getgenv()
    local missing = {}
    for _, n in ipairs({ "clonefunction", "hookfunction", "hookmetamethod", "newcclosure", "getrawmetatable" }) do
        if type(env[n]) ~= "function" and type(genv[n]) ~= "function" then
            missing[#missing + 1] = n
        end
    end
    if #missing > 0 then
        log("Executor not supported. Missing: " .. table.concat(missing, ", "))
        local noop = function() return false end
        local stub = setmetatable({ Version = VERSION, Supported = false }, { __index = function() return noop end })
        getgenv().Aegis = stub
        return stub
    end
end

local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local API = { Version = VERSION, Supported = true }

local enabled = true
local detected = false
local kicked = false
local detections = {}
local listeners = {}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
local function try(f, ...)
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

local islc = islclosure or is_l_closure or function(f) return try(debug.info, f, "s") ~= "[C]" end
local isc = iscclosure or is_c_closure or function(f) return not islc(f) end
local isExec = isexecutorclosure or checkclosure or is_synapse_function or function() return false end

local realHookFunction = clonefunction(hookfunction)
local realHookMetamethod = clonefunction(hookmetamethod)
local mySource = try(debug.info, 1, "s")

local originals = {}
local HTTP_METHODS = {
    HttpGet = true,
    HttpPost = true,
    GetAsync = true,
    PostAsync = true,
    RequestAsync = true,
    GetObjects = true, -- game:GetObjects(assetId) also fetches over the network
}

-- Allows both Aegis:Method(x) and Aegis.Method(x)
local function norm(a, ...)
    if a == API then return ... end
    return a, ...
end

----------------------------------------------------------------------
-- DETECTION REPORTING
----------------------------------------------------------------------
local function runAction(info)
    local action = cfg.Action
    if type(action) == "function" then
        task.spawn(action, info)
    elseif action == "Kick" and not kicked then
        kicked = true
        pcall(function() Players.LocalPlayer:Kick(cfg.KickMessage) end)
    end
end

local function report(target, reason)
    if not enabled then return end
    detected = true

    local info = { Target = target, Reason = reason, Time = os.time() }
    detections[#detections + 1] = info
    if #detections > 50 then table.remove(detections, 1) end

    log(("%s - %s"):format(target, reason))

    if type(cfg.OnDetect) == "function" then task.spawn(cfg.OnDetect, info) end
    for _, fn in ipairs({ table.unpack(listeners) }) do task.spawn(fn, info) end
    runAction(info)
end

----------------------------------------------------------------------
-- UPVALUE COLLECTION / ORIGINAL RECOVERY
----------------------------------------------------------------------
local function deepCollect(fn, visited, depth)
    local found = {}
    if depth > 6 or type(fn) ~= "function" then return found end
    if visited[fn] then return found end
    visited[fn] = true

    local function process(v)
        if type(v) == "function" then
            found[v] = true
            for f in pairs(deepCollect(v, visited, depth + 1)) do found[f] = true end
        elseif type(v) == "table" and depth < 4 then
            for _, tv in pairs(v) do
                if type(tv) == "function" then
                    found[tv] = true
                    for f in pairs(deepCollect(tv, visited, depth + 2)) do found[f] = true end
                end
            end
        end
    end

    pcall(function()
        local ups = getupvalues(fn)
        if ups then for _, v in pairs(ups) do process(v) end end
    end)
    pcall(function()
        for i = 1, 50 do
            local a, b = getupvalue(fn, i)
            if a == nil and b == nil then break end
            process(a)
            if b ~= nil then process(b) end
        end
    end)
    pcall(function()
        for i = 1, 50 do
            local name, val = debug.getupvalue(fn, i)
            if not name then break end
            process(val)
        end
    end)

    return found
end

-- Picks the most likely original function among a spy's upvalues (matches by name).
local function pickOriginal(prev, expectedName)
    local fallback
    for f in pairs(deepCollect(prev, {}, 0)) do
        local looksNative = isc(f) and not islc(f)
        local looksGenuine = not (cfg.TrustExecutorClosureCheck and isExec(f))
        if looksNative and looksGenuine then
            local n = try(debug.info, f, "n")
            if n == expectedName then return f end
            if n == nil or n == "" then fallback = fallback or f end
        end
    end
    return fallback
end

local function recoverOriginal(fn, name, short)
    if type(fn) ~= "function" then return nil, false end
    local hooked = false

    -- Basic check: a genuine Lua-closure hook.
    if islc(fn) then hooked = true end

    -- newcclosure() disguise check: some spies wrap their hook in newcclosure()
    -- specifically so islclosure()/iscclosure() report it as a native C function.
    -- isexecutorclosure() / checkclosure() see through that disguise on most
    -- executors, because it flags anything the executor itself generated,
    -- regardless of how it presents to islclosure().
    if cfg.TrustExecutorClosureCheck and isExec(fn) then
        hooked = true
        log("Executor-generated closure detected on " .. name .. " (possible newcclosure() disguised hook)")
    end

    local restored
    pcall(function() restored = getoriginalfunction(fn) end)
    if restored and type(restored) == "function" and isc(restored) then
        if restored ~= fn then
            -- getoriginalfunction() found a different underlying function than what's
            -- currently installed. On virtually every executor that implements it,
            -- that only happens when something hooked the target - including
            -- newcclosure()-disguised hooks that fooled the checks above.
            if cfg.TrustOriginalFunctionCheck then hooked = true end
            pcall(realHookFunction, fn, restored)
        end
        return restored, hooked
    end

    local dummy = newcclosure(function() end)
    local prev
    pcall(function() prev = realHookFunction(fn, dummy) end)

    if not prev then
        pcall(realHookFunction, fn, fn)
        return try(clonefunction, fn), hooked
    end

    -- A hook is either a genuine Lua closure, or an executor-generated closure
    -- (islc(prev) false, isExec(prev) true) disguised via newcclosure() - in
    -- both cases the real original is most likely sitting in its upvalues.
    if islc(prev) or (cfg.TrustExecutorClosureCheck and isExec(prev)) then
        local f = pickOriginal(prev, short)
        if f then
            realHookFunction(fn, f)
            return f, true
        end
        local cl = try(clonefunction, prev)
        if cl and isc(cl) and not (cfg.TrustExecutorClosureCheck and isExec(cl)) then
            realHookFunction(fn, cl)
            return cl, true
        end
        realHookFunction(fn, prev)
        return try(clonefunction, fn) or prev, true
    end

    realHookFunction(fn, prev)
    return prev, hooked
end

----------------------------------------------------------------------
-- PROTECTED TARGETS
----------------------------------------------------------------------
local targets = {
    { key = "HttpGet",      short = "HttpGet",      name = "game.HttpGet",             get = function() return game.HttpGet end },
    { key = "HttpPost",     short = "HttpPost",     name = "game.HttpPost",            get = function() return game.HttpPost end },
    { key = "GetObjects",   short = "GetObjects",   name = "game.GetObjects",          get = function() return game.GetObjects end },
    { key = "GetAsync",     short = "GetAsync",     name = "HttpService.GetAsync",     get = function() return HttpService.GetAsync end },
    { key = "PostAsync",    short = "PostAsync",    name = "HttpService.PostAsync",    get = function() return HttpService.PostAsync end },
    { key = "RequestAsync", short = "RequestAsync", name = "HttpService.RequestAsync", get = function() return HttpService.RequestAsync end },

    { key = "request", short = "request", name = "request",
      get = function() return getgenv().request end,
      set = function(v) getgenv().request = v end },
    { key = "http_request", short = "http_request", name = "http_request",
      get = function() return getgenv().http_request end,
      set = function(v) getgenv().http_request = v end },
    { key = "http_dot_request", short = "request", name = "http.request",
      get = function() return http and http.request end,
      set = function(v) if http then http.request = v end end },
    { key = "syn_request", short = "request", name = "syn.request",
      get = function() return syn and syn.request end,
      set = function(v) if syn then syn.request = v end end },
}

local function currentOf(t) return try(t.get) end

local function snap(fn)
    return {
        fn = fn,
        l = islc(fn) and true or false,
        e = isExec(fn) and true or false,
        s = try(debug.info, fn, "s"),
    }
end

local function changed(fn, s)
    local n = snap(fn)
    return (n.l and not s.l) or (n.e and not s.e) or (n.s ~= s.s) or (n.fn ~= s.fn)
end

local snaps = {}

for _, t in ipairs(targets) do
    local fn = currentOf(t)
    if type(fn) == "function" then
        local orig, hooked = recoverOriginal(fn, t.name, t.short)
        originals[t.key] = orig
        if t.set and orig then pcall(t.set, orig) end
        if hooked then report(t.name, "hook neutralized at startup") end
    end
end

for _, t in ipairs(targets) do
    local fn = currentOf(t)
    if type(fn) == "function" then snaps[t.key] = snap(fn) end
end

----------------------------------------------------------------------
-- __namecall
----------------------------------------------------------------------
local originalNc
local prevNc = try(realHookMetamethod, game, "__namecall", newcclosure(function() return nil end))

if prevNc then
    if islc(prevNc) then
        originalNc = pickOriginal(prevNc, "__namecall") or try(clonefunction, prevNc) or prevNc
        report("__namecall", "spy hook neutralized at startup")
    else
        originalNc = prevNc
    end
else
    local mt = try(getrawmetatable, game)
    originalNc = mt and try(rawget, mt, "__namecall")
end

local ncHandler = newcclosure(function(self, ...)
    local method = getnamecallmethod()
    if enabled and HTTP_METHODS[method] and originals[method] then
        return originals[method](self, ...)
    end
    if originalNc then return originalNc(self, ...) end
end)

pcall(function() realHookMetamethod(game, "__namecall", ncHandler) end)
pcall(function()
    local mt = getrawmetatable(game)
    setreadonly(mt, false)
    mt.__namecall = ncHandler
    setreadonly(mt, true)
end)

local function readNc()
    local mt = try(getrawmetatable, game)
    return mt and try(rawget, mt, "__namecall")
end

local lastNc = readNc()

----------------------------------------------------------------------
-- SPY LOG CLEANUP
----------------------------------------------------------------------
local function cleanupSpyData()
    pcall(function()
        for _, obj in pairs(getgc(true)) do
            if type(obj) == "table" then
                pcall(function()
                    local first = rawget(obj, 1)
                    if type(first) == "table" then
                        local url = rawget(first, "Url") or rawget(first, "url")
                        local method = rawget(first, "Method") or rawget(first, "method")
                        if type(url) == "string" and type(method) == "string" then
                            for i = #obj, 1, -1 do rawset(obj, i, nil) end
                        end
                    end
                end)
            end
        end
    end)
end

cleanupSpyData()

task.spawn(function()
    while task.wait(cfg.CleanupInterval) do
        if enabled then cleanupSpyData() end
    end
end)

----------------------------------------------------------------------
-- CONTINUOUS INTEGRITY CHECK
----------------------------------------------------------------------
local function recheck()
    local flagged = false

    for _, t in ipairs(targets) do
        local fn = currentOf(t)
        local s = snaps[t.key]
        if type(fn) == "function" and s then
            if t.set and s.fn and fn ~= s.fn then
                flagged = true
                pcall(t.set, s.fn)
                report(t.name, "function was replaced - reference restored")
            elseif changed(fn, s) then
                flagged = true
                local orig = recoverOriginal(fn, t.name, t.short)
                if orig then
                    originals[t.key] = orig
                    if t.set then pcall(t.set, orig) end
                end
                local cur = currentOf(t)
                if type(cur) == "function" then snaps[t.key] = snap(cur) end
                report(t.name, "late hook detected - original recovered")
            end
        end
    end

    local cur = readNc()
    if cur and lastNc and cur ~= lastNc then
        lastNc = cur
        if cfg.ReportOnMetaMismatch then
            flagged = true
            report("__namecall", "replaced outside Aegis wrappers")
        else
            log("__namecall changed outside Aegis wrappers (possible bypass)")
        end
    end

    return flagged
end

task.spawn(function()
    while task.wait(cfg.RecheckInterval) do
        if enabled then pcall(recheck) end
    end
end)

----------------------------------------------------------------------
-- DEEP SCAN (heuristic)
----------------------------------------------------------------------
-- Three independent categories of tell-tale constants. Two matching categories
-- in the same function is treated as suspicious - a single category alone is
-- too common in unrelated, legitimate scripts to act on.
local SPY_HTTP = {
    HttpGet = true, HttpPost = true, GetAsync = true, PostAsync = true, RequestAsync = true,
    GetObjects = true, request = true, http_request = true, reqfunc = true,
}
local SPY_HOOK = {
    getnamecallmethod = true, hookmetamethod = true, hookfunction = true, __namecall = true,
    replaceclosure = true, getoriginalfunction = true, newcclosure = true,
}
local SPY_UI = {
    ScreenGui = true, CoreGui = true, ["Requests: "] = true, ["Http Logs"] = true,
    ["Clear Logs"] = true, ["Filter requests..."] = true,
}
local seenSuspicious = {}

local function deepScan()
    if not (getgc and getconstants and mySource) then return 0 end
    local found, n = 0, 0

    for _, obj in ipairs(getgc(false)) do
        n += 1
        if n % 500 == 0 then task.wait() end

        -- Any function the executor generated is a candidate, regardless of
        -- whether it disguises itself as a C-closure via newcclosure().
        if type(obj) == "function" and isExec(obj) then
            local src = try(debug.info, obj, "s")
            if src ~= mySource then
                local consts = try(getconstants, obj)
                if type(consts) == "table" then
                    local h, k, u = false, false, false
                    for _, c in pairs(consts) do
                        if type(c) == "string" then
                            if SPY_HTTP[c] then h = true end
                            if SPY_HOOK[c] then k = true end
                            if SPY_UI[c] then u = true end
                        end
                    end
                    local categories = (h and 1 or 0) + (k and 1 or 0) + (u and 1 or 0)
                    if categories >= 2 then
                        found += 1
                        local key = tostring(src)
                        if not seenSuspicious[key] then
                            seenSuspicious[key] = true
                            if cfg.DeepScanReport then
                                report("GC", "suspicious function (spy-like constants): " .. key)
                            else
                                log("Suspicious function in GC (spy-like constants): " .. key)
                            end
                        end
                    end
                end
            end
        end
    end

    return found
end

task.spawn(function()
    task.wait(5)
    while true do
        if enabled and cfg.DeepScan then pcall(deepScan) end
        task.wait(cfg.DeepScanInterval)
    end
end)

----------------------------------------------------------------------
-- HOOK PROTECTION
----------------------------------------------------------------------
local function isProtectedFunction(fn)
    if type(fn) ~= "function" then return false end
    for _, t in ipairs(targets) do
        if fn == currentOf(t) then return true end
    end
    for _, o in pairs(originals) do
        if fn == o then return true end
    end
    return false
end

realHookFunction(hookfunction, newcclosure(function(target, hook)
    if enabled and isProtectedFunction(target) then
        report("hookfunction", "blocked attempt to hook an HTTP function")
        return target
    end
    return realHookFunction(target, hook)
end))

for _, alias in ipairs({ "replaceclosure", "hookfunc", "detour_function" }) do
    local fn = getgenv()[alias]
    if type(fn) == "function" then
        local realAlias = clonefunction(fn)
        pcall(realHookFunction, fn, newcclosure(function(target, hook)
            if enabled and isProtectedFunction(target) then
                report(alias, "blocked attempt to hook an HTTP function")
                return target
            end
            return realAlias(target, hook)
        end))
    end
end

realHookFunction(hookmetamethod, newcclosure(function(obj, method, hook)
    if obj == game and method == "__namecall" and type(hook) == "function" then
        local actualHook = hook
        local result = realHookMetamethod(obj, method, newcclosure(function(self, ...)
            local m = getnamecallmethod()
            if enabled and HTTP_METHODS[m] and originals[m] then
                return originals[m](self, ...)
            end
            return actualHook(self, ...)
        end))
        lastNc = readNc()
        return result
    end
    return realHookMetamethod(obj, method, hook)
end))

----------------------------------------------------------------------
-- SAFE REQUESTS
----------------------------------------------------------------------
local function safeRequest(opts)
    local fn = originals.request or originals.http_request or originals.syn_request or originals.http_dot_request
    if not fn then return nil, 0 end
    local ok, res = pcall(fn, opts)
    if ok and res then return res.Body, res.StatusCode end
    return nil, 0
end

API.Safe = {
    Get = function(url, headers)
        return safeRequest({ Url = url, Method = "GET", Headers = headers or {} })
    end,
    Post = function(url, body, headers)
        return safeRequest({
            Url = url,
            Method = "POST",
            Headers = headers or { ["Content-Type"] = "application/json" },
            Body = body,
        })
    end,
}

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------
local function setEnabled(state)
    state = state and true or false
    if state == enabled then return end
    enabled = state
    if enabled then
        cleanupSpyData()
        pcall(recheck)
    end
    log(enabled and "Protection enabled" or "Protection disabled")
end

--- Aegis:HttpSpy(true|false) sets the state. Aegis:HttpSpy() returns it.
function API.HttpSpy(...)
    local state = norm(...)
    if state ~= nil then setEnabled(state) end
    return enabled
end

function API.Toggle()
    setEnabled(not enabled)
    return enabled
end

function API.IsEnabled() return enabled end
function API.IsDetected() return detected end

function API.GetStatus()
    return {
        Version = VERSION,
        Supported = true,
        Enabled = enabled,
        Detected = detected,
        Detections = #detections,
    }
end

function API.GetDetections()
    return { table.unpack(detections) }
end

--- Registers a detection callback. Past detections are replayed unless replay == false.
function API.OnDetect(...)
    local fn, replay = norm(...)
    if type(fn) ~= "function" then return nil end
    listeners[#listeners + 1] = fn
    if replay ~= false then
        for _, info in ipairs(detections) do task.spawn(fn, info) end
    end
    return {
        Disconnect = function()
            for i, f in ipairs(listeners) do
                if f == fn then table.remove(listeners, i) break end
            end
        end,
    }
end

function API.Configure(...)
    local opts = norm(...)
    if type(opts) == "table" then
        for k, v in pairs(opts) do cfg[k] = v end
    end
    return API
end

function API.Scan() return select(2, pcall(recheck)) == true end
function API.DeepScan() return try(deepScan) or 0 end

function API.Restore()
    for _, t in ipairs(targets) do
        local cur, orig = currentOf(t), originals[t.key]
        if type(cur) == "function" and orig then pcall(realHookFunction, cur, orig) end
    end
    log("Original functions restored")
end

getgenv().Aegis = API

if cfg.ToggleKey then
    UserInputService.InputBegan:Connect(function(input, gp)
        if not gp and input.KeyCode == cfg.ToggleKey then API.Toggle() end
    end)
end

log("v" .. VERSION .. " loaded")
return API
