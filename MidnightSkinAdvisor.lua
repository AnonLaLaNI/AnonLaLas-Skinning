local ADDON_NAME = ...
local MSA = CreateFrame("Frame")

MSA:RegisterEvent("ADDON_LOADED")
MSA:RegisterEvent("CHAT_MSG_LOOT")
MSA:RegisterEvent("PLAYER_LOGIN")

local function now()
    return time()
end

local function n(v)
    return tonumber(v) or 0
end

local function round(v, d)
    local p = 10 ^ (d or 0)
    return math.floor((v * p) + 0.5) / p
end

-- v2.0 preset items from user links
-- weight = relative value in spot scoring
-- special = requires Gainful Gathering spec to be realistically farmable
local PRESET_ITEMS = {
    [238511] = { name = "Void-Tempered Leather",   weight = 1.00, type = "leather" },
    [238513] = { name = "Void-Tempered Scales",    weight = 1.00, type = "scales" },
    [238518] = { name = "Void-Tempered Hide",      weight = 1.35, type = "hide" },
    [238520] = { name = "Void-Tempered Plating",   weight = 1.45, type = "plating" },
    [238525] = { name = "Fantastic Fur",           weight = 8.00, type = "special", special = true },
    [238522] = { name = "Peerless Plumage",        weight = 8.00, type = "special", special = true },
    [238523] = { name = "Carving Canine",          weight = 8.00, type = "special", special = true },
    [238528] = { name = "Majestic Claw",           weight = 2.50, type = "majestic" },
    [238529] = { name = "Majestic Hide",           weight = 2.50, type = "majestic" },
    [238530] = { name = "Majestic Fin",            weight = 2.50, type = "majestic" },
}

local DEFAULT_CONFIG = {
    highValueBeastBonus = 1.20, -- multiplier used when user flags "high value beast" kills in a zone
    useTomTom = true,
}

local function ensureDB()
    MidnightSkinAdvisorDB = MidnightSkinAdvisorDB or {}
    local db = MidnightSkinAdvisorDB

    db.version = "2.0.0"
    db.createdAt = db.createdAt or now()
    db.config = db.config or {}
    for k, v in pairs(DEFAULT_CONFIG) do
        if db.config[k] == nil then db.config[k] = v end
    end

    db.items = db.items or {}
    db.zones = db.zones or {}
    db.spots = db.spots or {} -- user curated spot list per zone
    db.notes = db.notes or {
        "Special mats (Fantastic Fur / Peerless Plumage / Carving Canine) need Gainful Gathering spec.",
        "Those three mats currently appear extremely rare; community reports possible drop bug.",
        "High Value Beasts usually add 5-10 extra leather/scales when skinned.",
    }

    -- Auto-import preset item ids once
    if not db.itemConfig then
        db.itemConfig = {}
        for itemID, info in pairs(PRESET_ITEMS) do
            db.itemConfig[itemID] = {
                name = info.name,
                weight = info.weight,
                special = info.special and true or false,
                enabled = true,
            }
        end
    end
end

local function getZoneKey()
    local zone = GetRealZoneText() or "Unknown Zone"
    local sub = GetSubZoneText() or "Unknown Subzone"
    return zone .. " :: " .. sub
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

    local zoneKey = getZoneKey()
    local zone = getOrCreateZone(zoneKey)

    zone.lastAt = now()
    zone.totalCount = zone.totalCount + count
    zone.items[itemID] = (zone.items[itemID] or 0) + count

    local weight = n(cfg.weight)
    zone.weightedScore = zone.weightedScore + (count * weight)
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

local function printHeader(text)
    print("|cff6de1ffMidnightSkinAdvisor|r " .. text)
end

local function collectRankedZones()
    local rows = {}
    for zoneKey, zone in pairs(MidnightSkinAdvisorDB.zones) do
        table.insert(rows, {
            zoneKey = zoneKey,
            score = zone.weightedScore,
            scorePH = zoneScorePerHour(zone),
            total = zone.totalCount,
            highValueFlags = zone.highValueFlags or 0,
        })
    end
    table.sort(rows, function(a, b)
        if a.scorePH == b.scorePH then return a.total > b.total end
        return a.scorePH > b.scorePH
    end)
    return rows
end

local function cmdTop()
    local rows = collectRankedZones()
    printHeader("Top farm spots (weighted score/hour)")
    if #rows == 0 then
        print("  Noch keine Daten. Geh skinnen und nutze /msa top erneut.")
        return
    end

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
    for _, line in ipairs(MidnightSkinAdvisorDB.notes) do
        print("  - " .. line)
    end
end

local function cmdReset()
    MidnightSkinAdvisorDB.zones = {}
    MidnightSkinAdvisorDB.items = {}
    printHeader("Session data reset.")
end

local function ensureWindow()
    if MSA.window then return end

    local f = CreateFrame("Frame", "MSA_MainFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(620, 420)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("LEFT", f.TitleBg, "LEFT", 8, 0)
    f.title:SetText("Midnight Skin Advisor v2.0")

    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 12, -36)
    f.scroll:SetPoint("BOTTOMRIGHT", -28, 12)

    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(560, 1)
    f.scroll:SetScrollChild(f.content)

    f.text = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", 0, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetJustifyV("TOP")

    MSA.window = f
end

local function renderWindow()
    ensureWindow()

    local lines = {}
    table.insert(lines, "|cff6de1ffTop spots by weighted score/hour|r")

    local ranked = collectRankedZones()
    if #ranked == 0 then
        table.insert(lines, "No data yet. Start skinning.")
    else
        for i = 1, math.min(12, #ranked) do
            local r = ranked[i]
            table.insert(lines, string.format("%d) %s", i, r.zoneKey))
            table.insert(lines, string.format("   score/h: %.1f | total: %d | high-value flags: %d", r.scorePH, r.total, r.highValueFlags))
        end
    end

    table.insert(lines, "")
    table.insert(lines, "|cff6de1ffTracked Items|r")
    for itemID, cfg in pairs(MidnightSkinAdvisorDB.itemConfig) do
        local special = cfg.special and " |cffffd100[Gainful Gathering]|r" or ""
        table.insert(lines, string.format("%d - %s (w=%.2f)%s", itemID, cfg.name or "?", n(cfg.weight), special))
    end

    table.insert(lines, "")
    table.insert(lines, "|cff6de1ffNotes|r")
    for _, note in ipairs(MidnightSkinAdvisorDB.notes) do
        table.insert(lines, "- " .. note)
    end

    local text = table.concat(lines, "\n")
    MSA.window.text:SetText(text)
    MSA.window.content:SetHeight(math.max(400, 14 * #lines))
end

local function cmdUI()
    ensureWindow()
    if MSA.window:IsShown() then
        MSA.window:Hide()
    else
        renderWindow()
        MSA.window:Show()
    end
end

local function cmdFlagHV()
    local zone = getOrCreateZone(getZoneKey())
    zone.highValueFlags = (zone.highValueFlags or 0) + 1
    printHeader("High Value Beast flag added for current zone (bonus weighted in ranking).")
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
    if #spots == 0 then
        print("  Keine Spots gespeichert. /msa addspot Name 45.2 63.8")
        return
    end
    for i, s in ipairs(spots) do
        print(string.format("  %d) %s (%.1f, %.1f)", i, s.name, s.x, s.y))
    end
end

local function cmdTomTom(idx)
    if not TomTom or not TomTom.AddWaypoint then
        printHeader("TomTom nicht gefunden. Installiere TomTom für Waypoints.")
        return
    end

    local zone = GetRealZoneText() or "Unknown Zone"
    local spots = MidnightSkinAdvisorDB.spots[zone] or {}
    local nIdx = tonumber(idx) or 1
    local s = spots[nIdx]
    if not s then
        printHeader("Spot index nicht gefunden. /msa spots")
        return
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        printHeader("Kein mapID gefunden.")
        return
    end

    TomTom:AddWaypoint(mapID, s.x / 100, s.y / 100, {
        title = "MSA: " .. s.name,
        persistent = false,
        minimap = true,
        world = true,
    })
    printHeader("TomTom waypoint gesetzt: " .. s.name)
end

local function cmdWeight(itemID, weight)
    itemID = tonumber(itemID)
    weight = tonumber(weight)
    if not itemID or not weight then
        print("Usage: /msa weight <itemID> <weight>")
        return
    end

    MidnightSkinAdvisorDB.itemConfig[itemID] = MidnightSkinAdvisorDB.itemConfig[itemID] or {
        name = "Item " .. itemID,
        enabled = true,
        special = false,
    }
    MidnightSkinAdvisorDB.itemConfig[itemID].weight = weight
    printHeader(string.format("Weight set: %d -> %.2f", itemID, weight))
end

local function cmdAdd(itemLink, weight)
    local itemID = parseItemIDFromLink(itemLink)
    if not itemID then
        print("Usage: /msa add [itemLink] <weight>")
        return
    end

    local name = itemLink:match("%[(.-)%]") or ("Item " .. itemID)
    MidnightSkinAdvisorDB.itemConfig[itemID] = {
        name = name,
        weight = tonumber(weight) or 1,
        special = false,
        enabled = true,
    }
    printHeader(string.format("Item added: %s (%d)", name, itemID))
end

local function cmdHelp()
    printHeader("Commands")
    print("  /msa top              - Ranked zones by weighted score/hour")
    print("  /msa ui               - Toggle compact UI")
    print("  /msa items            - List tracked item IDs and weights")
    print("  /msa note             - Show important farm notes")
    print("  /msa reset            - Reset collected session data")
    print("  /msa hv               - Flag current zone for High Value Beast activity")
    print("  /msa add [link] <w>   - Add tracked item from link")
    print("  /msa weight <id> <w>  - Set item weight")
    print("  /msa addspot Name x y - Save spot in current zone")
    print("  /msa spots            - List saved spots in current zone")
    print("  /msa tomtom [index]   - Set TomTom waypoint to saved spot")
end

SLASH_MSA1 = "/msa"
SlashCmdList["MSA"] = function(msg)
    msg = msg or ""

    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "help" then
        cmdHelp()
    elseif cmd == "top" then
        cmdTop()
    elseif cmd == "ui" then
        cmdUI()
    elseif cmd == "items" then
        cmdItems()
    elseif cmd == "note" then
        cmdNote()
    elseif cmd == "reset" then
        cmdReset()
    elseif cmd == "hv" then
        cmdFlagHV()
    elseif cmd == "spots" then
        cmdSpots()
    elseif cmd == "tomtom" then
        cmdTomTom(rest)
    elseif cmd == "weight" then
        local itemID, weight = rest:match("^(%d+)%s+([%d%.]+)$")
        cmdWeight(itemID, weight)
    elseif cmd == "add" then
        local link, weight = rest:match("^(|Hitem:.-|h%[.-%]|h)%s*([%d%.]*)$")
        cmdAdd(link, weight)
    elseif cmd == "addspot" then
        local name, x, y = rest:match("^(.-)%s+([%d%.]+)%s+([%d%.]+)$")
        if not name then
            print("Usage: /msa addspot Name 45.2 63.8")
            return
        end
        cmdAddSpot(name, tonumber(x), tonumber(y))
    else
        cmdHelp()
    end
end

MSA:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon == ADDON_NAME then
            ensureDB()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        printHeader("v2.0 loaded. /msa help")
        return
    end

    if event == "CHAT_MSG_LOOT" then
        local msg = ...
        local itemLink = msg and msg:match("(|Hitem:.-|h%[.-%]|h)")
        if not itemLink then return end

        local itemID = parseItemIDFromLink(itemLink)
        if not itemID then return end

        local count = tonumber(msg:match("x(%d+)")) or 1
        addLoot(itemID, count)
    end
end)
