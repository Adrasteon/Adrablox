local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterShared = ReplicatedStorage:WaitForChild("CharacterShared")
local MovementConfig = require(CharacterShared:WaitForChild("MovementConfig"))

print("CharacterInit", MovementConfig.WalkSpeed)
