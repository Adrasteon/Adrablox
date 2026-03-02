local Selection = game:GetService("Selection")
local ScriptEditorService = nil
pcall(function()
    ScriptEditorService = game:GetService("ScriptEditorService")
end)

local PatchSerializer = require(script.Parent.PatchSerializer)

local SyncEngine = {}
SyncEngine.__index = SyncEngine

function SyncEngine.new(connectionManager)
    local self = setmetatable({}, SyncEngine)
    self.connectionManager = connectionManager
    self.widget = nil
    self.sessionId = nil
    self.cursor = 0
    self.running = false
    self.statusSink = nil
    self.conflictSink = nil
    self.lastTree = nil
    self.patchSequence = 0
    self.instanceById = {}
    self.selectionConnection = nil
    self.instanceChangedConnection = nil
    self.observedInstance = nil
    self.scriptEditorChangedConnection = nil
    self.lastSentValues = {}
    self.suppressLocalChanges = false
    self.fileBackedById = {}
    self.sessionCapabilities = nil
    self.realtimeMode = "http"
    self.lastReplaySeq = 0
    return self
end

function SyncEngine:setWidget(widget)
    self.widget = widget
end

function SyncEngine:_applySessionMetadata(payload)
    if not payload then
        return
    end

    if payload.sessionCapabilities then
        self.sessionCapabilities = payload.sessionCapabilities
    end

    local fileBackedInstanceIds = payload.fileBackedInstanceIds or {}
    for _, instanceId in ipairs(fileBackedInstanceIds) do
        self.fileBackedById[instanceId] = true
    end
end

function SyncEngine:_isFileBackedInstance(instanceId)
    return self.fileBackedById[instanceId] == true
end

function SyncEngine:setStatusSink(callback)
    self.statusSink = callback
end

function SyncEngine:setConflictSink(callback)
    self.conflictSink = callback
end

function SyncEngine:_isSessionMissingError(err, errCode)
    if errCode == "SESSION_NOT_FOUND" then
        return true
    end

    if not err then
        return false
    end

    local text = string.lower(tostring(err))
    return string.find(text, "session does not exist", 1, true) ~= nil
end

function SyncEngine:_recoverSession(reason)
    self:_emitStatus("Recovering session: " .. tostring(reason))

    local openOk, openSession, openErr = self.connectionManager:openSession("src")
    if not openOk then
        self:_emitStatus("Session recovery open failed: " .. tostring(openErr))
        return false
    end

    self.sessionId = openSession.sessionId
    self.cursor = tonumber(openSession.initialCursor) or 0
    self.fileBackedById = {}
    self.sessionCapabilities = nil
    self:_applySessionMetadata(openSession)

    local readOk, tree, readErr = self.connectionManager:readTree(self.sessionId, openSession.rootInstanceId)
    if not readOk then
        self:_emitStatus("Session recovery read failed: " .. tostring(readErr))
        return false
    end

    self.lastTree = tree
    self:_applySessionMetadata(tree)
    self.cursor = tonumber(tree.cursor) or self.cursor
    self:_bindTreeToStudioInstances(tree)
    self:_bindSelectionWatcher()
    self:_bindScriptEditorHooks()
    self:_startRealtime()
    self:_emitStatus(string.format("Session recovered (session=%s, cursor=%d)", tostring(self.sessionId), self.cursor))
    return true
end

function SyncEngine:_emitStatus(message)
    if self.statusSink then
        self.statusSink(message)
    end
end

function SyncEngine:_emitConflict(message)
    if self.conflictSink then
        self.conflictSink(message)
    end
end

function SyncEngine:_handleRealtimeEvent(payload, mode)
    if type(payload) ~= "table" then
        return
    end

    local seq = tonumber(payload.seq)
    if seq and seq > self.lastReplaySeq then
        self.lastReplaySeq = seq
    end

    local eventType = payload.type
    if eventType == "importProgress" then
        local info = payload.payload or payload
        self:_emitStatus(string.format(
            "Realtime(%s) import chunk=%s added=%s",
            tostring(mode),
            tostring(info.chunk or "?"),
            tostring(info.addedCount or 0)
        ))
    elseif eventType == "change" and type(payload.payload) == "table" then
        self:_applyRemoteChanges(payload.payload)
    end
end

function SyncEngine:_startRealtime()
    if not self.sessionId then
        return
    end

    local ok, mode, err = self.connectionManager:startRealtime(
        self.sessionId,
        self.lastReplaySeq,
        function(eventPayload, transportMode)
            self:_handleRealtimeEvent(eventPayload, transportMode)
        end,
        function(status)
            self:_emitStatus(status)
        end
    )

    if ok then
        self.realtimeMode = mode or "http"
        self:_emitStatus("Realtime mode: " .. tostring(self.realtimeMode))
    else
        self.realtimeMode = "http"
        self:_emitStatus("Realtime fallback to HTTP polling: " .. tostring(err or "unavailable"))
    end
end

function SyncEngine:_startPolling()
    if self.running then
        return
    end

    self.running = true
    task.spawn(function()
        while self.running do
            local ok, changes, err, errCode = self.connectionManager:subscribeChanges(self.sessionId, self.cursor)
            if not ok then
                if self:_isSessionMissingError(err, errCode) then
                    local recovered = self:_recoverSession("subscribe")
                    if recovered then
                        task.wait(0.2)
                        continue
                    end
                end
                self:_emitStatus("Subscribe failed: " .. tostring(err))
                task.wait(1)
                continue
            end

            local nextCursor = tonumber(changes.cursor) or self.cursor
            self.cursor = nextCursor
            self:_applySessionMetadata(changes)

            self:_applyRemoteChanges(changes)

            local addedCount = 0
            for _ in pairs(changes.added or {}) do
                addedCount += 1
            end
            local updatedCount = #(changes.updated or {})
            local removedCount = #(changes.removed or {})

            self:_emitStatus(string.format("Synced (cursor=%d, +%d ~%d -%d)", self.cursor, addedCount, updatedCount, removedCount))
            task.wait(0.75)
        end
    end)
end

function SyncEngine:_cacheLocalValue(instanceId, property, value)
    local key = string.format("%s:%s", instanceId, property)
    self.lastSentValues[key] = value
end

function SyncEngine:_ensureStudioInstance(instanceId, node)
    if self.instanceById[instanceId] then
        return self.instanceById[instanceId]
    end

    local parent = nil
    if node.Parent then
        parent = self.instanceById[node.Parent]
    end

    local existing = nil
    if parent then
        for _, child in ipairs(parent:GetChildren()) do
            if child.Name == node.Name and child.ClassName == node.ClassName then
                existing = child
                break
            end
        end
    else
        local service = game:FindFirstChild(node.Name)
        if service and service.ClassName == node.ClassName then
            existing = service
        end
    end

    if existing then
        existing:SetAttribute("McpInstanceId", instanceId)
        self.instanceById[instanceId] = existing
        return existing
    end

    if parent then
        local ok, created = pcall(function()
            local instance = Instance.new(node.ClassName)
            instance.Name = node.Name
            instance.Parent = parent
            return instance
        end)

        if ok and created then
            created:SetAttribute("McpInstanceId", instanceId)
            self.instanceById[instanceId] = created
            return created
        end
    end

    return nil
end

function SyncEngine:_applyRemoteChanges(changes)
    self.suppressLocalChanges = true

    local added = changes.added or {}
    for instanceId, node in pairs(added) do
        local studioInstance = self:_ensureStudioInstance(instanceId, node)
        if studioInstance and node.Properties then
            for property, value in pairs(node.Properties) do
                pcall(function()
                    studioInstance[property] = value
                end)
                self:_cacheLocalValue(instanceId, property, value)
            end
        end
    end

    local updated = changes.updated or {}
    for _, item in ipairs(updated) do
        local instanceId = item.id
        local studioInstance = self.instanceById[instanceId]
        if studioInstance then
            if item.changedName then
                studioInstance.Name = item.changedName
                self:_cacheLocalValue(instanceId, "Name", item.changedName)
            end

            for property, value in pairs(item.changedProperties or {}) do
                pcall(function()
                    studioInstance[property] = value
                end)
                self:_cacheLocalValue(instanceId, property, value)
            end
        end
    end

    local removed = changes.removed or {}
    for _, instanceId in ipairs(removed) do
        local studioInstance = self.instanceById[instanceId]
        if studioInstance and studioInstance ~= game then
            pcall(function()
                studioInstance:Destroy()
            end)
        end
        self.instanceById[instanceId] = nil
        self.fileBackedById[instanceId] = nil
    end

    self.suppressLocalChanges = false
end

function SyncEngine:_nextPatchSequence()
    self.patchSequence += 1
    return self.patchSequence
end

function SyncEngine:_bindTreeToStudioInstances(tree)
    self.instanceById = {}

    local nodes = tree.instances or {}
    local unresolved = {}
    for instanceId, node in pairs(nodes) do
        unresolved[instanceId] = node
    end

    local progress = true
    while progress do
        progress = false

        for instanceId, node in pairs(unresolved) do
            local studioInstance = nil

            if node.ClassName == "DataModel" then
                studioInstance = game
            else
                local parentId = node.Parent
                if parentId and self.instanceById[parentId] then
                    local parent = self.instanceById[parentId]
                    for _, child in ipairs(parent:GetChildren()) do
                        if child.Name == node.Name and child.ClassName == node.ClassName then
                            studioInstance = child
                            break
                        end
                    end
                else
                    local service = game:FindFirstChild(node.Name)
                    if service and service.ClassName == node.ClassName then
                        studioInstance = service
                    end
                end
            end

            if studioInstance then
                studioInstance:SetAttribute("McpInstanceId", instanceId)
                self.instanceById[instanceId] = studioInstance
                unresolved[instanceId] = nil
                progress = true
            end
        end
    end

    local boundCount = 0
    for _ in pairs(self.instanceById) do
        boundCount += 1
    end
    self:_emitStatus(string.format("Bound %d Studio instance(s) to MCP IDs", boundCount))
end

function SyncEngine:_sendPatch(operations)
    local patchId = PatchSerializer.makePatchId(self.sessionId, self:_nextPatchSequence())
    local ok, result, err, errCode = self.connectionManager:applyPatch(
        self.sessionId,
        patchId,
        self.cursor,
        "studio-plugin",
        operations
    )

    if (not ok) and self:_isSessionMissingError(err, errCode) then
        local recovered = self:_recoverSession("applyPatch")
        if recovered then
            ok, result, err, errCode = self.connectionManager:applyPatch(
                self.sessionId,
                patchId,
                self.cursor,
                "studio-plugin",
                operations
            )
        end
    end

    if not ok then
        self:_emitStatus("ApplyPatch failed: " .. tostring(err))
        return false
    end

    self.cursor = tonumber(result.appliedCursor) or self.cursor
    if result.conflicts and #result.conflicts > 0 then
        self:_rollbackConflicts(result.conflictDetails or {})
        for _, detail in ipairs(result.conflictDetails or {}) do
            local line = string.format(
                "%s.%s (%s)",
                tostring(detail.instanceId or "unknown"),
                tostring(detail.property or "unknown"),
                tostring(detail.reason or "conflict")
            )
            self:_emitConflict(line)
        end
        self:_emitStatus(string.format("Patch conflict(s): %s", table.concat(result.conflicts, "; ")))
    else
        self:_emitStatus(string.format("Patch applied (cursor=%d, idempotent=%s)", self.cursor, tostring(result.idempotent)))
    end
    return true
end

function SyncEngine:_rollbackConflicts(conflictDetails)
    for _, detail in ipairs(conflictDetails) do
        local instanceId = detail.instanceId
        local property = detail.property

        if instanceId and property then
            local ok, tree, err = self.connectionManager:readTree(self.sessionId, instanceId)
            if not ok then
                self:_emitStatus("Conflict rollback read failed: " .. tostring(err))
                self:_emitConflict(string.format("rollback_failed:%s.%s", tostring(instanceId), tostring(property)))
                continue
            end

            local nodes = tree.instances or {}
            local node = nodes[instanceId]
            local studioInstance = self.instanceById[instanceId]
            if not node or not studioInstance then
                continue
            end

            self.suppressLocalChanges = true

            if property == "Name" then
                local remoteName = node.Name
                if remoteName then
                    studioInstance.Name = remoteName
                    self:_cacheLocalValue(instanceId, "Name", remoteName)
                end
            else
                local remoteValue = (node.Properties or {})[property]
                if remoteValue ~= nil then
                    pcall(function()
                        studioInstance[property] = remoteValue
                    end)
                    self:_cacheLocalValue(instanceId, property, remoteValue)
                end
            end

            self.suppressLocalChanges = false
        end
    end
end

function SyncEngine:_refreshInstanceFromServer(instanceId)
    local ok, tree, err, errCode = self.connectionManager:readTree(self.sessionId, instanceId)
    if not ok then
        if self:_isSessionMissingError(err, errCode) then
            local recovered = self:_recoverSession("re-read")
            if recovered then
                ok, tree, err, errCode = self.connectionManager:readTree(self.sessionId, instanceId)
            end
        end
    end

    if not ok then
        self:_emitStatus("Re-read failed: " .. tostring(err))
        return false
    end

    local nodes = tree.instances or {}
    local node = nodes[instanceId]
    local studioInstance = self.instanceById[instanceId]
    if not node or not studioInstance then
        self:_emitStatus("Re-read skipped: instance not bound")
        return false
    end

    self.suppressLocalChanges = true
    self:_applySessionMetadata(tree)
    if node.Name then
        studioInstance.Name = node.Name
        self:_cacheLocalValue(instanceId, "Name", node.Name)
    end

    for property, value in pairs(node.Properties or {}) do
        pcall(function()
            studioInstance[property] = value
        end)
        self:_cacheLocalValue(instanceId, property, value)
    end
    self.suppressLocalChanges = false

    self.cursor = tonumber(tree.cursor) or self.cursor
    self:_emitStatus("Re-read complete for " .. tostring(instanceId))
    return true
end

function SyncEngine:refreshSelectedInstance()
    if not self.sessionId then
        self:_emitStatus("Re-read unavailable: no active session")
        return false
    end

    local selected = Selection:Get()
    local instance = selected[1]
    if not instance then
        self:_emitStatus("Re-read unavailable: no selection")
        return false
    end

    local instanceId = instance:GetAttribute("McpInstanceId")
    if not instanceId then
        self:_emitStatus("Re-read unavailable: selection is not MCP-bound")
        return false
    end

    return self:_refreshInstanceFromServer(instanceId)
end

function SyncEngine:_onObservedInstanceChanged(instance, property)
    if self.suppressLocalChanges then
        return
    end

    local instanceId = instance:GetAttribute("McpInstanceId")
    if not instanceId then
        return
    end

    local cacheKey = string.format("%s:%s", instanceId, property)

    if property == "Name" then
        if self:_isFileBackedInstance(instanceId) then
            local filePolicy = self.sessionCapabilities and self.sessionCapabilities.fileBackedMutationPolicy
            if filePolicy and filePolicy.allowSetName == false then
                self:_emitStatus("Blocked local rename for file-backed instance")
                self:_emitConflict(string.format("%s.Name (blocked_by_policy)", tostring(instanceId)))
                return
            end
        end

        local value = instance.Name
        if self.lastSentValues[cacheKey] == value then
            return
        end

        self.lastSentValues[cacheKey] = value
        self:_sendPatch(PatchSerializer.setName(instanceId, value))
        return
    end

    if property == "Source" and instance:IsA("LuaSourceContainer") then
        if self:_isFileBackedInstance(instanceId) then
            local filePolicy = self.sessionCapabilities and self.sessionCapabilities.fileBackedMutationPolicy
            local allowed = false
            if filePolicy and filePolicy.allowedSetProperty then
                for _, allowedProperty in ipairs(filePolicy.allowedSetProperty) do
                    if allowedProperty == "Source" then
                        allowed = true
                        break
                    end
                end
            end

            if not allowed then
                self:_emitStatus("Blocked local Source edit due to server policy")
                self:_emitConflict(string.format("%s.Source (blocked_by_policy)", tostring(instanceId)))
                return
            end
        end

        local value = instance.Source
        if self.lastSentValues[cacheKey] == value then
            return
        end

        self.lastSentValues[cacheKey] = value
        self:_sendPatch(PatchSerializer.setProperty(instanceId, "Source", value))
    end
end

function SyncEngine:_observeInstance(instance)
    if self.instanceChangedConnection then
        self.instanceChangedConnection:Disconnect()
        self.instanceChangedConnection = nil
    end

    self.observedInstance = instance
    if not instance then
        return
    end

    self.instanceChangedConnection = instance.Changed:Connect(function(property)
        self:_onObservedInstanceChanged(instance, property)
    end)

    self:_emitStatus("Watching local changes: " .. instance:GetFullName())
end

function SyncEngine:_bindScriptEditorHooks()
    if self.scriptEditorChangedConnection then
        self.scriptEditorChangedConnection:Disconnect()
        self.scriptEditorChangedConnection = nil
    end

    if not ScriptEditorService then
        return
    end

    local changeSignal = ScriptEditorService.TextDocumentDidChange
    if not changeSignal then
        return
    end

    self.scriptEditorChangedConnection = changeSignal:Connect(function()
        if self.suppressLocalChanges or (not self.sessionId) then
            return
        end

        local instance = self.observedInstance
        if not instance or not instance:IsA("LuaSourceContainer") then
            return
        end

        self:_onObservedInstanceChanged(instance, "Source")
    end)
end

function SyncEngine:_bindSelectionWatcher()
    if self.selectionConnection then
        self.selectionConnection:Disconnect()
        self.selectionConnection = nil
    end

    self.selectionConnection = Selection.SelectionChanged:Connect(function()
        local selected = Selection:Get()
        local instance = selected[1]

        if instance and instance:GetAttribute("McpInstanceId") then
            self:_observeInstance(instance)
        else
            self:_observeInstance(nil)
        end
    end)

    local selected = Selection:Get()
    local instance = selected[1]
    if instance and instance:GetAttribute("McpInstanceId") then
        self:_observeInstance(instance)
    end
end

function SyncEngine:stop()
    self.running = false
    self.connectionManager:stopRealtime()

    if self.selectionConnection then
        self.selectionConnection:Disconnect()
        self.selectionConnection = nil
    end

    if self.instanceChangedConnection then
        self.instanceChangedConnection:Disconnect()
        self.instanceChangedConnection = nil
    end

    if self.scriptEditorChangedConnection then
        self.scriptEditorChangedConnection:Disconnect()
        self.scriptEditorChangedConnection = nil
    end

    if self.sessionId then
        self.connectionManager:closeSession(self.sessionId)
    end
end

function SyncEngine:bootstrap()
    self:_emitStatus("Connecting...")

    local initOk, _, initErr = self.connectionManager:initialize()
    if not initOk then
        warn("MCP initialize failed", initErr)
        self:_emitStatus("Initialize failed: " .. tostring(initErr))
        return false
    end

    self.connectionManager:sendInitialized()

    local openOk, openSession, openErr = self.connectionManager:openSession("src")
    if not openOk then
        self:_emitStatus("OpenSession failed: " .. tostring(openErr))
        return false
    end

    self.sessionId = openSession.sessionId
    self.cursor = tonumber(openSession.initialCursor) or 0
    self:_applySessionMetadata(openSession)

    if self.widget and self.widget.setSession then
        pcall(function()
            self.widget.setSession(self.sessionId)
        end)
    end

    local readOk, tree, readErr = self.connectionManager:readTree(self.sessionId, openSession.rootInstanceId)
    if not readOk then
        self:_emitStatus("ReadTree failed: " .. tostring(readErr))
        return false
    end

    self.lastTree = tree
    self:_applySessionMetadata(tree)
    self.cursor = tonumber(tree.cursor) or self.cursor
    self:_bindTreeToStudioInstances(tree)
    self:_bindSelectionWatcher()
    self:_bindScriptEditorHooks()

    self:_emitStatus(string.format("Connected (session=%s, cursor=%d)", tostring(self.sessionId), self.cursor))
    self:_startRealtime()
    self:_startPolling()

    return true
end

return SyncEngine
