local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Templates = ServerStorage:WaitForChild("Templates")
local EnemyTemplate = require(Templates:WaitForChild("EnemyTemplate"))
local SpawnConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpawnConfig"))

print("ServerStorageFlow", EnemyTemplate.Id, SpawnConfig.WaveSize)
