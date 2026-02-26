local Widget = {}

function Widget.mount(plugin, connection)
    local widgetInfo = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Float,
        true,
        false,
        360,
        220,
        280,
        160
    )

    local dock = plugin:CreateDockWidgetPluginGui("EdiyorMCPWidget", widgetInfo)
    dock.Title = "Ediyor MCP"

    local frame = Instance.new("Frame")
    frame.BackgroundTransparency = 1
    frame.Size = UDim2.new(1, -16, 1, -16)
    frame.Position = UDim2.new(0, 8, 0, 8)
    frame.Parent = dock

    local statusLabel = Instance.new("TextLabel")
    statusLabel.BackgroundTransparency = 1
    statusLabel.Size = UDim2.new(1, 0, 0, 58)
    statusLabel.Position = UDim2.new(0, 0, 0, 0)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    statusLabel.TextWrapped = true
    statusLabel.Font = Enum.Font.Code
    statusLabel.TextSize = 14
    statusLabel.Text = string.format("Endpoint: %s\nStatus: %s", connection.endpoint, connection.connected and "Connected" or "Disconnected")
    statusLabel.Parent = frame

    local conflictHeader = Instance.new("TextLabel")
    conflictHeader.BackgroundTransparency = 1
    conflictHeader.Size = UDim2.new(1, -130, 0, 20)
    conflictHeader.Position = UDim2.new(0, 0, 0, 62)
    conflictHeader.TextXAlignment = Enum.TextXAlignment.Left
    conflictHeader.TextYAlignment = Enum.TextYAlignment.Top
    conflictHeader.Font = Enum.Font.Code
    conflictHeader.TextSize = 14
    conflictHeader.Text = "Recent conflicts:"
    conflictHeader.Parent = frame

    local refreshButton = Instance.new("TextButton")
    refreshButton.Size = UDim2.new(0, 122, 0, 20)
    refreshButton.Position = UDim2.new(1, -122, 0, 62)
    refreshButton.Text = "Re-read selected"
    refreshButton.Font = Enum.Font.Code
    refreshButton.TextSize = 12
    refreshButton.Parent = frame

    local conflictLabel = Instance.new("TextLabel")
    conflictLabel.BackgroundTransparency = 1
    conflictLabel.Size = UDim2.new(1, 0, 1, -86)
    conflictLabel.Position = UDim2.new(0, 0, 0, 86)
    conflictLabel.TextXAlignment = Enum.TextXAlignment.Left
    conflictLabel.TextYAlignment = Enum.TextYAlignment.Top
    conflictLabel.TextWrapped = true
    conflictLabel.Font = Enum.Font.Code
    conflictLabel.TextSize = 13
    conflictLabel.Text = "(none)"
    conflictLabel.Parent = frame

    local conflictLines = {}
    local refreshAction = nil

    local function updateStatus(message)
        statusLabel.Text = string.format("Endpoint: %s\nStatus: %s", connection.endpoint, message)
    end

    local function addConflict(message)
        table.insert(conflictLines, 1, message)
        while #conflictLines > 5 do
            table.remove(conflictLines)
        end

        if #conflictLines == 0 then
            conflictLabel.Text = "(none)"
        else
            conflictLabel.Text = table.concat(conflictLines, "\n")
        end
    end

    local function clearConflicts()
        table.clear(conflictLines)
        conflictLabel.Text = "(none)"
    end

    refreshButton.MouseButton1Click:Connect(function()
        if refreshAction then
            refreshAction()
        end
    end)

    local function setRefreshAction(callback)
        refreshAction = callback
    end

    return {
        updateStatus = updateStatus,
        addConflict = addConflict,
        clearConflicts = clearConflicts,
        setRefreshAction = setRefreshAction,
        dock = dock,
    }
end

return Widget
