local ServerScriptService = game:GetService("ServerScriptService")
local Features = ServerScriptService:WaitForChild("Game"):WaitForChild("Features")
local Prices = require(Features:WaitForChild("Economy"):WaitForChild("Prices"))

print("Nested Bootstrap", Prices.Base)
