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
        return nil, string.format("HTTP %d %s", response.StatusCode, response.StatusMessage), nil
    end

    local decodeOk, payload = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)

    if not decodeOk then
        self.connected = false
        return nil, "Failed to decode JSON-RPC response", nil
    end

    if payload.error then
        self.connected = false
        local code = nil
        if payload.error.data and payload.error.data.code then
            code = tostring(payload.error.data.code)
        end
        return nil, payload.error.message or "JSON-RPC error", code
    end

    self.connected = true
    return payload.result, nil, nil
end

function ConnectionManager:initialize()
    local result, err, errCode = self:_request("initialize", {
        protocolVersion = self.protocolVersion,
        capabilities = {
            resources = { subscribe = true },
            tools = {},
        },
        clientInfo = {
            name = "AdrabloxMCP",
            version = "0.1.0",
        },
    })

    if err then
        return false, nil, err, errCode
    end

    return true, result, nil, nil
end

function ConnectionManager:sendInitialized()
    local ok, _, err, errCode = pcall(function()
        return self:_request("notifications/initialized", {})
    end)

    if not ok then
        return false, "failed to send initialized notification"
    end

    if err then
        return false, err, errCode
    end

    return true, nil, nil
end

function ConnectionManager:callTool(name, arguments)
    local result, err, errCode = self:_request("tools/call", {
        name = name,
        arguments = arguments,
    })

    if err then
        return false, nil, err, errCode
    end
    -- Prefer `structuredContent` when present (server wraps tool payloads this way),
    -- but also accept a direct result object that already matches expected structure.
    if result == nil then
        return false, nil, "empty tool response", nil
    end

    if type(result) == "table" and result.structuredContent ~= nil then
        return true, result.structuredContent, nil, nil
    end

    -- If the server returned a plain ProjectSnapshot or other structured payload,
    -- return it as-is.
    if type(result) == "table" then
        return true, result, nil, nil
    end

    return false, nil, "unexpected tool response format", nil
end

function ConnectionManager:exportSnapshot(sessionId)
    return self:callTool("roblox.exportSnapshot", { sessionId = sessionId })
end

function ConnectionManager:importSnapshot(sessionId, snapshot)
    return self:callTool("roblox.importSnapshot", { sessionId = sessionId, snapshot = snapshot })
end

function ConnectionManager:importProgress(sessionId)
    return self:callTool("roblox.importProgress", { sessionId = sessionId })
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

-- Request tools/list and normalize advertised names back to canonical names.
function ConnectionManager:listTools()
    local result, err, errCode = self:_request("tools/list", {})
    if err then
        return false, nil, err, errCode
    end

    local payload = result
    if payload == nil then
        return false, nil, "empty tools/list response", nil
    end

    local tools = payload.tools or {}
    local out = {}
    for _, t in ipairs(tools) do
        local name = t.name or t["name"]
        local desc = t.description or t["description"]
        if name then
            -- Map sanitized names like 'roblox-opensession' -> 'roblox.openSession'
            local canonical = string.gsub(name, "%-%w", function(s) return string.upper(string.sub(s,2,2)) end)
            -- Also replace hyphens with dots
            canonical = string.gsub(name, "-", ".")
            -- naive camel-case fallback: leave as-is if not matched
            table.insert(out, { name = name, description = desc, canonical = canonical })
        end
    end

    return true, out, nil, nil
end

-- Call a tool by name, trying the provided name, then a canonicalized fallback
function ConnectionManager:callNormalized(name, arguments)
    local ok, res, err, errCode = self:callTool(name, arguments)
    if ok then return ok, res, err, errCode end

    -- try replacing hyphens with dots
    local alt = string.gsub(name, "-", ".")
    if alt ~= name then
        return self:callTool(alt, arguments)
    end

    return ok, res, err, errCode
end

return ConnectionManager


