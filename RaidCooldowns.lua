------------------------------------------------
-- RaidCooldowns.lua (CLEAN / STABLE TEMPLATE BASE)
------------------------------------------------

------------------------------------------------
-- SAVED VARIABLES
------------------------------------------------
RaidCooldownsDB = RaidCooldownsDB or {}
RaidCooldownsDB.settings = RaidCooldownsDB.settings or {
    barWidth   = 180,
    barHeight  = 18,
    barSpacing = 6,
    centerBars = true,
    template   = "BAR_ONLY",
}

RaidCooldownsDB.layout = RaidCooldownsDB.layout or {
    width  = 360,
    height = 300,
}

RaidCooldownsDB.columns = RaidCooldownsDB.columns or {}
RaidCooldownsDB.order = RaidCooldownsDB.order or {}

------------------------------------------------
-- INTERNAL STATE
------------------------------------------------
local RC = {
    spells = {},      -- [spellID] = group
    ordered = {},     -- ordered list of groups
    locked = true,
}

RC.version = "0.1.1"

------------------------------------------------
-- CONSTANTS
------------------------------------------------
local ICON_GAP = 6
local OWNER_LINE_HEIGHT = 14
local OWNER_PADDING = 4


------------------------------------------------
-- FORWARD DECLARATIONS
------------------------------------------------
local templateDrop
local reset
local UpdateLayout

------------------------------------------------
-- BAR TEMPLATES
------------------------------------------------
local BAR_TEMPLATES = {
    SPELL_OWNERS = "Spell Owners",
    BAR_ONLY   = "Bar Only",
    ICON_BAR  = "Icon + Bar",
    ICON_ONLY = "Icon Only",
	COLUMN_LIST = "Column List",
}
local BAR_TEMPLATE_ORDER = {
    "ICON_BAR",
	"COLUMN_LIST",
    "BAR_ONLY",
    "SPELL_OWNERS",
    "ICON_ONLY",
}


------------------------------------------------
-- APPLY BAR TEMPLATE
------------------------------------------------
local function ApplyTemplate(bar, template)
    if not bar then return end

    -- DEBUG: PROVE TEMPLATE VALUE
   

    bar.icon:Show()
    bar.fill:Show()
    bar.label:Show()

    bar.icon:ClearAllPoints()
    bar.fill:ClearAllPoints()
    bar.label:ClearAllPoints()

    if template == "BAR_ONLY" then
        bar.icon:Hide()

        bar.fill:SetAllPoints(bar)
        bar.label:SetPoint("CENTER", bar)

    elseif template == "ICON_ONLY" then
        bar.fill:Hide()
        bar.label:Hide()

     local iconSize = RaidCooldownsDB.settings.barHeight

bar.icon:ClearAllPoints()
bar.icon:SetSize(iconSize, iconSize)
bar.icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)

		
		elseif template == "SPELL_OWNERS" then
    -- Hide bar fill
    bar.fill:Hide()

    -- Header
    bar.icon:Show()
    bar.label:Show()
    bar.ownersText:Show()

    bar.icon:SetSize(RaidCooldownsDB.settings.barHeight, RaidCooldownsDB.settings.barHeight)
    bar.icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)

    bar.label:SetPoint("LEFT", bar.icon, "RIGHT", 6, 0)

    -- Owners text container (content set elsewhere)
    bar.ownersText:ClearAllPoints()
    bar.ownersText:SetPoint("TOPLEFT", bar.icon, "BOTTOMLEFT", 0, -4)
    bar.ownersText:SetWidth(RaidCooldownsDB.settings.barWidth)



    else -- ICON_BAR
        bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

        bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", ICON_GAP, 0)
        bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 0)

        bar.label:SetPoint("LEFT", bar.fill, "LEFT", 4, 0)
    end
end
local function ApplyTemplateToAllBars()
    local template = RaidCooldownsDB.settings.template
    for _, group in ipairs(RC.ordered) do
        if group.bar then
            ApplyTemplate(group.bar, template)
        end
    end
end



------------------------------------------------
-- SHOW COLUMN MENU
------------------------------------------------

local function ShowColumnMenu(group, anchor)
    -- 🔒 SAFETY: ensure column always exists
    if type(group.column) ~= "number" then
        group.column = 1
        RaidCooldownsDB.columns[group.spellID] = 1
    end

    local menu = {
        {
            text = "Move to Column",
            isTitle = true,
            notCheckable = true,
        },
        {
            text = "Column 1",
            checked = (group.column == 1),
            func = function()
                group.column = 1
                RaidCooldownsDB.columns[group.spellID] = 1
                UpdateLayout()
            end,
        },
        {
            text = "Column 2",
            checked = (group.column == 2),
            func = function()
                group.column = 2
                RaidCooldownsDB.columns[group.spellID] = 2
                UpdateLayout()
            end,
        },
        {
            text = "Column 3",
            checked = (group.column == 3),
            func = function()
                group.column = 3
                RaidCooldownsDB.columns[group.spellID] = 3
                UpdateLayout()
            end,
        },
    }

    EasyMenu(
        menu,
        CreateFrame("Frame", nil, UIParent, "UIDropDownMenuTemplate"),
        anchor,
        0,
        0,
        "MENU"
    )
end

------------------------------------------------
-- GET COLUMN FROM Y 
------------------------------------------------
local function GetOrderFromY(columnGroups, dropY)
    local count = #columnGroups
    if count == 0 then
        return 1
    end

    if not dropY then
        return count + 1
    end

    local firstBar = columnGroups[1].bar
    if not firstBar or not firstBar:GetTop() then
        return count + 1
    end

    local barHeight = firstBar:GetHeight()
    local spacing   = RaidCooldownsDB.settings.barSpacing
    local slotHeight = barHeight + spacing

    local topY = firstBar:GetTop()

    -- distance from top of column
    local offset = topY - dropY

    -- raw floating index
    local rawIndex = offset / slotHeight

    -- 🔒 DEADZONE (40%)
    local DEADZONE = 0.40

    local slot
    if rawIndex < 0 then
        slot = 1
    else
        local base = math.floor(rawIndex)
        local frac = rawIndex - base

        if frac > (0.5 + DEADZONE / 2) then
            slot = base + 2
        elseif frac < (0.5 - DEADZONE / 2) then
            slot = base + 1
        else
            -- inside deadzone → snap to nearest
            slot = base + 1
        end
    end

    if slot < 1 then
        slot = 1
    elseif slot > count + 1 then
        slot = count + 1
    end

    return slot
end






------------------------------------------------
-- GET COLUMN FROM X 
------------------------------------------------
local function GetColumnFromX(x)
    local s = RaidCooldownsDB.settings
    local colGap = 24

    local totalWidth = (3 * s.barWidth) + (2 * colGap)
    local startX

    if s.centerBars then
        startX = (panel:GetWidth() - totalWidth) / 2
    else
        startX = 16
    end

    for col = 1, 3 do
        local colStart = startX + (col - 1) * (s.barWidth + colGap)
        local colEnd   = colStart + s.barWidth

        if x >= colStart and x <= colEnd then
            return col
        end
    end

    return nil
end


------------------------------------------------
-- HEALING / RAID COOLDOWNS (SOURCE OF TRUTH)
------------------------------------------------
local HEALING_COOLDOWNS = {

    -- DRUID
    [740]    = { name = "Tranquility", class = "DRUID", cooldown = 180 },
    [33891]  = { name = "Incarnation: Tree of Life", class = "DRUID", cooldown = 180 },
    [29166]  = { name = "Innervate", class = "DRUID", cooldown = 180 },
    [20484]  = { name = "Rebirth", class = "DRUID", cooldown = 600 },

    -- SHAMAN
    [108280] = { name = "Healing Tide Totem", class = "SHAMAN", cooldown = 180 },
    [98008]  = { name = "Spirit Link Totem", class = "SHAMAN", cooldown = 180 },
    [114052] = { name = "Ascendance", class = "SHAMAN", cooldown = 180 },
    [2825]   = { name = "Bloodlust", class = "SHAMAN", cooldown = 300 },

    -- PRIEST
    [64843]  = { name = "Divine Hymn", class = "PRIEST", cooldown = 180 },
    [47788]  = { name = "Guardian Spirit", class = "PRIEST", cooldown = 180 },
    [33206]  = { name = "Pain Suppression", class = "PRIEST", cooldown = 180 },
    [62618]  = { name = "Power Word: Barrier", class = "PRIEST", cooldown = 180 },
    [421453] = { name = "Ultimate Penitence", class = "PRIEST", cooldown = 240 },

    -- MONK
    [115310] = { name = "Revival", class = "MONK", cooldown = 180 },
    [388615] = { name = "Restoral", class = "MONK", cooldown = 180 },

    -- PALADIN
    [31821]  = { name = "Aura Mastery", class = "PALADIN", cooldown = 180 },

    -- EVOKER
    [363534] = { name = "Rewind", class = "EVOKER", cooldown = 240 },

    -- DEATH KNIGHT
    [51052]  = { name = "Anti-Magic Zone", class = "DEATHKNIGHT", cooldown = 240 },
    [61999]  = { name = "Raise Ally", class = "DEATHKNIGHT", cooldown = 600 },

    -- MAGE
    [80353]  = { name = "Time Warp", class = "MAGE", cooldown = 300 },

    -- DEMON HUNTER
    [196718] = { name = "Darkness", class = "DEMONHUNTER", cooldown = 300 },

    -- WARLOCK
    [20707]  = { name = "Soulstone", class = "WARLOCK", cooldown = 600 },
}


------------------------------------------------
-- MAIN PANEL (REQUIRED – DO NOT MOVE)
------------------------------------------------
local panel = CreateFrame("Frame", "RaidCooldownsPanel", UIParent)

panel:SetSize(
    RaidCooldownsDB.layout.width or 360,
    RaidCooldownsDB.layout.height or 300
)
panel:SetPoint("CENTER")
if RaidCooldownsDB.layout.point then
    panel:ClearAllPoints()
    panel:SetPoint(
        RaidCooldownsDB.layout.point,
        UIParent,
        RaidCooldownsDB.layout.relativePoint,
        RaidCooldownsDB.layout.x,
        RaidCooldownsDB.layout.y
    )
end

panel:SetMovable(true)
panel:SetResizable(true)
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")

panel:SetScript("OnDragStart", function(self)
    if RC.locked then return end
    self:StartMoving()
end)

panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    RaidCooldownsDB.layout.point = p
    RaidCooldownsDB.layout.relativePoint = rp
    RaidCooldownsDB.layout.x = x
    RaidCooldownsDB.layout.y = y
end)

local bg = panel:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.7)

------------------------------------------------
-- CREATE SPELL GROUPS + BARS (GLOBAL / REQUIRED)
------------------------------------------------
local function CreateGroups()
    for spellID, data in pairs(HEALING_COOLDOWNS) do
local bar = CreateFrame("Button", nil, panel)

-- Enable mouse for dragging
bar:EnableMouse(true)
bar:SetMovable(true)
bar:SetClampedToScreen(true)
bar:RegisterForDrag("LeftButton")

-- DRAG START
bar:SetScript("OnDragStart", function(self)
    if RC.locked then return end

    RC.dragging = true
    RC.suppressLayout = true

    self:SetFrameStrata("HIGH")
    self:SetAlpha(0.85)

    self:StartMoving()
end)

-- DRAG STOP
bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()

    self:SetFrameStrata("MEDIUM")
    self:SetAlpha(1)

    RC.dragging = false
    RC.suppressLayout = false

    HandleBarDrop(self)
end)


-- ❌ HARD DISABLE default click handling
bar:SetScript("OnClick", nil)

bar:SetMovable(true)
bar:SetClampedToScreen(true)
bar:RegisterForDrag("LeftButton")
bar:EnableMouse(true)



     



           

        bar.spellID = spellID
        bar.class = data.class

        -- Icon
        local icon = bar:CreateTexture(nil, "OVERLAY")
        icon:SetPoint("LEFT", 0, 0)
        icon:SetTexture(C_Spell.GetSpellTexture(spellID))
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        bar.icon = icon

        -- Fill
        local fill = CreateFrame("StatusBar", nil, bar)
        fill:SetFrameLevel(bar:GetFrameLevel())
        fill:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
        fill:SetMinMaxValues(0, 1)
        fill:SetValue(1)
        bar.fill = fill

        -- Label
        local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetText(data.name)
        label:SetDrawLayer("OVERLAY", 2)
        bar.label = label

        -- Owners text
        local ownersText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ownersText:SetJustifyH("LEFT")
        ownersText:SetJustifyV("TOP")
        ownersText:Hide()
        bar.ownersText = ownersText
		-- 🔒 Prevent child frames from stealing mouse input
bar.icon:EnableMouse(false)
bar.fill:EnableMouse(false)
bar.label:EnableMouse(false)
bar.ownersText:EnableMouse(false)


        local col = RaidCooldownsDB.columns[spellID] or 1

       RC.spells[spellID] = {
    spellID   = spellID,
    name      = data.name,
    class     = data.class,
    bar       = bar,
    owners    = {},
    hasOwners = false,
    column    = col,
    order     = RaidCooldownsDB.order and RaidCooldownsDB.order[spellID] or 1,
}


        table.insert(RC.ordered, RC.spells[spellID])
    end
end


------------------------------------------------
-- Bar Anchor
------------------------------------------------
local function GetBarAnchorX(barWidth)
    if RaidCooldownsDB.settings.centerBars then
        return "TOP", 0
    else
        return "TOPLEFT", 16
    end
end


------------------------------------------------
-- HELPERS
------------------------------------------------
local function GetClassColor(class)
    local c = RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.7, 0.7, 0.7
end



------------------------------------------------
-- UPDATE OWNERS (GLOBAL / REQUIRED)
------------------------------------------------
local function UpdateOwners()
    -- reset
    for _, group in pairs(RC.spells) do
        wipe(group.owners)
        group.hasOwners = false
    end

    local function UnitKnowsSpell(unit, spellID)
        local spellName = GetSpellInfo(spellID)
        if not spellName then return false end

        for i = 1, GetNumSpellTabs() do
            local _, _, offset, numSpells = GetSpellTabInfo(i)
            for s = offset + 1, offset + numSpells do
                local name = GetSpellBookItemName(s, BOOKTYPE_SPELL)
                if name == spellName then
                    return true
                end
            end
        end

        return false
    end

    local function CheckUnit(unit)
        local name = UnitName(unit)
        if not name then return end

        for spellID, group in pairs(RC.spells) do
            if UnitIsUnit(unit, "player") then
                if IsSpellKnown(spellID) then
                    group.owners[name] = true
                    group.hasOwners = true
                end
            end
        end
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            CheckUnit("raid" .. i)
        end
    elseif IsInGroup() then
        CheckUnit("player")
        for i = 1, GetNumSubgroupMembers() do
            CheckUnit("party" .. i)
        end
    else
        CheckUnit("player")
    end
end


------------------------------------------------
-- UPDATE PANEL MOUSE STATE
------------------------------------------------
local function UpdatePanelMouseState()
    panel:EnableMouse(not RC.locked)

    for _, group in pairs(RC.spells) do
        local bar = group.bar
        if bar then
            bar:EnableMouse(not RC.locked)
        end
    end
end



------------------------------------------------
-- APPLY CLASS COLOR
------------------------------------------------
local function ApplyClassColor(bar, class)
    local c = RAID_CLASS_COLORS[class]
    if c then
        bar.fill:SetStatusBarColor(c.r * 0.85, c.g * 0.85, c.b * 0.85)
    else
        bar.fill:SetStatusBarColor(0.7, 0.7, 0.7)
    end
end

------------------------------------------------
-- HANDLE BAR DROP
------------------------------------------------
function HandleBarDrop(bar)
    if RC.locked then
        UpdateLayout()
        return
    end

    RaidCooldownsDB.order = RaidCooldownsDB.order or {}

    local group = RC.spells[bar.spellID]
    if not group then
        UpdateLayout()
        return
    end

    -- COLUMN CALC (X AXIS)
    local barCenterX = bar:GetCenter()
    local panelLeft = panel:GetLeft()
    if not barCenterX or not panelLeft then
        UpdateLayout()
        return
    end

    local relativeX = barCenterX - panelLeft
    local newCol = GetColumnFromX(relativeX)
    if not newCol then
        UpdateLayout()
        return
    end

    -- BUILD COLUMN LIST (EXCLUDING SELF)
    local columnGroups = {}
    for _, g in pairs(RC.spells) do
        if g.column == newCol and g ~= group then
            table.insert(columnGroups, g)
        end
    end

    table.sort(columnGroups, function(a, b)
        return (a.order or 1) < (b.order or 1)
    end)

    -- ORDER CALC (Y AXIS)
local dropY = bar:GetTop() - (bar:GetHeight() / 2)

if not dropY then
    UpdateLayout()
    return
end


   local top = bar:GetTop()
if not top then
    UpdateLayout()
    return
end

local dropY = top - (bar:GetHeight() / 2)
local dropY = select(2, bar:GetCenter())
local newOrder = GetOrderFromY(columnGroups, dropY)

-- 🔒 Prevent multi-slot jumps
if group.order then
    if newOrder > group.order + 1 then
        newOrder = group.order + 1
    elseif newOrder < group.order - 1 then
        newOrder = group.order - 1
    end
end

    -- ASSIGN
    group.column = newCol
    group.order = newOrder

    -- NORMALIZE ORDERS
    for i, g in ipairs(columnGroups) do
        if i >= newOrder then
            g.order = i + 1
        else
            g.order = i
        end
        RaidCooldownsDB.order[g.spellID] = g.order
    end

    RaidCooldownsDB.columns[group.spellID] = newCol
    RaidCooldownsDB.order[group.spellID] = newOrder

    UpdateLayout()
end



------------------------------------------------
-- LAYOUT HANDLERS
------------------------------------------------
LayoutHandlers = {}


-- LAYOUT DISPATCHER & TEMPLATE HANDLERS
LayoutHandlers.COLUMN_LIST = function()
    local s = RaidCooldownsDB.settings
    local paddingX = 16
    local paddingY = -16
    local colGap = 24

    -- Build columns
    local columns = { [1]={}, [2]={}, [3]={} }

    for _, group in pairs(RC.spells) do
        local col = group.column or 1
        if col < 1 or col > 3 then col = 1 end
        table.insert(columns[col], group)
    end

    -- Sort each column by order
    for col = 1, 3 do
        table.sort(columns[col], function(a, b)
            return (a.order or 1) < (b.order or 1)
        end)
    end

    -- Layout columns
    for colIndex = 1, 3 do
        local totalWidth = (3 * s.barWidth) + (2 * colGap)
        local startX

        if s.centerBars then
            startX = (panel:GetWidth() - totalWidth) / 2
        else
            startX = paddingX
        end

        local x = startX + (colIndex - 1) * (s.barWidth + colGap)
        local y = paddingY

        for _, group in ipairs(columns[colIndex]) do
            local bar = group.bar
            bar:Show()

            bar:SetSize(s.barWidth, s.barHeight)
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", panel, x, y)

            bar.icon:Show()
            bar.icon:SetSize(s.barHeight, s.barHeight)
            bar.icon:ClearAllPoints()
            bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

            bar.fill:Show()
            bar.fill:ClearAllPoints()
            bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 6, 0)
            bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 0)

            ApplyClassColor(bar, group.class)

            bar.label:Show()
            bar.label:ClearAllPoints()
            bar.label:SetPoint("LEFT", bar.fill, "LEFT", 4, 0)

            y = y - s.barHeight - s.barSpacing
        end
    end
end



LayoutHandlers.BAR_ONLY = function()
    local s = RaidCooldownsDB.settings
    local y = -16

    for _, group in ipairs(RC.ordered) do
        local bar = group.bar
        bar:Show()

        bar:SetSize(s.barWidth, s.barHeight)
        bar:ClearAllPoints()
      local point, x = GetBarAnchorX(s.barWidth)
bar:SetPoint(point, panel, x, y)


        bar.icon:Hide()

        bar.fill:Show()
        bar.fill:ClearAllPoints()
        bar.fill:SetAllPoints(bar)
        ApplyClassColor(bar, group.class)

        bar.label:Show()
        bar.label:ClearAllPoints()
        bar.label:SetPoint("CENTER", bar)

        y = y - s.barHeight - s.barSpacing
    end
end
LayoutHandlers.SPELL_OWNERS = function()
    local s = RaidCooldownsDB.settings
    local y = -16

    for _, group in ipairs(RC.ordered) do
        if not group.hasOwners then
            group.bar:Hide()
        else
            local bar = group.bar
            bar:Show()

            bar:SetSize(s.barWidth, s.barHeight)
            bar:ClearAllPoints()
          local point, x = GetBarAnchorX(s.barWidth)
bar:SetPoint(point, panel, x, y)


            bar.icon:Show()
            bar.icon:SetSize(s.barHeight, s.barHeight)
            bar.icon:ClearAllPoints()
            bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

            bar.fill:Hide()

            bar.label:Show()
            bar.label:ClearAllPoints()
            bar.label:SetPoint("LEFT", bar.icon, "RIGHT", 6, 0)

            y = y - s.barHeight - s.barSpacing
        end
    end
end


LayoutHandlers.ICON_BAR = function()
    local s = RaidCooldownsDB.settings
    local y = -16

    for _, group in ipairs(RC.ordered) do
        local bar = group.bar
        bar:Show()

        ------------------------------------------------
        -- BUILD OWNER TEXT (single line for now)
        ------------------------------------------------
        local owners = {}
        if group.hasOwners then
            for name in pairs(group.owners) do
                table.insert(owners, name)
            end
        end
        table.sort(owners)

        local ownerText = table.concat(owners, ", ")
        local hasOwnerLine = (#owners > 0)

        ------------------------------------------------
        -- BAR HEIGHT (EXPANDS IF OWNERS EXIST)
        ------------------------------------------------
local barHeight =
    s.barHeight +
    (hasOwnerLine and (OWNER_LINE_HEIGHT + OWNER_PADDING + 2) or 0)


        bar:SetSize(s.barWidth, barHeight)
        bar:ClearAllPoints()

        local point, x = GetBarAnchorX(s.barWidth)
        bar:SetPoint(point, panel, x, y)

        ------------------------------------------------
        -- ICON
        ------------------------------------------------
        bar.icon:Show()
        bar.icon:ClearAllPoints()
        bar.icon:SetSize(s.barHeight, s.barHeight)
        bar.icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)

        ------------------------------------------------
        -- BAR FILL
        ------------------------------------------------
        bar.fill:Show()
        bar.fill:ClearAllPoints()
bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 6, 0)
bar.fill:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -4, 0)
bar.fill:SetPoint("BOTTOMLEFT", bar.icon, "BOTTOMRIGHT", 6, 0)
bar.fill:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", -4, -s.barHeight)


        ApplyClassColor(bar, group.class)

        ------------------------------------------------
        -- SPELL LABEL
        ------------------------------------------------
        bar.label:Show()
        bar.label:ClearAllPoints()
       bar.label:ClearAllPoints()
bar.label:SetPoint(
    "TOPLEFT",
    bar.icon,
    "TOPRIGHT",
    6,
    0
)
bar.label:SetPoint(
    "TOPRIGHT",
    bar,
    "TOPRIGHT",
    -6,
    0
)


        bar.label:SetJustifyH("LEFT")
        bar.label:SetJustifyV("MIDDLE")
        bar.label:SetWordWrap(false)
        bar.label:SetMaxLines(1)
        bar.label:SetDrawLayer("OVERLAY", 2)

        ------------------------------------------------
        -- OWNER TEXT (UNDER BAR)
        ------------------------------------------------
        if hasOwnerLine then
            bar.ownersText:Show()
            bar.ownersText:SetText(ownerText)

            bar.ownersText:ClearAllPoints()
            bar.ownersText:ClearAllPoints()
bar.ownersText:ClearAllPoints()
bar.ownersText:SetPoint(
    "TOPLEFT",
    bar.label,
    "BOTTOMLEFT",
    0,
    -2
)

bar.ownersText:SetWidth(s.barWidth - s.barHeight - 14)
bar.ownersText:SetHeight(OWNER_LINE_HEIGHT)
bar.ownersText:SetJustifyH("LEFT")
bar.ownersText:SetJustifyV("TOP")
bar.ownersText:SetWordWrap(false)
bar.ownersText:SetMaxLines(1)


            bar.ownersText:SetWidth(
                s.barWidth - s.barHeight - 14
            )
            bar.ownersText:SetHeight(OWNER_LINE_HEIGHT)
            bar.ownersText:SetJustifyH("LEFT")
            bar.ownersText:SetJustifyV("TOP")
            bar.ownersText:SetWordWrap(false)
            bar.ownersText:SetDrawLayer("OVERLAY", 2)
        else
            bar.ownersText:Hide()
        end

        ------------------------------------------------
        -- NEXT ROW (USES FULL BAR HEIGHT)
        ------------------------------------------------
       y = y - barHeight - s.barSpacing

    end
end


LayoutHandlers.ICON_ONLY = function()
    local s = RaidCooldownsDB.settings
    local y = -16

    for _, group in ipairs(RC.ordered) do
        local bar = group.bar
        bar:Show()

        local size = s.barHeight
        bar:SetSize(size, size)
        bar:ClearAllPoints()
      local point, x = GetBarAnchorX(s.barWidth)
bar:SetPoint(point, panel, x, y)


        bar.icon:Show()
        bar.icon:ClearAllPoints()
        bar.icon:SetAllPoints(bar)

        bar.fill:Hide()
        bar.label:Hide()

        y = y - size - s.barSpacing
    end
end


------------------------------------------------
-- UPDATE LAYOUT
------------------------------------------------
function UpdateLayout()
    -- 🔒 HARD BLOCK during ANY interaction
    if RC.dragging or RC.suppressLayout then
        return
    end

    local template = RaidCooldownsDB.settings.template
    local handler = LayoutHandlers[template]

    if handler then
        handler()
    end
end











------------------------------------------------
-- OPTIONS WINDOW (STABLE)
------------------------------------------------
local ROW_SPACING = -40
local options = CreateFrame("Frame", "RaidCooldownsOptionsWindow", UIParent, "BackdropTemplate")
options:SetSize(420, 540)
options:SetPoint("CENTER")
options:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
options:SetBackdropColor(0, 0, 0, 0.9)
options:Hide()
options:SetScript("OnShow", function()
    if lock then
        lock:SetChecked(RC.locked)
    end
    UpdateLayout()
end)





-- Title
local optTitle = options:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
optTitle:SetPoint("TOP", 0, -12)
optTitle:SetText("RaidCooldowns – Layout")

local s = RaidCooldownsDB.settings

options:SetMovable(true)
options:EnableMouse(true)
options:RegisterForDrag("LeftButton")

options:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

options:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)


------------------------------------------------
-- OPTIONS CONTROLS (ORDER MATTERS)
------------------------------------------------

-- Bar Width
local barWidth = CreateFrame("Slider", nil, options, "OptionsSliderTemplate")
barWidth:SetPoint("TOPLEFT", 20, -50)
barWidth:SetMinMaxValues(120, 320)
barWidth:SetValueStep(5)
barWidth:SetObeyStepOnDrag(true)
barWidth:SetValue(RaidCooldownsDB.settings.barWidth)

barWidth.Text:SetText("Bar Width")
barWidth.Low:SetText("120")
barWidth.High:SetText("320")

barWidth:SetScript("OnValueChanged", function(self, value)
    RaidCooldownsDB.settings.barWidth = math.floor(value)
    UpdateLayout()
end)





-- Bar Height
local barHeight = CreateFrame("Slider", nil, options, "OptionsSliderTemplate")
barHeight:SetPoint("TOPLEFT", barWidth, "BOTTOMLEFT", 0, ROW_SPACING)

barHeight:SetMinMaxValues(12, 40)
barHeight:SetValueStep(1)
barHeight:SetObeyStepOnDrag(true)
barHeight:SetValue(RaidCooldownsDB.settings.barHeight)

barHeight.Text:SetText("Bar Height")
barHeight.Low:SetText("12")
barHeight.High:SetText("40")

barHeight:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.settings.barHeight = math.floor(value)
    UpdateLayout()
end)





-- Bar Spacing
local barSpacing = CreateFrame("Slider", nil, options, "OptionsSliderTemplate")
barSpacing:SetPoint("TOPLEFT", barHeight, "BOTTOMLEFT", 0, ROW_SPACING)

barSpacing:SetMinMaxValues(2, 20)
barSpacing:SetValueStep(1)
barSpacing:SetObeyStepOnDrag(true)
barSpacing:SetValue(RaidCooldownsDB.settings.barSpacing)

barSpacing.Text:SetText("Bar Spacing")
barSpacing.Low:SetText("2")
barSpacing.High:SetText("20")

barSpacing:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.settings.barSpacing = math.floor(value)
    UpdateLayout()
end)





-- Center Bars
local center = CreateFrame("CheckButton", nil, options, "InterfaceOptionsCheckButtonTemplate")
center:SetPoint("TOPLEFT", barSpacing, "BOTTOMLEFT", 0, ROW_SPACING)
center.Text:SetText("Center Bars")
center:SetScript("OnClick", function(self)
    RaidCooldownsDB.settings.centerBars = self:GetChecked()
    UpdateLayout()
end)




-- Lock Panel
local lock = CreateFrame("CheckButton", nil, options, "InterfaceOptionsCheckButtonTemplate")
lock:SetPoint("TOPLEFT", center, "BOTTOMLEFT", 0, ROW_SPACING)
lock.Text:SetText("Lock Panel")
lock:SetChecked(RC.locked)
lock:SetScript("OnClick", function(self)
    RC.locked = self:GetChecked()
    UpdatePanelMouseState()
	

    if RC.locked then
        bg:SetColorTexture(0, 0, 0, 0.7)
        print("RaidCooldowns locked")
    else
        bg:SetColorTexture(0, 0, 0, 0.25)
        print("RaidCooldowns unlocked (drag panel)")
    end
end)







-- Panel Width
local panelWidth = CreateFrame("Slider", nil, options, "OptionsSliderTemplate")
panelWidth:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, ROW_SPACING)

panelWidth:SetMinMaxValues(240, 900)
panelWidth:SetValueStep(10)
panelWidth:SetObeyStepOnDrag(true)
panelWidth:SetValue(RaidCooldownsDB.layout.width or 360)

panelWidth.Text:SetText("Panel Width")
panelWidth.Low:SetText("240")
panelWidth.High:SetText("900")

panelWidth:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.layout.width = math.floor(value)
    panel:SetWidth(RaidCooldownsDB.layout.width)
    UpdateLayout()
end)




-- Panel Height
local panelHeight = CreateFrame("Slider", nil, options, "OptionsSliderTemplate")
panelHeight:SetPoint("TOPLEFT", panelWidth, "BOTTOMLEFT", 0, ROW_SPACING)

panelHeight:SetMinMaxValues(150, 700)
panelHeight:SetValueStep(10)
panelHeight:SetObeyStepOnDrag(true)
panelHeight:SetValue(RaidCooldownsDB.layout.height or 300)

panelHeight.Text:SetText("Panel Height")
panelHeight.Low:SetText("150")
panelHeight.High:SetText("700")

panelHeight:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.layout.height = math.floor(value)
    panel:SetHeight(RaidCooldownsDB.layout.height)
    UpdateLayout()
end)




------------------------------------------------
-- BAR TEMPLATE (RIGHT COLUMN)
------------------------------------------------

local templateLabel = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
templateLabel:SetText("Bar Template")
templateLabel:SetPoint("TOPRIGHT", options, "TOPRIGHT", -40, -80)

templateDrop = CreateFrame(
    "Frame",
    "RaidCooldownsTemplateDropdown",
    options,
    "UIDropDownMenuTemplate"
)

templateDrop:SetPoint("TOPRIGHT", templateLabel, "BOTTOMRIGHT", 20, -6)
UIDropDownMenu_SetWidth(templateDrop, 180)
UIDropDownMenu_SetText(templateDrop, BAR_TEMPLATES[s.template])

UIDropDownMenu_Initialize(templateDrop, function(self, level)
    for _, id in ipairs(BAR_TEMPLATE_ORDER) do
        UIDropDownMenu_AddButton({
            text = BAR_TEMPLATES[id],
            checked = (RaidCooldownsDB.settings.template == id),
            func = function()
                RaidCooldownsDB.settings.template = id
                UpdateLayout()
            end,
        })
    end
end)



------------------------------------------------
-- RESET LAYOUT BUTTON (RIGHT COLUMN)
------------------------------------------------

reset = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
reset:SetSize(180, 24)
reset:SetText("Reset Layout")

reset:SetPoint("TOP", templateDrop, "BOTTOM", 0, -16)
reset:SetFrameLevel(templateDrop:GetFrameLevel() + 2)
reset:Show()

reset:SetScript("OnClick", function()
    RaidCooldownsDB.settings.barWidth   = 180
    RaidCooldownsDB.settings.barHeight  = 18
    RaidCooldownsDB.settings.barSpacing = 6
    RaidCooldownsDB.settings.centerBars = true

    RaidCooldownsDB.layout.width  = 360
    RaidCooldownsDB.layout.height = 300
    panel:SetSize(360, 300)

    UpdateLayout()
end)





------------------------------------------------
-- EVENTS
------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")

ev:SetScript("OnEvent", function(_, event, addon)

    if event == "ADDON_LOADED" and addon == "RaidCooldowns" then
        ------------------------------------------------
        -- INIT
        ------------------------------------------------
        CreateGroups()

        -- Saved column container
        RaidCooldownsDB.columns = RaidCooldownsDB.columns or {}
		RaidCooldownsDB.order = RaidCooldownsDB.order or {}


        -- Default column assignment
        for spellID, group in pairs(RC.spells) do
            if not RaidCooldownsDB.columns[spellID] then
                RaidCooldownsDB.columns[spellID] = 1
            end
            group.column = RaidCooldownsDB.columns[spellID]
        end

        UpdatePanelMouseState()
        UpdateLayout()
        return
    end

    if event == "PLAYER_LOGIN" or event == "GROUP_ROSTER_UPDATE" then
        UpdateOwners()
        UpdateLayout()
    end
end)



------------------------------------------------
-- SLASH COMMANDS
------------------------------------------------

-- Toggle lock / unlock
SLASH_RAIDCOOLDOWNS1 = "/raidcd"
SlashCmdList.RAIDCOOLDOWNS = function()
    RC.locked = not RC.locked
    UpdatePanelMouseState()

    if RC.locked then
        bg:SetColorTexture(0, 0, 0, 0.7)
        print("RaidCooldowns locked")
    else
        bg:SetColorTexture(0, 0, 0, 0.25)
        print("RaidCooldowns unlocked (drag panel)")
    end
end

-- Force unlock (failsafe)
SLASH_RAIDCDUNLOCK1 = "/raidcdunlock"
SlashCmdList.RAIDCDUNLOCK = function()
    RC.locked = false
    UpdatePanelMouseState()
    bg:SetColorTexture(0, 0, 0, 0.25)
    print("RaidCooldowns force-unlocked")
end

-- Options window
SLASH_RAIDCDOPTIONS1 = "/raidcdoptions"
SlashCmdList.RAIDCDOPTIONS = function()
    options:SetShown(not options:IsShown())
end

-- Short alias
SLASH_RAIDCDCONFIG1 = "/rcd"
SlashCmdList.RAIDCDCONFIG = SlashCmdList.RAIDCDOPTIONS

-- Reset layout (position + size)
SLASH_RAIDCDRESET1 = "/raidcdreset"
SlashCmdList.RAIDCDRESET = function()
    RaidCooldownsDB.layout = {}
    ReloadUI()
end
