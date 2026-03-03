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

    local dock = plugin:CreateDockWidgetPluginGui("AdrabloxMCPWidget", widgetInfo)
    dock.Title = "Adrablox MCP"

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
    
    local snapshotExportButton = Instance.new("TextButton")
    snapshotExportButton.Size = UDim2.new(0, 122, 0, 20)
    snapshotExportButton.Position = UDim2.new(1, -122, 0, 86)
    snapshotExportButton.Text = "Export Snapshot"
    snapshotExportButton.Font = Enum.Font.Code
    snapshotExportButton.TextSize = 12
    snapshotExportButton.Parent = frame

    local snapshotImportButton = Instance.new("TextButton")
    snapshotImportButton.Size = UDim2.new(0, 122, 0, 20)
    snapshotImportButton.Position = UDim2.new(1, -122, 0, 110)
    snapshotImportButton.Text = "Import Snapshot"
    snapshotImportButton.Font = Enum.Font.Code
    snapshotImportButton.TextSize = 12
    snapshotImportButton.Parent = frame

    local progressLabel = Instance.new("TextLabel")
    progressLabel.BackgroundTransparency = 1
    progressLabel.Size = UDim2.new(1, -140, 0, 60)
    progressLabel.Position = UDim2.new(0, 0, 0, 62)
    progressLabel.TextXAlignment = Enum.TextXAlignment.Left
    progressLabel.TextYAlignment = Enum.TextYAlignment.Top
    progressLabel.TextWrapped = true
    progressLabel.Font = Enum.Font.Code
    progressLabel.TextSize = 12
    progressLabel.Text = ""
    progressLabel.Parent = frame
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

    local sessionId = nil

    local function setSession(sid)
        sessionId = sid
    end

    local function appendProgress(line)
        if progressLabel.Text == "" then
            progressLabel.Text = line
        else
            progressLabel.Text = progressLabel.Text .. "\n" .. line
        end
    end

    snapshotExportButton.MouseButton1Click:Connect(function()
        if not sessionId then
            updateStatus("No session available")
            return
        end
        updateStatus("Exporting snapshot...")
        local ok, snapshot, err = pcall(function()
            return connection:exportSnapshot(sessionId)
        end)
        if not ok or not snapshot then
            updateStatus("Export failed: " .. tostring(err))
            return
        end
        updateStatus("Exported snapshot")
        appendProgress("Exported snapshot payload")
    end)

    snapshotImportButton.MouseButton1Click:Connect(function()
        if not sessionId then
            updateStatus("No session available")
            return
        end
        updateStatus("Exporting snapshot (for import)...")
        local ok, snapshot, err = connection:exportSnapshot(sessionId)
        if not ok then
            updateStatus("Export failed: " .. tostring(snapshot))
            return
        end
        updateStatus("Importing snapshot...")
        local impOk, impRes, impErr = connection:importSnapshot(sessionId, snapshot)
        if not impOk then
            updateStatus("Import failed: " .. tostring(impRes))
            return
        end

        appendProgress("Import started")

        -- Poll importProgress until imported
        task.spawn(function()
            while true do
                local pOk, pRes, pErr = connection:importProgress(sessionId)
                if not pOk then
                    appendProgress("importProgress error: " .. tostring(pRes))
                    updateStatus("importProgress error")
                    break
                end
                if pRes and pRes.importSummary then
                    appendProgress("chunks=" .. tostring(pRes.importSummary.chunks) .. " appliedCursor=" .. tostring(pRes.importSummary.appliedCursor))
                elseif pRes and pRes.imported then
                    appendProgress("imported: " .. tostring(pRes.imported))
                else
                    appendProgress("progress: " .. tostring(pRes and pRes.cursor or "?"))
                end
                if pRes and pRes.imported then
                    updateStatus("Import complete")
                    break
                end
                task.wait(0.5)
            end
        end)
    end)

    return {
        updateStatus = updateStatus,
        addConflict = addConflict,
        clearConflicts = clearConflicts,
        setRefreshAction = setRefreshAction,
        setSession = setSession,
        dock = dock,
    }
end

return Widget

