-- Basic usage: load once, toggle whenever you want.
loadstring(game:HttpGet("https://raw.githubusercontent.com/DudxJs/aegis-http-engine/refs/heads/main/Loader.lua"))()

Aegis:HttpSpy(false) -- disable
task.wait(5)
Aegis:HttpSpy(true)  -- enable again

print("Protected:", Aegis:HttpSpy())
