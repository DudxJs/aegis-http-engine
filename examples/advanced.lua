-- Advanced usage: custom config, detection events and safe requests.
getgenv().AegisConfig = {
    Action = function(info)
        warn("Custom action for:", info.Target)
    end,
    ToggleKey = Enum.KeyCode.RightControl,
}

loadstring(game:HttpGet("https://raw.githubusercontent.com/DudxJs/aegis-http-engine/refs/heads/main/Loader.lua"))()

local conn = Aegis:OnDetect(function(info)
    warn(("Spy detected at %s: %s"):format(info.Target, info.Reason))
end)

local body, status = Aegis.Safe.Get("https://example.com")
print("Status:", status)

local s = Aegis:GetStatus()
print(("Aegis v%s | enabled=%s | detections=%d"):format(s.Version, tostring(s.Enabled), s.Detections))

-- conn.Disconnect() to stop listening
