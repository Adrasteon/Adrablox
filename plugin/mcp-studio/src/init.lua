local ConnectionManager = require(script.Parent.ConnectionManager)
local SyncEngine = require(script.Parent.SyncEngine)
local Widget = require(script.Parent.Parent.ui.Widget)

local pluginController = {}

function pluginController.start(plugin)
    local connection = ConnectionManager.new({
        endpoint = "http://127.0.0.1:44877/mcp",
    })

    local syncEngine = SyncEngine.new(connection)
    local widget = Widget.mount(plugin, connection)
    syncEngine:setStatusSink(function(status)
        widget.updateStatus(status)
    end)
    syncEngine:setConflictSink(function(conflictLine)
        widget.addConflict(conflictLine)
    end)
    widget.setRefreshAction(function()
        syncEngine:refreshSelectedInstance()
    end)

    syncEngine:bootstrap()
end

return pluginController
