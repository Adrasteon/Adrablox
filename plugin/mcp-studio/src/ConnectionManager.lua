local HttpService = game:GetService("HttpService")

local ConnectionManager = {}
ConnectionManager.__index = ConnectionManager

function ConnectionManager.new(config)
    local self = setmetatable({}, ConnectionManager)
    self.endpoint = config.endpoint
    self.nextId = 1
    self.protocolVersion = "2025-11-25"
    self.connected = false
    return self
end

function ConnectionManager:_request(method, params)
    local id = self.nextId
    self.nextId += 1

    local body = HttpService:JSONEncode({
        jsonrpc = "2.0",
        id = id,
        method = method,
        params = params,
    })

    local response = HttpService:RequestAsync({
        Url = self.endpoint,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
        },
        Body = body,
    })

    if not response.Success then
        self.connected = false
        return nil, string.format("HTTP %d %s", response.StatusCode, response.StatusMessage)
    end

    local decodeOk, payload = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)

    if not decodeOk then
        self.connected = false
        return nil, "Failed to decode JSON-RPC response"
    end

    if payload.error then
        self.connected = false
        return nil, payload.error.message or "JSON-RPC error"
    end

    self.connected = true
    return payload.result, nil
end

function ConnectionManager:initialize()
    local result, err = self:_request("initialize", {
        protocolVersion = self.protocolVersion,
        capabilities = {
            resources = { subscribe = true },
            tools = {},
        },
        clientInfo = {
            name = "EdiyorStudioPlugin",
            version = "0.1.0",
        },
    })

    if err then
        return false, nil, err
    end

    return true, result, nil
end

function ConnectionManager:sendInitialized()
    local ok, _, err = pcall(function()
        return self:_request("notifications/initialized", {})
    end)

    if not ok then
        return false, "failed to send initialized notification"
    end

    if err then
        return false, err
    end

    return true, nil
end

function ConnectionManager:callTool(name, arguments)
    local result, err = self:_request("tools/call", {
        name = name,
        arguments = arguments,
    })

    if err then
        return false, nil, err
    end

    local structured = result and result.structuredContent
    if structured == nil then
        return false, nil, "missing structuredContent in tool response"
    end

    return true, structured, nil
end

function ConnectionManager:openSession(projectPath)
    return self:callTool("roblox.openSession", {
        projectPath = projectPath,
    })
end

function ConnectionManager:readTree(sessionId, instanceId)
    return self:callTool("roblox.readTree", {
        sessionId = sessionId,
        instanceId = instanceId,
    })
end

function ConnectionManager:subscribeChanges(sessionId, cursor)
    return self:callTool("roblox.subscribeChanges", {
        sessionId = sessionId,
        cursor = tostring(cursor),
    })
end

function ConnectionManager:applyPatch(sessionId, patchId, baseCursor, origin, operations)
    return self:callTool("roblox.applyPatch", {
        sessionId = sessionId,
        patchId = patchId,
        baseCursor = tostring(baseCursor),
        origin = origin,
        operations = operations,
    })
end

function ConnectionManager:closeSession(sessionId)
    return self:callTool("roblox.closeSession", {
        sessionId = sessionId,
    })
end

return ConnectionManager
