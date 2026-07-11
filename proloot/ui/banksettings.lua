-- Bank & Vendor settings window: two stacked bordered sections

local Widgets = require('proloot.ui.widgets')

local BankSettings = {}

local _open   = false
local _config = nil

function BankSettings.Open(config)
    _config = config
    _open   = true
end

function BankSettings.IsOpen()
    return _open
end

function BankSettings.Close()
    _open = false
end

local function renderVendorSection()
    ImGui.TextColored(ImVec4(1.0, 0.80, 0.20, 1.0), 'Vendor')
    ImGui.Separator()
    ImGui.Spacing()

    if ImGui.BeginTable('##vendoropts', 2, 0) then
        ImGui.TableSetupColumn('##vlbl', ImGuiTableColumnFlags.WidthFixed,  150)
        ImGui.TableSetupColumn('##vctl', ImGuiTableColumnFlags.WidthStretch)

        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Auto Sell')
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.PushTextWrapPos(280)
            ImGui.TextWrapped('Skip the Sell Stuff confirmation window and sell items immediately when running /proloot sellstuff.')
            ImGui.PopTextWrapPos()
            ImGui.EndTooltip()
        end
        ImGui.TableNextColumn()
        local autoSell, sellChanged = Widgets.Toggle('##autosell', _config:Get('SellAutoSell'))
        if sellChanged then _config:SetAndSave('SellAutoSell', autoSell) end

        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Auto Restock')
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.PushTextWrapPos(280)
            ImGui.TextWrapped('Skip the Restock confirmation window and buy items immediately when running /proloot restock.')
            ImGui.PopTextWrapPos()
            ImGui.EndTooltip()
        end
        ImGui.TableNextColumn()
        local autoRestock, restockChanged = Widgets.Toggle('##autorestock', _config:Get('RestockAutoRestock'))
        if restockChanged then _config:SetAndSave('RestockAutoRestock', autoRestock) end

        ImGui.EndTable()
    end
end

local function renderBankSection()
    ImGui.TextColored(ImVec4(0.30, 0.70, 1.0, 1.0), 'Bank')
    ImGui.Separator()
    ImGui.Spacing()

    if ImGui.BeginTable('##bankopts', 2, 0) then
        ImGui.TableSetupColumn('##blbl', ImGuiTableColumnFlags.WidthFixed,  150)
        ImGui.TableSetupColumn('##bctl', ImGuiTableColumnFlags.WidthStretch)

        -- Auto Consolidate Coins
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Auto Consolidate Coins')
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.PushTextWrapPos(280)
            ImGui.TextWrapped('Automatically convert CP \xe2\x86\x92 SP \xe2\x86\x92 GP \xe2\x86\x92 PP after a Bank Stuff deposit. The Consolidate Coins button always runs regardless of this setting.')
            ImGui.PopTextWrapPos()
            ImGui.EndTooltip()
        end
        ImGui.TableNextColumn()
        local autoConsolidate, consolidateChanged = Widgets.Toggle('##autoconsolidate', _config:Get('AutoConsolidateCoins'))
        if consolidateChanged then _config:SetAndSave('AutoConsolidateCoins', autoConsolidate) end

        -- Auto Deposit
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Auto Deposit')
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.PushTextWrapPos(280)
            ImGui.TextWrapped('Skip the Bank Stuff confirmation window and deposit bank-list items immediately when running /proloot bankstuff.')
            ImGui.PopTextWrapPos()
            ImGui.EndTooltip()
        end
        ImGui.TableNextColumn()
        local autoDeposit, depositChanged = Widgets.Toggle('##autodeposit', _config:Get('BankAutoDeposit'))
        if depositChanged then _config:SetAndSave('BankAutoDeposit', autoDeposit) end

        ImGui.EndTable()
    end
end

local VENDOR_H = 130
local BANK_H   = 100

function BankSettings.Render()
    if not _open or not _config then return end

    ImGui.SetNextWindowSize(ImVec2(238, 275), ImGuiCond.FirstUseEver)
    local open, shouldDraw = ImGui.Begin('ProLoot \xe2\x80\x94 Bank & Vendor', _open, ImGuiWindowFlags.None)
    _open = open
    if ImGui.IsWindowFocused() and ImGui.IsKeyPressed(ImGuiKey.Escape) then _open = false end

    if shouldDraw then
        ImGui.BeginChild('##vendor_sect', ImVec2(-1, VENDOR_H), ImGuiChildFlags.Border)
        renderVendorSection()
        ImGui.EndChild()

        ImGui.Spacing()

        ImGui.BeginChild('##bank_sect', ImVec2(-1, BANK_H), ImGuiChildFlags.Border)
        renderBankSection()
        ImGui.EndChild()
    end

    ImGui.End()
end

return BankSettings
