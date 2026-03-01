local PatchSerializer = {}

local function sanitizeSessionId(sessionId)
    return string.gsub(sessionId or "session", "[^%w]", "_")
end

function PatchSerializer.makePatchId(sessionId, sequence)
    return string.format("patch_%s_%06d", sanitizeSessionId(sessionId), sequence)
end

function PatchSerializer.setName(instanceId, name)
    return {
        {
            op = "setName",
            instanceId = instanceId,
            name = name,
        },
    }
end

function PatchSerializer.setProperty(instanceId, property, value)
    return {
        {
            op = "setProperty",
            instanceId = instanceId,
            property = property,
            value = value,
        },
    }
end

return PatchSerializer

