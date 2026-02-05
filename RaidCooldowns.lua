------------------------------------------------
-- RaidCooldowns.lua (CLEAN / STABLE TEMPLATE BASE)
------------------------------------------------

------------------------------------------------
-- SAVED VARIABLES
------------------------------------------------
RaidCooldownsDB = RaidCooldownsDB or {}
RaidCooldownsDB.settings = RaidCooldownsDB.settings or {}
RaidCooldownsDB.layout   = RaidCooldownsDB.layout   or {}
RaidCooldownsDB.columns  = RaidCooldownsDB.columns  or {}
RaidCooldownsDB.order    = RaidCooldownsDB.order    or {}
RaidCooldownsDB.profiles = RaidCooldownsDB.profiles or {}
RaidCooldownsDB.char     = RaidCooldownsDB.char or {}
RaidCooldownsDB.specProfiles = RaidCooldownsDB.specProfiles or {}


-- ✅ DEFAULTS (SAFE MERGE)
local DEFAULT_SETTINGS = {
font = "Fonts\\FRIZQT__.TTF",
    barWidth   = 180,
    barHeight  = 18,
    barSpacing = 6,
    centerBars = true,
    hideUnused = true,
    template   = "BAR_ONLY",

    spellTextOffsetX = 0,
    spellTextOffsetY = 0,
    cdTextOffsetX    = 0,
    cdTextOffsetY    = 0,
	spellTextSize = 12,
cdTextSize    = 12,

}


for k, v in pairs(DEFAULT_SETTINGS) do
    if RaidCooldownsDB.settings[k] == nil then
        RaidCooldownsDB.settings[k] = v
    end
end


local function GetSpellTextOffsets()
    local s = RaidCooldownsDB.settings or {}
    return s.spellTextOffsetX or 0, s.spellTextOffsetY or 0
end

------------------------------------------------
-- GET CD TEXT OFFSETS
------------------------------------------------
local function GetCDTextOffsets()
    local s = RaidCooldownsDB.settings or {}
    return s.cdTextOffsetX or 0, s.cdTextOffsetY or 0
end

------------------------------------------------
-- PROFILE SYSTEM (CORE)
------------------------------------------------
RaidCooldownsDB.profiles = RaidCooldownsDB.profiles or {}
RaidCooldownsDB.char     = RaidCooldownsDB.char or {}

local function GetCharKey()
    return UnitName("player").."-"..GetNormalizedRealmName()
end

local function GetCurrentProfileName()
    local key = GetCharKey()
    return RaidCooldownsDB.char[key] or "Default"
end

local function GetProfile()
    local name = GetCurrentProfileName()

    RaidCooldownsDB.profiles[name] = RaidCooldownsDB.profiles[name] or {
        settings = {},
        layout   = {},
        columns  = {},
        order    = {},
    }

    return RaidCooldownsDB.profiles[name]
end

local function ApplyProfile()
    local p = GetProfile()

    RaidCooldownsDB.settings = p.settings
    RaidCooldownsDB.layout   = p.layout
    RaidCooldownsDB.columns  = p.columns
    RaidCooldownsDB.order    = p.order
end


------------------------------------------------
-- INTERNAL STATE
------------------------------------------------
local RC = {
    previewOrdered = nil,   -- ⭐ must be inside table like this
    dragThrottle = 0,
    dragLastOrder = nil,
	dragCurrentOrder = nil,
	dragStarted = false,
	justDragged = false,


    spells = {},
    ordered = {},
    locked = true,

    -- Talent commit tracking
    talentCommitInProgress = false,
}

RC.debugShowAllSpells = false
RC.version = "0.1.1"
RC.specCache = {}



------------------------------------------------
-- CONSTANTS
------------------------------------------------
local ICON_GAP = 6
local OWNER_LINE_HEIGHT = 14
local OWNER_PADDING = 4
local NON_HEALER_COOLDOWNS = {
    [2825]  = true, -- Bloodlust
    [80353] = true, -- Time Warp
    [196718]= true, -- Darkness
    [51052] = true, -- Anti-Magic Zone
    [20707] = true, -- Soulstone
}

------------------------------------------------
-- PLAYER HAS SPELL
------------------------------------------------
local function PlayerHasSpell(spellID)
    return C_SpellBook.IsSpellKnown(spellID)
end


------------------------------------------------
-- 🔥 REMOVE CHECKBOX COLUMN FROM ALL DROPDOWNS
------------------------------------------------
hooksecurefunc("UIDropDownMenu_AddButton", function(_, level)

    if not level then return end

    local list = _G["DropDownList"..level]
    if not list then return end

    for i = 1, UIDROPDOWNMENU_MAXBUTTONS do
        local b = _G[list:GetName().."Button"..i]

        if b then
            -- Hide Blizzard checkbox/radio visuals
            if b.Check then b.Check:Hide() end
            if b.UnCheck then b.UnCheck:Hide() end
            if b.IconCheck then b.IconCheck:Hide() end

            -- ⭐ SHIFT TEXT LEFT (removes square spacing)
            if b:GetName() and b:GetFontString() then
                local fs = b:GetFontString()
                fs:ClearAllPoints()
        fs:SetPoint("LEFT", b, "LEFT", 4, 0)

            end
        end
    end
end)



------------------------------------------------
-- HEALER COOLDOWNS ONLY
------------------------------------------------
local HEALER_ONLY = {
    [740]    = true,
    [29166]  = true,
    [108280] = true, -- Healing Tide
    [114052] = true, -- ✅ Ascendance (FIX)
    [98008]  = true,
    [64843]  = true,
    [62618]  = true,
    [47788]  = true,
    [33206]  = true,
    [31821]  = true,
    [363534] = true,
}


------------------------------------------------
-- NON-HEALER SPELL → VALID SPECS
------------------------------------------------
local NON_HEALER_SPELL_SPECS = {
   [2825] = { [262]=true, [263]=true, [264]=true },                             -- Bloodlust 
    [80353] = { [62] = true, [63] = true, [64] = true },     -- Time Warp (Mage)
    [196718]= { [577] = true, [581] = true },                -- Darkness (DH)
    [51052] = { [250] = true },                              -- AMZ (Blood DK)
    [20707] = { [265] = true, [266] = true, [267] = true },  -- Soulstone (Warlock)
}


local FONT_CHOICES = {
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"]  = "Fonts\\ARIALN.TTF",
    ["Morpheus"]      = "Fonts\\MORPHEUS.ttf",
    ["Skurri"]        = "Fonts\\skurri.ttf",
}


------------------------------------------------
-- FONT CHOICE
------------------------------------------------
local panel      -- ⭐ ADD THIS LINE
local templateDrop
local reset
local UpdateLayout
local HideAllBars


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

local sx = RaidCooldownsDB.settings.spellTextOffsetX or 0
local sy = RaidCooldownsDB.settings.spellTextOffsetY or 0

bar.label:SetPoint("LEFT", bar.fill, "LEFT", 4 + sx, sy)


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
-- TIME FORMATTER (REQUIRED)
------------------------------------------------
local function FormatTime(seconds)
    if seconds >= 60 then
        local m = math.floor(seconds / 60)
        local s = math.floor(seconds % 60)
        return string.format("%d:%02d", m, s)
    elseif seconds >= 10 then
        return string.format("%d", math.floor(seconds))
    else
        return string.format("%.1f", seconds)
    end
end


------------------------------------------------
-- READY LABEL HELPER (MUST BE ABOVE COOLDOWN LOOP)
------------------------------------------------
local function GetReadyLabel(group)
    local ownerCount = 0
    local ownerName

    for name in pairs(group.owners) do
        ownerName = name
        ownerCount = ownerCount + 1
        if ownerCount > 1 then
            break
        end
    end

    if ownerCount == 1 and ownerName then
        return ownerName .. " - READY"
    end

    return "READY"
end


------------------------------------------------
-- COOLDOWN BAR UPDATE (DRAG SAFE / NO GOTO)
------------------------------------------------
local function CooldownOnUpdate(self, elapsed)

    local now = GetTime()

    for _, group in pairs(RC.spells) do
        local bar = group.bar

        if bar and bar:IsShown() and bar.cdText then

            local cdText = bar.cdText

            ------------------------------------------------
            -- ACTIVE COOLDOWN
            ------------------------------------------------
            if group.onCooldown then
                local remaining = group.cooldownEnd - now

                if remaining <= 0 then
                    group.onCooldown = false

                    if bar.fill then
                        bar.fill:SetValue(1)
                    end

                    cdText:SetText("READY")
                    cdText:SetTextColor(0,1,0)
                    cdText:Show()

                else
                    if group.cooldownDuration > 0 and bar.fill then
                        bar.fill:SetValue(remaining / group.cooldownDuration)
                    end

                    cdText:SetText(FormatTime(remaining))
                    cdText:SetTextColor(1,1,1)
                    cdText:Show()
                end

            ------------------------------------------------
            -- NOT ON COOLDOWN
            ------------------------------------------------
            else
                if bar.fill then
                    bar.fill:SetValue(1)
                end

                cdText:SetText("READY")
                cdText:SetTextColor(0,1,0)
                cdText:Show()
            end

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
   -- SHAMAN
[114052] = { name = "Ascendance", class = "SHAMAN", cooldown = 180 },
[108280] = { name = "Healing Tide Totem", class = "SHAMAN", cooldown = 180 },
[98008]  = { name = "Spirit Link Totem", class = "SHAMAN", cooldown = 180 },
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
-- SPEC FILTER (SOURCE OF TRUTH)
------------------------------------------------
local SPEC_FILTER = {
    -- PRIEST
    [64843]  = { Holy = true },           -- Divine Hymn
    [62618]  = { Discipline = true },     -- Barrier
    [47788]  = { Holy = true },           -- Guardian Spirit
    [33206]  = { Discipline = true },     -- Pain Suppression

    -- DRUID
    [740]    = { Restoration = true },    -- Tranquility
    [29166]  = { Restoration = true },    -- Innervate

    -- SHAMAN
    [108280] = { Restoration = true },    -- Healing Tide
    [98008]  = { Restoration = true },    -- Spirit Link

    -- PALADIN
    [31821]  = { Holy = true },            -- Aura Mastery
}




------------------------------------------------
-- MAIN PANEL (REQUIRED – DO NOT MOVE)
------------------------------------------------
panel = CreateFrame("Frame", "RaidCooldownsPanel", UIParent)

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
------------------------------------------------
-- PANEL DRAG (RESTORE)
------------------------------------------------
panel:SetScript("OnDragStart", function(self)
    if RC.locked then return end
    self:StartMoving()
end)

panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()

    local point, _, relativePoint, x, y = self:GetPoint()
    RaidCooldownsDB.layout.point = point
    RaidCooldownsDB.layout.relativePoint = relativePoint
    RaidCooldownsDB.layout.x = x
    RaidCooldownsDB.layout.y = y
end)



local bg = panel:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.7)

------------------------------------------------
-- COOLDOWN UPDATE LOOP (AFTER PANEL EXISTS)
------------------------------------------------
panel:SetScript("OnUpdate", CooldownOnUpdate)
panel:HookScript("OnUpdate", function()

    local draggingBar = RC.dragging
    if not draggingBar then return end
	-- ⭐ SKIP FIRST FRAME (fix first-drag jump)
if not RC.dragStarted then
    RC.dragStarted = true
    return
end


    local group = RC.spells[draggingBar.spellID]
    if not group then return end

    local s = RaidCooldownsDB.settings

    ------------------------------------------------
    -- ⭐ CURSOR POSITION (UI SCALE SAFE)
    ------------------------------------------------
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()

    cursorX = cursorX / scale
    cursorY = cursorY / scale

    ------------------------------------------------
    -- ⭐ MOVE DRAGGED BAR WITH CURSOR
    ------------------------------------------------
    draggingBar:ClearAllPoints()
draggingBar:SetPoint(
    "CENTER",
    UIParent,
    "BOTTOMLEFT",
    cursorX,
    cursorY
)


   ------------------------------------------------
-- ⭐ BUILD REAL VISIBLE LIST (NOT PREVIEW)
------------------------------------------------
local visible = GetVisibleOrdered()
if #visible == 0 then return end

------------------------------------------------
-- ⭐ CLEAN SLOT CALCULATION (PIXEL BASED)
------------------------------------------------
local rowSize = s.barHeight + s.barSpacing

local _, panelTop = panel:GetCenter()
panelTop = panelTop + (panel:GetHeight() / 2)

if not panelTop then return end

-- distance from top of panel
local offsetFromTop = panelTop - cursorY

-- convert cursor position into list index
local newOrder = math.floor((offsetFromTop - 16) / rowSize) + 1

------------------------------------------------
-- CLAMP
------------------------------------------------
if newOrder < 1 then newOrder = 1 end
if newOrder > #visible then newOrder = #visible end

------------------------------------------------
-- ⭐ STOP REBUILDING IF ORDER DID NOT CHANGE
------------------------------------------------
-- ⭐ ONLY UPDATE WHEN SLOT ACTUALLY CHANGES
if RC.dragCurrentOrder == newOrder then
    return
end

RC.dragCurrentOrder = newOrder




    ------------------------------------------------
    -- BUILD PREVIEW ORDER
    ------------------------------------------------
    local preview = {}

    for _, g in ipairs(visible) do
        table.insert(preview, g)
    end

    -- remove dragged
    for i = #preview, 1, -1 do
        if preview[i] == group then
            table.remove(preview, i)
            break
        end
    end

   -- insert at new position
table.insert(preview, newOrder, group)

RC.previewOrdered = preview

UpdateLayout()


  
end)





------------------------------------------------
-- SHORT DISPLAY NAMES (UI ONLY)
------------------------------------------------
local SHORT_SPELL_NAMES = {
    -- Shaman
    [108280] = "Healing Tide",
    [98008]  = "Spirit Link",
    [114052] = "Ascendance",

    -- Death Knight
    [51052]  = "AMZ",

    -- Priest
    [62618]  = "Barrier",
    [64843]  = "Divine Hymn",

    -- Druid
    [33891]    = "Incarnation",
}

local function GetDisplaySpellName(spellID, fallbackName)
    return SHORT_SPELL_NAMES[spellID] or fallbackName
end

------------------------------------------------
-- CREATE SPELL GROUPS + BARS (GLOBAL / REQUIRED)
------------------------------------------------
local function CreateGroups()
    -- ⭐ BUILD STABLE SPELL LIST (fix first-drag reorder)
local sortedSpells = {}

for spellID in pairs(HEALING_COOLDOWNS) do
    table.insert(sortedSpells, spellID)
end

-- DO NOT SORT HERE

for _, spellID in ipairs(sortedSpells) do
    local data = HEALING_COOLDOWNS[spellID]

	local bar = CreateFrame("Button", nil, panel)
    bar:Hide()


bar:EnableMouse(true)   -- ⭐ REQUIRED
bar:SetMovable(true)    -- ⭐ REQUIRED
bar:RegisterForDrag("LeftButton")

------------------------------------------------
-- DRAG TO REORDER (NO FRAME MOVEMENT)
------------------------------------------------
bar:SetScript("OnDragStart", function(self)
    if RC.locked then return end

RC.dragging = self
-- ⭐ Get REAL visible index (fix first-drag reorder)
local visible = GetVisibleOrdered()
for i, g in ipairs(visible) do
    if g.bar == self then
        RC.dragInitialOrder = i
        break
    end
end


RC.dragStarted = false   -- ⭐ RESET FIRST FRAME
RC.dragCurrentOrder = nil


    -- ⭐ FIX FIRST-DRAG JUMP
   RC.previewOrdered = nil
  RC.dragLastOrder = -999
   


    self:SetAlpha(0.6)
    self:SetFrameStrata("DIALOG")

   

    RC.dragSnapshot = {}

    for _, g in ipairs(GetVisibleOrdered()) do
        if g.bar and g.bar ~= self then
            local _, y = g.bar:GetCenter()
            if y then
                table.insert(RC.dragSnapshot, y)
            end
        end
    end

    table.sort(RC.dragSnapshot, function(a,b) return a > b end)
end)



   

bar:SetScript("OnDragStop", function(self)

    self:SetFrameStrata("MEDIUM")
    self:SetAlpha(1)

    ------------------------------------------------
    -- ⭐ COMMIT PREVIEW ORDER SAFELY
    ------------------------------------------------
    if RC.previewOrdered then

        for i, g in ipairs(RC.previewOrdered) do
            g.order = i
            RaidCooldownsDB.order[g.spellID] = i
        end

        -- ⭐ COPY PREVIEW INTO REAL ORDERED LIST
        wipe(RC.ordered)

        for _, g in ipairs(RC.previewOrdered) do
            table.insert(RC.ordered, g)
        end
    end

    RC.previewOrdered = nil
    RC.dragging = nil
	RC.dragCurrentOrder = nil
    RC.dragStarted = false
    RC.justDragged = true

    UpdateLayout()
end)








-- ❌ HARD DISABLE default click handling
bar:SetScript("OnClick", nil)
           

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

-- 🔽 FORCE BELOW ALL TEXT
fill:SetFrameLevel(bar:GetFrameLevel() - 2)

fill:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
fill:SetMinMaxValues(0, 1)
fill:SetValue(1)

bar.fill = fill
local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetText(GetDisplaySpellName(spellID, data.name))




bar.label = label
-- Cooldown text (right side of bar)
local cdText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cdText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)


cdText:SetJustifyH("RIGHT")
cdText:Hide()

bar.cdText = cdText



fill:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
fill:SetMinMaxValues(0, 1)
fill:SetValue(1)

bar.fill = fill

        fill:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
        fill:SetMinMaxValues(0, 1)
        fill:SetValue(1)
        bar.fill = fill

       

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
    name = GetDisplaySpellName(spellID, data.name),
    class     = data.class,
    bar       = bar,
    owners    = {},
    hasOwners = false,
    column    = col,
order = RaidCooldownsDB.order[spellID] or (#RC.ordered + 1),
	cooldownStart = 0,
cooldownDuration = 0,
cooldownEnd = 0,
onCooldown = false,

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
-- BUILD BAR LABEL TEXT
------------------------------------------------
local function GetBarLabelText(group)
    -- Single owner → "Name - Spell"
    local ownerCount = 0
    local ownerName

    for name in pairs(group.owners) do
        ownerName = name
        ownerCount = ownerCount + 1
        if ownerCount > 1 then
            break
        end
    end

    if ownerCount == 1 and ownerName then
        return ownerName .. " - " .. group.name
    end

    -- Multiple or unknown owners → spell name only
    return group.name
end







------------------------------------------------
-- UNIT HAS TALENT SPELL
------------------------------------------------
local function UnitHasTalentSpell(unit, spellID)
    for i = 1, 3 do
        for j = 1, 7 do
            local _, _, _, _, _, spell = GetTalentInfo(i, j, 1)
            if spell == spellID then
                return true
            end
        end
    end
    return false
end






------------------------------------------------
-- UPDATE GROUP COOLDOWNS (RETAIL SAFE)
------------------------------------------------
local function UpdateGroupCooldown(group)
    local cd = C_Spell.GetSpellCooldown(group.spellID)

    if not cd or not cd.startTime or cd.duration == 0 then
        group.onCooldown = false
        return false
    end

    -- Ignore GCD / fake cooldowns
    if cd.duration <= 1.5 then
        group.onCooldown = false
        return false
    end

    group.cooldownStart    = cd.startTime
    group.cooldownDuration = cd.duration
    group.cooldownEnd      = cd.startTime + cd.duration
    group.onCooldown       = true

    return true
end




------------------------------------------------
-- PLAYER HAS ACTION BAR SPELL (MIDNIGHT SAFE)
------------------------------------------------
local function PlayerHasActionBarSpell(spellID)
    local buttons = C_ActionBar.FindSpellActionButtons(spellID)
    return buttons and #buttons > 0
end


------------------------------------------------
-- UPDATE OWNERS (CHOICE NODE AUTHORITATIVE)
------------------------------------------------
local function UpdateOwners()
if RC.dragging then return end


    ------------------------------------------------
    -- RESET
    ------------------------------------------------
    for _, group in pairs(RC.spells) do
        wipe(group.owners)
        group.hasOwners = false
    end

  ------------------------------------------------
-- PLAYER RESTO SHAMAN CHOICE (SPELL-AUTHORITATIVE)
------------------------------------------------
local activeRestoShamanSpell
local inactiveRestoShamanSpell

if select(2, UnitClass("player")) == "SHAMAN" then
    local hasAscendance  = IsPlayerSpell(114052)
    local hasHealingTide = IsPlayerSpell(108280)

    if hasAscendance then
        activeRestoShamanSpell = 114052
        inactiveRestoShamanSpell = 108280
    elseif hasHealingTide then
        activeRestoShamanSpell = 108280
        inactiveRestoShamanSpell = 114052
    end
end


    ------------------------------------------------
    -- CHECK ONE UNIT
    ------------------------------------------------
    local function CheckUnit(unit)
        local name = UnitName(unit)
        if not name then return end

        local _, class = UnitClass(unit)
        local role = UnitGroupRolesAssigned(unit)
        local specID = RC.specCache[name]

        for spellID, group in pairs(RC.spells) do

            ------------------------------------------------
            -- ❌ HARD BLOCK INACTIVE SHAMAN TALENT
            ------------------------------------------------
            if inactiveRestoShamanSpell and spellID == inactiveRestoShamanSpell then
                -- skip entirely
            else

                ------------------------------------------------
                -- PLAYER RESTO SHAMAN (ACTIVE TALENT ONLY)
                ------------------------------------------------
                if unit == "player"
                   and class == "SHAMAN"
                   and role == "HEALER"
                   and group.class == "SHAMAN"
                   and spellID == activeRestoShamanSpell
                then
                    group.owners[name] = true
                    group.hasOwners = true

                ------------------------------------------------
                -- ALL OTHER HEALER COOLDOWNS
                ------------------------------------------------
               elseif HEALER_ONLY[spellID]
   and group.class == class
then

                    if unit == "player" then
                        if IsPlayerSpell(spellID) then
                            group.owners[name] = true
                            group.hasOwners = true
                        end
                    else
                        group.owners[name] = true
                        group.hasOwners = true
                    end
                end

                ------------------------------------------------
                -- NON-HEALER COOLDOWNS
                ------------------------------------------------
                if NON_HEALER_SPELL_SPECS[spellID]
                   and specID
                   and group.class == class
                   and NON_HEALER_SPELL_SPECS[spellID][specID]
                then
                    group.owners[name] = true
                    group.hasOwners = true
                end
            end
        end
    end

    ------------------------------------------------
    -- SCAN GROUP
    ------------------------------------------------
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            CheckUnit("raid"..i)
        end
    elseif IsInGroup() then
        CheckUnit("player")
        for i = 1, GetNumSubgroupMembers() do
            CheckUnit("party"..i)
        end
    else
        CheckUnit("player")
    end
end



------------------------------------------------
-- BUILD OWNER STRING
------------------------------------------------
local function BuildOwnerString(group)
    local owners = {}

    for name in pairs(group.owners) do
        table.insert(owners, name)
    end

    table.sort(owners)
    return table.concat(owners, ", ")
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
-- GET VISIBLE ORDERED LIST (ICON_BAR SAFE)
------------------------------------------------
function GetVisibleOrdered()
    local list = {}

    ------------------------------------------------
    -- ⭐ ALWAYS USE STABLE ORDER
    ------------------------------------------------
    local source = RC.previewOrdered or RC.ordered

    ------------------------------------------------
    -- FILTER VISIBLE
    ------------------------------------------------
    for _, g in ipairs(source) do
        if RC.debugShowAllSpells or g.hasOwners then
            table.insert(list, g)
        end
    end

    return list
end





------------------------------------------------
-- NormalizeColumnOrders
------------------------------------------------
function NormalizeColumnOrders()

    -- ⭐ DO NOT NORMALIZE FOR ICON_BAR / BAR_ONLY / ICON_ONLY
    if RaidCooldownsDB.settings.template ~= "COLUMN_LIST" then
        return
    end

    if RC.dragging then return end

    local cols = { [1]={}, [2]={}, [3]={} }


    ------------------------------------------------
    -- ⭐ USE ORDERED LIST (NOT HASH TABLE)
    ------------------------------------------------
    for _, g in ipairs(RC.ordered) do
    table.insert(cols[g.column or 1], g)
end


    for col = 1, 3 do
        table.sort(cols[col], function(a, b)
            return (a.order or 1) < (b.order or 1)
        end)

        for i, g in ipairs(cols[col]) do
            g.order = i
            RaidCooldownsDB.order[g.spellID] = i
        end
    end
end


------------------------------------------------
-- HANDLE BAR DROP
------------------------------------------------
function HandleBarDrop(bar)
    if RC.locked then
	RebuildOrderedList()

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

for _, g in ipairs(GetVisibleOrdered()) do
    if g.column == newCol and g ~= group then
        table.insert(columnGroups, g)
    end
end


    table.sort(columnGroups, function(a, b)
        return (a.order or 1) < (b.order or 1)
    end)

    -- ORDER CALC (Y AXIS)
local _, dropY = bar:GetCenter()
if not dropY then
    UpdateLayout()
    return
end

local newOrder = GetOrderFromY(nil, dropY)

-- ⭐ Clamp order safely (prevents skipping)
local visible = {}

for _, g in ipairs(RC.ordered) do
    if RC.debugShowAllSpells or g.hasOwners then
        table.insert(visible, g)
    end
end


if newOrder < 1 then newOrder = 1 end
if newOrder > #visible then newOrder = #visible end







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

NormalizeColumnOrders()
RebuildOrderedList()   -- ⭐ THIS WAS MISSING
UpdateLayout()


end




------------------------------------------------
-- RESETBARVISUALS 
------------------------------------------------
local function ResetBarVisuals(bar, group)
    bar.icon:Show()
    bar.fill:Show()
    bar.label:Show()

    -- ALWAYS SAFE FONT
    local font = (RaidCooldownsDB.settings and RaidCooldownsDB.settings.font)
        or "Fonts\\FRIZQT__.TTF"

    -- TEXT CONTENT
    bar.label:SetText(GetBarLabelText(group))

    ------------------------------------------------
    -- SPELL / NAME TEXT
    ------------------------------------------------
    bar.label:SetFont(
        font,
        RaidCooldownsDB.settings.spellTextSize or 12,
        "OUTLINE"
    )

    local sx = RaidCooldownsDB.settings.spellTextOffsetX or 0
    local sy = RaidCooldownsDB.settings.spellTextOffsetY or 0

    bar.label:ClearAllPoints()
    bar.label:SetPoint("LEFT", bar.fill, "LEFT", 4 + sx, sy)

    ------------------------------------------------
    -- COUNTDOWN / READY TEXT
    ------------------------------------------------
    if bar.cdText then
        bar.cdText:SetFont(
            font,
            RaidCooldownsDB.settings.cdTextSize or 12,
            "OUTLINE"
        )

        local cx = RaidCooldownsDB.settings.cdTextOffsetX or 0
        local cy = RaidCooldownsDB.settings.cdTextOffsetY or 0

        bar.cdText:ClearAllPoints()
        bar.cdText:SetPoint("RIGHT", bar, "RIGHT", -4 + cx, cy)
    end
end




------------------------------------------------
-- LAYOUT HANDLERS (SINGLE SOURCE OF TRUTH)
------------------------------------------------
LayoutHandlers = LayoutHandlers or {}
-- 🧹 TEMP SAFETY STUBS (prevents ghost bars)




HideAllBars = function()
    for _, group in pairs(RC.spells) do
        if group.bar then
            group.bar:Hide()
        end
    end
end


------------------------------------------------
-- ICON + BAR (CLEAN / STABLE)
------------------------------------------------
LayoutHandlers.ICON_BAR = function()

    -- Only hide bars when NOT dragging
    if not RC.dragging then
        HideAllBars()
    end

    local s = RaidCooldownsDB.settings
    local rowSize = s.barHeight + s.barSpacing

    -- ALWAYS use visible ordered list
    local list = GetVisibleOrdered()

    for index, group in ipairs(list) do
        if RC.debugShowAllSpells or group.hasOwners then

            local bar = group.bar
            bar:Show()

            -- Reset visuals only when not dragging
            if not RC.dragging then
                ResetBarVisuals(bar, group)
            end

            bar:SetSize(s.barWidth, s.barHeight)

            ------------------------------------------------
            -- ⭐ NORMAL STACKING (DRAG SAFE)
            ------------------------------------------------
            if not RC.dragging or bar ~= RC.dragging then

                local barY = -16 - ((index - 1) * rowSize)

                bar:ClearAllPoints()
                local point, x = GetBarAnchorX(s.barWidth)
                bar:SetPoint(point, panel, x, barY)
            end

            ------------------------------------------------
            -- ICON
            ------------------------------------------------
            bar.icon:ClearAllPoints()
            bar.icon:SetSize(s.barHeight, s.barHeight)
            bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

            ------------------------------------------------
            -- FILL
            ------------------------------------------------
            bar.fill:ClearAllPoints()
            bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", ICON_GAP, 0)
            bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 0)

            ApplyClassColor(bar, group.class)

            ------------------------------------------------
            -- LABEL
            ------------------------------------------------
            bar.label:SetText(GetBarLabelText(group))
            bar.label:Show()
            bar.ownersText:Hide()
        end
    end
end




------------------------------------------------
-- BAR ONLY
------------------------------------------------
LayoutHandlers.BAR_ONLY = function()
    HideAllBars()

    local s = RaidCooldownsDB.settings
    local y = -16

   for _, group in ipairs(RC.ordered) do
    if not group.hasOwners then
        group.bar:Hide()
    else
        local bar = group.bar


        bar:Show()
        ResetBarVisuals(bar, group)

        bar:SetSize(s.barWidth, s.barHeight)
        bar:ClearAllPoints()

        local point, x = GetBarAnchorX(s.barWidth)
        bar:SetPoint(point, panel, x, y)
		bar.icon:ClearAllPoints()
bar.icon:SetSize(s.barHeight, s.barHeight)

        bar.icon:Hide()
        bar.fill:SetAllPoints(bar)
        ApplyClassColor(bar, group.class)

       bar.label:SetText(GetBarLabelText(group))


        bar.ownersText:Hide()

        y = y - s.barHeight - s.barSpacing
    end
end
end

------------------------------------------------
-- ICON ONLY (ANCHOR SAFE)
------------------------------------------------
LayoutHandlers.ICON_ONLY = function()
    HideAllBars()

    local s = RaidCooldownsDB.settings
    local y = -16

   for _, group in ipairs(RC.ordered) do
    if not group.hasOwners then
        group.bar:Hide()
    else

        local bar = group.bar

        bar:Show()
        ResetBarVisuals(bar, group)

        -- Bar is just an icon container
        bar:SetSize(s.barHeight, s.barHeight)
        bar:ClearAllPoints()

        local point, x = GetBarAnchorX(s.barWidth)
        bar:SetPoint(point, panel, x, y)

        -- ICON: single anchor, no SetAllPoints
        bar.icon:ClearAllPoints()
        bar.icon:SetSize(s.barHeight, s.barHeight)
        bar.icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)

        -- Hide everything else
        bar.fill:Hide()
        bar.label:Hide()
        bar.ownersText:Hide()

        y = y - s.barHeight - s.barSpacing
    end
end


end
------------------------------------------------
-- COLUMN LIST
------------------------------------------------
LayoutHandlers.COLUMN_LIST = function()
    HideAllBars()

    local s = RaidCooldownsDB.settings
    local paddingY = -16
    local colGap = 24

    local columns = { {}, {}, {} }

    for _, group in pairs(RC.spells) do
        table.insert(columns[group.column or 1], group)
    end

    for col = 1, 3 do
        table.sort(columns[col], function(a,b)
            return (a.order or 1) < (b.order or 1)
        end)
    end

    for colIndex = 1, 3 do
        local x = 16 + (colIndex - 1) * (s.barWidth + colGap)
        local y = paddingY

       for _, group in ipairs(columns[colIndex]) do
    if RC.debugShowAllSpells or group.hasOwners then
            local bar = group.bar

            bar:Show()
            ResetBarVisuals(bar, group)

            bar:SetSize(s.barWidth, s.barHeight)
            bar:SetPoint("TOPLEFT", panel, x, y)
			bar.icon:ClearAllPoints()
bar.icon:SetSize(s.barHeight, s.barHeight)

            bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
            bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 6, 0)
            bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 0)

bar.label:SetText(GetBarLabelText(group))


            y = y - s.barHeight - s.barSpacing
        end
    end
end


end







------------------------------------------------
-- SPELL OWNERS
------------------------------------------------
LayoutHandlers.SPELL_OWNERS = function()
    local s = RaidCooldownsDB.settings
    local y = -16

    for _, group in ipairs(RC.ordered) do
        local bar = group.bar

       if not (RC.debugShowAllSpells or group.hasOwners) then
            bar:Hide()
        else
			bar:Show()
            ResetBarVisuals(bar, group)

            bar:SetSize(s.barWidth, s.barHeight)
            bar:ClearAllPoints()

            local point, x = GetBarAnchorX(s.barWidth)
            bar:SetPoint(point, panel, x, y)



            bar.icon:SetSize(s.barHeight, s.barHeight)
            bar.icon:ClearAllPoints()
            bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
			bar.icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)

            bar.fill:Hide()

      
            bar.label:SetPoint("LEFT", bar.icon, "RIGHT", 6, 0)

            bar.ownersText:Show()

            y = y - s.barHeight - s.barSpacing
        end
    end
end



------------------------------------------------
-- UPDATE ALL BAR FONTS
------------------------------------------------
function UpdateAllBarFonts()
 local font = RaidCooldownsDB.settings.font or "Fonts\\FRIZQT__.TTF"

    for _, group in pairs(RC.spells) do
        local bar = group.bar
        if bar then
            if bar.label then
                bar.label:SetFont(
                    font,
                    RaidCooldownsDB.settings.spellTextSize or 12,
                    "OUTLINE"
                )
            end

            if bar.cdText then
                bar.cdText:SetFont(
                    font,
                    RaidCooldownsDB.settings.cdTextSize or 12,
                    "OUTLINE"
                )
            end
        end
    end
end




------------------------------------------------
-- UPDATE LAYOUT
------------------------------------------------
function UpdateLayout()

    if RC.suppressLayout then
        return
    end

    if not RC.dragging then
        HideAllBars()
    end

    local handler = LayoutHandlers[RaidCooldownsDB.settings.template]
    if handler then
        handler()
    end
end





------------------------------------------------
-- Fonts
------------------------------------------------

local FONT_CHOICES = {
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
    ["Morpheus"]     = "Fonts\\MORPHEUS.ttf",
    ["Skurri"]       = "Fonts\\skurri.ttf",
}





------------------------------------------------
-- OPTIONS WINDOW (STABLE)
------------------------------------------------
local ROW_SPACING = -36
local options = CreateFrame("Frame", "RaidCooldownsOptionsWindow", UIParent, "BackdropTemplate")
options:SetSize(640, 700)
options:SetPoint("CENTER")

local content = CreateFrame("Frame", nil, options)
content:SetPoint("TOPLEFT", options, "TOPLEFT", 12, -40)
content:SetPoint("BOTTOMRIGHT", options, "BOTTOMRIGHT", -12, 12)


------------------------------------------------
-- ⭐ UI HELPERS (ADD RIGHT UNDER OPTIONS WINDOW)
------------------------------------------------
local function CreateSection(parent, text, anchor)
    local fs = parent:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -28)
    fs:SetText("|cffffcc00"..text.."|r")
    return fs
end

local function CreateCard(parent, anchor, width, height)

    local f = CreateFrame("Frame",nil,parent,"BackdropTemplate")
    f:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",-12,8)
    f:SetSize(width,height)

   f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
})

f:SetBackdropColor(0.06,0.06,0.06,0.92)
f:SetBackdropBorderColor(0.2,0.2,0.2,0.9)


    return f
end

------------------------------------------------
-- ⭐ SIDEBAR NAVIGATION (NEW)
------------------------------------------------
local sidebar = CreateFrame("Frame", nil, content, "BackdropTemplate")
sidebar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
sidebar:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
sidebar:SetWidth(150)
sidebar:SetHeight(content:GetHeight())

sidebar:SetWidth(150)



sidebar:SetBackdrop({
    bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize=12,
    insets={left=3,right=3,top=3,bottom=3}
})

sidebar:SetBackdropColor(0.08,0.08,0.09,0.8)

------------------------------------------------
-- SIDEBAR BUTTON HELPER
------------------------------------------------
local function CreateSidebarButton(text, anchor)
    local b = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    b:SetSize(120,24)
    b:SetPoint("TOP", anchor, "BOTTOM", 0, -8)
    b:SetText(text)
    return b
end

------------------------------------------------
-- SIDEBAR BUTTONS
------------------------------------------------
local sbTitle = sidebar:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
sbTitle:SetPoint("TOP",0,-12)
sbTitle:SetText("RaidCooldowns")

local btnLayout   = CreateSidebarButton("Layout", sbTitle)
local btnProfiles = CreateSidebarButton("Profiles", btnLayout)
local btnTracking = CreateSidebarButton("Tracking", btnProfiles)
local btnAbout = CreateSidebarButton("About", btnTracking)

btnLayout:SetScript("OnClick", function() ShowPage("Layout") end)
btnProfiles:SetScript("OnClick", function() ShowPage("Profiles") end)
btnTracking:SetScript("OnClick", function() ShowPage("Tracking") end)
btnAbout:SetScript("OnClick", function() ShowPage("About") end)


local function SidebarGlow(btn)
    if not btn then return end

    btn:HookScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(1,0.82,0)
        end
    end)

    btn:HookScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(1,1,1)
        end
    end)
end


SidebarGlow(btnLayout)
SidebarGlow(btnProfiles)
SidebarGlow(btnTracking)
SidebarGlow(btnAbout)







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

    UIDropDownMenu_SetText(
        templateDrop,
        BAR_TEMPLATES[RaidCooldownsDB.settings.template]
    )

    UpdateLayout()
end)






-- Title
-- local optTitle = options:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
-- optTitle:SetPoint("TOP", 0, -12)
-- optTitle:SetText("RaidCooldowns – Layout")



local s = RaidCooldownsDB.settings

options:SetMovable(true)
options:EnableMouse(true)
options:RegisterForDrag("LeftButton")

options:SetScript("OnDragStart", function(self)
   self:StartMoving()          -- ✅ CORRECT
end)


options:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)


------------------------------------------------
-- PAGE SYSTEM (REAL NAVIGATION)
------------------------------------------------
local Pages = {}

function ShowPage(name)
    if not Pages then return end   -- ⭐ ADD THIS LINE

    for n, frame in pairs(Pages) do
        frame:SetShown(n == name)
    end
end


-- Layout page (your existing UI)
Pages["Layout"] = CreateFrame("Frame", nil, content)
Pages["Layout"]:SetAllPoints()

-- Profiles page
Pages["Profiles"] = CreateFrame("Frame", nil, content)
Pages["Profiles"]:SetAllPoints()
Pages["Profiles"]:Hide()


------------------------------------------------
-- PROFILES PAGE COLUMN (NEW)
------------------------------------------------
local profilesColumn = CreateFrame("Frame", nil, Pages["Profiles"])
profilesColumn:SetPoint("TOPLEFT", Pages["Profiles"], "TOPLEFT", 180, -20)
profilesColumn:SetSize(300, 1400)
local profilesRightColumn = CreateFrame("Frame", nil, Pages["Profiles"])
profilesRightColumn:ClearAllPoints()
profilesRightColumn:ClearAllPoints()
profilesRightColumn:SetPoint("TOPLEFT", profilesColumn, "TOPLEFT", 260, 0)
profilesRightColumn:SetSize(260, 1400)

-- ⭐ FIX OVERLAP (draw above left column)
profilesRightColumn:SetFrameLevel(profilesColumn:GetFrameLevel() + 5)



-- Tracking page
Pages["Tracking"] = CreateFrame("Frame", nil, content)
Pages["Tracking"]:SetAllPoints()
Pages["Tracking"]:Hide()

-- About page
Pages["About"] = CreateFrame("Frame", nil, content)
Pages["About"]:SetAllPoints()
Pages["About"]:Hide()
local aboutTitle = Pages["About"]:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
aboutTitle:SetPoint("TOPLEFT", 180, -20)
aboutTitle:SetText("RaidCooldowns")

ShowPage("Layout")

------------------------------------------------
-- AUTO LAYOUT COLUMNS (ADD RIGHT HERE)
------------------------------------------------
local leftColumn = CreateFrame("Frame", nil, Pages["Layout"])
leftColumn:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 20, -20)
leftColumn:SetSize(240, 900)

local rightColumn = CreateFrame("Frame", nil, Pages["Layout"])
rightColumn:SetPoint("TOPLEFT", leftColumn, "TOPRIGHT", 40, 0)
rightColumn:SetSize(260, 1200)







------------------------------------------------
-- 🎨 APPEARANCE SECTION
------------------------------------------------
local appearanceHeader = rightColumn:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
appearanceHeader:SetPoint("TOPLEFT", rightColumn, "TOPLEFT", 0, -20)
appearanceHeader:SetText("|TInterface\\Icons\\inv_misc_paintbrush:18|t Appearance")

local appearanceCard = CreateCard(rightColumn, appearanceHeader, 240, 260)




------------------------------------------------
-- BAR TEMPLATE (RIGHT COLUMN)
------------------------------------------------

local templateLabel = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
templateLabel:SetText("Bar Template")
templateLabel:SetPoint("TOPLEFT", appearanceCard, "TOPLEFT", 12, -30)

templateDrop = CreateFrame(
    "Frame",
    "RaidCooldownsTemplateDropdown",
    rightColumn,   -- ✅ MUST BE rightColumn
    "UIDropDownMenuTemplate"
)



templateDrop:SetPoint("TOPLEFT", templateLabel, "BOTTOMLEFT", -16, -6)
UIDropDownMenu_SetWidth(templateDrop, 180)


UIDropDownMenu_Initialize(templateDrop, function(self, level)

    if level ~= 1 then return end

    UIDropDownMenu_ClearAll(templateDrop) -- ⭐ VERY IMPORTANT (prevents duplicates)

    for _, key in ipairs(BAR_TEMPLATE_ORDER) do
        local info = UIDropDownMenu_CreateInfo()

        info.text = BAR_TEMPLATES[key]
        info.value = key
        info.isNotRadio = false
        info.checked = (RaidCooldownsDB.settings.template == key)

        info.func = function(btn)
            CloseDropDownMenus()

            RaidCooldownsDB.settings.template = btn.value

            UIDropDownMenu_SetSelectedValue(templateDrop, btn.value)
            UIDropDownMenu_SetText(templateDrop, BAR_TEMPLATES[btn.value])

            UpdateLayout()
        end

        UIDropDownMenu_AddButton(info, level)
    end
end)


------------------------------------------------
-- RESET LAYOUT BUTTON (RIGHT COLUMN)
------------------------------------------------

reset = CreateFrame("Button", nil, rightColumn, "UIPanelButtonTemplate")
reset:SetSize(180, 24)
reset:SetText("Reset Layout")

reset:SetPoint("TOPLEFT", templateDrop, "BOTTOMLEFT", 0, -20)
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


-- Lock Panel
local lock = CreateFrame("CheckButton", nil, rightColumn, "InterfaceOptionsCheckButtonTemplate")
lock:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -12)
lock.Text:SetText("Lock Panel")
lock:SetChecked(RC.locked)
lock:SetScript("OnClick", function(self)
    RC.locked = self:GetChecked()
    UpdatePanelMouseState()
    if RC.locked then
        bg:Hide()
    else
        bg:Show()
        bg:SetColorTexture(0, 0, 0, 0.25)
    end
end)


------------------------------------------------
-- 🧪 TEST MODE BUTTON
------------------------------------------------
local testBtn = CreateFrame("CheckButton", nil, rightColumn, "InterfaceOptionsCheckButtonTemplate")
testBtn:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, ROW_SPACING)
testBtn.Text:SetText("Test Mode (Show All Spells)")
testBtn:SetChecked(RC.debugShowAllSpells)

testBtn:SetScript("OnClick", function(self)
    RC.debugShowAllSpells = self:GetChecked()
    UpdateLayout()
end)



------------------------------------------------
-- FONT DROPDOWN (FIXED ANCHOR VERSION)
------------------------------------------------
local fontLabel = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
fontLabel:SetText("Font")
fontLabel:SetPoint("TOPLEFT", appearanceCard, "BOTTOMLEFT", 12, -30)

local fontDrop = CreateFrame(
    "Frame",
    "RaidCooldownsFontDropdown",
    rightColumn,
    "UIDropDownMenuTemplate"
)

fontDrop:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -6)
UIDropDownMenu_SetWidth(fontDrop, 180)
UIDropDownMenu_JustifyText(fontDrop, "LEFT")

fontDrop.initialize = function(self, level)
    if level ~= 1 then return end

    for name, path in pairs(FONT_CHOICES) do
        local info = UIDropDownMenu_CreateInfo()

        info.text = name
        info.value = path
        info.checked = (RaidCooldownsDB.settings.font == path)

        info.func = function(btn)
            CloseDropDownMenus()
            RaidCooldownsDB.settings.font = btn.value
            UIDropDownMenu_SetText(fontDrop, name)

            UpdateAllBarFonts()
            UpdateLayout()
        end

        UIDropDownMenu_AddButton(info, level)
    end
end

-- Initial label
for name, path in pairs(FONT_CHOICES) do
    if path == RaidCooldownsDB.settings.font then
        UIDropDownMenu_SetText(fontDrop, name)
        break
    end
end




-- Bar Width
local barWidth = CreateFrame("Slider", nil, leftColumn, "OptionsSliderTemplate")
barWidth:SetPoint("TOPLEFT", 20, -50)
barWidth:SetMinMaxValues(120, 320)
barWidth:SetValueStep(5)
barWidth:SetValue(RaidCooldownsDB.settings.barWidth)
barWidth.Text:SetText("Bar Width")
barWidth.Low:SetText("120")
barWidth.High:SetText("320")
barWidth:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.settings.barWidth = math.floor(value)
    UpdateLayout()
end)

-- Bar Height
local barHeight = CreateFrame("Slider", nil, leftColumn, "OptionsSliderTemplate")
barHeight:SetPoint("TOPLEFT", barWidth, "BOTTOMLEFT", 0, ROW_SPACING)
barHeight:SetMinMaxValues(12, 40)
barHeight:SetValueStep(1)
barHeight:SetValue(RaidCooldownsDB.settings.barHeight)
barHeight.Text:SetText("Bar Height")
barHeight.Low:SetText("12")
barHeight.High:SetText("40")
barHeight:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.settings.barHeight = math.floor(value)
    UpdateLayout()
end)

-- Bar Spacing
local barSpacing = CreateFrame("Slider", nil, leftColumn, "OptionsSliderTemplate")
barSpacing:SetPoint("TOPLEFT", barHeight, "BOTTOMLEFT", 0, ROW_SPACING)
barSpacing:SetMinMaxValues(2, 20)
barSpacing:SetValueStep(1)
barSpacing:SetValue(RaidCooldownsDB.settings.barSpacing)
barSpacing.Text:SetText("Bar Spacing")
barSpacing.Low:SetText("2")
barSpacing.High:SetText("20")
barSpacing:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.settings.barSpacing = math.floor(value)
    UpdateLayout()
end)

-- Spell / Name Text X
local spellTextX = CreateFrame("Slider", nil, leftColumn, "OptionsSliderTemplate")
spellTextX:SetPoint("TOPLEFT", barSpacing, "BOTTOMLEFT", 0, ROW_SPACING)
spellTextX:SetMinMaxValues(-50, 50)
spellTextX:SetValueStep(1)
spellTextX:SetValue(RaidCooldownsDB.settings.spellTextOffsetX)
spellTextX.Text:SetText("Spell / Name Text X")
spellTextX.Low:SetText("-50")
spellTextX.High:SetText("50")
spellTextX:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.settings.spellTextOffsetX = math.floor(value)
    UpdateLayout()
end)

-- Spell / Name Text Y
local spellTextY = CreateFrame("Slider", nil, leftColumn, "OptionsSliderTemplate")
spellTextY:SetPoint("TOPLEFT", spellTextX, "BOTTOMLEFT", 0, ROW_SPACING)
spellTextY:SetMinMaxValues(-20, 20)
spellTextY:SetValueStep(1)
spellTextY:SetValue(RaidCooldownsDB.settings.spellTextOffsetY)
spellTextY.Text:SetText("Spell / Name Text Y")
spellTextY.Low:SetText("-20")
spellTextY.High:SetText("20")
spellTextY:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.settings.spellTextOffsetY = math.floor(value)
    UpdateLayout()
end)

-- Spell / Name Text Size
local spellTextSize = CreateFrame("Slider", nil, leftColumn, "OptionsSliderTemplate")
spellTextSize:SetPoint("TOPLEFT", spellTextY, "BOTTOMLEFT", 0, ROW_SPACING)
spellTextSize:SetMinMaxValues(8, 24)
spellTextSize:SetValueStep(1)
spellTextSize:SetValue(RaidCooldownsDB.settings.spellTextSize)
spellTextSize.Text:SetText("Spell / Name Text Size")
spellTextSize.Low:SetText("8")
spellTextSize.High:SetText("24")
spellTextSize:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.settings.spellTextSize = math.floor(value)
    UpdateLayout()
	UpdateAllBarFonts()

end)

-- Countdown / READY X
local cdTextX = CreateFrame("Slider", nil, leftColumn, "OptionsSliderTemplate")
cdTextX:SetPoint("TOPLEFT", spellTextSize, "BOTTOMLEFT", 0, ROW_SPACING)
cdTextX:SetMinMaxValues(-50, 50)
cdTextX:SetValueStep(1)
cdTextX:SetValue(RaidCooldownsDB.settings.cdTextOffsetX)
cdTextX.Text:SetText("Countdown / READY X")
cdTextX.Low:SetText("-50")
cdTextX.High:SetText("50")
cdTextX:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.settings.cdTextOffsetX = math.floor(value)
    UpdateLayout()
end)

-- Countdown / READY Y
local cdTextY = CreateFrame("Slider", nil, leftColumn, "OptionsSliderTemplate")
cdTextY:SetPoint("TOPLEFT", cdTextX, "BOTTOMLEFT", 0, ROW_SPACING)
cdTextY:SetMinMaxValues(-20, 20)
cdTextY:SetValueStep(1)
cdTextY:SetValue(RaidCooldownsDB.settings.cdTextOffsetY)
cdTextY.Text:SetText("Countdown / READY Y")
cdTextY.Low:SetText("-20")
cdTextY.High:SetText("20")
cdTextY:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.settings.cdTextOffsetY = math.floor(value)
    UpdateLayout()
end)

-- Countdown / READY Text Size
local cdTextSize = CreateFrame("Slider", nil, leftColumn, "OptionsSliderTemplate")
cdTextSize:SetPoint("TOPLEFT", cdTextY, "BOTTOMLEFT", 0, ROW_SPACING)
cdTextSize:SetMinMaxValues(8, 24)
cdTextSize:SetValueStep(1)
cdTextSize:SetValue(RaidCooldownsDB.settings.cdTextSize)
cdTextSize.Text:SetText("Countdown / READY Text Size")
cdTextSize.Low:SetText("8")
cdTextSize.High:SetText("24")
cdTextSize:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.settings.cdTextSize = math.floor(value)
    UpdateLayout()
	UpdateAllBarFonts()

end)

-- Center Bars
local center = CreateFrame("CheckButton", nil, rightColumn, "InterfaceOptionsCheckButtonTemplate")
center:SetPoint("TOPLEFT", cdTextSize, "BOTTOMLEFT", 0, ROW_SPACING)
center.Text:SetText("Center Bars")
center:SetChecked(RaidCooldownsDB.settings.centerBars)
center:SetScript("OnClick", function(self)
    RaidCooldownsDB.settings.centerBars = self:GetChecked()
    UpdateLayout()
end)




------------------------------------------------
-- PANEL SIZE HEADER (RIGHT COLUMN)
------------------------------------------------
local panelSizeHeader = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panelSizeHeader:SetPoint("TOPLEFT", fontDrop, "BOTTOMLEFT", 16, ROW_SPACING * 2)
panelSizeHeader:SetText("Panel Size")

------------------------------------------------
-- PANEL WIDTH
------------------------------------------------
local panelWidth = CreateFrame("Slider", nil, rightColumn, "OptionsSliderTemplate")
panelWidth:SetPoint("TOPLEFT", panelSizeHeader, "BOTTOMLEFT", 0, ROW_SPACING)
panelWidth:SetMinMaxValues(240, 900)
panelWidth:SetValueStep(10)
panelWidth:SetValue(RaidCooldownsDB.layout.width or 360)
panelWidth.Text:SetText("Panel Width")
panelWidth.Low:SetText("240")
panelWidth.High:SetText("900")

panelWidth:SetScript("OnValueChanged", function(_, value)
    RaidCooldownsDB.layout.width = math.floor(value)
    panel:SetWidth(RaidCooldownsDB.layout.width)
    UpdateLayout()
end)

------------------------------------------------
-- PANEL HEIGHT
------------------------------------------------
local panelHeight = CreateFrame("Slider", nil, rightColumn, "OptionsSliderTemplate")
panelHeight:SetPoint("TOPLEFT", panelWidth, "BOTTOMLEFT", 0, ROW_SPACING)
panelHeight:SetMinMaxValues(100, 700)
panelHeight:SetValueStep(10)
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
-- PROFILE DROPDOWN
------------------------------------------------
local profileLabel = profilesColumn:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
profileLabel:SetText("Profile")
profileLabel:ClearAllPoints()
profileLabel:SetPoint("TOPLEFT", profilesColumn, "TOPLEFT", 0, -20)

profileLabel:SetTextColor(1,0.82,0)

local profileDrop = CreateFrame(
    "Frame",
    "RaidCooldownsProfileDropdown",
    profilesColumn,
    "UIDropDownMenuTemplate"
)


profileDrop:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", -16, -6)
UIDropDownMenu_SetWidth(profileDrop, 180)

UIDropDownMenu_Initialize(profileDrop, function(self, level)

    if level ~= 1 then return end

    for name,_ in pairs(RaidCooldownsDB.profiles) do
        local info = UIDropDownMenu_CreateInfo()

        info.notCheckable = true
        info.isNotRadio   = true
        info.checked      = nil

        info.text  = name
        info.value = name

        info.func = function(btn)

            RaidCooldownsDB.char[GetCharKey()] = btn.value

            ApplyProfile()
            UpdateAllBarFonts()
            NormalizeColumnOrders()
            RebuildOrderedList()
            UpdateLayout()

            UIDropDownMenu_SetText(profileDrop, btn.value)
        end

        UIDropDownMenu_AddButton(info, level)
    end
end)


UIDropDownMenu_SetText(profileDrop, GetCurrentProfileName())

------------------------------------------------
-- BUTTON HOVER GLOW (SAFE VERSION)
------------------------------------------------
local function AddHoverGlow(btn)
    if not btn then return end

    btn:HookScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(1,0.82,0)
        end
    end)

    btn:HookScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(1,1,1)
        end
    end)
end


------------------------------------------------
-- CREATE NEW PROFILE BUTTON
------------------------------------------------
local newProfileBtn = CreateFrame(
    "Button",
    nil,
   profilesColumn,
    "UIPanelButtonTemplate"
)





newProfileBtn:SetSize(180,24)
newProfileBtn:SetPoint("TOPLEFT", profileDrop, "BOTTOMLEFT", 16, ROW_SPACING)
newProfileBtn:SetText("Create New Profile")
AddHoverGlow(newProfileBtn)
newProfileBtn:SetScript("OnClick", function()
AddHoverGlow(newProfileBtn)


    local baseName = "Profile"
    local i = 1
    local newName = baseName..i

    -- Find unused profile name
    while RaidCooldownsDB.profiles[newName] do
        i = i + 1
        newName = baseName..i
    end

    ------------------------------------------------
    -- COPY CURRENT PROFILE
    ------------------------------------------------
    local current = GetProfile()

    RaidCooldownsDB.profiles[newName] = {
        settings = CopyTable(current.settings),
        layout   = CopyTable(current.layout),
        columns  = CopyTable(current.columns),
        order    = CopyTable(current.order),
    }

    ------------------------------------------------
    -- SWITCH CHARACTER TO NEW PROFILE
    ------------------------------------------------
    RaidCooldownsDB.char[GetCharKey()] = newName

    ApplyProfile()
    UpdateAllBarFonts()
    NormalizeColumnOrders()
    RebuildOrderedList()
    UpdateLayout()

    UIDropDownMenu_SetText(profileDrop, newName)

    print("RaidCooldowns: Created profile", newName)
end)






    



------------------------------------------------
-- SIMPLE TABLE SERIALIZER (EXPORT SAFE)
------------------------------------------------
local function SerializeTable(val, name, depth)

    depth = depth or 0
    local indent = string.rep(" ", depth * 2)

    if type(val) ~= "table" then
        if type(val) == "string" then
            return string.format("%q", val)
        else
            return tostring(val)
        end
    end

    local result = "{\n"

    for k, v in pairs(val) do
        local key

        if type(k) == "string" then
            key = "["..string.format("%q", k).."]"
        else
            key = "["..k.."]"
        end

        result = result .. indent.."  "..key.." = "
            .. SerializeTable(v, nil, depth+1) .. ",\n"
    end

    result = result .. indent.."}"

    return result
end


------------------------------------------------
-- EXPORT WINDOW (CREATE ONCE)
------------------------------------------------
local function CreateExportWindow()

    if RaidCooldownsExportFrame then return end

    local f = CreateFrame("Frame","RaidCooldownsExportFrame",UIParent,"BackdropTemplate")
	------------------------------------------------
-- CLOSE BUTTON
------------------------------------------------
local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", f, "TOPRIGHT")
f:SetPropagateKeyboardInput(true)
f:EnableKeyboard(true)

f:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
        self:Hide()
    end
end)

    f:SetSize(500,400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")

    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = {left=4,right=4,top=4,bottom=4}
    })
    f:SetBackdropColor(0,0,0,0.95)

    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local scroll = CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",12,-12)
    scroll:SetPoint("BOTTOMRIGHT",-28,12)

    local edit = CreateFrame("EditBox",nil,scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(440)
    edit:SetAutoFocus(true)

    scroll:SetScrollChild(edit)

    f.editBox = edit
	edit:SetScript("OnEscapePressed", function()
    f:Hide()
end)

end

------------------------------------------------
-- IMPORT WINDOW
------------------------------------------------
local function CreateImportWindow()

    if RaidCooldownsImportFrame then return end

    local f = CreateFrame("Frame","RaidCooldownsImportFrame",UIParent,"BackdropTemplate")
    f:SetSize(500,400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")

    f:SetBackdrop({
        bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4}
    })
    f:SetBackdropColor(0,0,0,0.95)

    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT")

    f:SetPropagateKeyboardInput(true)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
        end
    end)

    local scroll = CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",12,-12)
    scroll:SetPoint("BOTTOMRIGHT",-28,40)

    local edit = CreateFrame("EditBox",nil,scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(440)
    edit:SetAutoFocus(true)

    edit:SetScript("OnEscapePressed", function()
        f:Hide()
    end)

    scroll:SetScrollChild(edit)
    f.editBox = edit

    local import = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    import:SetSize(140,24)
    import:SetPoint("BOTTOM",0,10)
    import:SetText("Import Profile")

    import:SetScript("OnClick", function()
        RaidCooldowns_ImportProfileFromText(edit:GetText())
        f:Hide()
    end)
end


------------------------------------------------
-- EXPORT PROFILE BUTTON
------------------------------------------------
local exportBtn = CreateFrame(
    "Button",
    nil,
    profilesColumn,
    "UIPanelButtonTemplate"
)

exportBtn:SetSize(180,24)
exportBtn:SetPoint("TOPLEFT", newProfileBtn, "BOTTOMLEFT", 0, ROW_SPACING)
exportBtn:SetText("Export Profile")
AddHoverGlow(exportBtn)


exportBtn:SetScript("OnClick", function()

    local profile = GetProfile()
    if not profile then
        print("RaidCooldowns: No profile.")
        return
    end

    ------------------------------------------------
    -- MAKE SURE WINDOW EXISTS
    ------------------------------------------------
    CreateExportWindow()

    ------------------------------------------------
    -- SERIALIZE PROFILE
    ------------------------------------------------
    local text = "return " .. SerializeTable(profile)

    RaidCooldownsExportFrame.editBox:SetText(text)
    RaidCooldownsExportFrame.editBox:HighlightText()
    RaidCooldownsExportFrame:Show()

end)

------------------------------------------------
-- RENAME PROFILE WINDOW
------------------------------------------------
local function CreateRenameWindow()

    if RaidCooldownsRenameFrame then return end

    local f = CreateFrame("Frame","RaidCooldownsRenameFrame",UIParent,"BackdropTemplate")
	f:SetPropagateKeyboardInput(true)
f:EnableKeyboard(true)

f:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
        self:Hide()
    end
end)

    f:SetSize(260,120)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")

    f:SetBackdrop({
        bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4}
    })
    f:SetBackdropColor(0,0,0,0.95)

    local edit = CreateFrame("EditBox",nil,f,"InputBoxTemplate")
	edit:SetScript("OnEscapePressed", function()
    f:Hide()
end)

    edit:SetSize(180,30)
    edit:SetPoint("TOP",0,-30)
    edit:SetAutoFocus(true)
    f.editBox = edit

    local ok = CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    ok:SetSize(120,24)
    ok:SetPoint("BOTTOM",0,12)
    ok:SetText("Rename")

    ok:SetScript("OnClick", function()

        local newName = edit:GetText()
        local oldName = GetCurrentProfileName()

        if not newName or newName == "" then return end
        if RaidCooldownsDB.profiles[newName] then
            print("RaidCooldowns: Profile already exists.")
            return
        end

        RaidCooldownsDB.profiles[newName] =
            RaidCooldownsDB.profiles[oldName]

        RaidCooldownsDB.profiles[oldName] = nil
        RaidCooldownsDB.char[GetCharKey()] = newName

        ApplyProfile()
        UpdateLayout()

        f:Hide()
        print("RaidCooldowns: Renamed profile to", newName)
    end)
end

------------------------------------------------
-- IMPORT PROFILE BUTTON
------------------------------------------------
local importBtn = CreateFrame("Button",nil,profilesColumn,"UIPanelButtonTemplate")
importBtn:SetSize(180,24)
importBtn:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, ROW_SPACING)
importBtn:SetText("Import Profile")
AddHoverGlow(importBtn)

importBtn:SetScript("OnClick", function()
    CreateImportWindow()
    RaidCooldownsImportFrame:Show()
end)

------------------------------------------------
-- DUPLICATE PROFILE BUTTON
------------------------------------------------
local dupBtn = CreateFrame("Button",nil,profilesColumn,"UIPanelButtonTemplate")
dupBtn:SetSize(180,24)
dupBtn:SetPoint("TOPLEFT", importBtn, "BOTTOMLEFT", 0, ROW_SPACING)
dupBtn:SetText("Duplicate Profile")
AddHoverGlow(dupBtn)



dupBtn:SetScript("OnClick", function()
AddHoverGlow(newProfileBtn)


    local currentName = GetCurrentProfileName()
    local current = GetProfile()

    local i = 1
    local newName = currentName.."Copy"..i

    while RaidCooldownsDB.profiles[newName] do
        i=i+1
        newName = currentName.."Copy"..i
    end

    RaidCooldownsDB.profiles[newName] = {
        settings = CopyTable(current.settings),
        layout   = CopyTable(current.layout),
        columns  = CopyTable(current.columns),
        order    = CopyTable(current.order),
    }

    RaidCooldownsDB.char[GetCharKey()] = newName

    ApplyProfile()
    UpdateAllBarFonts()
    NormalizeColumnOrders()
    RebuildOrderedList()
    UpdateLayout()

    print("RaidCooldowns: Duplicated profile", newName)
end)


------------------------------------------------
-- RENAME PROFILE BUTTON
------------------------------------------------
local renameBtn = CreateFrame("Button",nil,profilesColumn,"UIPanelButtonTemplate")
renameBtn:SetSize(180,24)
renameBtn:SetPoint("TOPLEFT", dupBtn, "BOTTOMLEFT", 0, -12)
renameBtn:SetText("Rename Profile")
AddHoverGlow(renameBtn)



renameBtn:SetScript("OnClick", function()
AddHoverGlow(newProfileBtn)

    CreateRenameWindow()
    RaidCooldownsRenameFrame.editBox:SetText(GetCurrentProfileName())
    RaidCooldownsRenameFrame:Show()
end)

------------------------------------------------
-- IMPORT PROFILE FROM TEXT
------------------------------------------------
function RaidCooldowns_ImportProfileFromText(text)

    if not text or text == "" then
        print("RaidCooldowns: No import data.")
        return
    end

    local func = loadstring(text)
    if not func then
        print("RaidCooldowns: Invalid import string.")
        return
    end

    local ok, data = pcall(func)
    if not ok or type(data) ~= "table" then
        print("RaidCooldowns: Import failed.")
        return
    end

    ------------------------------------------------
    -- CREATE UNIQUE PROFILE NAME
    ------------------------------------------------
    local base = "Imported"
    local i = 1
    local newName = base..i

    while RaidCooldownsDB.profiles[newName] do
        i = i + 1
        newName = base..i
    end

    ------------------------------------------------
    -- SAVE PROFILE
    ------------------------------------------------
    RaidCooldownsDB.profiles[newName] = data
    RaidCooldownsDB.char[GetCharKey()] = newName

    ------------------------------------------------
    -- APPLY PROFILE LIVE
    ------------------------------------------------
    ApplyProfile()
    UpdateAllBarFonts()
    NormalizeColumnOrders()
    RebuildOrderedList()
    UpdateLayout()

    print("RaidCooldowns: Imported profile", newName)
end


------------------------------------------------
-- DELETE PROFILE BUTTON
------------------------------------------------
local deleteBtn = CreateFrame("Button",nil,profilesColumn,"UIPanelButtonTemplate")
deleteBtn:SetSize(180,24)
deleteBtn:SetPoint("TOPLEFT", importBtn, "BOTTOMLEFT", 0, ROW_SPACING * 3)
deleteBtn:SetText("Delete Profile")
AddHoverGlow(deleteBtn)




deleteBtn:SetScript("OnClick", function()
AddHoverGlow(newProfileBtn)


    local name = GetCurrentProfileName()

    if name == "Default" then
        print("RaidCooldowns: Cannot delete Default profile.")
        return
    end

    RaidCooldownsDB.profiles[name] = nil

    ------------------------------------------------
    -- SWITCH BACK TO DEFAULT
    ------------------------------------------------
    RaidCooldownsDB.char[GetCharKey()] = "Default"

    ApplyProfile()
    UpdateAllBarFonts()
    NormalizeColumnOrders()
    RebuildOrderedList()
    UpdateLayout()

    ------------------------------------------------
    -- ⭐ REFRESH DROPDOWN TEXT (THIS WAS MISSING)
    ------------------------------------------------
   UIDropDownMenu_SetSelectedValue(profileDrop, "Default")
UIDropDownMenu_SetText(profileDrop, "Default")

    print("RaidCooldowns: Deleted profile", name)
end)





------------------------------------------------
-- INSPECT HELPERS
------------------------------------------------
local pendingInspectUnit

local function RequestInspect(unit)
    if not CanInspect(unit) then return end
    if UnitIsUnit(unit, "player") then
        RC.specCache[UnitName(unit)] = GetSpecializationInfo(GetSpecialization())
        return
    end

    pendingInspectUnit = unit
    NotifyInspect(unit)
end

------------------------------------------------
-- BUILDOWNERSTRING
------------------------------------------------
local function BuildOwnerString(group)
    local owners = {}
    for name in pairs(group.owners) do
        table.insert(owners, name)
    end
    table.sort(owners)
    return table.concat(owners, ", ")
end
------------------------------------------------
-- RebuildOrderedList
------------------------------------------------
function RebuildOrderedList()

    -- ⭐ DO NOT REBUILD WHILE DRAGGING
    if RC.dragging then
        return
    end

    ------------------------------------------------
    -- ⭐ MAKE STABLE SOURCE COPY
    ------------------------------------------------
    local source = {}

    for _, g in ipairs(RC.ordered) do
        table.insert(source, g)
    end

    wipe(RC.ordered)

    local visible = {}
    local hidden  = {}

    ------------------------------------------------
    -- ⭐ BUILD FROM STABLE COPY (NOT HASH TABLE)
    ------------------------------------------------
    for _, g in ipairs(source) do
        if RC.debugShowAllSpells or g.hasOwners then
            table.insert(visible, g)
        else
            table.insert(hidden, g)
        end
    end

    -- ⭐ DO NOT SORT FOR ICON_BAR
if RaidCooldownsDB.settings.template == "COLUMN_LIST" then
    table.sort(visible, function(a, b)
        if (a.column or 1) == (b.column or 1) then
            return (a.order or 1) < (b.order or 1)
        else
            return (a.column or 1) < (b.column or 1)
        end
    end)
end


    for _, g in ipairs(visible) do
        table.insert(RC.ordered, g)
    end

    for _, g in ipairs(hidden) do
        table.insert(RC.ordered, g)
    end
end




------------------------------------------------
-- BUILD SPEC PROFILE UI (FIXED COLUMN ANCHOR)
------------------------------------------------
local function BuildSpecProfileUI()

    if not profilesRightColumn then return end
    if RaidCooldownsSpecBuilt then return end
    RaidCooldownsSpecBuilt = true

    ------------------------------------------------
    -- HEADER
    ------------------------------------------------
    local specHeader = profilesRightColumn:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    specHeader:SetPoint("TOPLEFT", profilesRightColumn, "TOPLEFT", -10, -20)
    specHeader:SetText("|TInterface\\Icons\\Ability_Shaman_ElementalOath:18|t Spec Profiles")

    ------------------------------------------------
    -- SPECS
    ------------------------------------------------
    local numSpecs = GetNumSpecializations()
    if not numSpecs or numSpecs == 0 then return end

    for i = 1, numSpecs do

        local id, name = GetSpecializationInfo(i)

        ------------------------------------------------
        -- ⭐ FIXED ROW POSITION (NO CHAINING)
        ------------------------------------------------
        local yOffset = -60 - ((i-1) * 60)

        ------------------------------------------------
        -- LABEL
        ------------------------------------------------
        local specLabel = profilesRightColumn:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        specLabel:SetPoint("TOPLEFT", profilesRightColumn, "TOPLEFT", 0, yOffset)
        specLabel:SetText(name)

        ------------------------------------------------
        -- DROPDOWN
        ------------------------------------------------
        local drop = CreateFrame(
            "Frame",
            "RaidCooldownsSpecProfileDrop"..i,
            profilesRightColumn,
            "UIDropDownMenuTemplate"
        )

        drop:SetPoint("TOPLEFT", profilesRightColumn, "TOPLEFT", -16, yOffset - 20)

        UIDropDownMenu_SetWidth(drop,130)
        UIDropDownMenu_JustifyText(drop,"LEFT")

        UIDropDownMenu_Initialize(drop,function(self,level)
            if level ~= 1 then return end

            for profileName,_ in pairs(RaidCooldownsDB.profiles) do
                local info = UIDropDownMenu_CreateInfo()

                info.text = profileName
                info.value = profileName
                info.notCheckable = true
                info.isNotRadio   = true
                info.checked      = nil
                info.keepShownOnClick = false

                info.func = function(btn)
                    RaidCooldownsDB.specProfiles[i] = btn.value
                    UIDropDownMenu_SetText(drop, btn.value)
                end

                UIDropDownMenu_AddButton(info, level)
            end
        end)

        UIDropDownMenu_SetText(drop, RaidCooldownsDB.specProfiles[i] or "-")
    end
end



------------------------------------------------
-- EVENTS
------------------------------------------------
local ev = CreateFrame("Frame")

-- Core lifecycle
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("INSPECT_READY")

-- Talents / spells
ev:RegisterEvent("PLAYER_TALENT_UPDATE")
ev:RegisterEvent("SPELLS_CHANGED")

-- Cooldowns
ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

------------------------------------------------
-- EVENT HANDLER
------------------------------------------------
ev:SetScript("OnEvent", function(self, event, ...)
    ------------------------------------------------
    -- ADDON LOADED (INIT)
    ------------------------------------------------
   if event == "ADDON_LOADED" then
    local addonName = ...
    if addonName ~= "RaidCooldowns" then return end

    ------------------------------------------------
    -- ⭐ PROFILE TABLE SAFETY (RUN AFTER DB EXISTS)
    ------------------------------------------------
    RaidCooldownsDB = RaidCooldownsDB or {}
    RaidCooldownsDB.profiles = RaidCooldownsDB.profiles or {}
    RaidCooldownsDB.char     = RaidCooldownsDB.char or {}

    ------------------------------------------------
-- PROFILE INIT
------------------------------------------------
local charKey = GetCharKey()

-- ⭐ ONLY assign Default if character has NO profile yet
if not RaidCooldownsDB.char[charKey] then
    RaidCooldownsDB.char[charKey] = "Default"
end

-- ⭐ Only create Default profile if it doesn't exist
if not RaidCooldownsDB.profiles["Default"] then
   ------------------------------------------------
-- ⭐ GUARANTEE DEFAULT PROFILE EXISTS
------------------------------------------------
RaidCooldownsDB.profiles["Default"] =
    RaidCooldownsDB.profiles["Default"] or {
        settings = RaidCooldownsDB.settings or {},
        layout   = RaidCooldownsDB.layout   or {},
        columns  = RaidCooldownsDB.columns  or {},
        order    = RaidCooldownsDB.order    or {},
    }

end


    ------------------------------------------------
    -- ⭐ APPLY PROFILE
    ------------------------------------------------
    ApplyProfile()
	UIDropDownMenu_SetText(profileDrop, GetCurrentProfileName())

	-- ⭐ Refresh profile dropdown label after reload
C_Timer.After(0, function()
    if profileDrop then
        local name = GetCurrentProfileName()
        UIDropDownMenu_SetSelectedValue(profileDrop, name)
        UIDropDownMenu_SetText(profileDrop, name)
    end
end)


    CreateGroups()

    UpdateAllBarFonts()
    NormalizeColumnOrders()




        RaidCooldownsDB.columns = RaidCooldownsDB.columns or {}
        RaidCooldownsDB.order   = RaidCooldownsDB.order or {}

        for spellID, group in pairs(RC.spells) do
            group.column = RaidCooldownsDB.columns[spellID] or 1
        end

        UpdateOwners()
		NormalizeColumnOrders()   -- ⭐ FIX FIRST DRAG JUMP
        RebuildOrderedList()
        UpdatePanelMouseState()
        UpdateLayout()
		RC.justDragged = false

		-- ⭐ FORCE STABLE BASE ORDER (FIX FIRST DRAG JUMP)
C_Timer.After(0, function()
    NormalizeColumnOrders()
    RebuildOrderedList()
end)

        return
    end

    ------------------------------------------------
    -- PLAYER LOGIN / GROUP CHANGES
    ------------------------------------------------
    if event == "PLAYER_LOGIN" or event == "GROUP_ROSTER_UPDATE" then
BuildSpecProfileUI()


       
	   wipe(RC.specCache)

        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                RequestInspect("raid"..i)
            end
        elseif IsInGroup() then
            RequestInspect("player")
            for i = 1, GetNumSubgroupMembers() do
                RequestInspect("party"..i)
            end
        else
            RequestInspect("player")
        end

        UpdateOwners()
        RebuildOrderedList()
        UpdateLayout()
		RC.justDragged = false

        return
    end

    ------------------------------------------------
    -- INSPECT RESULTS
    ------------------------------------------------
    if event == "INSPECT_READY" then
        local guid = ...
        if not pendingInspectUnit then return end
        if UnitGUID(pendingInspectUnit) ~= guid then return end

        local name = UnitName(pendingInspectUnit)
        local spec = GetInspectSpecialization(pendingInspectUnit)

        if spec and spec > 0 then
            RC.specCache[name] = spec
        end

        ClearInspectPlayer()
        pendingInspectUnit = nil

        UpdateOwners()
        RebuildOrderedList()
        UpdateLayout()
		RC.justDragged = false

        return
    end

    ------------------------------------------------
    -- TALENTS / SPELLBOOK CHANGED
    ------------------------------------------------
   if event == "PLAYER_TALENT_UPDATE" then
    C_Timer.After(0, function()

        local specIndex = GetSpecialization()
        local assigned = specIndex and RaidCooldownsDB.specProfiles[specIndex]

        if assigned and RaidCooldownsDB.profiles[assigned] then
            RaidCooldownsDB.char[GetCharKey()] = assigned

            ApplyProfile()
            UpdateAllBarFonts()
            NormalizeColumnOrders()
            RebuildOrderedList()
        end

        UpdateOwners()
        UpdateLayout()
    end)
    return
end


   ------------------------------------------------
-- SPELL CAST (START COOLDOWN)
------------------------------------------------
if event == "UNIT_SPELLCAST_SUCCEEDED" then
    if RC.dragging then return end   -- ⭐ guard

    local unit, castGUID, spellID = ...

    if unit ~= "player" then return end
    if not spellID then return end

    local group = RC.spells[spellID]
    if not group then return end

    local data = HEALING_COOLDOWNS[spellID]
    if not data then return end

    local now = GetTime()
    group.cooldownStart    = now
    group.cooldownDuration = data.cooldown
    group.cooldownEnd      = now + data.cooldown
    group.onCooldown       = true

    if group.bar and group.bar.fill then
        group.bar.fill:SetValue(0)
    end

    return
end

    ------------------------------------------------
-- SPELL COOLDOWN UPDATE (SAFETY NET)
------------------------------------------------
if event == "SPELL_UPDATE_COOLDOWN" then
    if RC.dragging then return end   -- ⭐ guard

    for _, group in pairs(RC.spells) do
        UpdateGroupCooldown(group)
    end
    return
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
    bg:Hide()
    print("RaidCooldowns locked")
else
    bg:Show()
    bg:SetColorTexture(0, 0, 0, 0.25)
    print("RaidCooldowns unlocked (drag panel)")
end

end

-- Force unlock (failsafe)
SLASH_RAIDCDUNLOCK1 = "/raidcdunlock"
SlashCmdList.RAIDCDUNLOCK = function()
    RC.locked = false
    UpdatePanelMouseState()
   bg:Show()
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
-- DEBUG ONLY
_G.RaidCD_Debug = function()
    if not RC or not RC.spells then
        print("RC not initialized yet")
        return
    end

    for _, g in pairs(RC.spells) do
        print(g.name, g.hasOwners)
    end
end
