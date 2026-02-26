local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")
local Selector = require(Workspace:WaitForChild("SpawnPoints"):WaitForChild("Selector"))

local red = Teams:FindFirstChild("Red")
local blue = Teams:FindFirstChild("Blue")
print("AssignTeam", Selector.DefaultSpawn, red ~= nil, blue ~= nil)
