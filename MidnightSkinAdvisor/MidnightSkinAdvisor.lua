local ADDON_NAME = ...
local MSA = CreateFrame("Frame")

MSA:RegisterEvent("ADDON_LOADED")
MSA:RegisterEvent("CHAT_MSG_LOOT")
MSA:RegisterEvent("PLAYER_LOGIN")

local cmdUI

local function now() return time() end
local function n(v) return tonumber(v) or 0 end

local PRESET_ITEMS = {
    [238511] = { name = "Void-Tempered Leather", weight = 1.00, type = "leather" },
    [238513] = { name = "Void-Tempered Scales", weight = 1.00, type = "scales" },
    [238518] = { name = "Void-Tempered Hide", weight = 1.35, type = "hide" },
    [238520] = { name = "Void-Tempered Plating", weight = 1.45, type = "plating" },
    [238525] = { name = "Fantastic Fur", weight = 8.00, type = "special", special = true },
    [238522] = { name = "Peerless Plumage", weight = 8.00, type = "special", special = true },
    [238523] = { name = "Carving Canine", weight = 8.00, type = "special", special = true },
    [238528] = { name = "Majestic Claw", weight = 2.50, type = "majestic" },
    [238529] = { name = "Majestic Hide", weight = 2.50, type = "majestic" },
    [238530] = { name = "Majestic Fin", weight = 2.50, type = "majestic" },
}

local DEFAULT_CONFIG = {
    highValueBeastBonus = 1.20,
    useTomTom = true,
}

local function ensureDB()
    MidnightSkinAdvisorDB = MidnightSkinAdvisorDB or {}
    local db = MidnightSkinAdvisorDB
    db.version = "2.3.1"
    db.createdAt = db.createdAt or now()
    db.config = db.config or {}
    for k, v in pairs(DEFAULT_CONFIG) do if db.config[k] == nil then db.config[k] = v end end

    db.items = db.items or {}
    db.zones = db.zones or {}
    db.spots = db.spots or {}
    db.notes = db.notes or {
        "Special mats (Fantastic Fur / Peerless Plumage / Carving Canine) need Gainful Gathering spec.",
        "Those three mats currently appear extremely rare; community reports possible drop bug.",
        "High Value Beasts usually add 5-10 extra leather/scales when skinned.",
    }
    db.minimap = db.minimap or { angle = 225, hide = false }

    if not db.itemConfig then
        db.itemConfig = {}
        for itemID, info in pairs(PRESET_ITEMS) do
            db.itemConfig[itemID] = { name = info.name, weight = info.weight, special = info.special and true or false, enabled = true }
        end
    end
end

local function getZoneKey()
    return (GetRealZoneText() or "Unknown Zone") .. " :: " .. (GetSubZoneText() or "Unknown Subzone")
end

local function parseItemIDFromLink(itemLink)
    if not itemLink then return nil end
    local itemID = itemLink:match("item:(%d+):")
    return itemID and tonumber(itemID) or nil
end

local function getOrCreateZone(zoneKey)
    local db = MidnightSkinAdvisorDB
    db.zones[zoneKey] = db.zones[zoneKey] or {
        startedAt = now(),
        lastAt = now(),
        totalCount = 0,
        weightedScore = 0,
        items = {},
        highValueFlags = 0,
    }
    return db.zones[zoneKey]
end

local function addLoot(itemID, count)
    local db = MidnightSkinAdvisorDB
    local cfg = db.itemConfig[itemID]
    if not cfg or not cfg.enabled then return end

    local zone = getOrCreateZone(getZoneKey())
    zone.lastAt = now()
    zone.totalCount = zone.totalCount + count
    zone.items[itemID] = (zone.items[itemID] or 0) + count
    zone.weightedScore = zone.weightedScore + (count * n(cfg.weight))
    db.items[itemID] = (db.items[itemID] or 0) + count
end

local function zoneHours(zone)
    local elapsed = math.max(1, (zone.lastAt or now()) - (zone.startedAt or now()))
    return elapsed / 3600
end

local function zoneScorePerHour(zone)
    local base = zone.weightedScore / math.max(0.02, zoneHours(zone))
    if (zone.highValueFlags or 0) > 0 then
        local bonus = 1 + ((MidnightSkinAdvisorDB.config.highValueBeastBonus - 1) * math.min(zone.highValueFlags, 5) / 5)
        return base * bonus
    end
    return base
end

local function collectRankedZones()
    local rows = {}
    for zoneKey, zone in pairs(MidnightSkinAdvisorDB.zones) do
        rows[#rows + 1] = {
            zoneKey = zoneKey,
            scorePH = zoneScorePerHour(zone),
            total = zone.totalCount,
            highValueFlags = zone.highValueFlags or 0,
            zone = zone,
        }
    end
    table.sort(rows, function(a, b)
        if a.scorePH == b.scorePH then return a.total > b.total end
        return a.scorePH > b.scorePH
    end)
    return rows
end

local function printHeader(text)
    print("|cff6de1ffMidnightSkinAdvisor|r " .. text)
end

local function cmdTop()
    local rows = collectRankedZones()
    printHeader("Top farm spots (weighted score/hour)")
    if #rows == 0 then print("  Noch keine Daten. Geh skinnen und nutze /msa top erneut.") return end
    for i = 1, math.min(10, #rows) do
        local r = rows[i]
        print(string.format("  %d) %s | %.1f /h | total:%d | HV flags:%d", i, r.zoneKey, r.scorePH, r.total, r.highValueFlags))
    end
end

local function cmdItems()
    printHeader("Tracked items")
    for itemID, cfg in pairs(MidnightSkinAdvisorDB.itemConfig) do
        local marker = cfg.special and " [Gainful Gathering]" or ""
        local enabled = cfg.enabled and "on" or "off"
        print(string.format("  %d: %s | w=%.2f | %s%s", itemID, cfg.name or "?", n(cfg.weight), enabled, marker))
    end
end

local function cmdNote()
    printHeader("Important notes")
    for _, line in ipairs(MidnightSkinAdvisorDB.notes) do print("  - " .. line) end
end

local function cmdReset()
    MidnightSkinAdvisorDB.zones = {}
    MidnightSkinAdvisorDB.items = {}
    printHeader("Session data reset.")
end

local function cmdFlagHV()
    local zone = getOrCreateZone(getZoneKey())
    zone.highValueFlags = (zone.highValueFlags or 0) + 1
    printHeader("High Value Beast flag added for current zone.")
end

local function cmdAddSpot(name, x, y)
    local zone = GetRealZoneText() or "Unknown Zone"
    MidnightSkinAdvisorDB.spots[zone] = MidnightSkinAdvisorDB.spots[zone] or {}
    table.insert(MidnightSkinAdvisorDB.spots[zone], { name = name, x = x, y = y })
    printHeader(string.format("Spot added: %s (%.1f, %.1f) in %s", name, x, y, zone))
end

local function cmdSpots()
    local zone = GetRealZoneText() or "Unknown Zone"
    local spots = MidnightSkinAdvisorDB.spots[zone] or {}
    printHeader("Spots for " .. zone)
    if #spots == 0 then print("  Keine Spots gespeichert. /msa addspot Name 45.2 63.8") return end
    for i, s in ipairs(spots) do print(string.format("  %d) %s (%.1f, %.1f)", i, s.name, s.x, s.y)) end
end

local function cmdTomTom(idx)
    if not TomTom or not TomTom.AddWaypoint then printHeader("TomTom nicht gefunden. Installiere TomTom für Waypoints.") return end
    local zone = GetRealZoneText() or "Unknown Zone"
    local spots = MidnightSkinAdvisorDB.spots[zone] or {}
    local s = spots[tonumber(idx) or 1]
    if not s then printHeader("Spot index nicht gefunden. /msa spots") return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then printHeader("Kein mapID gefunden.") return end
    TomTom:AddWaypoint(mapID, s.x / 100, s.y / 100, { title = "MSA: " .. s.name, persistent = false, minimap = true, world = true })
    printHeader("TomTom waypoint gesetzt: " .. s.name)
end

local function cmdWeight(itemID, weight)
    itemID, weight = tonumber(itemID), tonumber(weight)
    if not itemID or not weight then print("Usage: /msa weight <itemID> <weight>") return end
    MidnightSkinAdvisorDB.itemConfig[itemID] = MidnightSkinAdvisorDB.itemConfig[itemID] or { name = "Item " .. itemID, enabled = true, special = false }
    MidnightSkinAdvisorDB.itemConfig[itemID].weight = weight
    printHeader(string.format("Weight set: %d -> %.2f", itemID, weight))
end

local function cmdAdd(itemLink, weight)
    local itemID = parseItemIDFromLink(itemLink)
    if not itemID then print("Usage: /msa add [itemLink] <weight>") return end
    MidnightSkinAdvisorDB.itemConfig[itemID] = {
        name = itemLink:match("%[(.-)%]") or ("Item " .. itemID),
        weight = tonumber(weight) or 1,
        special = false,
        enabled = true,
    }
    printHeader("Item added: " .. MidnightSkinAdvisorDB.itemConfig[itemID].name)
end

-- UI -------------------------------------------------------------------------
MSA.ui = { activeTab = "overview" }
local TAB_COLOR = "|cff8fe9ff"
local TITLE_COLOR = "|cffb89bff"

local function clearRows(rows)
    for i = 1, #rows do
        rows[i].itemID = nil
        rows[i].zoneKey = nil
        rows[i].spot = nil
        rows[i]:Hide()
    end
end

local function setRowTooltip(row)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemID then
            GameTooltip:SetItemByID(self.itemID)
            if self.itemWeight then GameTooltip:AddLine(string.format("Weight: %.2f", self.itemWeight), 0.55, 0.8, 1) end
            if self.itemCount then GameTooltip:AddLine("Looted: " .. self.itemCount, 0.55, 0.8, 1) end
        elseif self.zoneKey and MidnightSkinAdvisorDB and MidnightSkinAdvisorDB.zones[self.zoneKey] then
            local z = MidnightSkinAdvisorDB.zones[self.zoneKey]
            GameTooltip:AddLine(self.zoneKey, 0.5, 0.85, 1)
            GameTooltip:AddLine(string.format("Score/h: %.1f", zoneScorePerHour(z)), 1, 1, 1)
            GameTooltip:AddLine("Total Loot: " .. (z.totalCount or 0), 1, 1, 1)
            GameTooltip:AddLine("HV Flags: " .. (z.highValueFlags or 0), 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Hovercard", 0.7, 0.7, 0.9)
        elseif self.spot then
            GameTooltip:AddLine(self.spot.name, 0.5, 0.85, 1)
            GameTooltip:AddLine(string.format("Coordinates: %.1f, %.1f", self.spot.x, self.spot.y), 1, 1, 1)
            GameTooltip:AddLine("Use /msa tomtom <index>", 0.65, 0.9, 0.65)
        else
            return
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function ensureMinimapButton()
    if MSA.minimapButton then
        if MidnightSkinAdvisorDB.minimap and MidnightSkinAdvisorDB.minimap.hide then MSA.minimapButton:Hide() else MSA.minimapButton:Show() end
        return
    end

    local b = CreateFrame("Button", "MSA_MinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetNormalTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("CENTER", 0, 1)
    b.icon:SetTexture("Interface\\Icons\\INV_Misc_Pelt_Wolf_01")

    local function updatePosition()
        local angle = (MidnightSkinAdvisorDB.minimap and MidnightSkinAdvisorDB.minimap.angle) or 225
        local rad = math.rad(angle)
        local x = math.cos(rad) * 80
        local y = math.sin(rad) * 80
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    b:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            cmdUI()
        elseif btn == "RightButton" then
            self.isDragging = true
        end
    end)
    b:SetScript("OnMouseUp", function(self) self.isDragging = false end)
    b:SetScript("OnUpdate", function(self)
        if not self.isDragging then return end
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        px, py = px / scale, py / scale
        local angle = math.deg((math.atan2 and math.atan2(py - my, px - mx)) or math.atan((py - my), (px - mx)))
        MidnightSkinAdvisorDB.minimap.angle = angle
        updatePosition()
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Midnight Skin Advisor", 0.55, 0.85, 1)
        GameTooltip:AddLine("Left Click: Open UI", 1, 1, 1)
        GameTooltip:AddLine("Right Drag: Move", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updatePosition()
    if MidnightSkinAdvisorDB.minimap and MidnightSkinAdvisorDB.minimap.hide then b:Hide() end
    MSA.minimapButton = b
end

local function ensureWindow()
    if MSA.window then return end

    local f = CreateFrame("Frame", "MSA_MainFrame", UIParent, "BasicFrameTemplateWithInset,BackdropTemplate")
    f:SetSize(760, 500)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    f:SetBackdropColor(0.03, 0.04, 0.08, 0.96)
    f:SetBackdropBorderColor(0.35, 0.5, 0.95, 1)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -8)
    f.title:SetText(TITLE_COLOR .. "Midnight Skin Advisor v2.3.1|r")

    f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.subtitle:SetPoint("TOPLEFT", 16, -34)
    f.subtitle:SetText("Route your best Skinning + Leatherworking farm spots")

    f.panel = CreateFrame("Frame", nil, f, "InsetFrameTemplate3")
    f.panel:SetPoint("TOPLEFT", 12, -64)
    f.panel:SetPoint("BOTTOMRIGHT", -12, 12)

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", f.panel, "TOPLEFT", 12, -10)
    f.status:SetText("Session: --")

    f.hvButton = CreateFrame("Button", nil, f.panel, "UIPanelButtonTemplate")
    f.hvButton:SetSize(120, 22)
    f.hvButton:SetPoint("TOPRIGHT", -12, -8)
    f.hvButton:SetText("+ High Value")
    f.hvButton:SetScript("OnClick", function() cmdFlagHV(); if MSA.window:IsShown() then MSA.renderActiveTab() end end)

    local function makeTab(name, key, x)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(120, 24)
        b:SetPoint("TOPLEFT", f.panel, "TOPLEFT", x, 20)
        b:SetText(name)
        b.key = key
        b:SetScript("OnClick", function()
            MSA.ui.activeTab = b.key
            MSA.renderActiveTab()
        end)
        return b
    end

    f.tabs = {
        makeTab("Overview", "overview", 8),
        makeTab("Spots", "spots", 136),
        makeTab("Items", "items", 264),
        makeTab("Settings", "settings", 392),
    }

    f.content = CreateFrame("Frame", nil, f.panel)
    f.content:SetPoint("TOPLEFT", 10, -36)
    f.content:SetPoint("BOTTOMRIGHT", -10, 10)

    local function createRow(parent, y)
        local row = CreateFrame("Button", nil, parent)
        row:SetSize(700, 28)
        row:SetPoint("TOPLEFT", 4, y)

        row.barBg = row:CreateTexture(nil, "BACKGROUND")
        row.barBg:SetAllPoints()
        row.barBg:SetColorTexture(0.08, 0.10, 0.16, 0.8)

        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
        row.bar:SetMinMaxValues(0, 100)
        row.bar:SetValue(0)
        row.bar:SetPoint("TOPLEFT", 1, -1)
        row.bar:SetPoint("BOTTOMLEFT", 1, 1)
        row.bar:SetWidth(1)
        row.bar:SetStatusBarColor(0.28, 0.55, 1, 0.8)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:Hide()

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", 30, 0)
        row.text:SetJustifyH("LEFT")

        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.right:SetPoint("RIGHT", -8, 0)
        row.right:SetJustifyH("RIGHT")

        setRowTooltip(row)
        row:Hide()
        return row
    end

    for i = 1, 11 do f.overviewRows = f.overviewRows or {}; f.overviewRows[i] = createRow(f.content, -8 - ((i - 1) * 32)) end
    for i = 1, 14 do f.itemRows = f.itemRows or {}; f.itemRows[i] = createRow(f.content, -8 - ((i - 1) * 30)) end
    for i = 1, 12 do f.spotRows = f.spotRows or {}; f.spotRows[i] = createRow(f.content, -8 - ((i - 1) * 32)) end

    f.noteText = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.noteText:SetPoint("TOPLEFT", 8, -10)
    f.noteText:SetWidth(690)
    f.noteText:SetJustifyH("LEFT")
    f.noteText:SetJustifyV("TOP")
    f.noteText:Hide()

    f.resetButton = CreateFrame("Button", nil, f.content, "UIPanelButtonTemplate")
    f.resetButton:SetSize(180, 24)
    f.resetButton:SetPoint("BOTTOMLEFT", 8, 8)
    f.resetButton:SetText("Reset Session Data")
    f.resetButton:SetScript("OnClick", function() cmdReset(); MSA.renderActiveTab() end)
    f.resetButton:Hide()

    MSA.window = f
end

local function updateStatusLine()
    local db = MidnightSkinAdvisorDB
    local totalLoot = 0
    for _, count in pairs(db.items) do totalLoot = totalLoot + count end
    local zones = 0
    for _ in pairs(db.zones) do zones = zones + 1 end
    local mins = math.floor((now() - (db.createdAt or now())) / 60)
    MSA.window.status:SetText(string.format("|cffa8c7ffSession|r %dm   |cffa8c7ffZones|r %d   |cffa8c7ffTotal Loot|r %d", mins, zones, totalLoot))
end

function MSA.renderActiveTab()
    ensureWindow()
    local f = MSA.window
    updateStatusLine()

    clearRows(f.overviewRows); clearRows(f.itemRows); clearRows(f.spotRows)
    f.noteText:Hide(); f.resetButton:Hide()

    for _, tab in ipairs(f.tabs) do
        if tab.key == MSA.ui.activeTab then
            tab:GetFontString():SetText(TAB_COLOR .. tab:GetText() .. "|r")
        else
            tab:GetFontString():SetText(tab:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        end
    end

    if MSA.ui.activeTab == "overview" then
        local ranked = collectRankedZones()
        if #ranked == 0 then
            local r = f.overviewRows[1]
            r:Show(); r.icon:Hide(); r.bar:SetWidth(1)
            r.text:SetText("No data yet — start skinning and loot tracking will fill this view.")
            r.right:SetText("")
            return
        end

        local maxScore = ranked[1].scorePH > 0 and ranked[1].scorePH or 1
        for i = 1, math.min(#ranked, #f.overviewRows) do
            local rec, row = ranked[i], f.overviewRows[i]
            row:Show(); row.icon:Hide(); row.zoneKey = rec.zoneKey
            row.text:SetText(string.format("%d) %s", i, rec.zoneKey))
            row.right:SetText(string.format("%.1f/h  •  %d loot  •  HV %d", rec.scorePH, rec.total, rec.highValueFlags))
            local pct = math.max(0.02, math.min(1, rec.scorePH / maxScore))
            row.bar:SetWidth(698 * pct)
            if i == 1 then row.bar:SetStatusBarColor(0.48, 0.82, 0.36, 0.85)
            elseif i <= 3 then row.bar:SetStatusBarColor(0.34, 0.62, 1.0, 0.85)
            else row.bar:SetStatusBarColor(0.45, 0.45, 0.78, 0.7) end
        end

    elseif MSA.ui.activeTab == "items" then
        local rows = {}
        for itemID, cfg in pairs(MidnightSkinAdvisorDB.itemConfig) do
            rows[#rows + 1] = { id = itemID, cfg = cfg, count = MidnightSkinAdvisorDB.items[itemID] or 0 }
        end
        table.sort(rows, function(a, b) return a.count > b.count end)

        for i = 1, math.min(#rows, #f.itemRows) do
            local row, rec = f.itemRows[i], rows[i]
            row:Show()
            row.icon:Show()
            row.itemID = rec.id
            row.itemWeight = n(rec.cfg.weight)
            row.itemCount = rec.count
            row.icon:SetTexture(GetItemIcon(rec.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local special = rec.cfg.special and " |cffffd100[Gainful Gathering]|r" or ""
            row.text:SetText(string.format("%s%s", rec.cfg.name or ("Item " .. rec.id), special))
            row.right:SetText(string.format("ID:%d  w:%.2f  looted:%d", rec.id, n(rec.cfg.weight), rec.count))
            local pct = math.min(1, math.max(0.03, rec.count / math.max(1, rows[1].count)))
            row.bar:SetWidth(698 * pct)
            if rec.cfg.special then row.bar:SetStatusBarColor(0.92, 0.72, 0.2, 0.85)
            else row.bar:SetStatusBarColor(0.3, 0.6, 1.0, 0.75) end
        end

    elseif MSA.ui.activeTab == "spots" then
        local zone = GetRealZoneText() or "Unknown Zone"
        local spots = MidnightSkinAdvisorDB.spots[zone] or {}

        local header = f.spotRows[1]
        header:Show(); header.icon:Hide(); header.bar:SetWidth(698); header.spot = nil
        header.text:SetText("Current Zone: " .. zone)
        header.right:SetText("/msa addspot Name x y")
        header.bar:SetStatusBarColor(0.28, 0.50, 0.92, 0.45)

        if #spots == 0 then
            local r = f.spotRows[2]
            r:Show(); r.icon:Hide(); r.spot = nil
            r.text:SetText("No saved spots here yet.")
            r.right:SetText("Use /msa addspot River Packs 45.2 63.8")
            r.bar:SetWidth(1)
            return
        end

        for i = 1, math.min(#spots, #f.spotRows - 1) do
            local s = spots[i]
            local row = f.spotRows[i + 1]
            row:Show(); row.icon:Show(); row.spot = s
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
            row.text:SetText(string.format("%d) %s (%.1f, %.1f)", i, s.name, s.x, s.y))
            row.right:SetText("/msa tomtom " .. i)
            row.bar:SetWidth(698)
            row.bar:SetStatusBarColor(0.18, 0.38, 0.68, 0.45)
        end

    elseif MSA.ui.activeTab == "settings" then
        f.noteText:Show(); f.resetButton:Show()
        local notes = { "|cff8fe9ffFarm Intelligence|r" }
        for _, note in ipairs(MidnightSkinAdvisorDB.notes) do notes[#notes + 1] = "• " .. note end
        notes[#notes + 1] = ""
        notes[#notes + 1] = "|cff8fe9ffQuick Commands|r"
        notes[#notes + 1] = "/msa hv  •  Mark current zone as high-value beast farm"
        notes[#notes + 1] = "/msa weight <itemID> <weight>  •  tune value model"
        notes[#notes + 1] = "/msa ui  •  open/close advisor"
        notes[#notes + 1] = ""
        notes[#notes + 1] = "|cff8fe9ffMinimap|r"
        notes[#notes + 1] = "Left-click minimap icon to open UI, right-drag to move."
        f.noteText:SetText(table.concat(notes, "\n"))
    end
end

cmdUI = function()
    ensureWindow()
    if MSA.window:IsShown() then MSA.window:Hide() else MSA.renderActiveTab(); MSA.window:Show() end
end

local function cmdHelp()
    printHeader("Commands")
    print("  /msa ui               - Toggle beautiful UI")
    print("  /msa top              - Ranked zones by weighted score/hour")
    print("  /msa items            - List tracked item IDs and weights")
    print("  /msa note             - Show important farm notes")
    print("  /msa reset            - Reset collected session data")
    print("  /msa hv               - Flag High Value Beast activity")
    print("  /msa add [link] <w>   - Add tracked item from link")
    print("  /msa weight <id> <w>  - Set item weight")
    print("  /msa addspot Name x y - Save spot in current zone")
    print("  /msa spots            - List saved spots in current zone")
    print("  /msa tomtom [index]   - Set TomTom waypoint")
end

SLASH_MSA1 = "/msa"
SlashCmdList["MSA"] = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "help" then
        cmdHelp()
    elseif cmd == "ui" then
        cmdUI()
    elseif cmd == "top" then
        cmdTop()
    elseif cmd == "items" then
        cmdItems()
    elseif cmd == "note" then
        cmdNote()
    elseif cmd == "reset" then
        cmdReset(); if MSA.window and MSA.window:IsShown() then MSA.renderActiveTab() end
    elseif cmd == "hv" then
        cmdFlagHV(); if MSA.window and MSA.window:IsShown() then MSA.renderActiveTab() end
    elseif cmd == "spots" then
        cmdSpots()
    elseif cmd == "tomtom" then
        cmdTomTom(rest)
    elseif cmd == "weight" then
        local itemID, weight = rest:match("^(%d+)%s+([%d%.]+)$")
        cmdWeight(itemID, weight); if MSA.window and MSA.window:IsShown() then MSA.renderActiveTab() end
    elseif cmd == "add" then
        local link, weight = rest:match("^(|Hitem:.-|h%[.-%]|h)%s*([%d%.]*)$")
        cmdAdd(link, weight); if MSA.window and MSA.window:IsShown() then MSA.renderActiveTab() end
    elseif cmd == "addspot" then
        local name, x, y = rest:match("^(.-)%s+([%d%.]+)%s+([%d%.]+)$")
        if not name then print("Usage: /msa addspot Name 45.2 63.8") return end
        cmdAddSpot(name, tonumber(x), tonumber(y)); if MSA.window and MSA.window:IsShown() then MSA.renderActiveTab() end
    else
        cmdHelp()
    end
end

MSA:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON_NAME then ensureDB() end
        return
    end

    if event == "PLAYER_LOGIN" then
        ensureMinimapButton()
        printHeader("v2.3.1 loaded. /msa ui")
        return
    end

    if event == "CHAT_MSG_LOOT" then
        local msg = ...
        local itemLink = msg and msg:match("(|Hitem:.-|h%[.-%]|h)")
        if not itemLink then return end
        local itemID = parseItemIDFromLink(itemLink)
        if not itemID then return end
        addLoot(itemID, tonumber(msg:match("x(%d+)")) or 1)
        if MSA.window and MSA.window:IsShown() then MSA.renderActiveTab() end
    end
end)
