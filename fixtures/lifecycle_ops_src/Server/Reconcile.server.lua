local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LifecycleFlags = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LifecycleFlags"))

print("Reconcile", LifecycleFlags.EnableArchive)
