print("RaidCooldowns file loaded")




------------------------------------------------
-- HEALING / RAID COOLDOWNS (SOURCE OF TRUTH)
------------------------------------------------
local HEALING_COOLDOWNS = {

    -- DRUID
    [740]   = { name = "Tranquility", class = "DRUID", cooldown = 180, category = "raid" },
[33891] = { name = "Incarnation: Tree of Life", class = "DRUID", cooldown = 180, category = "raid" },
[29166] = { name = "Innervate", class = "DRUID", cooldown = 180, category = "external" },
[20484] = { name = "Rebirth", class = "DRUID", cooldown = 600, category = "bres" },

    -- SHAMAN
  [114052] = { name = "Ascendance", class = "SHAMAN", cooldown = 180, category = "raid" },
[108280] = { name = "Healing Tide Totem", class = "SHAMAN", cooldown = 180, category = "raid" },
[98008]  = { name = "Spirit Link Totem", class = "SHAMAN", cooldown = 180, category = "raid" },
[2825]   = { name = "Bloodlust", class = "SHAMAN", cooldown = 300, category = "utility" },


    -- PRIEST
   [64843]  = { name = "Divine Hymn", class = "PRIEST", cooldown = 180, category = "raid" },
[47788]  = { name = "Guardian Spirit", class = "PRIEST", cooldown = 180, category = "external" },
[33206]  = { name = "Pain Suppression", class = "PRIEST", cooldown = 180, category = "external" },
[62618]  = { name = "Power Word: Barrier", class = "PRIEST", cooldown = 180, category = "raid" },
[421453] = { name = "Ultimate Penitence", class = "PRIEST", cooldown = 240, category = "raid" },

    -- MONK
  [115310] = { name = "Revival", class = "MONK", cooldown = 180, category = "raid" },
[388615] = { name = "Restoral", class = "MONK", cooldown = 180, category = "raid" },

    -- PALADIN
  [31821]  = { name = "Aura Mastery", class = "PALADIN", cooldown = 180, category = "raid" },

    -- EVOKER
  [363534] = { name = "Rewind", class = "EVOKER", cooldown = 240, category = "raid" },

    -- DEATH KNIGHT
   [51052] = { name = "Anti-Magic Zone", class = "DEATHKNIGHT", cooldown = 240, category = "raid" },
[61999] = { name = "Raise Ally", class = "DEATHKNIGHT", cooldown = 600, category = "bres" },

    -- MAGE
   [80353] = { name = "Time Warp", class = "MAGE", cooldown = 300, category = "utility" },

    -- DEMON HUNTER
    [196718] = { name = "Darkness", class = "DEMONHUNTER", cooldown = 300, category = "raid" },

    -- WARLOCK
   [20707] = { name = "Soulstone", class = "WARLOCK", cooldown = 600, category = "bres" },
}

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
	entries = {},
    locked = true,

    -- Talent commit tracking
    talentCommitInProgress = false,
	debugMode = false,
	spellScanComplete = false,


}
-- Drag preview state (gap + live updates)
RC.dragTargetIndex  = nil      -- for vertical layouts
RC.dragTargetColumn = nil      -- for COLUMN_LIST
RC.dragTargetRow    = nil      -- for COLUMN_LIST
RC._lastDragKey     = nil      -- prevents UpdateLayout spam
RC.barPool = RC.barPool or {}   -- key -> bar frame

RC.debugShowAllSpells = false
RC.version = "0.1.1"

------------------------------------------------
-- APPLY PANEL SIZE FROM SETTINGS 
------------------------------------------------
local function ApplyPanelSizeFromSettings()
    if not panel then return end
    if not RaidCooldownsDB or not RaidCooldownsDB.layout then return end

    local w = tonumber(RaidCooldownsDB.layout.width)  or 360
    local h = tonumber(RaidCooldownsDB.layout.height) or 300

    panel:SetSize(w, h)
end



------------------------------------------------
-- CREATE PANEL
------------------------------------------------
panel = CreateFrame("Frame", "RaidCooldownsPanel", UIParent, "BackdropTemplate")

-- one reusable gap placeholder for drag previews (MUST be after panel exists)
RC.gapFrame = RC.gapFrame or CreateFrame("Frame", nil, panel, "BackdropTemplate")
RC.gapFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
RC.gapFrame:SetBackdropColor(1, 1, 1, 0.20)
RC.gapFrame:SetFrameStrata("HIGH")
RC.gapFrame:SetFrameLevel(panel:GetFrameLevel() + 50)
RC.gapFrame:Hide()

panel:SetFrameStrata("LOW")
panel:SetFrameLevel(10)

panel:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
})

panel:SetBackdropColor(0, 0, 0, 0.6)

-- 🔒 SAFE DEFAULTS ONLY (NO DB ACCESS HERE)
panel:SetSize(360, 300)
panel:SetPoint("CENTER")
panel:SetClampedToScreen(false)
panel:EnableMouse(true)

panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")

panel:SetScript("OnDragStart", function(self)
    if not RC.locked then
        self:StartMoving()
    end
end)

panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)



------------------------------------------------
-- Forward Declarations
------------------------------------------------
local ApplyProfile
local InitUI
local UpdateOwners
local UpdateLayout
local SafeRefreshLayout
local CreateGroups
local RefreshTemplateDropdown
local CreateExportWindow
local SerializeTable
local CreateImportWindow
local GetCharKey
local UpdateAllBarFonts  
local GetCurrentProfileName
local ApplyTemplateToAllBars
local PreCreateAllBars
local DistributeSlidersEvenly
local RefreshFontDropdown
local UpdateProfileStatusText
local LayoutHandlers = {}
local ProfilesLeftStack
local ProfilesRightStack
local HideAllBars
local rebuildPending = false
local UpdateDragPreview

local function RC_Debug(msg)
    if RC and RC.debugMode then
        print("|cff33ff99RaidCooldowns:|r", msg)
    end
end

SLASH_RCDDEBUG1 = "/rcddebug"
SlashCmdList.RCDDEBUG = function(msg)
    msg = (msg or ""):lower()
    if msg == "on" then
        RC.debugMode = true
        print("|cff33ff99RaidCooldowns:|r debug ON")
    elseif msg == "off" then
        RC.debugMode = false
        print("|cff33ff99RaidCooldowns:|r debug OFF")
    elseif msg == "dump" then
        if RebuildOrderedList then RebuildOrderedList() end
        if UpdateLayout then UpdateLayout() end
        print("|cff33ff99RaidCooldowns:|r dump done")
    else
        print("|cff33ff99RaidCooldowns:|r /rcddebug on | off | dump")
    end
end


------------------------------------------------
-- UNIVERSAL VISIBILITY RULE (SINGLE SOURCE)
------------------------------------------------
local function ShouldDisplaySpell(entry)

    if not entry then
        return false
    end

    -- Test mode shows everything
    if RC.testMode then
        return true
    end

    -- Must be tracked
    if not IsSpellTracked(entry.spellID) then
        return false
    end

    return true
end




------------------------------------------------
-- DO SPEC REBUILD
------------------------------------------------
local function DoSpecRebuild()

    CreateGroups()
    PreCreateAllBars()
    UpdateOwners()
    RebuildOrderedList()

    RefreshActiveProfileLabel()
    UpdateSpecButtonStates()
    RefreshTemplateDropdown()
    UpdateAllBarFonts()
    UpdateLayout()
end

------------------------------------------------
-- HARD RESET STATE
------------------------------------------------
local function HardResetState()

    -- Stop drag
    RC.previewOrdered   = nil
    RC.dragging         = nil
    RC.dragStarted      = false
    RC.dragCurrentOrder = nil

    

    wipe(RC.spells)
    wipe(RC.ordered)
end



------------------------------------------------
-- PROFILE SWITCH CORE
------------------------------------------------
function SwitchToProfile(name)

local charKey = GetCharKey()
local current = RaidCooldownsDB.char[charKey]

-- Prevent redundant switching
if current == name then
    return
end

    RaidCooldownsDB.char[GetCharKey()] = name

    ApplyProfile()

    -- 🔥 Force dropdown to display correct profile
    if profileDrop then
        UIDropDownMenu_SetSelectedValue(profileDrop, nil)
        UIDropDownMenu_SetSelectedValue(profileDrop, name)
        UIDropDownMenu_SetText(profileDrop, name)
    end

    UpdateSpecButtonStates()
	UpdateProfileStatusText()

end

------------------------------------------------
-- GET TEMPLATE STORAGE
------------------------------------------------
local function GetTemplateStorage()

    local profile  = GetProfile()
    local template = RaidCooldownsDB.settings.template

    profile.templateOrders = profile.templateOrders or {}

    ------------------------------------------------
    -- Ensure template key exists
    ------------------------------------------------
    if type(profile.templateOrders[template]) ~= "table" then
        profile.templateOrders[template] = {
            order   = {},
            columns = {}
        }
    end

    local storage = profile.templateOrders[template]

    ------------------------------------------------
    -- Ensure sub-tables exist
    ------------------------------------------------
    storage.order   = storage.order   or {}
    storage.columns = storage.columns or {}

    return storage
end


------------------------------------------------
-- ENSURE TEMPLATE ORDER INITIALIZED 
------------------------------------------------
local function EnsureTemplateOrderInitialized(storage)
    storage.order   = storage.order   or {}
    storage.columns = storage.columns or {}

    local template = RaidCooldownsDB.settings.template
    local maxCols  = tonumber(RaidCooldownsDB.settings.columns) or 3

    -- Find max existing order index (non-column)
    local maxOrder = 0
    for _, v in pairs(storage.order) do
        if type(v) == "number" and v > maxOrder then
            maxOrder = v
        end
    end

    if template == "COLUMN_LIST" then
        local colMax = {}
        for c = 1, maxCols do colMax[c] = 0 end

        -- pass 1: find max per column from existing storage
        for spellID, ord in pairs(storage.order) do
            local col = tonumber(storage.columns[spellID]) or 1
            if col < 1 or col > maxCols then col = 1 end

            if type(ord) == "number" and ord > (colMax[col] or 0) then
                colMax[col] = ord
            end
        end

        -- pass 2: assign missing column/order for every entry we might show
        for _, e in ipairs(RC.entries or {}) do
            local id = e.spellID
            if id then
                local col = tonumber(storage.columns[id]) or tonumber(e.column) or 1
                if col < 1 or col > maxCols then col = 1 end

                storage.columns[id] = col
                e.column = col

                if type(storage.order[id]) ~= "number" then
                    colMax[col] = (colMax[col] or 0) + 1
                    storage.order[id] = colMax[col]
                end
            end
        end

    else
        -- single list mode
        for _, e in ipairs(RC.entries or {}) do
            local id = e.spellID
            if id and type(storage.order[id]) ~= "number" then
                maxOrder = maxOrder + 1
                storage.order[id] = maxOrder
            end
        end
    end
end

------------------------------------------------
-- RebuildOrderedList (CLEAN / STABLE)
------------------------------------------------
RebuildOrderedList = function()
    RC_Debug("RebuildOrderedList running")
    if not RC then return end

    RC.entries = RC.entries or {}
    RC.ordered = RC.ordered or {}
    wipe(RC.ordered)

    local template = RaidCooldownsDB.settings.template
    local storage  = GetTemplateStorage()
    EnsureTemplateOrderInitialized(storage)

    ------------------------------------------------
    -- COLUMN LIST MODE
    ------------------------------------------------
    if template == "COLUMN_LIST" then
        -- IMPORTANT: force numeric
        local maxColumns = tonumber(RaidCooldownsDB.settings.columns) or 3
        storage.columns = storage.columns or {}

        local columns = {}
        for i = 1, maxColumns do
            columns[i] = {}
        end

        for _, entry in ipairs(RC.entries) do
            if ShouldDisplaySpell(entry) then
                local col = tonumber(storage.columns[entry.spellID]) or 1
                if col < 1 or col > maxColumns then col = 1 end

                entry.column = col

                RC_Debug(("KEEP(column): %s (%d) tracked=%s"):format(
                    entry.name or "?", entry.spellID or -1, tostring(IsSpellTracked(entry.spellID))
                ))

                table.insert(columns[col], entry)
            else
                RC_Debug(("DROP(column): %s (%d) tracked=%s"):format(
                    entry.name or "?", entry.spellID or -1, tostring(IsSpellTracked(entry.spellID))
                ))
            end
        end

        -- sort each column then append into RC.ordered
        for col = 1, maxColumns do
            table.sort(columns[col], function(a, b)
                return (storage.order[a.spellID] or 9999) < (storage.order[b.spellID] or 9999)
            end)

            for _, entry in ipairs(columns[col]) do
                table.insert(RC.ordered, entry)
            end
        end

        return
    end

    ------------------------------------------------
    -- NON COLUMN MODE (ICON_BAR, BAR_ONLY, etc.)
    ------------------------------------------------
    for _, entry in ipairs(RC.entries) do
        if ShouldDisplaySpell(entry) then
            RC_Debug(("KEEP: %s (%d) tracked=%s"):format(
                entry.name or "?", entry.spellID or -1, tostring(IsSpellTracked(entry.spellID))
            ))
            table.insert(RC.ordered, entry)
        else
            RC_Debug(("DROP: %s (%d) tracked=%s"):format(
                entry.name or "?", entry.spellID or -1, tostring(IsSpellTracked(entry.spellID))
            ))
        end
    end

    table.sort(RC.ordered, function(a, b)
        return (storage.order[a.spellID] or 9999) < (storage.order[b.spellID] or 9999)
    end)
end
------------------------------------------------
-- SAFE LAYOUT REFRESH (THROTTLED)
------------------------------------------------
local function SafeRefreshLayout()
if RC and RC.dragging then return end
    if InCombatLockdown() then
        pendingLayoutUpdate = true
        return
    end

    UpdateOwners()
    RebuildOrderedList()
    UpdateLayout()
end

------------------------------------------------
-- UPDATE BAR MOUSE STATE
------------------------------------------------
local function UpdateBarMouseState()
    -- Allow dragging ONLY when:
    -- - Test mode is on
    -- - Panel is unlocked
    local allow = (not RC.locked) and RC.testMode

    for _, entry in ipairs(RC.entries or {}) do
        if entry.bar then
            entry.bar:EnableMouse(allow)
        end
    end
end
------------------------------------------------
-- ANCHOR BAR TO PANEL 
------------------------------------------------
local function AnchorBarToPanelTop(bar, y)
    if RaidCooldownsDB.settings.centerBars then
        bar:SetPoint("TOP", panel, "TOP", 0, y)
    else
        bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    end
end



------------------------------------------------
-- SAVED VARIABLES
------------------------------------------------
RaidCooldownsDB = RaidCooldownsDB or {}
RaidCooldownsDB.settings = RaidCooldownsDB.settings or {}
RaidCooldownsDB.layout   = RaidCooldownsDB.layout   or {}
RaidCooldownsDB.profiles = RaidCooldownsDB.profiles or {}
RaidCooldownsDB.char     = RaidCooldownsDB.char or {}
RaidCooldownsDB.specProfiles = RaidCooldownsDB.specProfiles or {}

RaidCooldownsDB.roleProfiles = RaidCooldownsDB.roleProfiles or {}

-- 🔥 ENSURE DEFAULT PROFILE EXISTS AT LOAD
if not RaidCooldownsDB.profiles["Default"] then
    RaidCooldownsDB.profiles["Default"] = {
        settings       = {},
        layout         = {},
        templateOrders = {},
        trackedSpells  = {},
    }
end





------------------------------------------------
-- CLEAN LOGIN BOOTSTRAP (NO ADDON_LOADED)
------------------------------------------------
local ev = CreateFrame("Frame")

ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("TRAIT_CONFIG_UPDATED")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("UNIT_HEALTH")

ev:SetScript("OnEvent", function(self, event, ...)

if event == "ADDON_LOADED" then
    local addonNameLoaded = ...

    if addonNameLoaded ~= "RaidCooldowns" then
        return
    end

    -- DB INIT ONLY HERE
    RaidCooldownsDB = RaidCooldownsDB or {}
    RaidCooldownsDB.settings = RaidCooldownsDB.settings or {}
    RaidCooldownsDB.layout = RaidCooldownsDB.layout or {}
    RaidCooldownsDB.profiles = RaidCooldownsDB.profiles or {}
    RaidCooldownsDB.char = RaidCooldownsDB.char or {}
    RaidCooldownsDB.specProfiles = RaidCooldownsDB.specProfiles or {}
    RaidCooldownsDB.roleProfiles = RaidCooldownsDB.roleProfiles or {}
	RaidCooldownsDB.settings.spellNameColor = RaidCooldownsDB.settings.spellNameColor or { r=1, g=1, b=1, a=1 }
RaidCooldownsDB.settings.cdTextColor    = RaidCooldownsDB.settings.cdTextColor    or { r=1, g=0.82, b=0, a=1 }
  
  print("DB initialized once")


end

 if event == "PLAYER_LOGIN" then

    C_Timer.After(0.5, function()

        InitUI()
		ApplyPanelSizeFromSettings()
		local charKey = GetCharKey()

-- Ensure character always has an assigned profile
if not RaidCooldownsDB.char[charKey] then
    for name in pairs(RaidCooldownsDB.profiles) do
        RaidCooldownsDB.char[charKey] = name
        print("Assigned default profile to character:", name)
        break
    end
end
        ApplyProfile()

CreateGroups()
UpdateOwners()
PreCreateAllBars()
UpdateBarMouseState()
RebuildOrderedList()
UpdateAllBarFonts()
UpdateLayout()
UpdateProfileStatusText()
       
        UpdatePanelBackground()

        -- 🔥 FORCE SPEC SYNC
        local specIndex = GetSpecialization()
        if specIndex then
            local specID = GetSpecializationInfo(specIndex)
            local assignedProfile = RaidCooldownsDB.specProfiles[specID]

            if assignedProfile then
                SwitchToProfile(assignedProfile)
            end
        end

    end)

    return
end




if event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then


    if InCombatLockdown() then
        C_Timer.After(0.5, function()
            ev:GetScript("OnEvent")(ev, "ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        end)
        return
    end

    local specIndex = GetSpecialization()
    if not specIndex then return end

    local specID = GetSpecializationInfo(specIndex)
    if not specID then return end

-- 1️⃣ Try spec-specific profile
local assignedProfile = RaidCooldownsDB.specProfiles[specID]

-- 2️⃣ Fallback to role-based profile if no spec override
if not assignedProfile then
    local role = GetSpecializationRole(specIndex)
    assignedProfile = RaidCooldownsDB.roleProfiles[role]
end

    local charKey = GetCharKey()
  local current = RaidCooldownsDB.char[charKey]

-- Safety fallback
if not current then
    for name in pairs(RaidCooldownsDB.profiles) do
        RaidCooldownsDB.char[charKey] = name
        current = name
        break
    end
end
	


   if assignedProfile then
    SwitchToProfile(assignedProfile)
end
UpdateProfileStatusText()
    C_Timer.After(0, function()

        if not profileDrop then return end

        local now = GetCurrentProfileName()

        UIDropDownMenu_Initialize(profileDrop, InitializeProfileDropDown)
        UIDropDownMenu_SetSelectedValue(profileDrop, nil)
        UIDropDownMenu_SetSelectedValue(profileDrop, now)
        UIDropDownMenu_SetText(profileDrop, now)

    end)

    return
end


if event == "TRAIT_CONFIG_UPDATED"
or event == "SPELLS_CHANGED"
or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then

 if RC and RC.dragging then return end

    if rebuildPending then return end
    rebuildPending = true

    C_Timer.After(0.15, function()

        rebuildPending = false

        -- Clean runtime state
        if RC.entries then
            for _, entry in ipairs(RC.entries) do
                if entry.bar then
                    entry.bar:Hide()
                end
            end
        end

        wipe(RC.entries)
        wipe(RC.ordered)

        CreateGroups()
        UpdateOwners()
        RebuildOrderedList()
        PreCreateAllBars()
        UpdateLayout()

    end)

    return
end

    if event == "GROUP_ROSTER_UPDATE" then
	  if RC and RC.dragging then return end
        SafeRefreshLayout()
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        RC.dragging = nil
        RC.previewOrdered = nil
        RC.dragStarted = false
        RC.dragCurrentOrder = nil
		RC._lastDragKey = nil
RC.dragTargetIndex = nil
RC.dragTargetColumn = nil
RC.dragTargetRow = nil
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        SafeRefreshLayout()
        return
    end
if event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, castGUID, spellID = ...

    if not unit or not spellID then return end
    if not UnitExists(unit) then return end

    local name, realm = UnitName(unit)
    if not name then return end
    if realm and realm ~= "" then
        name = name .. "-" .. realm
    end

    -- Match correct entry
    for _, entry in ipairs(RC.entries or {}) do
        if entry.spellID == spellID and entry.owner == name then
            UpdateGroupCooldown(entry)
            break
        end
    end

    return
end

if event == "UNIT_HEALTH" then

    local unit = ...

    if not unit then return end
    if not UnitExists(unit) then return end

    local name, realm = UnitName(unit)
    if not name then return end

    if realm and realm ~= "" then
        name = name .. "-" .. realm
    end

    local isDead = UnitIsDeadOrGhost(unit)

    for _, entry in ipairs(RC.entries or {}) do
        if entry.owner == name then
            entry.isDead = isDead

            if entry.bar then
                UpdateDeathVisual(entry)
            end
        end
    end

    return
end

end)


-- IMPORTANT: register this LAST
ev:RegisterEvent("ADDON_LOADED")



------------------------------------------------
-- UPDATE ALL BAR FONTS
------------------------------------------------
UpdateAllBarFonts = function()

    local font = RaidCooldownsDB.settings.font
    if not font or not font:find("\\") then
        font = "Fonts\\FRIZQT__.TTF"
    end

    for _, entry in ipairs(RC.entries or {}) do
        if entry.bar then

            if entry.bar.label then
                entry.bar.label:SetFont(
                    font,
                    RaidCooldownsDB.settings.spellTextSize or 12,
                    "OUTLINE"
                )
            end

            if entry.bar.cdText then
                entry.bar.cdText:SetFont(
                    font,
                    RaidCooldownsDB.settings.cdTextSize or 12,
                    "OUTLINE"
                )
            end
        end
    end
end




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
	[115310] = true,
[388615] = true,

}

local ALWAYS_VISIBLE = {
    [51052] = true,  -- Anti-Magic Zone
    [61999] = true,  -- Raise Ally
    [20484] = true,  -- Rebirth
    [20707] = true,  -- Soulstone
}

------------------------------------------------
-- NON-HEALER SPELL → VALID SPECS
------------------------------------------------
local NON_HEALER_SPELL_SPECS = {
  [2825] = { [262]=true, [263]=true, [264]=true }, -- Bloodlust
    [80353] = { [62] = true, [63] = true, [64] = true },     -- Time Warp (Mage)
    [196718]= { [577] = true, [581] = true },                -- Darkness (DH)
    [51052] = { [250] = true },                              -- AMZ (Blood DK)
    [20707] = { [265] = true, [266] = true, [267] = true },  -- Soulstone (Warlock)
}



------------------------------------------------
-- SPEC FILTER (SOURCE OF TRUTH)
------------------------------------------------
local SPEC_FILTER = {

    -- PRIEST
    [64843]  = { [257] = true }, -- Divine Hymn (Holy)
    [62618]  = { [256] = true }, -- Barrier (Disc)
    [47788]  = { [257] = true }, -- Guardian Spirit (Holy)
    [33206]  = { [256] = true }, -- Pain Suppression (Disc)

    -- DRUID
    [740]    = { [105] = true }, -- Tranquility
    [29166]  = { [105] = true }, -- Innervate

    -- SHAMAN
    [108280] = { [264] = true }, -- Healing Tide
    [98008]  = { [264] = true }, -- Spirit Link
	[114052] = { [264] = true }, -- Ascendance (Resto only)
    -- PALADIN
    [31821]  = { [65] = true },  -- Aura Mastery
}







------------------------------------------------
-- SHORT DISPLAY NAMES (UI ONLY)
------------------------------------------------
SHORT_SPELL_NAMES = {

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
shortSpellNames = true,

}





------------------------------------------------
-- RaidCooldowns.lua (CLEAN / STABLE TEMPLATE BASE)
------------------------------------------------
-- COLUMN CONSTANTS
local ROW_SPACING = -12
local RIGHT_CARD_SPACING = -32
local COLUMN_WIDTH = 220
local COLUMN_GAP   = 16
local MAX_COLUMNS = 3

------------------------------------------------
-- 📐 NORMALIZED SECTION METRICS (GLOBAL)
------------------------------------------------
local SECTION_TOP_Y        = -8
local TITLE_HEIGHT         = 24
local TITLE_SPACING        = -6
local SEPARATOR_SPACING    = -12
local CARD_SPACING         = -20
local STACK_ROW_SPACING    = -20
local STACK_START_Y = -8
local CARD_TOP_PADDING     = -20
local LABEL_TO_DROPDOWN    = -18
local DROPDOWN_TO_LABEL    = -28
local ICON_GAP = 6
local OWNER_LINE_HEIGHT = 14
local SLIDER_FOOTPRINT = 36
local SLIDER_BLOCK_HEIGHT = 65
local OWNER_PADDING = 4
local UpdateLayoutPageHeight
local STACK_TOP_OFFSET = 14
local BuildTrackingUI


------------------------------------------------
-- CREATE GROUPS
------------------------------------------------
CreateGroups = function(forceProfileName)


if InCombatLockdown() then
    C_Timer.After(0.5, function()
        CreateGroups()
        UpdateOwners()
        RebuildOrderedList()
        UpdateLayout()
    end)
    return
end



    wipe(RC.spells)
    wipe(RC.ordered)

  local profile

if forceProfileName then
    profile = RaidCooldownsDB.profiles[forceProfileName]
else
    profile = GetProfile()
end

local template = RaidCooldownsDB.settings.template or "ICON_BAR"
RaidCooldownsDB.settings.template = template


    profile.templateOrders = profile.templateOrders or {}

    local storage = profile.templateOrders[template]

    ------------------------------------------------
    -- 🔥 HANDLE OLD STRUCTURE SAFELY
    ------------------------------------------------
    if storage and not storage.order then
        -- old flat structure → convert in-place
        local migrated = {
            order = {},
            columns = {}
        }

        for spellID, orderIndex in pairs(storage) do
            if type(spellID) == "number" then
                migrated.order[spellID] = orderIndex
            end
        end

        profile.templateOrders[template] = migrated
        storage = migrated
    end

    ------------------------------------------------
    -- ENSURE STORAGE EXISTS
    ------------------------------------------------
    if not storage then
        storage = {
            order = {},
            columns = {}
        }
        profile.templateOrders[template] = storage
    end

   ------------------------------------------------
-- BUILD SPELL METADATA ONLY
------------------------------------------------
local sortedSpells = {}

for spellID in pairs(HEALING_COOLDOWNS) do
    table.insert(sortedSpells, spellID)
end

table.sort(sortedSpells)

for _, spellID in ipairs(sortedSpells) do

    local data = HEALING_COOLDOWNS[spellID]

    RC.spells[spellID] = {
        spellID = spellID,
        name = data.name,
        class = data.class,
        category = data.category,
        cooldown = data.cooldown,
    }

end
end

------------------------------------------------
-- IS SPELL ACTUALLY ACTIVE
------------------------------------------------
local function IsSpellActuallyActive(spellID)
    local cdInfo = C_Spell.GetSpellCooldown(spellID)
    if not cdInfo then return false end

    -- Inactive talent spells return 0 duration
    if cdInfo.duration == 0 then
        return false
    end

    return true
end




------------------------------------------------
-- IS ACTIVE CHOICE SPELL
------------------------------------------------
local function IsActiveChoiceSpell(spellID)

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return false end

    local configInfo = C_Traits.GetConfigInfo(configID)
    if not configInfo then return false end

    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodes = C_Traits.GetTreeNodes(treeID)

        for _, nodeID in ipairs(nodes) do
            local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)

            if nodeInfo and nodeInfo.entryIDs and #nodeInfo.entryIDs > 1 then
                -- This is a choice node

                for _, entryID in ipairs(nodeInfo.entryIDs) do
                    local entryInfo = C_Traits.GetEntryInfo(configID, entryID)

                    if entryInfo and entryInfo.definitionID then
                        local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)

                        if defInfo and defInfo.spellID == spellID then
                            return nodeInfo.activeEntry
                                and nodeInfo.activeEntry.entryID == entryID
                        end
                    end
                end
            end
        end
    end

    return true -- Not in a choice node, allow normally
end


------------------------------------------------
-- UPDATE OWNERS (FINAL SAFE - NO GOTO)
------------------------------------------------
UpdateOwners = function()

if RC and RC.dragging then return end
    if InCombatLockdown() then return end
    if not RC or not RC.spells then return end

-- Reuse existing bars (prevents duplicates forever)
RC._usedBars = RC._usedBars or {}
wipe(RC._usedBars)

-- Hide current entry bars and return them to pool
for _, e in ipairs(RC.entries or {}) do
    if e.bar then
        e.bar:Hide()
        -- store by key if we can
        if e.owner and e.spellID then
local k = e.owner .. "#" .. e.spellID
e.bar._rcKey = k
RC.barPool[k] = e.bar
        end
    end
end

wipe(RC.entries)

    ------------------------------------------------
    -- UNIT CHECK
    ------------------------------------------------
    local function CheckUnit(unit)

        if not UnitExists(unit) then return end

        local name, realm = UnitName(unit)
        if not name then return end
        if realm and realm ~= "" then
            name = name .. "-" .. realm
        end

        local _, class = UnitClass(unit)
        if not class then return end

        local specID
        if unit == "player" then
            local specIndex = GetSpecialization()
            if specIndex then
                specID = GetSpecializationInfo(specIndex)
            end
        end

        for spellID, group in pairs(RC.spells) do

            if group.class == class then

                local allow = false

                ------------------------------------------------
                -- HEALER SPELLS
                ------------------------------------------------
                if HEALER_ONLY and HEALER_ONLY[spellID] then

                    if unit == "player" then
                        if SPEC_FILTER and SPEC_FILTER[spellID] then
                            if specID and SPEC_FILTER[spellID][specID] then
                                allow = true
                            end
                        end
                    else
                        if UnitGroupRolesAssigned(unit) == "HEALER" then
                            allow = true
                        end
                    end

                ------------------------------------------------
                -- NON HEALER SPELLS
                ------------------------------------------------
                elseif NON_HEALER_SPELL_SPECS and NON_HEALER_SPELL_SPECS[spellID] then

                    if unit == "player" then
                        if specID and NON_HEALER_SPELL_SPECS[spellID][specID] then
                            allow = true
                        end
                    else
                        allow = true
                    end
                end

                ------------------------------------------------
                -- FINAL TALENT CHECK (PLAYER ONLY)
                ------------------------------------------------
                if allow and unit == "player" then
                    if not IsPlayerSpell(spellID) then
                        allow = false
                    end
                end

                ------------------------------------------------
                -- ADD ENTRY
                ------------------------------------------------
                if allow then
local key = name .. "#" .. spellID
local pooledBar = RC.barPool[key]

-- ✅ safety: only reuse if it truly belongs to this key
if pooledBar and pooledBar._rcKey and pooledBar._rcKey ~= key then
    pooledBar = nil
end

-- ✅ claim it so it cannot be assigned twice
RC.barPool[key] = nil

table.insert(RC.entries, {
    spellID = spellID,
    name = group.name,
    class = class,
    owner = name,
    onCooldown = false,
    cooldownStart = nil,
    cooldownDuration = nil,
    cooldownEnd = nil,
    bar = pooledBar,          -- ✅ reuse if it exists
})
RC._usedBars[key] = true
                end
            end
        end
    end

    ------------------------------------------------
    -- SCAN UNITS
    ------------------------------------------------
    CheckUnit("player")

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid"..i
            if not UnitIsUnit(unit, "player") then
                CheckUnit(unit)
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            CheckUnit("party"..i)
        end
    end
	for key, bar in pairs(RC.barPool or {}) do
    if not RC._usedBars[key] and bar then
        bar:Hide()
    end
end
end




local FONT_CHOICES = {
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"]  = "Fonts\\ARIALN.TTF",
    ["Morpheus"]      = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]        = "Fonts\\SKURRI.TTF",
}

RefreshFontDropdown = function()

    if not fontDrop then return end

    local current = RaidCooldownsDB.settings and RaidCooldownsDB.settings.font
    if not current then return end

    for name, path in pairs(FONT_CHOICES) do
        if path == current then

            -- 🔥 HARD SET INTERNAL STATE
            fontDrop.selectedValue = path

            UIDropDownMenu_SetSelectedValue(fontDrop, path)
            UIDropDownMenu_SetText(fontDrop, name)

            -- 🔥 Force Blizzard text region update
            local textRegion = _G[fontDrop:GetName() .. "Text"]
            if textRegion then
                textRegion:SetText(name)
            end

            return
        end
    end
end




local function RestoreFontDropdown()

    if not fontDrop then return end

    local currentFont = RaidCooldownsDB.settings.font
    if not currentFont then return end

    for name, path in pairs(FONT_CHOICES) do
        if path == currentFont then

            UIDropDownMenu_SetSelectedValue(fontDrop, path)
            UIDropDownMenu_SetText(fontDrop, name)

            -- 🔥 Force Blizzard internal label refresh
            local textRegion = _G[fontDrop:GetName() .. "Text"]
            if textRegion then
                textRegion:SetText(name)
            end

            break
        end
    end
end



------------------------------------------------
-- NORMALIZE DROPDOWN
------------------------------------------------
local function NormalizeDropdown(drop)
    drop:SetHeight(32)
end




------------------------------------------------
-- ⭐ UNIVERSAL AUTO STACK LAYOUT ENGINE
------------------------------------------------

local function CreateStack(parent, firstAnchor, xOffset, startY, spacing)

    local stack = {
        parent = parent,
        firstAnchor = firstAnchor,
        xOffset = xOffset or 0,
        startY = startY or -16,
        spacing = spacing or -10,
        last = nil,
    }

 function stack:Add(frame, extraGap)
    if not frame or frame == self.last then
        return
    end

    frame:ClearAllPoints()
    frame:SetParent(self.parent)

    local gap = extraGap or self.spacing

   -- 🔒 SAFETY: only stack direct children of parent
if frame:GetParent() ~= self.parent then
    return
end

if not self.last then
    frame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.xOffset, self.startY)
else
    frame:SetPoint("TOPLEFT", self.last, "BOTTOMLEFT", 0, gap)
end

self.last = frame

end



    return stack
end

------------------------------------------------
-- SECTION SEPARATOR (CENTERED UNDER TITLE)
------------------------------------------------
local function CreateTitleSeparator(parent, titleFS, width)

    local sep = CreateFrame("Frame", nil, parent)
    sep:SetHeight(1)

    -- Default width
    width = width or (COLUMN_WIDTH - 24)
    sep:SetWidth(width)

    ------------------------------------------------
    -- CENTER IT UNDER THE TITLE
    ------------------------------------------------
    sep:SetPoint("TOP", titleFS, "BOTTOM", 0, -6)

    ------------------------------------------------
    -- TEXTURE
    ------------------------------------------------
    local tex = sep:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(1, 1, 1, 0.18)

    return sep
end



------------------------------------------------
-- BUTTON HOVER GLOW (SAFE VERSION)
------------------------------------------------
function AddHoverGlow(btn)
    if not btn then return end

    btn:HookScript("OnEnter", function(self)
        if self.GetBackdrop and self:GetBackdrop() then
            self:SetBackdropBorderColor(1, 0.82, 0)
        end
    end)

    btn:HookScript("OnLeave", function(self)
        if self.GetBackdrop and self:GetBackdrop() then
            self:SetBackdropBorderColor(1, 1, 1)
        end
    end)
end

------------------------------------------------
-- AUTO HEIGHT CARD
------------------------------------------------
local function CreateCard(parent, header, width)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetClampedToScreen(true)
    card:SetWidth(width)

    -- 🔑 ALWAYS initialize these
    card._height = 20
    card._last   = nil
    card._first  = nil
    card._minHeight = nil


	


    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    card:SetBackdropColor(0,0,0,0.45)
    card:SetBackdropBorderColor(0.4,0.4,0.4,1)
	
	

function card:Add(frame, spacing)

    if not frame then return end
    if frame == self._last then return end

    spacing = spacing or 12
    frame:ClearAllPoints()

    -- Fixed cards (manually positioned)
    if self._fixed then
        self._last = frame
        return
    end

    ------------------------------------------------
    -- POSITIONING
    ------------------------------------------------
    if not self._last then

        -- FIRST ELEMENT
if frame:IsObjectType("Slider")
or frame:GetObjectType() == "FontString"
or frame.Left
then


            frame:SetPoint("TOP", self, "TOP", 0, -8)
        else
            frame:SetPoint("TOPLEFT", self, "TOPLEFT", 12, -8)
        end

    else

        -- STACKED ELEMENTS
        if frame:IsObjectType("Slider")
        or (frame:GetObjectType() == "Frame" and frame.Left)
        or frame:GetObjectType() == "FontString"
        then
            frame:SetPoint("TOP", self._last, "BOTTOM", 0, -spacing)
        else
        frame:SetPoint("TOPLEFT", self, "TOPLEFT", 12, -(self._height + spacing))
        end

        self._height = self._height + spacing
    end

    ------------------------------------------------
    -- HEIGHT CALCULATION
    ------------------------------------------------
    local h

    if frame:IsObjectType("Slider") then
        h = 48
    elseif frame:IsObjectType("CheckButton") then
        h = 22
    else
        h = frame:GetHeight() or 24
    end

    self._height = self._height + h

    local finalHeight = self._height + 12

    if self._minHeight then
        finalHeight = math.max(finalHeight, self._minHeight)
    end

    self:SetHeight(finalHeight)

    self._last = frame
end



    return card
end

------------------------------------------------
-- CLAMP PROFILE CARD TO OPTIONS WINDOW
------------------------------------------------
local function ClampCardToPage(card)
    if not card or not options then return end

    local maxH = options:GetHeight() - 140
    if card:GetHeight() > maxH then
        card:SetHeight(maxH)
    end
end

------------------------------------------------
-- CHARACTER KEY 
------------------------------------------------
GetCharKey = function()
    local name  = UnitName("player") or "Unknown"
    local realm = GetNormalizedRealmName() or GetRealmName() or "Realm"

    return name.."-"..realm
end

------------------------------------------------
-- GET CURRENT PROFILE NAME
------------------------------------------------
GetCurrentProfileName = function()

    local key = GetCharKey()
    return RaidCooldownsDB.char[key] or "Default"
end

------------------------------------------------
-- REFRESH ACTIVE PROFILE LABEL
------------------------------------------------
function RefreshActiveProfileLabel()

    local current = GetCurrentProfileName()

    if profileDrop then
        UIDropDownMenu_SetSelectedValue(profileDrop, current)

        local textRegion = profileDrop.Text
            or _G[profileDrop:GetName() .. "Text"]

        if textRegion then
            textRegion:SetText(current)
        end
    end

end

------------------------------------------------
-- GET TEMPLATE SETTINGS
------------------------------------------------
local function GetTemplateSettings()
    local profile = GetProfile()
    local template = RaidCooldownsDB.settings.template

    profile.templateSettings = profile.templateSettings or {}
    profile.templateSettings[template] = profile.templateSettings[template] or {}

    return profile.templateSettings[template]
end






------------------------------------------------
-- GET PROFILE
------------------------------------------------
function GetProfile()
    local name = GetCurrentProfileName()

RaidCooldownsDB.profiles[name] = RaidCooldownsDB.profiles[name] or {
    settings       = {},
    layout         = {},
    templateOrders = {},  -- ⭐ unified system
    trackedSpells  = {},
}




    return RaidCooldownsDB.profiles[name]
end

------------------------------------------------
-- APPLY PROFILE 
------------------------------------------------
ApplyProfile = function()


    local p = GetProfile()

    ------------------------------------------------
    -- ENSURE TARGET TABLES EXIST
    ------------------------------------------------
    RaidCooldownsDB.settings      = RaidCooldownsDB.settings      or {}
    RaidCooldownsDB.layout        = RaidCooldownsDB.layout        or {}
    RaidCooldownsDB.trackedSpells = RaidCooldownsDB.trackedSpells or {}

    p.settings       = p.settings       or {}
    p.layout         = p.layout         or {}
    p.trackedSpells  = p.trackedSpells  or {}

    ------------------------------------------------
    -- 🔥 DO NOT REPLACE TABLES — COPY INTO THEM
    ------------------------------------------------
    wipe(RaidCooldownsDB.settings)
    for k,v in pairs(p.settings) do
        RaidCooldownsDB.settings[k] = v
    end

    wipe(RaidCooldownsDB.layout)
    for k,v in pairs(p.layout) do
        RaidCooldownsDB.layout[k] = v
    end

    wipe(RaidCooldownsDB.trackedSpells)
    for k,v in pairs(p.trackedSpells) do
        RaidCooldownsDB.trackedSpells[k] = v
    end

    ------------------------------------------------
    -- SAFE DEFAULT MERGE
    ------------------------------------------------
    for k, v in pairs(DEFAULT_SETTINGS) do
        if RaidCooldownsDB.settings[k] == nil then
            RaidCooldownsDB.settings[k] = v
        end
    end

    if not RaidCooldownsDB.settings.template then
        RaidCooldownsDB.settings.template = DEFAULT_SETTINGS.template
    end
	-- Ensure template always persists in profile
p.settings.template = RaidCooldownsDB.settings.template
end


------------------------------------------------
-- HideAllBars (DEFINE EARLY)
------------------------------------------------
HideAllBars = function()
    for _, child in ipairs({ panel:GetChildren() }) do
        if child and child.icon and child ~= RC.dragging then
            child:Hide()
        end
    end
end

------------------------------------------------
-- UPDATE LAYOUT
------------------------------------------------
UpdateLayout = function()
    if not RC or not panel or not RaidCooldownsDB then return end
    if RC.suppressLayout then return end

    HideAllBars()
    if RC.gapFrame then RC.gapFrame:Hide() end

    local template = RaidCooldownsDB.settings.template
    local handler = LayoutHandlers and LayoutHandlers[template]
    if handler then
	
	
        handler()
    end
end


------------------------------------------------
-- GLOBAL UI REFERENCES (MUST EXIST BEFORE InitUI)
------------------------------------------------
local layoutQueued = false

local options
local content
local Pages = {}
local profileLabel = nil

local controlsCard
local appearanceCard
local panelSizeCard
local importExportCard
local specCard
local activeProfileCard
profileDrop = nil
local templateDrop
local reset





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





local function GetSpellTextOffsets()
    local s = RaidCooldownsDB.settings or {}
    return s.spellTextOffsetX or 0, s.spellTextOffsetY or 0
end


------------------------------------------------
-- SECTION SEPARATOR (RIGHT COLUMN)
------------------------------------------------
local function CreateSectionSeparator(parent)
    local sep = CreateFrame("Frame", nil, parent)
    sep:SetSize(COLUMN_WIDTH - 24, 1)

    local tex = sep:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(1, 1, 1, 0.15)

    return sep
end

------------------------------------------------
-- ⭐ NORMALIZED SECTION HEADER
------------------------------------------------
local function CreateSection(parent, text, width)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetText("|cffffcc00"..text.."|r")
    title:SetJustifyH("CENTER")
    title:SetWidth(width)
    title:SetHeight(TITLE_HEIGHT)

    local sep = CreateFrame("Frame", nil, parent)
sep:SetHeight(1)
sep:SetWidth(width)   -- full width

local tex = sep:CreateTexture(nil, "ARTWORK")
tex:SetPoint("CENTER")
tex:SetHeight(1)
tex:SetWidth(width - 60)  -- actual visible line length
tex:SetColorTexture(1, 1, 1, 0.18)


    -- ✅ CENTER HORIZONTALLY ONLY
  sep:SetPoint("TOP", title, "BOTTOM", 0, -6)

    return title, sep
end


	
------------------------------------------------
-- ⭐ STANDARD CARD DROPDOWN (FINAL / SAFE)
------------------------------------------------
local function CreateCardDropdown(card, labelText, yOffset)

    local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText(labelText)
    label:SetJustifyH("CENTER")

    label:SetPoint("TOP", card, "TOP", 0, yOffset)

local drop = CreateFrame(
    "Frame",
    "RaidCooldownsDropdown_" .. labelText:gsub("%s+", ""),
    card,
    "UIDropDownMenuTemplate"
)


    NormalizeDropdown(drop)

    drop:SetPoint("TOP", label, "BOTTOM", 0, -18)

    UIDropDownMenu_SetWidth(drop, card:GetWidth() - 48)

    return label, drop

end

------------------------------------------------
-- NORMALIZE SLIDER
------------------------------------------------
local function NormalizeSlider(slider)
    if not slider then return end

    -- Core size
    slider:SetWidth(180)
    slider:SetHeight(18)

    slider:ClearAllPoints()
    slider:SetPoint("TOP", slider:GetParent(), "TOP", 0, 0)

    -- ⭐ LABEL — give it real air
    if slider.Text then
        slider.Text:ClearAllPoints()
        slider.Text:SetPoint("BOTTOM", slider, "TOP", 0, 6)
        slider.Text:SetJustifyH("CENTER")
    end

   -- Min value (closer to slider)
if slider.Low then
    slider.Low:ClearAllPoints()
    slider.Low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
end

-- Max value (closer to slider)
if slider.High then
    slider.High:ClearAllPoints()
    slider.High:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
end

end



------------------------------------------------
-- CHECKBOX NORMALIZATION (FIX STRETCHING)
------------------------------------------------
local function NormalizeCheckButton(cb)
    if not cb then return end

    cb:SetWidth(24)
    cb:SetHeight(24)

    if cb.Text then
        cb.Text:ClearAllPoints()
        cb.Text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        cb.Text:SetJustifyH("LEFT")
        cb.Text:SetJustifyV("MIDDLE")
        cb.Text:SetFontObject("GameFontHighlight")
    end
end


------------------------------------------------
-- ADD SLIDER VALUE TEXT
------------------------------------------------
local function AddSliderValueText(slider)
    if slider.ValueText then return end

    local valueText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetJustifyH("CENTER")
    valueText:SetTextColor(1, 0.82, 0)

    -- 🔽 DIRECTLY UNDER THE SLIDER BAR
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, -8)

    slider.ValueText = valueText

    function slider:UpdateValueText(val)
        if type(val) ~= "number" then
            val = self:GetValue()
        end
        self.ValueText:SetText(math.floor(val))
    end

    -- initialize
    slider:UpdateValueText(slider:GetValue())
end


------------------------------------------------
-- GET AVAILABLE CARD HEIGHT
------------------------------------------------
local function GetAvailableCardHeight()
    local paddingTop    = 80   -- header + margins
    local paddingBottom = 32   -- window bottom padding

    local h = options:GetHeight() - paddingTop - paddingBottom

    -- safety clamp
    if h < 260 then h = 260 end
    return h
end


------------------------------------------------
-- PAGE LOGO (REUSABLE)
------------------------------------------------
local function AddPageLogo(parent)

    if not parent then return end

    local logo = parent:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\RaidCooldowns\\Media\\logo")

    logo:SetSize(80, 80) -- adjust size here

    logo:SetPoint("TOP", parent, "TOP", 0, 22)
	
	logo:SetAlpha(0.60)
logo:SetDrawLayer("BACKGROUND")


    return logo
end

------------------------------------------------
-- TRACKING PAGE 
------------------------------------------------
local function BuildTrackingPage()

trackingCenterWrap = CreateFrame("Frame", nil, Pages["Tracking"])
trackingCenterWrap:SetPoint("TOPLEFT", content, "TOPLEFT", 150 + 16, 20)
trackingCenterWrap:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 150 + 16, 0)
trackingCenterWrap:SetWidth((COLUMN_WIDTH * 2) + COLUMN_GAP)
AddPageLogo(trackingCenterWrap)

local displayTitle, displaySep =
    CreateSection(
        trackingCenterWrap,
        "Display Spells",
        (COLUMN_WIDTH * 2) + COLUMN_GAP
    )

displayTitle:SetPoint("TOP", trackingCenterWrap, "TOP", 0, -8)
displaySep:SetPoint("TOP", displayTitle, "BOTTOM", 0, -6)

trackingOptionsCard = CreateCard(
    trackingCenterWrap,
    nil,
    (COLUMN_WIDTH * 2) + COLUMN_GAP
)

trackingOptionsCard:SetPoint("TOP", displaySep, "BOTTOM", 0, -12)
trackingOptionsCard._minHeight = 70

local shortNamesCB = CreateFrame(
    "CheckButton",
    nil,
    trackingOptionsCard,
    "InterfaceOptionsCheckButtonTemplate"
)

NormalizeCheckButton(shortNamesCB)
shortNamesCB.Text:SetText("Use Short Spell Names")
shortNamesCB:SetChecked(RaidCooldownsDB.settings.shortSpellNames)

shortNamesCB:SetScript("OnClick", function(self)
    RaidCooldownsDB.settings.shortSpellNames = self:GetChecked()
    UpdateLayout()
end)


trackingOptionsCard:Add(shortNamesCB, 14)


-- LEFT COLUMN
trackingLeftColumn = CreateFrame("Frame", nil, trackingCenterWrap)
trackingLeftColumn:ClearAllPoints()
trackingLeftColumn:SetPoint("TOPLEFT", trackingOptionsCard, "BOTTOMLEFT", 0, -24)
trackingLeftColumn:SetPoint("BOTTOMLEFT", trackingCenterWrap, "BOTTOMLEFT", 0, 0)
trackingLeftColumn:SetWidth(COLUMN_WIDTH)

-- RIGHT COLUMN
trackingRightColumn = CreateFrame("Frame", nil, trackingCenterWrap)
trackingRightColumn:ClearAllPoints()
trackingRightColumn:SetPoint("TOPLEFT", trackingLeftColumn, "TOPRIGHT", COLUMN_GAP, 0)
trackingRightColumn:SetPoint("BOTTOMLEFT", trackingCenterWrap, "BOTTOMLEFT", COLUMN_WIDTH + COLUMN_GAP, 0)
trackingRightColumn:SetWidth(COLUMN_WIDTH)

TrackingLeftStack = CreateStack(
    trackingLeftColumn,
    trackingLeftColumn,
    0,
    0,
    8
)

TrackingRightStack = CreateStack(
    trackingRightColumn,
    trackingRightColumn,
    0,
    0,
    8
)

trackingCenterWrap:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)


-- NOW create cards
trackingLeftCard = CreateCard(trackingLeftColumn, nil, COLUMN_WIDTH)
trackingRightCard = CreateCard(trackingRightColumn, nil, COLUMN_WIDTH)

trackingLeftCard:SetPoint("TOPLEFT", trackingLeftColumn, "TOPLEFT", 0, 0)
trackingRightCard:SetPoint("TOPLEFT", trackingRightColumn, "TOPLEFT", 0, 0)

-- Title only on LEFT
local trackingTitle, trackingSep =
    CreateSection(
        trackingCenterWrap,
        "Tracked Spells",
        (COLUMN_WIDTH * 2) + COLUMN_GAP
    )



local spacerTitle = trackingRightColumn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
spacerTitle:SetText(" ")
spacerTitle:SetHeight(TITLE_HEIGHT)
spacerTitle:SetWidth(COLUMN_WIDTH)

local spacerSep = CreateFrame("Frame", nil, trackingRightColumn)
spacerSep:SetHeight(1)
spacerSep:SetWidth(COLUMN_WIDTH)

TrackingRightStack:Add(spacerTitle)
TrackingRightStack:Add(spacerSep, -6)





end


------------------------------------------------
-- CREATE COLUMN WRAPPERS 
------------------------------------------------
local function BuildLayoutPage()

-- Layout page columns
centerWrap = CreateFrame("Frame", nil, Pages["Layout"])
centerWrap:ClearAllPoints()
centerWrap:SetPoint("TOPLEFT", content, "TOPLEFT", 150 + 16, 20)
centerWrap:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 150 + 16, 0)
centerWrap:SetWidth((COLUMN_WIDTH * 2) + COLUMN_GAP)
AddPageLogo(centerWrap)

leftColumn = CreateFrame("Frame", nil, centerWrap)
leftColumn:SetPoint("TOPLEFT", centerWrap, "TOPLEFT", 0, 0)
leftColumn:SetPoint("BOTTOMLEFT", centerWrap, "BOTTOMLEFT", 0, 0)
leftColumn:SetWidth(COLUMN_WIDTH)

rightColumn = CreateFrame("Frame", nil, centerWrap)
rightColumn:SetPoint("TOPLEFT", leftColumn, "TOPRIGHT", COLUMN_GAP, 0)
rightColumn:SetPoint("BOTTOMLEFT", leftColumn, "BOTTOMRIGHT", COLUMN_GAP, 0)
rightColumn:SetWidth(COLUMN_WIDTH)




------------------------------------------------
-- CREATE COLUMN STACKS (SAFE LOCATION)
------------------------------------------------

LeftStack = CreateStack(
    leftColumn,
    leftColumn,
    0,
    STACK_START_Y,
    STACK_ROW_SPACING
)


RightColumnStack = CreateStack(
    rightColumn,
    rightColumn,
    0,
    STACK_START_Y,
    STACK_ROW_SPACING
)

------------------------------------------------
-- CREATE SEPARATORS (SAFE LOCATION)
------------------------------------------------

sep1 = CreateSectionSeparator(rightColumn)
sep2 = CreateSectionSeparator(rightColumn)

   



end


------------------------------------------------
-- Distribute EVENLY
------------------------------------------------
DistributeSlidersEvenly = function(card, items, blockHeight)


    local topPad    = 40
    local bottomPad = 32

    local count = #items
    if count == 0 then return end

    local cardHeight = card:GetHeight()
    if not cardHeight or cardHeight <= 0 then return end

    local usableHeight = cardHeight - topPad - bottomPad
local height = blockHeight or SLIDER_BLOCK_HEIGHT
local totalBlocks  = count * height


    -- Center the whole group vertically
    local startY = -topPad - math.max(0, (usableHeight - totalBlocks) / 2)

    for i, slider in ipairs(items) do
        slider:ClearAllPoints()
        slider:SetPoint(
            "TOP",
            card,
            "TOP",
            0,
            startY - ((i - 1) * SLIDER_BLOCK_HEIGHT)
        )
    end
end



------------------------------------------------
-- CREATE COLOR SETTING BUTTON 
------------------------------------------------
local function CreateColorSettingRow(parent, labelText, getColor, setColor)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)

    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(60, 20)
    btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    btn:SetText("Set")

    local swatch = row:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(16, 16)
    swatch:SetPoint("RIGHT", btn, "LEFT", -4, 0)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetPoint("RIGHT", swatch, "LEFT", -6, 0)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)

    local function Refresh()
        local r,g,b,a = getColor()
        swatch:SetColorTexture(r, g, b, a or 1)
    end

   btn:SetScript("OnClick", function()
    local r,g,b,a = getColor()
    a = a or 1

    local function onChanged()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = 1 - (OpacitySliderFrame and OpacitySliderFrame:GetValue() or 0)
        setColor(nr, ng, nb, na)
        Refresh()
        UpdateLayout()
    end

    local function onCancel(prev)
        prev = prev or (ColorPickerFrame and ColorPickerFrame.previousValues) or { r=r, g=g, b=b, a=a }
        setColor(prev.r, prev.g, prev.b, prev.a)
        Refresh()
        UpdateLayout()
    end

    -- Modern API
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            hasOpacity = true,
            opacity = 1 - a,
            swatchFunc = onChanged,
            opacityFunc = onChanged,
            cancelFunc = onCancel,
        })
        return
    end

    -- Legacy fallback
    if not ColorPickerFrame then return end
    ColorPickerFrame.hasOpacity = true
    ColorPickerFrame.opacity = 1 - a
    ColorPickerFrame.previousValues = { r=r, g=g, b=b, a=a }
    ColorPickerFrame.func = onChanged
    ColorPickerFrame.opacityFunc = onChanged
    ColorPickerFrame.cancelFunc = onCancel

    if ColorPickerFrame.SetColorRGB then
        ColorPickerFrame:SetColorRGB(r, g, b)
    elseif ColorPickerFrame_SetColorRGB then
        ColorPickerFrame_SetColorRGB(r, g, b)
    end

    ColorPickerFrame:Show()
end)

    Refresh()
    row.Refresh = Refresh
    return row
end


------------------------------------------------
-- LAYOUT SLIDERS
------------------------------------------------
local function BuildLayoutSliders()
  -- Bar Settings
local barTitle, barSep = CreateSection(leftColumn, "Bar Settings", COLUMN_WIDTH)

local layoutCard = CreateCard(leftColumn, nil, COLUMN_WIDTH)
layoutCard:SetHeight(620)



-- Bar Width
local barWidth = CreateFrame("Slider", nil, layoutCard, "OptionsSliderTemplate")
barWidth:SetMinMaxValues(120, 320)
barWidth:SetValueStep(5)
barWidth:SetValue(RaidCooldownsDB.settings.barWidth)
barWidth:SetHeight(18)
NormalizeSlider(barWidth)
barWidth.Text:SetText("Bar Width")
barWidth.Low:SetText("120")
barWidth.High:SetText("320")
AddSliderValueText(barWidth)
barWidth:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
    RaidCooldownsDB.settings.barWidth = value
    self:UpdateValueText(value)
    UpdateLayout()
end)




-- Bar Height
local barHeight = CreateFrame("Slider", nil, layoutCard, "OptionsSliderTemplate")
barHeight:SetMinMaxValues(12, 40)
barHeight:SetValueStep(1)
barHeight:SetValue(RaidCooldownsDB.settings.barHeight)
barHeight:SetHeight(18)
NormalizeSlider(barHeight)
barHeight.Text:SetText("Bar Height")
barHeight.Low:SetText("12")
barHeight.High:SetText("40")
AddSliderValueText(barHeight)
barHeight:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
    RaidCooldownsDB.settings.barHeight = value
    self:UpdateValueText(value)
    UpdateLayout()
end)




-- Bar Spacing
local barSpacing = CreateFrame("Slider", nil, layoutCard, "OptionsSliderTemplate")
barSpacing:SetMinMaxValues(2, 20)
barSpacing:SetValueStep(1)
barSpacing:SetValue(RaidCooldownsDB.settings.barSpacing)
barSpacing:SetHeight(18)
NormalizeSlider(barSpacing)
barSpacing.Text:SetText("Bar Spacing")
barSpacing.Low:SetText("2")
barSpacing.High:SetText("20")
AddSliderValueText(barSpacing)
barSpacing:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
    RaidCooldownsDB.settings.barSpacing = value
    self:UpdateValueText(value)
    UpdateLayout()
end)



-- Spell / Name Text X
local spellTextX = CreateFrame("Slider", nil, layoutCard, "OptionsSliderTemplate")
spellTextX:SetMinMaxValues(-50, 50)
spellTextX:SetValueStep(1)
spellTextX:SetValue(RaidCooldownsDB.settings.spellTextOffsetX)
spellTextX:SetHeight(18)
NormalizeSlider(spellTextX)
spellTextX.Text:SetText("Name X")
spellTextX.Low:SetText("-50")
spellTextX.High:SetText("50")
AddSliderValueText(spellTextX)
spellTextX:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
   RaidCooldownsDB.settings.spellTextOffsetX = value
    self:UpdateValueText(value)
    UpdateLayout()
end)



-- Spell / Name Text Y
local spellTextY = CreateFrame("Slider", nil, layoutCard, "OptionsSliderTemplate")
spellTextY:SetMinMaxValues(-20, 20)
spellTextY:SetValueStep(1)
spellTextY:SetValue(RaidCooldownsDB.settings.spellTextOffsetY)
spellTextY:SetHeight(18)
NormalizeSlider(spellTextY)
spellTextY.Text:SetText("Name Y")
spellTextY.Low:SetText("-20")
spellTextY.High:SetText("20")
AddSliderValueText(spellTextY)
spellTextY:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
    RaidCooldownsDB.settings.spellTextOffsetY = value
    self:UpdateValueText(value)
    UpdateLayout()
end)



-- Spell / Name Text Size
local spellTextSize = CreateFrame("Slider", nil, layoutCard, "OptionsSliderTemplate")
spellTextSize:SetMinMaxValues(8, 24)
spellTextSize:SetValueStep(1)
spellTextSize:SetValue(RaidCooldownsDB.settings.spellTextSize)
spellTextSize:SetHeight(18)
NormalizeSlider(spellTextSize)
spellTextSize.Text:SetText("Name Size")
spellTextSize.Low:SetText("8")
spellTextSize.High:SetText("24")
AddSliderValueText(spellTextSize)
spellTextSize:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
    RaidCooldownsDB.settings.spellTextSize = value
    self:UpdateValueText(value)
    UpdateLayout()
end)



-- Countdown / READY X
local cdTextX = CreateFrame("Slider", nil, layoutCard, "OptionsSliderTemplate")
cdTextX:SetMinMaxValues(-50, 50)
cdTextX:SetValueStep(1)
cdTextX:SetValue(RaidCooldownsDB.settings.cdTextOffsetX)
cdTextX:SetHeight(18)
NormalizeSlider(cdTextX)
cdTextX.Text:SetText("Cooldown X")
cdTextX.Low:SetText("-50")
cdTextX.High:SetText("50")
AddSliderValueText(cdTextX)
cdTextX:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
   RaidCooldownsDB.settings.cdTextOffsetX = value
    self:UpdateValueText(value)
    UpdateLayout()
end)



-- Countdown / READY Y
local cdTextY = CreateFrame("Slider", nil, layoutCard, "OptionsSliderTemplate")
cdTextY:SetMinMaxValues(-20, 20)
cdTextY:SetValueStep(1)
cdTextY:SetValue(RaidCooldownsDB.settings.cdTextOffsetY)
cdTextY:SetHeight(18)
NormalizeSlider(cdTextY)
cdTextY.Text:SetText("Cooldown Y")
cdTextY.Low:SetText("-20")
cdTextY.High:SetText("20")
AddSliderValueText(cdTextY)
cdTextY:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
   RaidCooldownsDB.settings.cdTextOffsetY = value
    self:UpdateValueText(value)
    UpdateLayout()
end)



-- Countdown / READY Text Size
local cdTextSize = CreateFrame("Slider", nil, layoutCard, "OptionsSliderTemplate")
cdTextSize:SetMinMaxValues(8, 24)
cdTextSize:SetValueStep(1)
cdTextSize:SetValue(RaidCooldownsDB.settings.cdTextSize)
cdTextSize:SetHeight(18)
NormalizeSlider(cdTextSize)
cdTextSize.Text:SetText("Cooldown Size")
cdTextSize.Low:SetText("8")
cdTextSize.High:SetText("24")
AddSliderValueText(cdTextSize)
cdTextSize:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
    RaidCooldownsDB.settings.cdTextSize = value
    self:UpdateValueText(value)
    UpdateLayout()
end)


LeftStack:Add(barTitle)
LeftStack:Add(barSep, -6)
LeftStack:Add(layoutCard, -8)


local layoutSliders = {
    barWidth,
    barHeight,
    barSpacing,
    spellTextX,
    spellTextY,
    spellTextSize,
    cdTextX,
    cdTextY,
    cdTextSize,
}

DistributeSlidersEvenly(layoutCard, layoutSliders)





------------------------------------------------
-- CLAMP CARD HEIGHT
------------------------------------------------
local function ClampCardHeight(card)
    local maxH = options:GetHeight() - 180
    if card:GetHeight() > maxH then
        card:SetHeight(maxH)
    end
end










------------------------------------------------
-- ⭐ AUTO GRID (LAYOUT ROOT)
------------------------------------------------
-- RIGHT COLUMN SECTION WRAPPER

local function CreateRightSection(width)
    local card = CreateCard(rightColumn, nil, width or 260)
    return card
end


-- Card
appearanceCard = CreateRightSection(COLUMN_WIDTH)
appearanceCard:SetHeight(200)



------------------------------------------------
-- BAR TEMPLATE (CLEAN)
------------------------------------------------
-- Bar Template
local templateLabel, templateDrop =
    CreateCardDropdown(appearanceCard, "Bar Template", -10)




UIDropDownMenu_Initialize(templateDrop, function(self, level)



    if level ~= 1 then return end



    for _, key in ipairs(BAR_TEMPLATE_ORDER) do
        local info = UIDropDownMenu_CreateInfo()

        info.text = BAR_TEMPLATES[key]
        info.value = key
        info.isNotRadio = false
        info.checked = (RaidCooldownsDB.settings.template == key)

    info.func = function(btn)

    CloseDropDownMenus()

    RaidCooldownsDB.settings.template = btn.value

    -- 🔥 SAVE TO PROFILE
    local profile = GetProfile()
    profile.settings.template = btn.value

    UIDropDownMenu_SetSelectedValue(templateDrop, btn.value)
    UIDropDownMenu_SetText(templateDrop, BAR_TEMPLATES[btn.value])

-- 🔒 Safety: stop any stuck drag state
RC.dragging = nil
RC.dragStarted = false

-- Ensure bars aren't left in DIALOG strata from a prior drag
for _, entry in ipairs(RC.entries or {}) do
    if entry.bar then
        entry.bar:StopMovingOrSizing()
        entry.bar:SetFrameStrata("MEDIUM")
        entry.bar:SetFrameLevel(panel:GetFrameLevel() + 5)
    end
end

-- Re-apply click-through rule after template change
UpdateBarMouseState()
    RebuildOrderedList()
    UpdateLayout()
end
 UIDropDownMenu_AddButton(info, level)
    end

end)

C_Timer.After(0, function()
    local current = RaidCooldownsDB.settings.template
    if BAR_TEMPLATES[current] then
        UIDropDownMenu_SetSelectedValue(templateDrop, current)
        UIDropDownMenu_SetText(templateDrop, BAR_TEMPLATES[current])
    end
end)

 
-- Force restore selected template text
local currentTemplate = RaidCooldownsDB.settings.template
if BAR_TEMPLATES[currentTemplate] then
    UIDropDownMenu_SetText(templateDrop, BAR_TEMPLATES[currentTemplate])
    UIDropDownMenu_SetSelectedValue(templateDrop, currentTemplate)
end

------------------------------------------------
-- COLOR PICKERS (Bar Style)
------------------------------------------------
local function EnsureColorDefaults()
    RaidCooldownsDB.settings.spellNameColor = RaidCooldownsDB.settings.spellNameColor or { r=1, g=1, b=1, a=1 }
    RaidCooldownsDB.settings.cdTextColor    = RaidCooldownsDB.settings.cdTextColor    or { r=1, g=0.82, b=0, a=1 }
end
EnsureColorDefaults()

local nameRow = CreateColorSettingRow(
    appearanceCard,
    "Spell Name Color",
    function()
        EnsureColorDefaults()
        local n = RaidCooldownsDB.settings.spellNameColor
        return n.r, n.g, n.b, n.a
    end,
    function(r,g,b,a)
        RaidCooldownsDB.settings.spellNameColor = { r=r, g=g, b=b, a=a }
        UpdateLayout()
    end
)

local cdRow = CreateColorSettingRow(
    appearanceCard,
    "Cooldown Text Color",
    function()
        EnsureColorDefaults()
        local c = RaidCooldownsDB.settings.cdTextColor
        return c.r, c.g, c.b, c.a
    end,
    function(r,g,b,a)
        RaidCooldownsDB.settings.cdTextColor = { r=r, g=g, b=b, a=a }
        UpdateLayout()
    end
)

-- Size + anchor them inside Bar Style card (no card:Add here)
local rowW = appearanceCard:GetWidth() - 48
nameRow:SetSize(rowW, 24)
cdRow:SetSize(rowW, 24)

nameRow:ClearAllPoints()
nameRow:SetPoint("TOP", templateDrop, "BOTTOM", 0, -10)

cdRow:ClearAllPoints()
cdRow:SetPoint("TOP", nameRow, "BOTTOM", 0, -6)

------------------------------------------------
-- FONT DROPDOWN (STABLE + SIMPLE)
------------------------------------------------
local fontLabel, fontDrop =
    CreateCardDropdown(appearanceCard, "Font", -20)

fontLabel:ClearAllPoints()
fontLabel:SetPoint("TOP", cdRow, "BOTTOM", 0, -10)

fontDrop:ClearAllPoints()
fontDrop:SetPoint("TOP", fontLabel, "BOTTOM", 0, -10)




fontDrop.initialize = function(self, level)
    if level ~= 1 then return end

    local currentFont = RaidCooldownsDB.settings.font

    for name, path in pairs(FONT_CHOICES) do

        local fontName = name
        local fontPath = path

        local info = UIDropDownMenu_CreateInfo()

        info.text = fontName
        info.value = fontPath

        info.isNotRadio = false

       info.func = function()
    CloseDropDownMenus()

    RaidCooldownsDB.settings.font = fontPath

    -- 🔥 SAVE INTO PROFILE
    local profile = GetProfile()
    profile.settings = profile.settings or {}
    profile.settings.font = fontPath

    UIDropDownMenu_SetSelectedValue(fontDrop, fontPath)
    UIDropDownMenu_SetText(fontDrop, fontName)

    UpdateAllBarFonts()
end


        UIDropDownMenu_AddButton(info, level)
    end
end

UIDropDownMenu_Initialize(fontDrop, fontDrop.initialize)

C_Timer.After(0, function()

    local current = RaidCooldownsDB.settings.font

    for name, path in pairs(FONT_CHOICES) do
        if path == current then
            UIDropDownMenu_SetSelectedValue(fontDrop, path)
            UIDropDownMenu_SetText(fontDrop, name)
            break
        end
    end

end)


UIDropDownMenu_SetWidth(fontDrop, appearanceCard:GetWidth() - 48)







	


controlsCard = CreateRightSection(COLUMN_WIDTH)
controlsCard:SetHeight(160)
controlsCard:SetWidth(COLUMN_WIDTH)

controlsCard._height = 12
controlsCard._last = nil
controlsCard._minHeight = 120


------------------------------------------------
-- RESET LAYOUT BUTTON (RIGHT COLUMN)
------------------------------------------------

-- RESET LAYOUT BUTTON
reset = CreateFrame("Button", nil, controlsCard, "UIPanelButtonTemplate")

reset:SetSize(COLUMN_WIDTH - 20, 24)   -- ✅ explicit width
reset:SetText("Reset Layout")



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


-- Center Bars
local center = CreateFrame("CheckButton", nil, controlsCard, "InterfaceOptionsCheckButtonTemplate")
NormalizeCheckButton(center)
center.Text:SetText("Center Bars")
center:SetChecked(RaidCooldownsDB.settings.centerBars)
center:SetScript("OnClick", function(self)
    RaidCooldownsDB.settings.centerBars = self:GetChecked()
    UpdateLayout()
end)

-- Lock Panel
local lock = CreateFrame("CheckButton", nil, controlsCard, "InterfaceOptionsCheckButtonTemplate")
NormalizeCheckButton(lock)
lock.Text:SetText("Lock Panel")
lock:SetChecked(RC.locked)
lock:SetScript("OnClick", function(self)
    RC.locked = self:GetChecked()
    UpdatePanelMouseState()
    UpdatePanelBackground()
    UpdateBarMouseState()
end)



------------------------------------------------
-- 🧪 TEST MODE BUTTON
------------------------------------------------
local testBtn = CreateFrame("CheckButton", nil, controlsCard, "InterfaceOptionsCheckButtonTemplate")
NormalizeCheckButton(testBtn)
testBtn.Text:SetText("Test Mode")
testBtn.Text:SetFontObject("GameFontNormal")
testBtn.Text:SetTextColor(1, 1, 1)
testBtn:SetChecked(RC.testMode)

testBtn:SetScript("OnClick", function(self)
    local wantTest = self:GetChecked()

    if wantTest then
        RC.testMode = true

        -- Build spell metadata if needed
        if not RC.spells or next(RC.spells) == nil then
            CreateGroups()
        end

        -- Build test entries (one per spell)
        wipe(RC.entries)
        local playerName = UnitName("player") or "Player"
        local realm = GetNormalizedRealmName()
        if realm and realm ~= "" then
            playerName = playerName .. "-" .. realm
        end

        for spellID, data in pairs(RC.spells) do
            table.insert(RC.entries, {
                spellID = spellID,
                name = data.name,
                class = data.class,
                owner = playerName,          -- or "Test"
                onCooldown = false,
                cooldownStart = nil,
                cooldownDuration = nil,
                cooldownEnd = nil,
                bar = RC.barPool[playerName .. "#" .. spellID], -- reuse if exists
            })
        end

        PreCreateAllBars()
        RebuildOrderedList()

        -- Preview list = ordered list
        RC.previewOrdered = {}
        for _, entry in ipairs(RC.ordered or {}) do
            table.insert(RC.previewOrdered, entry)
        end

    else
        RC.testMode = false
        RC.previewOrdered = nil

        -- Return to real entries
        UpdateOwners()
        PreCreateAllBars()
        RebuildOrderedList()
    end

    UpdateBarMouseState()
    UpdateLayout()
end)


controlsCard:Add(reset, 18)
controlsCard:Add(center, 14)
controlsCard:Add(lock, 14)
controlsCard:Add(testBtn, 14)





panelSizeCard = CreateRightSection(COLUMN_WIDTH)
panelSizeCard:SetWidth(COLUMN_WIDTH)
panelSizeCard._fixed = true
panelSizeCard:SetHeight(150)


------------------------------------------------
-- PANEL WIDTH
------------------------------------------------
panelWidth = CreateFrame("Slider", nil, panelSizeCard, "OptionsSliderTemplate")
panelWidth:SetMinMaxValues(240, 900)
panelWidth:SetValueStep(10)
panelWidth:SetValue(RaidCooldownsDB.layout.width or 360)
panelWidth.Text:SetText("Panel Width")
panelWidth.Low:SetText("240")
panelWidth.High:SetText("900")
AddSliderValueText(panelWidth)

panelWidth:SetScript("OnValueChanged", function(self, value)
    value = math.floor(tonumber(value) or 360)

    RaidCooldownsDB = RaidCooldownsDB or {}
    RaidCooldownsDB.layout = RaidCooldownsDB.layout or {}
    RaidCooldownsDB.layout.width = value

    if panel then
        panel:SetWidth(value)
    end

    self:UpdateValueText(value)
    UpdateLayout()
end)




------------------------------------------------
-- PANEL HEIGHT
------------------------------------------------
panelHeight = CreateFrame("Slider", nil, panelSizeCard, "OptionsSliderTemplate")
panelHeight:SetMinMaxValues(100, 700)
panelHeight:SetValueStep(10)
panelHeight:SetValue(RaidCooldownsDB.layout.height or 300)
panelHeight.Text:SetText("Panel Height")
panelHeight.Low:SetText("150")
panelHeight.High:SetText("700")
AddSliderValueText(panelHeight)

-- Extra spacing for Panel Size sliders only
if panelWidth.Text then
    panelWidth.Text:ClearAllPoints()
    panelWidth.Text:SetPoint("BOTTOM", panelWidth, "TOP", 0, 10) -- was 6
end

if panelHeight.Text then
    panelHeight.Text:ClearAllPoints()
    panelHeight.Text:SetPoint("BOTTOM", panelHeight, "TOP", 0, 10)
end


panelHeight:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value)
    RaidCooldownsDB.layout.height = value
    panel:SetHeight(value)
    self:UpdateValueText(value)
    UpdateLayout()
end)



local panelSizeSliders = {
    panelWidth,
    panelHeight,
}



DistributeSlidersEvenly(panelSizeCard, panelSizeSliders)
for _, s in ipairs(panelSizeSliders) do
    s:SetPoint("LEFT", panelSizeCard, "LEFT", 16, 0)
    s:SetPoint("RIGHT", panelSizeCard, "RIGHT", -16, 0)
end



-- Bar Style
local styleTitle, styleSep =
    CreateSection(rightColumn, "Bar Style", COLUMN_WIDTH)

RightColumnStack:Add(styleTitle)
RightColumnStack:Add(styleSep, -6)
RightColumnStack:Add(appearanceCard, -8)


-- General
local generalTitle, generalSep =
    CreateSection(rightColumn, "General", COLUMN_WIDTH)

RightColumnStack:Add(generalTitle)
RightColumnStack:Add(generalSep, -6)
RightColumnStack:Add(controlsCard, -8)






-- Panel Size
local sizeTitle, sizeSep =
    CreateSection(rightColumn, "Panel Size", COLUMN_WIDTH)

RightColumnStack:Add(sizeTitle)
RightColumnStack:Add(sizeSep, -6)
RightColumnStack:Add(panelSizeCard, -8)

end


------------------------------------------------
-- PROFILE DROPDOWN
------------------------------------------------
function InitializeProfileDropDown(self, level)

    if level ~= 1 then return end

    local current = GetCurrentProfileName()

    for name in pairs(RaidCooldownsDB.profiles) do

        local info = UIDropDownMenu_CreateInfo()

        info.text = name
        info.value = name
        info.checked = (name == current)

        info.func = function(btn)

            CloseDropDownMenus()

            SwitchToProfile(btn.value)

            UIDropDownMenu_SetSelectedValue(profileDrop, btn.value)
            UIDropDownMenu_SetText(profileDrop, btn.value)

        end

        UIDropDownMenu_AddButton(info, level)
    end
end

------------------------------------------------
-- UPDATE PROFILE STATUS TEXT
------------------------------------------------
UpdateProfileStatusText = function()

    if not profileStatusText then return end

    local specIndex = GetSpecialization()
    if not specIndex then
        profileStatusText:SetText("")
        return
    end

    local specID = GetSpecializationInfo(specIndex)
    local role = GetSpecializationRole(specIndex)
    local charKey = GetCharKey()

    local current = RaidCooldownsDB.char[charKey]
    local specProfile = RaidCooldownsDB.specProfiles[specID]
    local roleProfile = RaidCooldownsDB.roleProfiles[role]

    if specProfile and specProfile == current then
        profileStatusText:SetText("|cff00ff00Using: Spec Override|r")
    elseif roleProfile and roleProfile == current then
        profileStatusText:SetText("|cffffff00Using: Role Fallback (" .. role .. ")|r")
    else
        profileStatusText:SetText("|cffaaaaaaUsing: Manual Selection|r")
    end
end

------------------------------------------------
-- REFRESH PROFILE UI 
------------------------------------------------
local function RefreshProfileUI()

    -- Refresh active profile dropdown
    if profileDrop then
        UIDropDownMenu_Initialize(profileDrop, InitializeProfileDropDown)
        UIDropDownMenu_SetText(profileDrop, GetCurrentProfileName())
    end

    -- Rebuild spec UI colors / labels
    if BuildSpecProfileUI then
UpdateSpecButtonStates()
    end

    -- Refresh role dropdown text
    if healerDrop then
        UIDropDownMenu_SetText(healerDrop, RaidCooldownsDB.roleProfiles["HEALER"] or "None")
    end

    if dpsDrop then
        UIDropDownMenu_SetText(dpsDrop, RaidCooldownsDB.roleProfiles["DAMAGER"] or "None")
    end

    if tankDrop then
        UIDropDownMenu_SetText(tankDrop, RaidCooldownsDB.roleProfiles["TANK"] or "None")
    end

    UpdateProfileStatusText()
end


------------------------------------------------
-- SHOW COLOR PICKER 
------------------------------------------------
local function ShowColorPickerCompat(r, g, b, a, onChanged, onCancel)
    a = a or 1

    -- Modern API (Retail)
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            hasOpacity = true,
            opacity = 1 - a,
            swatchFunc = onChanged,
            opacityFunc = onChanged,
            cancelFunc = onCancel,
        })
        return
    end

    -- Legacy fallback
    if not ColorPickerFrame then return end

    ColorPickerFrame.hasOpacity = true
    ColorPickerFrame.opacity = 1 - a
    ColorPickerFrame.previousValues = { r=r, g=g, b=b, a=a }

    ColorPickerFrame.func = onChanged
    ColorPickerFrame.opacityFunc = onChanged
    ColorPickerFrame.cancelFunc = onCancel

    if ColorPickerFrame.SetColorRGB then
        ColorPickerFrame:SetColorRGB(r, g, b)
    elseif ColorPickerFrame_SetColorRGB then
        ColorPickerFrame_SetColorRGB(r, g, b)
    end

    ColorPickerFrame:Show()
end


------------------------------------------------
-- COPY POPUP 
------------------------------------------------
-- One-time URL copy popup
StaticPopupDialogs["RAIDCOOLDOWNS_COPY_URL"] = {
  text = "Copy this link:",
  button1 = OKAY,
  hasEditBox = true,
  editBoxWidth = 360,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,

  OnShow = function(self, data)
    local eb = self.editBox or self.EditBox or self:GetEditBox()
    if not eb then return end
    eb:SetText(data or "")
    eb:HighlightText()
    eb:SetFocus()
  end,

  EditBoxOnEscapePressed = function(self)
    self:GetParent():Hide()
  end,
}


------------------------------------------------
-- SAFE UI INIT FUNCTION
------------------------------------------------
InitUI = function()

    if InCombatLockdown() then
        C_Timer.After(0.5, InitUI)
        return
    end

    if RC.uiInitialized then
        return
    end

    RC.uiInitialized = true


	
------------------------------------------------
-- CREATE OPTIONS WINDOW SAFELY
------------------------------------------------
options = CreateFrame("Frame", "RaidCooldownsOptionsWindow", UIParent, "BackdropTemplate")

options:HookScript("OnShow", function()
    UpdateBarMouseState()
end)

options:HookScript("OnHide", function()
    UpdateBarMouseState()
end)

options:SetFrameStrata("DIALOG")
options:SetFrameLevel(100)

options:SetResizable(false)

local WINDOW_WIDTH =
    12 +
    150 +
    16 +
    (COLUMN_WIDTH * 2) +
    35

options:SetSize(WINDOW_WIDTH, 700)

options:SetPoint("CENTER")



options:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})

options:SetBackdropColor(0,0,0,0.9)

options:SetClampedToScreen(true)

table.insert(UISpecialFrames, "RaidCooldownsOptionsWindow")

options:Hide()

options:SetMovable(true)
options:EnableMouse(true)
options:RegisterForDrag("LeftButton")

options:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

options:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()

    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()

RaidCooldownsDB.optionsPosition = {
        point = point,
        relativePoint = relativePoint,
        x = xOfs,
        y = yOfs,
    }
end)

-- 🔥 Restore saved position AFTER frame fully initializes
C_Timer.After(0, function()

    if RaidCooldownsDB and RaidCooldownsDB.optionsPosition then
        local pos = RaidCooldownsDB.optionsPosition

        options:ClearAllPoints()

        options:SetPoint(
            pos.point,
            UIParent,
            pos.relativePoint,
            pos.x,
            pos.y
        )
    end

end)




------------------------------------------------
-- CREATE CONTENT FRAME (SAFE)
------------------------------------------------
content = CreateFrame("Frame", nil, options)
content:SetPoint("TOPLEFT", options, "TOPLEFT", 12, -40)
content:SetPoint("BOTTOMRIGHT", options, "BOTTOMRIGHT", -12, 12)

Pages["Layout"] = CreateFrame("Frame", nil, content)
Pages["Layout"]:SetAllPoints()

Pages["Profiles"] = CreateFrame("Frame", nil, content)
Pages["Profiles"]:SetAllPoints()
Pages["Profiles"]:Hide()



Pages["Tracking"] = CreateFrame("Frame", nil, content)
Pages["Tracking"]:SetAllPoints()
Pages["Tracking"]:Hide()



Pages["About"] = CreateFrame("Frame", nil, content)
Pages["About"]:SetAllPoints()
Pages["About"]:Hide()







-- ------------------------------------------------
-- ABOUT PAGE (scroll + proper sizing)
-- ------------------------------------------------
local function BuildAboutPage()
    local page = Pages.About
    if not page then return end

    -- Allow rebuilding if a previous attempt errored or UI got recreated
    if page._built and page._aboutHtml and page._aboutScroll then
        return
    end

    -- Cleanup any partially-created widgets
    if page._aboutScroll then
        page._aboutScroll:Hide()
        page._aboutScroll:SetParent(nil)
    end
    page._aboutScroll = nil
    page._aboutHtml = nil
    page._built = nil
	
	
	

   -- No scroll frame needed; place HTML directly on the page
local scroll = nil
local child = page

    -- SimpleHTML
   local html = CreateFrame("SimpleHTML", nil, child)
html:SetPoint("TOPLEFT",  page, "TOPLEFT",  12, -12 - 24)  
html:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -12, 12)
-- Bigger fonts for About page
local AboutBodyFont = CreateFont("RaidCooldownsAboutBodyFont")
AboutBodyFont:SetFont("Fonts\\FRIZQT__.TTF", 15, "")  -- FIX: flags must be a string
AboutBodyFont:SetTextColor(1, 1, 1)

local AboutH1Font = CreateFont("RaidCooldownsAboutH1Font")
AboutH1Font:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")

local AboutH2Font = CreateFont("RaidCooldownsAboutH2Font")
AboutH2Font:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")

    html:SetFontObject("h1", AboutH1Font)
    html:SetFontObject("h2", AboutH2Font)
    html:SetFontObject("p",  AboutBodyFont)
    html:SetJustifyH("p", "LEFT")
    html:SetJustifyV("p", "TOP")
    html:SetSpacing("p", 7)

    -- Hyperlink popup (WoW cannot open external URLs)
    html:SetHyperlinksEnabled(true)
    html:SetScript("OnHyperlinkClick", function(_, link)
        local url = link:match("^url:(.+)$")
        if url then
            StaticPopup_Show("RAIDCOOLDOWNS_COPY_URL", nil, nil, url)
        end
    end)

    -- Simple, safe markup (no weird bullets, valid tags)
    local aboutHTML =
        "<html><body>" ..
        "<h1></h1>" ..
        "<p>RaidCooldowns is a lightweight raid utility that tracks</p>" ..
		"<p>major defensive and utility cooldowns for your group  </p>" .. 
		"<p>or raid in a clean, easy-to-read bar list.</p>" ..
		"<p></p>" ..
		"<h2>How to use</h2>" ..
        "<p></p>" ..
		  "<p></p>" ..
		"<p>- Join a party or raid and the addon will build a list</p>" ..
		"<p>of tracked abilities for your group.<br/>" ..
        "- When someone uses a tracked cooldown,</p>" .. 
		"<p>their bar switches from READY to a countdown timer.<br/>" ..
        "- Drag bars to reorder them to your preferred priority.<br/>" ..
        "- Customize layout, text, and colors in the Options panel.</p>" ..
    "<p></p>" ..
"<p></p>" ..
	"<p>Created by Valszone<br/>" ..
' <a href="url:https://twitch.tv/valszone">|cff3399fftwitch.tv/valszone|r</a></p>' ..
        "</body></html>"

    html:SetText(aboutHTML)

    -- Keep references so we can detect a successful build
   page._aboutScroll = nil
page._aboutHtml = html
page._built = true

   
end


------------------------------------------------
-- CREATE SIDEBAR (SAFE)
------------------------------------------------
local sidebar = CreateFrame("Frame", nil, content, "BackdropTemplate")
sidebar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
sidebar:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
sidebar:SetWidth(150)

-- Constrain pages to the area to the right of the sidebar
local function AnchorPagesToContentArea()
    for _, p in pairs(Pages) do
        if p and p.ClearAllPoints then
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 12, 0)
            p:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -12, 0)
        end
    end
end

AnchorPagesToContentArea()


sidebar:SetBackdrop({
    bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize=12,
    insets={left=3,right=3,top=3,bottom=3}
})

sidebar:SetBackdropColor(0.08,0.08,0.09,0.8)

------------------------------------------------
-- SIDEBAR TITLE
------------------------------------------------
local sbTitle = sidebar:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
sbTitle:SetPoint("TOP",0,-12)
sbTitle:SetText("RaidCooldowns")

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

local btnLayout   = CreateSidebarButton("Layout", sbTitle)
local btnProfiles = CreateSidebarButton("Profiles", btnLayout)
local btnTracking = CreateSidebarButton("Tracking", btnProfiles)
local btnAbout    = CreateSidebarButton("About", btnTracking)

btnLayout:SetScript("OnClick", function() ShowPage("Layout") end)
btnProfiles:SetScript("OnClick", function() ShowPage("Profiles") end)
btnTracking:SetScript("OnClick", function() ShowPage("Tracking") end)
btnAbout:SetScript("OnClick", function() ShowPage("About") end)

if pageName == "About" then
    BuildAboutPage()
end

  
	if not RC.layoutBuilt then
    BuildLayoutPage()
    BuildLayoutSliders()
    RC.layoutBuilt = true
end




-- Profiles page columns
profilesCenterWrap = CreateFrame("Frame", nil, Pages["Profiles"])
profilesCenterWrap:SetPoint("TOPLEFT", content, "TOPLEFT", 150 + 16, 20)
profilesCenterWrap:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 150 + 16, 0)
profilesCenterWrap:SetWidth((COLUMN_WIDTH * 2) + COLUMN_GAP)
AddPageLogo(profilesCenterWrap)


profilesLeftColumn = CreateFrame("Frame", nil, profilesCenterWrap)
profilesLeftColumn:SetPoint("TOPLEFT", profilesCenterWrap, "TOPLEFT", 0, 0)
profilesLeftColumn:SetWidth(COLUMN_WIDTH)


	

local activeProfileTitle, activeProfileSep =
    CreateSection(profilesLeftColumn, "Active Profile", COLUMN_WIDTH)
	
local roleTitle, roleSep =
    CreateSection(profilesLeftColumn, "Role Profiles", COLUMN_WIDTH)




profilesRightColumn = CreateFrame("Frame", nil, profilesCenterWrap)
profilesRightColumn:SetPoint("TOPLEFT", profilesLeftColumn, "TOPRIGHT", COLUMN_GAP, 0)
profilesRightColumn:SetWidth(COLUMN_WIDTH)








ProfilesLeftStack = CreateStack(
    profilesLeftColumn,
    profilesLeftColumn,
    0,
    STACK_START_Y,
    STACK_ROW_SPACING
)

ProfilesRightStack = CreateStack(
    profilesRightColumn,
    profilesRightColumn,
    0,
    STACK_START_Y,
    STACK_ROW_SPACING
)



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
   

    bar.icon:SetSize(RaidCooldownsDB.settings.barHeight, RaidCooldownsDB.settings.barHeight)
    bar.icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)

    bar.label:SetPoint("LEFT", bar.icon, "RIGHT", 6, 0)



  




    else -- ICON_BAR
        bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

        bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", ICON_GAP, 0)
        bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 0)

local sx = RaidCooldownsDB.settings.spellTextOffsetX or 0
local sy = RaidCooldownsDB.settings.spellTextOffsetY or 0

bar.label:SetPoint("LEFT", bar.fill, "LEFT", 4 + sx, sy)


    end
end

ApplyTemplateToAllBars = function()
    local template = RaidCooldownsDB.settings.template
   for _, entry in ipairs(RC.ordered or {}) do
    if entry.bar then
        ApplyTemplate(entry.bar, template)
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
-- UPDATE DRAGGED BAR POSITION
------------------------------------------------
local function UpdateDraggedBarPosition()
    if not RC.dragging then return end

    local cx, cy = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    if not uiScale or uiScale == 0 then return end
    cx, cy = cx / uiScale, cy / uiScale

    RC.dragging:ClearAllPoints()
    RC.dragging:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
end

------------------------------------------------
-- DRAG FOLLOW CURSOR 
------------------------------------------------
local function DragFollowCursor_OnUpdate(self)
    local cx, cy = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    if not uiScale or uiScale == 0 then return end
    cx, cy = cx / uiScale, cy / uiScale

    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
end

------------------------------------------------
-- COOLDOWN BAR UPDATE (DRAG SAFE)
------------------------------------------------
local function CooldownOnUpdate(self, elapsed)
    local now = GetTime()

    for _, entry in ipairs(GetVisibleOrdered()) do
        local bar = entry.bar

        if bar and bar:IsShown() and bar.cdText then
            if entry.onCooldown then
                local remaining = (entry.cooldownEnd or 0) - now

                if remaining <= 0 then
                    entry.onCooldown = false
                    bar.fill:SetValue(1)
                    bar.cdText:SetText("READY")
                    bar.cdText:SetTextColor(0, 1, 0)
                else
                    bar.fill:SetValue(remaining / (entry.cooldownDuration or 1))
                    bar.cdText:SetText(FormatTime(remaining))
                    bar.cdText:SetTextColor(1, 1, 1)
                end
            else
                bar.fill:SetValue(1)
                bar.cdText:SetText("READY")
                bar.cdText:SetTextColor(0, 1, 0)
            end

            bar.cdText:Show()
        end
    end
end

panel:SetScript("OnUpdate", function(self, elapsed)
    if RC.dragging then
        UpdateDragPreview()         -- compute targets / may relayout
          end
    CooldownOnUpdate(self, elapsed)
end)




------------------------------------------------
-- SHOW COLUMN MENU
------------------------------------------------

local function ShowColumnMenu(group, anchor)
    -- 🔒 SAFETY: ensure column always exists
    if type(group.column) ~= "number" then
        group.column = 1
local storage = GetTemplateStorage()
storage.columns[group.spellID] = 1

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
local storage = GetTemplateStorage()
storage.columns[group.spellID] = 1

                UpdateLayout()
            end,
        },
        {
            text = "Column 2",
            checked = (group.column == 2),
            func = function()
                group.column = 2
                local storage = GetTemplateStorage()
storage.columns[group.spellID] = 2

                UpdateLayout()
            end,
        },
        {
            text = "Column 3",
            checked = (group.column == 3),
            func = function()
                group.column = 3
local storage = GetTemplateStorage()
storage.columns[group.spellID] = 3

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
local function GetColumnFromX(relativeX)
    local s = RaidCooldownsDB.settings
    local colGap = 24
    local leftPadding = 16
    local rightPadding = 16
    local barWidth = s.barWidth or 180

    -- ✅ dynamic column count (same logic as COLUMN_LIST)
    local wantedCols = tonumber(RaidCooldownsDB.settings.columns) or 3
    local usableWidth = panel:GetWidth() - leftPadding - rightPadding
    local fitCols = math.floor((usableWidth + colGap) / (barWidth + colGap))
    if fitCols < 1 then fitCols = 1 end
    local maxCols = math.min(wantedCols, fitCols)

    local totalWidth  = (maxCols * barWidth) + ((maxCols - 1) * colGap)

    -- center only if it fits; otherwise start at left padding
    local startX = leftPadding
    if totalWidth < usableWidth then
        startX = leftPadding + (usableWidth - totalWidth) / 2
    end

    -- clamp outside the whole column region
    if relativeX <= startX then
        return 1
    end
    if relativeX >= (startX + totalWidth) then
        return maxCols
    end

    -- pick the nearest column center (works even in the gaps)
    local bestCol, bestDist = 1, math.huge
    for col = 1, maxCols do
        local colStart = startX + (col - 1) * (barWidth + colGap)
        local centerX  = colStart + (barWidth * 0.5)
        local d = math.abs(relativeX - centerX)
        if d < bestDist then
            bestDist = d
            bestCol  = col
        end
    end

    return bestCol
end





------------------------------------------------
-- GET DISPLAY SPELL NAME
------------------------------------------------
local function GetDisplaySpellName(spellID, fallbackName)

    -- Always ensure fallback exists
    if not fallbackName then
        return "Unknown Spell"
    end

    -- If toggle disabled, return full name
    if not RaidCooldownsDB.settings.shortSpellNames then
        return fallbackName
    end

    -- Return short if exists, otherwise full
    local short = SHORT_SPELL_NAMES[spellID]
    if short then
        return short
    end

    return fallbackName
end




------------------------------------------------
-- IS SPELL TRACKED (PROFILE SAFE / DIRECT)
------------------------------------------------
function IsSpellTracked(spellID)
    local t = RaidCooldownsDB.trackedSpells
    if not t then
        return true -- default: tracked
    end
    return t[spellID] ~= false -- nil/true => tracked, false => untracked
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
-- STRIP REALM
------------------------------------------------
local function StripRealm(fullName)
    if not fullName then return "" end
    return fullName:match("^[^-]+") or fullName
end

------------------------------------------------
-- BUILD BAR LABEL TEXT
------------------------------------------------
local function GetBarLabelText(entry)
    local toon = StripRealm(entry.owner)
    return toon .. " - " .. GetDisplaySpellName(entry.spellID, entry.name)
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
-- UPDATE GROUP COOLDOWN (RETAIL SAFE / NO TAINT)
------------------------------------------------
function UpdateGroupCooldown(group)

    if not group or not group.spellID then
        return
    end

    if group.onCooldown then
        return
    end

    local spellData = HEALING_COOLDOWNS[group.spellID]
    if not spellData then
        return
    end

    local start = GetTime()
    local duration = spellData.cooldown

    if not duration or duration <= 0 then
        return
    end

    group.cooldownStart    = start
    group.cooldownDuration = duration
    group.cooldownEnd      = start + duration
    group.onCooldown       = true
end




------------------------------------------------
-- PLAYER HAS ACTION BAR SPELL (MIDNIGHT SAFE)
------------------------------------------------
local function PlayerHasActionBarSpell(spellID)
    local buttons = C_ActionBar.FindSpellActionButtons(spellID)
    return buttons and #buttons > 0
end



------------------------------------------------
-- UPDATE PANEL BACKGROUND
------------------------------------------------
function UpdatePanelBackground()
    if RC.locked then
        panel:SetBackdropColor(0, 0, 0, 0)
    else
        panel:SetBackdropColor(0, 0, 0, 0.6)
    end
end


------------------------------------------------
-- UPDATE PANEL MOUSE STATE
------------------------------------------------
function UpdatePanelMouseState()
    panel:EnableMouse(not RC.locked)
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
-- UPDATE DRAG PREVIEW
------------------------------------------------
function UpdateDragPreview()
    if not RC.dragging then return end
    if not RC.testMode then return end

    local s = RaidCooldownsDB.settings or {}
    local rowSize = (s.barHeight or 18) + (s.barSpacing or 6)

 -- ✅ Cursor in pixels -> UI units using UIParent scale (CORRECT SPACE)
local cx, cy = GetCursorPosition()
local uiScale = UIParent:GetEffectiveScale()
if not uiScale or uiScale == 0 then return end
cx, cy = cx / uiScale, cy / uiScale

-- ✅ Panel rect in the SAME UI space
local pLeft = panel:GetLeft()
local pTop  = panel:GetTop()
if not pLeft or not pTop then return end

local panelW = panel:GetWidth() or 0
local panelH = panel:GetHeight() or 0
if panelW <= 0 or panelH <= 0 then return end

-- Cursor position relative to panel
local relX = cx - pLeft
local relYFromTop = pTop - cy   -- 0 at top, increases downward

-- clamp inside panel
if relX < 0 then relX = 0 end
if relX > panelW then relX = panelW end
if relYFromTop < 0 then relYFromTop = 0 end
if relYFromTop > panelH then relYFromTop = panelH end

  

    local template = RaidCooldownsDB.settings.template

    ------------------------------------------------------------
    -- COLUMN_LIST (layout uses paddingTop = -16)
    ------------------------------------------------------------
    if template == "COLUMN_LIST" then
        local maxCols = tonumber(RaidCooldownsDB.settings.columns) or 3
local targetCol = GetColumnFromX(relX) or 1
if targetCol < 1 or targetCol > maxCols then targetCol = 1 end

-- count visible per column excluding dragged
local counts = {}
for c=1,maxCols do counts[c]=0 end
for _, e in ipairs(GetVisibleOrdered() or {}) do
    if e.bar and e.bar ~= RC.dragging then
        local c = tonumber(e.column) or 1
        if c < 1 or c > maxCols then c = 1 end
        counts[c] = counts[c] + 1
    end
end

-- ✅ list area padding (matches layout's paddingTop=-16)
local listTopPad    = 16
local listBottomPad = 16

-- map cursor Y into list region
local listY = relYFromTop - listTopPad
local listMax = (panelH - listTopPad - listBottomPad)
if listMax < 1 then listMax = 1 end

-- clamp into list region (prevents snap-to-extremes when cursor leaves panel slightly)
if listY < 0 then listY = 0 end
if listY > listMax then listY = listMax end

-- compute row (no "+0.5 rowSize" needed; it causes jumpiness near borders)
local row = math.floor(listY / rowSize) + 1

local maxRow = (counts[targetCol] or 0) + 1
if row < 1 then row = 1 end
if row > maxRow then row = maxRow end

RC.dragTargetColumn = targetCol
RC.dragTargetRow    = row
RC.dragTargetIndex  = nil

local key = "C:" .. targetCol .. ":" .. row
if RC._lastDragKey ~= key then
    RC._lastDragKey = key
    UpdateLayout()
end
return

end

    ------------------------------------------------------------
    -- NORMAL LIST (layout uses STACK_TOP_OFFSET)
    ------------------------------------------------------------
    local list = GetVisibleOrdered() or {}
    if #list == 0 then return end

    local topOffset = STACK_TOP_OFFSET or 14
    local idx = math.floor(((relYFromTop - topOffset) + (rowSize * 0.5)) / rowSize) + 1

    if idx < 1 then idx = 1 end
    if idx > (#list + 1) then idx = (#list + 1) end

    RC.dragTargetIndex  = idx
    RC.dragTargetColumn = nil
    RC.dragTargetRow    = nil

    local key = "I:" .. idx
    if RC._lastDragKey ~= key then
        RC._lastDragKey = key
        UpdateLayout()
    end
end

------------------------------------------------
-- PRECREATE BARS (ENTRY-BASED ONLY)
------------------------------------------------
PreCreateAllBars = function()
    if not RC.entries then return end

    for _, entry in ipairs(RC.entries) do

        -- ✅ if we already have a bar, re-bind it to this entry (prevents "combined bars")
        if entry.bar then
            entry.bar._rcEntry = entry
            entry.bar._rcKey   = entry.owner .. "#" .. entry.spellID
        end

        -- ✅ create a new bar if missing
        if not entry.bar then
            local bar = CreateFrame("Frame", nil, panel)
            bar:SetParent(panel)
            bar:SetFrameStrata("MEDIUM")
            bar:SetFrameLevel(panel:GetFrameLevel() + 5)

            bar:SetMovable(true)
            bar:EnableMouse(false)            -- default: click-through
            bar:RegisterForDrag("LeftButton")

            bar:SetScript("OnDragStart", function(self)
                if RC.locked then return end
                if not RC.testMode then return end

                RC.dragging = self
                RC.draggingEntry = self._rcEntry
                RC.dragStarted = true

                self:StopMovingOrSizing()
                self:ClearAllPoints()
                self:SetParent(UIParent)
                self:SetFrameStrata("DIALOG")
                self:SetFrameLevel(500)

                self:SetClampedToScreen(false)

                self:SetScript("OnUpdate", DragFollowCursor_OnUpdate)
                DragFollowCursor_OnUpdate(self)
            end)

            bar:SetScript("OnDragStop", function(self)
                if not RC.dragStarted then return end
                RC.dragStarted = false

                self:SetScript("OnUpdate", nil)

                self:SetParent(panel)
                self:SetFrameStrata("MEDIUM")
                self:SetFrameLevel(panel:GetFrameLevel() + 5)

                HandleBarDrop(self)
            end)

            -- ICON
            bar.icon = bar:CreateTexture(nil, "OVERLAY")
            bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            bar.icon:SetTexture(C_Spell.GetSpellTexture(entry.spellID))

            -- FILL
            bar.fill = CreateFrame("StatusBar", nil, bar)
            bar.fill:SetFrameLevel(bar:GetFrameLevel())
            bar.fill:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
            bar.fill:SetMinMaxValues(0, 1)
            bar.fill:SetValue(1)

            -- TEXT
            local font = RaidCooldownsDB.settings.font or "Fonts\\FRIZQT__.TTF"

            bar.label = bar:CreateFontString(nil, "OVERLAY")
            bar.label:SetDrawLayer("OVERLAY", 7)
            bar.label:SetFont(font, RaidCooldownsDB.settings.spellTextSize or 12, "OUTLINE")
            bar.label:SetTextColor(1, 1, 1)
            bar.label:SetJustifyH("LEFT")
            bar.label:SetJustifyV("MIDDLE")

            bar.cdText = bar:CreateFontString(nil, "OVERLAY")
            bar.cdText:SetFont(font, RaidCooldownsDB.settings.cdTextSize or 12, "OUTLINE")
            bar.cdText:SetTextColor(1, 1, 1)
            bar.cdText:SetDrawLayer("OVERLAY", 8)

            -- bind
            entry.bar = bar
            bar._rcEntry = entry
            bar._rcKey   = entry.owner .. "#" .. entry.spellID
        end
    end
end

------------------------------------------------
-- GET VISIBLE ORDERED LIST
------------------------------------------------
function GetVisibleOrdered()

    if RC.testMode then
        if RC.previewOrdered and #RC.previewOrdered > 0 then
            return RC.previewOrdered
        end
        return RC.ordered or {}
    end

    return RC.ordered or {}
end



------------------------------------------------
-- NormalizeColumnOrders (FIXED / STORAGE SAFE)
------------------------------------------------
function NormalizeColumnOrders()

    -- Only for column mode
    if RaidCooldownsDB.settings.template ~= "COLUMN_LIST" then
        return
    end

    if RC.dragging then return end

    local storage = GetTemplateStorage()

    local cols = {
        [1] = {},
        [2] = {},
        [3] = {},
    }

    ------------------------------------------------
    -- Build columns from ordered list
    ------------------------------------------------
    for _, g in ipairs(RC.ordered or {}) do
        local col = g.column or 1
        table.insert(cols[col], g)
    end

    ------------------------------------------------
    -- Sort each column using STORAGE order
    ------------------------------------------------
    for col = 1, 3 do

        table.sort(cols[col], function(a, b)
            return (storage.order[a.spellID] or 9999)
                 < (storage.order[b.spellID] or 9999)
        end)

        ------------------------------------------------
        -- Reassign normalized order
        ------------------------------------------------
        for index, g in ipairs(cols[col]) do
            storage.order[g.spellID] = index
            storage.columns[g.spellID] = col
        end
    end
end


------------------------------------------------
-- HANDLE BAR DROP (TEMPLATE ISOLATED / CLEAN)
------------------------------------------------
function HandleBarDrop(bar)
    if InCombatLockdown() then return end
    if not RC.dragging then return end
	
	-- stop cursor follow + restore bar back to panel
bar:SetScript("OnUpdate", nil)
bar:SetParent(panel)
bar:SetFrameStrata("MEDIUM")
bar:SetFrameLevel(panel:GetFrameLevel() + 5)
bar:StopMovingOrSizing()
bar:Show()

    RC.dragStarted = false

    local storage  = GetTemplateStorage()
    local template = RaidCooldownsDB.settings.template

    -- capture targets BEFORE clearing state
    local targetIndex = RC.dragTargetIndex
    local targetCol   = RC.dragTargetColumn
    local targetRow   = RC.dragTargetRow

    -- find dragged entry
    local draggedEntry
    for _, e in ipairs(RC.entries or {}) do
        if e.bar == bar then
            draggedEntry = e
            break
        end
    end
    if not draggedEntry then
        RC.dragging = nil
        return
    end

    ------------------------------------------------
    -- COLUMN_LIST DROP (fix row shift bug)
    ------------------------------------------------
    if template == "COLUMN_LIST" then
        targetCol = tonumber(targetCol) or (draggedEntry.column or 1)
        if targetCol < 1 or targetCol > MAX_COLUMNS then targetCol = 1 end

        targetRow = tonumber(targetRow) or 1
        if targetRow < 1 then targetRow = 1 end

        -- build columns from current visible order
        local cols = {}
        for c = 1, MAX_COLUMNS do cols[c] = {} end

        -- also record the dragged entry's current (col,row)
        local fromCol, fromRow = nil, nil

        for _, e in ipairs(GetVisibleOrdered() or {}) do
            local c = tonumber(e.column) or 1
            if c < 1 or c > MAX_COLUMNS then c = 1 end
            table.insert(cols[c], e)
        end

        -- find current row of dragged within its column
        for c = 1, MAX_COLUMNS do
            for r, e in ipairs(cols[c]) do
                if e == draggedEntry then
                    fromCol, fromRow = c, r
                    break
                end
            end
            if fromCol then break end
        end

        -- remove dragged from its old column list
        if fromCol and fromRow then
            table.remove(cols[fromCol], fromRow)
        end

        -- ✅ if staying in same column and moving DOWN, target row shifts up by 1 after removal
        if fromCol == targetCol and fromRow and targetRow > fromRow then
            targetRow = targetRow - 1
        end

        -- clamp insert row (allow insert at end => #col + 1)
        local maxInsert = #cols[targetCol] + 1
        if targetRow > maxInsert then targetRow = maxInsert end

        -- insert dragged
        draggedEntry.column = targetCol
        table.insert(cols[targetCol], targetRow, draggedEntry)

        -- write storage
        storage.order   = storage.order   or {}
        storage.columns = storage.columns or {}

        for c = 1, MAX_COLUMNS do
            for r, e in ipairs(cols[c]) do
                storage.columns[e.spellID] = c
                storage.order[e.spellID]   = r
            end
        end

    ------------------------------------------------
    -- NON-COLUMN DROP (fix index shift bug)
    ------------------------------------------------
    else
        local list = GetVisibleOrdered() or {}
        if #list == 0 then
            RC.dragging = nil
            return
        end

        -- find current index
        local fromIndex
        for i, e in ipairs(list) do
            if e == draggedEntry then
                fromIndex = i
                break
            end
        end
        if not fromIndex then
            RC.dragging = nil
            return
        end

        targetIndex = tonumber(targetIndex) or fromIndex

        -- remove first
        table.remove(list, fromIndex)

        -- ✅ if moving DOWN, target index shifts up by 1 after removal
        if targetIndex > fromIndex then
            targetIndex = targetIndex - 1
        end

        -- clamp (allow drop at end)
        local maxInsert = #list + 1
        if targetIndex < 1 then targetIndex = 1 end
        if targetIndex > maxInsert then targetIndex = maxInsert end

        table.insert(list, targetIndex, draggedEntry)

        wipe(storage.order)
        for i, e in ipairs(list) do
            storage.order[e.spellID] = i
        end
    end

  -- clear drag state AFTER commit
RC.dragging = nil
RC.draggingEntry = nil
RC.previewOrdered = nil        
RC._lastDragKey = nil
RC.dragTargetIndex = nil
RC.dragTargetColumn = nil
RC.dragTargetRow = nil

RebuildOrderedList()
UpdateLayout()
end
local function ApplyConfiguredTextColors(bar)
    if not bar or not RaidCooldownsDB or not RaidCooldownsDB.settings then return end
    local s = RaidCooldownsDB.settings
    s.spellNameColor = s.spellNameColor or { r=1, g=1, b=1, a=1 }
    s.cdTextColor    = s.cdTextColor    or { r=1, g=0.82, b=0, a=1 }

    local n = s.spellNameColor
    if bar.label then
        bar.label:SetTextColor(n.r, n.g, n.b, n.a or 1)
    end

    if bar.cdText then
        local c = s.cdTextColor
        bar.cdText:SetTextColor(c.r, c.g, c.b, c.a or 1)
    end
end

------------------------------------------------
-- UPDATE DEATH VISUAL
------------------------------------------------
local function UpdateDeathVisual(entry)

    local bar = entry.bar
    if not bar then return end

    if entry.isDead then
        -- Grey out
        bar.fill:SetStatusBarColor(0.4, 0.4, 0.4)
        bar.icon:SetVertexColor(0.4, 0.4, 0.4)
        if bar.label then
            bar.label:SetTextColor(0.6, 0.6, 0.6)
        end
        if bar.cdText then
            bar.cdText:SetTextColor(0.6, 0.6, 0.6)
        end
    else
        -- Restore visuals
        ApplyClassColor(bar, entry.class)
        bar.icon:SetVertexColor(1, 1, 1)
        ApplyConfiguredTextColors(bar)
    end
end

-- RESETBARVISUALS (FINAL / CORRECT)
------------------------------------------------
local function ResetBarVisuals(bar, entry)

    local s = RaidCooldownsDB.settings
    if not s then return end

    ------------------------------------------------
    -- Visibility
    ------------------------------------------------
    bar:Show()
    bar.icon:Show()
    bar.fill:Show()
    bar.label:Show()

    if bar.cdText then
        bar.cdText:Show()
    end

    ------------------------------------------------
    -- Size
    ------------------------------------------------
    bar:SetSize(s.barWidth, s.barHeight)

    ------------------------------------------------
    -- Fonts
    ------------------------------------------------
    local font = s.font or "Fonts\\FRIZQT__.TTF"

    bar.label:SetFont(font, s.spellTextSize or 12, "OUTLINE")
    bar.label:SetText(GetBarLabelText(entry))

    if bar.cdText then
        bar.cdText:SetFont(font, s.cdTextSize or 12, "OUTLINE")
    end
	
	-- Ensure defaults exist even if DB wasn't initialized yet
RaidCooldownsDB.settings.spellNameColor = RaidCooldownsDB.settings.spellNameColor or { r=1, g=1, b=1, a=1 }
RaidCooldownsDB.settings.cdTextColor    = RaidCooldownsDB.settings.cdTextColor    or { r=1, g=0.82, b=0, a=1 }

local n = RaidCooldownsDB.settings.spellNameColor
bar.label:SetTextColor(n.r, n.g, n.b, n.a or 1)

local c = RaidCooldownsDB.settings.cdTextColor
bar.cdText:SetTextColor(c.r, c.g, c.b, c.a or 1)

    ------------------------------------------------
    -- POSITION SPELL NAME
    ------------------------------------------------
    local sx = s.spellTextOffsetX or 0
    local sy = s.spellTextOffsetY or 0

    bar.label:ClearAllPoints()
    bar.label:SetPoint("LEFT", bar, "LEFT", s.barHeight + 4 + sx, sy)

    ------------------------------------------------
    -- POSITION COOLDOWN TEXT
    ------------------------------------------------
    if bar.cdText then
        local cx = s.cdTextOffsetX or 0
        local cy = s.cdTextOffsetY or 0

        bar.cdText:ClearAllPoints()
        bar.cdText:SetPoint("RIGHT", bar, "RIGHT", -4 + cx, cy)
    end

    ------------------------------------------------
    -- Reset Cooldown Visuals
    ------------------------------------------------
    bar.fill:SetValue(1)

    if bar.cdText then
        bar.cdText:SetText("READY")
    end

    ------------------------------------------------
    -- Color
    ------------------------------------------------
    ApplyClassColor(bar, entry.class)
	
	UpdateDeathVisual(entry)

end



------------------------------------------------
-- IS WITHIN PANEL
------------------------------------------------
local function IsWithinPanelUniversal(yPos, barHeight, paddingTop, paddingBottom)
    -- yPos is relative to panel TOP (0 at top, negative downward)
  paddingTop = paddingTop or (STACK_TOP_OFFSET or 14)
    paddingBottom = paddingBottom or 16

    local bottomLimit = -panel:GetHeight() + barHeight + paddingBottom
    local topLimit    = -paddingTop

    -- ✅ Allow anything from topLimit (ex: -16) down to bottomLimit (ex: -266)
    return (yPos <= topLimit) and (yPos >= bottomLimit)
end

------------------------------------------------
-- LAYOUT HANDLERS (SINGLE SOURCE OF TRUTH)
------------------------------------------------
LayoutHandlers = LayoutHandlers or {}
-- 🧹 TEMP SAFETY STUBS (prevents ghost bars)




------------------------------------------------
-- ICON + BAR (CLEAN / STABLE)
------------------------------------------------
LayoutHandlers.ICON_BAR = function()
    HideAllBars()

    local s = RaidCooldownsDB.settings
    local rowSize = math.max(1, (s.barHeight or 18) + (s.barSpacing or 0))
    local list = GetVisibleOrdered()

    local target = RC.dragTargetIndex

   

    -- We'll place bars by slot index (1-based). This prevents overlap/reuse bugs.
    local slot = 0

    for i, entry in ipairs(list) do
        slot = slot + 1

        -- Insert a blank slot at the drag target index (visual gap)
        if target and slot == target then
            slot = slot + 1
        end

        -- IMPORTANT: Acquire bar by slot, not by entry.bar
     local bar = entry.bar

        -- (Optional) keep a reference for clicks/tooltips etc.
        bar.entry = entry
        entry.bar = bar

       

        if bar == RC.dragging then
            -- Don't anchor dragged bar; it stays with the mouse
            bar:Show()
        else
            ResetBarVisuals(bar, entry)
            bar:SetSize(s.barWidth, s.barHeight)

            local barY = -STACK_TOP_OFFSET - ((slot - 1) * rowSize)

           

if (not RC.dragging) and (not IsWithinPanelUniversal(barY, s.barHeight, STACK_TOP_OFFSET, 16)) then
                bar:Hide()
            else
                bar:ClearAllPoints()
                AnchorBarToPanelTop(bar, barY)

              

                bar:Show()
            end

            -- Icon
            bar.icon:SetSize(s.barHeight, s.barHeight)
            bar.icon:ClearAllPoints()
            bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

            -- Fill
            bar.fill:ClearAllPoints()
            bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", ICON_GAP, 0)
            bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 0)

            -- Label
            local sx = s.spellTextOffsetX or 0
            local sy = s.spellTextOffsetY or 0
            bar.label:ClearAllPoints()
            bar.label:SetPoint("LEFT", bar.fill, "LEFT", 4 + sx, sy)
            bar.label:SetJustifyH("LEFT")
            bar.label:SetJustifyV("MIDDLE")

            -- CD Text
            bar.cdText:SetJustifyH("RIGHT")
            bar.cdText:SetJustifyV("MIDDLE")
            bar.cdText:Show()

            bar.label:SetText(GetBarLabelText(entry))
        end
    end

    -- Hide any remaining bars in the pool above 'slot' (safety)
    if RC.barPool then
        for j = slot + 1, #RC.barPool do
            if RC.barPool[j] then
                RC.barPool[j]:Hide()
                RC.barPool[j].entry = nil
            end
        end
    end
end

------------------------------------------------
-- BAR ONLY
------------------------------------------------
LayoutHandlers.BAR_ONLY = function()
 HideAllBars()

    local s = RaidCooldownsDB.settings
 local rowSize = math.max(1, (s.barHeight or 18) + (s.barSpacing or 0))
 
   local list = GetVisibleOrdered()
  

    local target = RC.dragTargetIndex
    local slot = 0

for _, entry in ipairs(list) do
    local bar = entry.bar

    if bar then
        if bar == RC.dragging then
            bar:Show()
        else
            slot = slot + 1

            if target and slot == target then
                slot = slot + 1
            end

            local barY = -STACK_TOP_OFFSET - ((slot - 1) * rowSize)
			
			RC_Debug(("PLACE: slot=%d %s (%d) barY=%s"):format(
    slot, tostring(entry.name), tonumber(entry.spellID or -1), tostring(barY)
))

            if (not RC.dragging) and (not IsWithinPanelUniversal(barY, s.barHeight)) then
                bar:Hide()
            else
                ResetBarVisuals(bar, entry)
                bar:SetSize(s.barWidth, s.barHeight)

                bar:ClearAllPoints()
                AnchorBarToPanelTop(bar, barY)
				
				local p1, rel, p2, x, y = bar:GetPoint(1)
RC_Debug(("POINT: %s => %s %s x=%s y=%s"):format(tostring(entry.name), tostring(p1), tostring(p2), tostring(x), tostring(y)))


                bar:Show()

                bar.icon:Hide()
                bar.fill:SetAllPoints(bar)

                bar.label:ClearAllPoints()
                bar.label:SetPoint("CENTER", bar)

                ApplyClassColor(bar, entry.class)
                bar.label:SetText(GetBarLabelText(entry))

                bar.cdText:SetJustifyH("RIGHT")
                bar.cdText:SetJustifyV("MIDDLE")
                bar.cdText:Show()
            end
        end
    end
end

end

------------------------------------------------
-- ICON ONLY (ANCHOR SAFE)
------------------------------------------------
LayoutHandlers.ICON_ONLY = function()

    HideAllBars()

    local s = RaidCooldownsDB.settings
    local rowSize = s.barHeight + s.barSpacing
    local list = GetVisibleOrdered()

    local target = RC.dragTargetIndex
    local slot = 0

for _, entry in ipairs(list) do
    local bar = entry.bar

    if bar then
        if bar == RC.dragging then
            bar:Show()
        else
            slot = slot + 1

            if target and slot == target then
                slot = slot + 1
            end

            local y = -16 - ((slot - 1) * rowSize)

            ResetBarVisuals(bar, entry)
            bar:SetSize(s.barHeight, s.barHeight)

            if IsWithinPanelUniversal(y, s.barHeight) then
                bar:ClearAllPoints()
                AnchorBarToPanelTop(bar, y)
                bar:Show()
            else
                bar:Hide()
            end

            bar.icon:ClearAllPoints()
            bar.icon:SetSize(s.barHeight, s.barHeight)
            bar.icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)

            bar.fill:Hide()
            bar.label:Hide()
        end
    end
end

end

------------------------------------------------
-- COLUMN LIST (OWNER-BASED, CORRECT)
------------------------------------------------
LayoutHandlers.COLUMN_LIST = function()
    HideAllBars()

    local s = RaidCooldownsDB.settings

    -- layout constants (same style as your existing code)
    local paddingTop   = -16
    local colGap       = 24
    local leftPadding  = 16
    local rightPadding = 16

    local barWidth = s.barWidth
    local rowSize  = math.max(1, (s.barHeight or 18) + (s.barSpacing or 0))

    -- How many columns the user configured (we KEEP this)
    local wantedCols = tonumber(RaidCooldownsDB.settings.columns) or 3

    -- How many columns can physically fit (we only RENDER this many)
    local panelW      = (panel and panel:GetWidth()) or 0
    local usableWidth = panelW - leftPadding - rightPadding
    local fitCols     = math.floor((usableWidth + colGap) / (barWidth + colGap))
    if fitCols < 1 then fitCols = 1 end

    local renderCols = math.min(wantedCols, fitCols)

    -- center only the rendered columns
    local totalWidth = (renderCols * barWidth) + ((renderCols - 1) * colGap)
    local startX = leftPadding
    if totalWidth < usableWidth then
        startX = leftPadding + (usableWidth - totalWidth) / 2
    end

    -- group visible list by the SAVED column (do NOT clamp to renderCols)
    local columns = {}
    for i = 1, wantedCols do columns[i] = {} end

    for _, entry in ipairs(GetVisibleOrdered() or {}) do
        local col = tonumber(entry.column) or 1
        if col < 1 or col > wantedCols then col = 1 end
        table.insert(columns[col], entry)
    end

    local targetCol = RC.dragTargetColumn
    local targetRow = RC.dragTargetRow
    if targetCol and (targetCol < 1 or targetCol > wantedCols) then targetCol = 1 end
    if targetCol and targetCol > renderCols then targetCol = renderCols end

    if RC.gapFrame then RC.gapFrame:Hide() end

    -- render columns that fit; hide columns that don't
    for col = 1, wantedCols do
        if col > renderCols then
            -- hide everything in hidden columns
            for _, entry in ipairs(columns[col]) do
                if entry.bar then entry.bar:Hide() end
            end
        else
            local x = startX + (col - 1) * (barWidth + colGap)

            local slot = 0
            for _, entry in ipairs(columns[col]) do
                slot = slot + 1

                if RC.dragging and RC.draggingEntry and entry == RC.draggingEntry then
                    -- cursor-follow owns it
                else
                    local bar = entry.bar
                    if bar then
                        local shift = 0
                        if RC.dragging and targetCol == col and targetRow then
                            if slot >= targetRow then shift = 1 end
                        end

                        ResetBarVisuals(bar, entry)
                        bar:SetSize(barWidth, s.barHeight)

                        -- ICON + BAR geometry (same as your existing handler)
                        bar.icon:Show(); bar.fill:Show(); bar.label:Show()
                        if bar.cdText then bar.cdText:Show() end

                        bar.icon:SetSize(s.barHeight, s.barHeight)
                        bar.icon:ClearAllPoints()
                        bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

                        bar.fill:ClearAllPoints()
                        bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", ICON_GAP, 0)
                        bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 0)

                        local sx = s.spellTextOffsetX or 0
                        local sy = s.spellTextOffsetY or 0
                        bar.label:ClearAllPoints()
                        bar.label:SetPoint("LEFT", bar.fill, "LEFT", 4 + sx, sy)
                        bar.label:SetJustifyH("LEFT")
                        bar.label:SetJustifyV("MIDDLE")

                        if bar.cdText then
                            local cx = s.cdTextOffsetX or 0
                            local cy = s.cdTextOffsetY or 0
                            bar.cdText:SetJustifyH("RIGHT")
                            bar.cdText:SetJustifyV("MIDDLE")
                            bar.cdText:ClearAllPoints()
                            bar.cdText:SetPoint("RIGHT", bar, "RIGHT", -4 + cx, cy)
                        end

                        bar.label:SetText(GetBarLabelText(entry))

                        local y = paddingTop - ((slot - 1 + shift) * rowSize)

                        -- pass explicit padding so it doesn't get hidden at the top
                        if (not RC.dragging) and (not IsWithinPanelUniversal(y, s.barHeight, 16, 16)) then
                            bar:Hide()
                        else
                            bar:ClearAllPoints()
                            bar:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
                            bar:Show()
                        end
                    end
                end
            end
        end
    end
end
------------------------------------------------
-- SPELL OWNERS
------------------------------------------------
LayoutHandlers.SPELL_OWNERS = function()
    HideAllBars()

    local s = RaidCooldownsDB.settings
    local rowSize = s.barHeight + s.barSpacing
    local list = GetVisibleOrdered()

    local target = RC.dragTargetIndex
    local slot = 0

    for _, entry in ipairs(list) do
        local bar = entry.bar
        if bar then
            if bar == RC.dragging then
                bar:Show()
            else
                slot = slot + 1
                if target and slot == target then
                    slot = slot + 1
                end

                local barY = -STACK_TOP_OFFSET - ((slot - 1) * rowSize)

                if (not RC.dragging) and (not IsWithinPanelUniversal(barY, s.barHeight)) then
                    bar:Hide()
                else
                    ResetBarVisuals(bar, entry)
                    bar:SetSize(s.barWidth, s.barHeight)

                    bar:ClearAllPoints()
                    AnchorBarToPanelTop(bar, barY)
                    bar:Show()

                    bar.icon:SetSize(s.barHeight, s.barHeight)
                    bar.icon:ClearAllPoints()
                    bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

                    bar.fill:Hide()

                    bar.label:ClearAllPoints()
                    bar.label:SetPoint("LEFT", bar.icon, "RIGHT", 6, 0)
                    bar.label:SetText(GetBarLabelText(entry))
                end
            end
        end
    end
end

------------------------------------------------
-- ⭐ SAFE SECTION HEADER (RIGHT COLUMN)
------------------------------------------------
local function CreateSectionHeader(parent, text)

    if not parent or not parent.CreateFontString then
        print("RaidCooldowns: CreateSection parent invalid:", parent)
        return nil
    end

    local fs = parent:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    fs:SetText("|cffffcc00"..text.."|r")

    return fs   -- ⭐ no anchors here
end


------------------------------------------------
-- SMART WIDTH DETECTOR (BLIZZARD SAFE)
------------------------------------------------
local function ShouldStretch(frame)

    if not frame then return false end

    -- ❌ Never stretch Blizzard widgets
    if frame:IsObjectType("Slider") then return false end
    if frame:IsObjectType("FontString") then return false end  -- ⭐ THIS FIXES YOUR LABELS
    if frame:GetName() and frame:GetName():find("Dropdown") then return false end
    if frame:GetObjectType() == "CheckButton" then return false end

    -- UIDropDownMenuTemplate parts
    if frame.Left or frame.Middle or frame.Right then
        return false
    end

    return true
end











------------------------------------------------
-- AUTO STACK HELPER (RIGHT COLUMN)
------------------------------------------------
local function StackBelow(frame, anchor, offset)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offset or -12)
end




------------------------------------------------
-- ESC CLOSE (OPTIONS WINDOW)
------------------------------------------------


-- Title
-- local optTitle = options:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
-- optTitle:SetPoint("TOP", 0, -12)
-- optTitle:SetText("RaidCooldowns – Layout")



local s = RaidCooldownsDB.settings





if not RC.trackingBuilt then
    BuildTrackingPage()
    RC.trackingBuilt = true
end





-- About page column
aboutCenterWrap = CreateFrame("Frame", nil, Pages["About"])
aboutCenterWrap:SetPoint("TOPLEFT", content, "TOPLEFT", 150 + 16, 20)
aboutCenterWrap:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 150 + 16, 0)
aboutCenterWrap:SetWidth((COLUMN_WIDTH * 2) + COLUMN_GAP)
AddPageLogo(aboutCenterWrap)


------------------------------------------------
-- CREATE ACTIVE PROFILE CARD (SAFE)
------------------------------------------------

activeProfileCard = CreateCard(
    profilesLeftColumn,
    nil,
    COLUMN_WIDTH
)
activeProfileCard._minHeight = 50
activeProfileCard._height = 12
activeProfileCard._last = nil
ClampCardToPage(activeProfileCard)


-- Active Profile Label
profileDrop = CreateFrame(
    "Frame",
    "RaidCooldownsProfileDropDown",
    activeProfileCard,
    "UIDropDownMenuTemplate"
)

UIDropDownMenu_SetWidth(profileDrop, 180)
UIDropDownMenu_Initialize(profileDrop, InitializeProfileDropDown)

-- 🔥 FORCE INITIAL TEXT
local current = GetCurrentProfileName()
UIDropDownMenu_SetSelectedValue(profileDrop, current)
UIDropDownMenu_SetText(profileDrop, current)

activeProfileCard:Add(profileDrop, 16)

-- STATUS TEXT
profileStatusText = activeProfileCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
profileStatusText:SetText("")
activeProfileCard:Add(profileStatusText, 4)

-- Create card (no clamp yet)
roleProfilesCard = CreateCard(
    profilesLeftColumn,
    nil,
    COLUMN_WIDTH
)



-- NOW clamp after stacking
roleProfilesCard._minHeight = 80
roleProfilesCard._height = 12
roleProfilesCard._last = nil
ClampCardToPage(roleProfilesCard)

-- TANK LABEL
local tankLabel = roleProfilesCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tankLabel:SetText("TANK")
roleProfilesCard:Add(tankLabel, 12)

-- TANK DROPDOWN
local tankDrop = CreateFrame("Frame", nil, roleProfilesCard, "UIDropDownMenuTemplate")
UIDropDownMenu_SetWidth(tankDrop, 160)

UIDropDownMenu_Initialize(tankDrop, function(self, level)

-- NONE OPTION
local noneInfo = UIDropDownMenu_CreateInfo()
noneInfo.text = "None"
noneInfo.func = function()

    RaidCooldownsDB.roleProfiles["TANK"] = nil
    UIDropDownMenu_SetText(tankDrop, "None")

    UpdateProfileStatusText()
end

noneInfo.checked = (RaidCooldownsDB.roleProfiles["TANK"] == nil)
UIDropDownMenu_AddButton(noneInfo)

    for name in pairs(RaidCooldownsDB.profiles) do
        local info = UIDropDownMenu_CreateInfo()

        info.text = name
        info.func = function()

            RaidCooldownsDB.roleProfiles["TANK"] = name
            UIDropDownMenu_SetText(tankDrop, name)

            -- Apply immediately if current spec is tank
            local specIndex = GetSpecialization()
            if specIndex and GetSpecializationRole(specIndex) == "TANK" then
                SwitchToProfile(name)
            end
        end

        info.checked = (RaidCooldownsDB.roleProfiles["TANK"] == name)
        UIDropDownMenu_AddButton(info)
    end
end)

-- Initial text
local tankCurrent = RaidCooldownsDB.roleProfiles["TANK"]
UIDropDownMenu_SetText(tankDrop, tankCurrent or "None")

roleProfilesCard:Add(tankDrop, 4)

-- HEALER LABEL
local healerLabel = roleProfilesCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
healerLabel:SetText("HEALER")
roleProfilesCard:Add(healerLabel, 12)

-- HEALER DROPDOWN
local healerDrop = CreateFrame("Frame", nil, roleProfilesCard, "UIDropDownMenuTemplate")
UIDropDownMenu_SetWidth(healerDrop, 160)

UIDropDownMenu_Initialize(healerDrop, function(self, level)

-- NONE OPTION
local noneInfo = UIDropDownMenu_CreateInfo()
noneInfo.text = "None"
noneInfo.func = function()

    RaidCooldownsDB.roleProfiles["HEALER"] = nil
    UIDropDownMenu_SetText(healerDrop, "None")

    UpdateProfileStatusText()
end

noneInfo.checked = (RaidCooldownsDB.roleProfiles["HEALER"] == nil)
UIDropDownMenu_AddButton(noneInfo)

    for name in pairs(RaidCooldownsDB.profiles) do
        local info = UIDropDownMenu_CreateInfo()

        info.text = name
        info.func = function()

            RaidCooldownsDB.roleProfiles["HEALER"] = name
            UIDropDownMenu_SetText(healerDrop, name)

            -- If current spec is healer, apply immediately
            local specIndex = GetSpecialization()
            if specIndex and GetSpecializationRole(specIndex) == "HEALER" then
                SwitchToProfile(name)
            end
        end

        info.checked = (RaidCooldownsDB.roleProfiles["HEALER"] == name)
        UIDropDownMenu_AddButton(info)
    end
end)

-- Set initial text
local healerCurrent = RaidCooldownsDB.roleProfiles["HEALER"]
UIDropDownMenu_SetText(healerDrop, healerCurrent or "None")

roleProfilesCard:Add(healerDrop, 4)

-- DAMAGER LABEL
local dpsLabel = roleProfilesCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dpsLabel:SetText("DAMAGER")
roleProfilesCard:Add(dpsLabel, 12)

-- DAMAGER DROPDOWN
local dpsDrop = CreateFrame("Frame", nil, roleProfilesCard, "UIDropDownMenuTemplate")
UIDropDownMenu_SetWidth(dpsDrop, 160)

UIDropDownMenu_Initialize(dpsDrop, function(self, level)

-- NONE OPTION
local noneInfo = UIDropDownMenu_CreateInfo()
noneInfo.text = "None"
noneInfo.func = function()

    RaidCooldownsDB.roleProfiles["DAMAGER"] = nil
    UIDropDownMenu_SetText(dpsDrop, "None")

    UpdateProfileStatusText()
end

noneInfo.checked = (RaidCooldownsDB.roleProfiles["DAMAGER"] == nil)
UIDropDownMenu_AddButton(noneInfo)

    for name in pairs(RaidCooldownsDB.profiles) do
        local info = UIDropDownMenu_CreateInfo()

        info.text = name
        info.func = function()

            RaidCooldownsDB.roleProfiles["DAMAGER"] = name
            UIDropDownMenu_SetText(dpsDrop, name)

            -- Apply immediately if current spec is DPS
            local specIndex = GetSpecialization()
            if specIndex and GetSpecializationRole(specIndex) == "DAMAGER" then
                SwitchToProfile(name)
            end
        end

        info.checked = (RaidCooldownsDB.roleProfiles["DAMAGER"] == name)
        UIDropDownMenu_AddButton(info)
    end
end)

-- Initial text
local dpsCurrent = RaidCooldownsDB.roleProfiles["DAMAGER"]
UIDropDownMenu_SetText(dpsDrop, dpsCurrent or "None")

roleProfilesCard:Add(dpsDrop, 4)





specCard = CreateCard(
    profilesLeftColumn,
    nil,
    COLUMN_WIDTH
)

specCard:SetHeight(160)


local specTitle, specSep =
 CreateSection(specCard, "Specializations", COLUMN_WIDTH)



importExportCard = CreateCard(
    profilesRightColumn,
    nil,
    COLUMN_WIDTH
)

importExportCard._minHeight = 100
importExportCard._height = 12
importExportCard._last = nil
ClampCardToPage(importExportCard)


profileActionsCard = CreateCard(
    profilesRightColumn,
    nil,
    COLUMN_WIDTH
)

local importTitle, importSep =
CreateSection(importExportCard, "Import / Export", COLUMN_WIDTH)

local managementTitle, managementSep =
  CreateSection(profileActionsCard, "Profile Management", COLUMN_WIDTH)
	
	
if not ProfilesRightStack then
    print("ProfilesRightStack not initialized")
    return
end


ProfilesRightStack:Add(importTitle)
ProfilesRightStack:Add(importSep, -6)
ProfilesRightStack:Add(importExportCard, -16)

ProfilesRightStack:Add(managementTitle)
ProfilesRightStack:Add(managementSep, -6)
ProfilesRightStack:Add(profileActionsCard, -16)


profileActionsCard._minHeight = 120
profileActionsCard._height = 12
profileActionsCard._last = nil
ClampCardToPage(profileActionsCard)

-- Create buttons FIRST (no SetPoint, no column parenting)

local newProfileBtn = CreateFrame("Button", nil, profileActionsCard, "UIPanelButtonTemplate")
newProfileBtn:SetSize(200, 24)
newProfileBtn:SetText("Create New Profile")
AddHoverGlow(newProfileBtn)

local dupBtn = CreateFrame("Button", nil, profileActionsCard, "UIPanelButtonTemplate")
dupBtn:SetSize(200, 24)
dupBtn:SetText("Duplicate Profile")
AddHoverGlow(dupBtn)


------------------------------------------------
-- RENAME PROFILE WINDOW
------------------------------------------------
function CreateRenameWindow()

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


local renameBtn = CreateFrame("Button", nil, profileActionsCard, "UIPanelButtonTemplate")
renameBtn:SetSize(200, 24)
renameBtn:SetText("Rename Profile")
AddHoverGlow(renameBtn)

local deleteBtn = CreateFrame("Button", nil, profileActionsCard, "UIPanelButtonTemplate")
deleteBtn:SetSize(200, 24)
deleteBtn:SetText("Delete Profile")
AddHoverGlow(deleteBtn)

-- NOW add them to the card (THIS controls layout)
profileActionsCard:Add(newProfileBtn, 14)
profileActionsCard:Add(dupBtn, 14)
profileActionsCard:Add(renameBtn, 14)
profileActionsCard:Add(deleteBtn, 14)


newProfileBtn:SetScript("OnClick", function()
    if not profileDrop then return end

    local base = "NewProfile"
    local i = 1
    local name = base .. i

    while RaidCooldownsDB.profiles[name] do
        i = i + 1
        name = base .. i
    end

    RaidCooldownsDB.profiles[name] = {
    settings       = CopyTable(RaidCooldownsDB.settings),
    layout         = CopyTable(RaidCooldownsDB.layout),
    templateOrders = CopyTable(GetProfile().templateOrders),
    trackedSpells  = CopyTable(RaidCooldownsDB.trackedSpells),
}


    RaidCooldownsDB.char[GetCharKey()] = name
   ApplyProfile()

CreateGroups()
UpdateOwners()
RebuildOrderedList()
RefreshProfileUI()
UIDropDownMenu_SetText(profileDrop, name)
UpdateLayout()

end)

dupBtn:SetScript("OnClick", function()
    if not profileDrop then return end

    local current = GetCurrentProfileName()
    local base = current .. "_Copy"
    local i = 1
    local name = base

    while RaidCooldownsDB.profiles[name] do
        i = i + 1
        name = base .. i
    end

    RaidCooldownsDB.profiles[name] =
        CopyTable(RaidCooldownsDB.profiles[current])

    RaidCooldownsDB.char[GetCharKey()] = name
 ApplyProfile()

CreateGroups()
UpdateOwners()
RebuildOrderedList()

UIDropDownMenu_SetText(profileDrop, name)
UpdateLayout()

end)

renameBtn:SetScript("OnClick", function()
    if not profileDrop then return end

    CreateRenameWindow()
    RaidCooldownsRenameFrame:Show()
end)

deleteBtn:SetScript("OnClick", function()
    if not profileDrop then return end

    local current = GetCurrentProfileName()

    if current == "Default" then
        print("RaidCooldowns: Cannot delete Default profile.")
        return
    end

    RaidCooldownsDB.profiles[current] = nil
    RaidCooldownsDB.char[GetCharKey()] = "Default"

 ApplyProfile()

CreateGroups()
UpdateOwners()
RebuildOrderedList()

UIDropDownMenu_SetText(profileDrop, "Default")
UpdateLayout()



end)



------------------------------------------------
-- PROFILE EXPORT / IMPORT BUTTONS
------------------------------------------------

local exportBtn = CreateFrame(
    "Button",
    nil,
    importExportCard,
    "UIPanelButtonTemplate"
)
exportBtn:SetSize(COLUMN_WIDTH - 20, 24)
exportBtn:SetText("Export Profile")
AddHoverGlow(exportBtn)

local importBtn = CreateFrame(
    "Button",
    nil,
    importExportCard,
    "UIPanelButtonTemplate"
)
importBtn:SetSize(COLUMN_WIDTH - 20, 24)
importBtn:SetText("Import Profile")
AddHoverGlow(importBtn)

exportBtn:SetScript("OnClick", function()
    local profile = GetProfile()
    if not profile then return end

    CreateExportWindow()

    local text = "return " .. SerializeTable(profile)
    RaidCooldownsExportFrame.editBox:SetText(text)
    RaidCooldownsExportFrame.editBox:HighlightText()
    RaidCooldownsExportFrame:Show()
end)

importBtn:SetScript("OnClick", function()
    CreateImportWindow()
    RaidCooldownsImportFrame:Show()
end)

importExportCard:Add(exportBtn, 18)
importExportCard:Add(importBtn, 24)






ProfilesLeftStack:Add(activeProfileTitle)
ProfilesLeftStack:Add(activeProfileSep, -6)
ProfilesLeftStack:Add(activeProfileCard, -16)

-- Stack them
ProfilesLeftStack:Add(roleTitle)
ProfilesLeftStack:Add(roleSep, -6)
ProfilesLeftStack:Add(roleProfilesCard, -16)

ProfilesLeftStack:Add(specTitle)
ProfilesLeftStack:Add(specSep, -6)
ProfilesLeftStack:Add(specCard, -16)




activeProfileCard.profileLabel =
    activeProfileCard:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalLarge"
    )

local profileLabel = activeProfileCard.profileLabel

profileLabel:SetJustifyH("CENTER")
profileLabel:SetWidth(COLUMN_WIDTH)

profileLabel:SetTextColor(1,0.82,0)




RefreshActiveProfileLabel()


  


------------------------------------------------
-- REFRESH TEMPLATE DROPDOWN
------------------------------------------------
RefreshTemplateDropdown = function()

    if not templateDrop then return end

    local current = RaidCooldownsDB.settings.template
	
	 print("Template on refresh:", current)

    UIDropDownMenu_SetSelectedValue(templateDrop, current)

    if BAR_TEMPLATES[current] then
        UIDropDownMenu_SetText(templateDrop, BAR_TEMPLATES[current])
    end
end




------------------------------------------------
-- PAGE SYSTEM (REAL NAVIGATION)
------------------------------------------------

function ShowPage(name)

    for n, frame in pairs(Pages) do
        frame:SetShown(n == name)
    end

if name == "Profiles" then
    BuildSpecProfileUI()
    UpdateSpecButtonStates()
    RefreshActiveProfileLabel()

        profilesLeftColumn:SetHeight(600)
        profilesRightColumn:SetHeight(600)
    end

if name == "About" then
    BuildAboutPage()
end

  if name == "Tracking" then
    if not RC.trackingBuilt then
        BuildTrackingPage()
        RC.trackingBuilt = true
    end
    BuildTrackingUI()
end
end


------------------------------------------------
-- UPDATE LAYOUT PAGE HEIGHT
------------------------------------------------
UpdateLayoutPageHeight = function()
    local leftH  = leftColumn and leftColumn:GetHeight() or 0
    local rightH = rightColumn and rightColumn:GetHeight() or 0

    contentHeight = math.max(leftH, rightH)

    if centerWrap then
        centerWrap:SetHeight(contentHeight + 40)
    end
end












------------------------------------------------
-- EXPORT WINDOW (CREATE ONCE)
------------------------------------------------
CreateExportWindow = function()


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
CreateImportWindow = function()


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

CreateGroups()
UpdateOwners()
RebuildOrderedList()
PreCreateAllBars()

UpdateAllBarFonts()
UpdateLayout()


  
end







-- END_INITUI_MARKER



------------------------------------------------
-- BUILD SPEC PROFILE UI
------------------------------------------------
function BuildSpecProfileUI()

    if InCombatLockdown() then
        print("BuildSpecProfileUI BLOCKED (combat)")
        return
    end



if InCombatLockdown() then
        C_Timer.After(0.5, BuildSpecProfileUI)
        return
    end


    -- safety guard
      if not specCard then return end

-- 🔒 Reset layout state ONLY
specCard._minHeight = 160
specCard._height = 12
specCard._last = nil


-- Hide previous buttons (do NOT reparent)
if specCard._buttons then
    for _, btn in ipairs(specCard._buttons) do
        btn:Hide()
    end
end

specCard._buttons = {}





    -- subtitle
    if not specCard.subtitle then
    specCard.subtitle = specCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    specCard.subtitle:SetJustifyH("CENTER")
    specCard.subtitle:SetWidth(COLUMN_WIDTH)
end

specCard.subtitle:SetText("Assign profiles per specialization")

specCard.subtitle:ClearAllPoints()
specCard.subtitle:SetPoint(
    "TOP",
    specCard,
    "TOP",
    -6,    -- 👈 compensates for left padding / inset
    -14
)

specCard.subtitle:SetJustifyH("CENTER")
specCard.subtitle:SetWidth(COLUMN_WIDTH - 24) -- match card inner width


specCard:Add(specCard.subtitle, 24) -- more breathing room



    local numSpecs = GetNumSpecializations()
    if not numSpecs or numSpecs == 0 then return end

    for i = 1, numSpecs do
        local specID, specName = GetSpecializationInfo(i)
        if specID and specName then
        local assignedProfile = RaidCooldownsDB.specProfiles[specID]
local currentProfile = GetCurrentProfileName()

local role = select(5, GetSpecializationInfoByID(specID))
local roleProfile = role and RaidCooldownsDB.roleProfiles[role]

local label = specName
if assignedProfile then
    label = specName .. "  |cffaaaaaa(" .. assignedProfile .. ")|r"
end

local btn = CreateFrame("Button", nil, specCard, "UIPanelButtonTemplate")
table.insert(specCard._buttons, btn)
btn:SetSize(COLUMN_WIDTH - 24, 24)
btn:SetAlpha(0.85) -- default (unselected)
btn:SetText(label)
btn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
btn:SetText(label)

local fs = btn:GetFontString()
fs:ClearAllPoints()
fs:ClearAllPoints()
fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
fs:SetJustifyH("CENTER")
fs:SetJustifyV("MIDDLE")
fs:SetWordWrap(false)
fs:SetWidth(btn:GetWidth() - 20)
fs:SetTextColor(1, 1, 1)


-- 🟢 Spec Override Active
if assignedProfile and assignedProfile == currentProfile then
    btn:SetAlpha(1)
    fs:SetTextColor(0.2, 1, 0.2)

-- 🟡 Role Fallback Active
elseif (not assignedProfile) and roleProfile and roleProfile == currentProfile then
    btn:SetAlpha(1)
    fs:SetTextColor(1, 0.85, 0)

-- ⚪ Manual / Inactive
else
    btn:SetAlpha(0.85)
    fs:SetTextColor(1, 1, 1)
end








btn:SetScript("OnClick", function()

    local specID = select(1, GetSpecializationInfo(i))
    if not specID then return end

    local currentProfile = GetCurrentProfileName()
    local assignedProfile = RaidCooldownsDB.specProfiles[specID]

    -- If already assigned → remove override
    if assignedProfile == currentProfile then
        RaidCooldownsDB.specProfiles[specID] = nil
        print("Removed spec override for specID", specID)

    -- Otherwise assign current profile
    else
        RaidCooldownsDB.specProfiles[specID] = currentProfile
        print("Assigned profile", currentProfile, "to specID", specID)
    end

    UpdateSpecButtonStates()
    UpdateProfileStatusText()
end)





specCard:Add(btn, 14)



        end
    end
end




------------------------------------------------
-- UPDATE SPEC BUTTON STATE
------------------------------------------------
function UpdateSpecButtonStates()

    if not specCard or not specCard._buttons then return end

    local currentProfile = GetCurrentProfileName()
    local activeSpec = GetSpecialization()

    for i, btn in ipairs(specCard._buttons) do

        local specID, specName = GetSpecializationInfo(i)
        if not specID then return end

        local assigned = RaidCooldownsDB.specProfiles[specID]
        local role = select(5, GetSpecializationInfoByID(specID))
        local roleProfile = role and RaidCooldownsDB.roleProfiles[role]

        local label = specName
        if assigned then
            label = specName .. "  |cffaaaaaa(" .. assigned .. ")|r"
        end

        btn:SetText(label)

        local fs = btn:GetFontString()

        -- 🟢 Spec Override Active
        if assigned and assigned == currentProfile then
            btn:SetAlpha(1)
            fs:SetTextColor(0.2, 1, 0.2)

        -- 🟡 Role Fallback Active
        elseif (not assigned) and roleProfile and roleProfile == currentProfile then
            btn:SetAlpha(1)
            fs:SetTextColor(1, 0.85, 0)

        -- 🔵 Active Spec (but no override/fallback)
        elseif i == activeSpec then
            btn:SetAlpha(1)
            fs:SetTextColor(0, 0.8, 1)

        -- ⚪ Inactive
        else
            btn:SetAlpha(0.85)
            fs:SetTextColor(1, 1, 1)
        end
    end
end

------------------------------------------------
-- BUILD TRACKING UI (CATEGORIZED)
------------------------------------------------
function BuildTrackingUI()

   if not trackingLeftCard or not trackingRightCard then
    return
end

-- Reset layout tracking
trackingLeftCard._height  = 12
trackingLeftCard._last    = nil
trackingRightCard._height = 12
trackingRightCard._last   = nil

-- Just hide old children instead of detaching
for _, child in ipairs({trackingLeftCard:GetChildren()}) do
    child:Hide()
end

for _, child in ipairs({trackingRightCard:GetChildren()}) do
    child:Hide()
end

    ------------------------------------------------
    -- GROUP SPELLS BY CATEGORY
    ------------------------------------------------
    local categories = {
        raid     = {},
        external = {},
        utility  = {},
        bres     = {},
    }

    for spellID, data in pairs(HEALING_COOLDOWNS) do
        local cat = data.category or "raid"
        if categories[cat] then
            table.insert(categories[cat], {
                id   = spellID,
                name = data.name
            })
        end
    end

    -- Sort inside each category
    for _, list in pairs(categories) do
        table.sort(list, function(a,b)
            return a.name < b.name
        end)
    end

    ------------------------------------------------
    -- RENDER FUNCTION
    ------------------------------------------------
  local function AddCategorySection(parentCard, title, spellList)
    if not spellList or #spellList == 0 then return end

    -- Header
    local header = parentCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetText(title)
    header:SetJustifyH("CENTER")
    header:SetWidth((parentCard:GetWidth() or 0) - 32)
    parentCard:Add(header, 12)
    header:SetPoint("LEFT", parentCard, "LEFT", 16, 0)
    header:SetPoint("RIGHT", parentCard, "RIGHT", -16, 0)

    -- Separator
    local sep = CreateFrame("Frame", nil, parentCard)
    sep:SetHeight(1)
    sep:SetWidth((parentCard:GetWidth() or 0) - 24)
    sep:SetPoint("LEFT", parentCard, "LEFT", 12, 0)
    sep:SetPoint("RIGHT", parentCard, "RIGHT", -12, 0)

    local tex = sep:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(1, 1, 1, 0.18)
    parentCard:Add(sep, 8)

    -- Checkboxes
    for _, spellData in ipairs(spellList) do
        local spellID   = spellData.id
        local spellName = spellData.name

        -- ✅ cb MUST be created before any cb.* calls
        local cb = CreateFrame("CheckButton", nil, parentCard, "InterfaceOptionsCheckButtonTemplate")
        NormalizeCheckButton(cb)

        cb.Text:SetText(spellName)
        cb:SetChecked(IsSpellTracked(spellID))

        cb:SetScript("OnClick", function(self)
            RaidCooldownsDB.trackedSpells = RaidCooldownsDB.trackedSpells or {}

            -- default tracked: nil; explicitly hidden: false
            if self:GetChecked() then
                RaidCooldownsDB.trackedSpells[spellID] = nil
            else
                RaidCooldownsDB.trackedSpells[spellID] = false
            end

            RebuildOrderedList()
            UpdateLayout()
        end)

        parentCard:Add(cb, 8)
    end
end

    ------------------------------------------------
    -- DISTRIBUTE CATEGORIES BETWEEN COLUMNS
    ------------------------------------------------
  -- LEFT COLUMN
AddCategorySection(trackingLeftCard, "Raid Cooldowns", categories.raid)

-- RIGHT
trackingRightCard._last = nil

AddCategorySection(trackingRightCard, "External Cooldowns", categories.external)
AddCategorySection(trackingRightCard, "Utility", categories.utility)
AddCategorySection(trackingRightCard, "Battle Res", categories.bres)

    trackingLeftCard._built = true
	
	local maxHeight = content:GetHeight() - 120

if trackingLeftCard:GetHeight() > maxHeight then
    trackingLeftCard:SetHeight(maxHeight)
end

if trackingRightCard:GetHeight() > maxHeight then
    trackingRightCard:SetHeight(maxHeight)
end
-- Add bottom padding to both cards
trackingLeftCard._height = trackingLeftCard._height + 12
trackingRightCard._height = trackingRightCard._height + 12

trackingLeftCard:SetHeight(trackingLeftCard._height)
trackingRightCard:SetHeight(trackingRightCard._height)
-- Equalize card heights
local leftHeight  = trackingLeftCard:GetHeight()
local rightHeight = trackingRightCard:GetHeight()

local maxHeight = math.max(leftHeight, rightHeight)

trackingLeftCard:SetHeight(maxHeight)
trackingRightCard:SetHeight(maxHeight)
end


 
------------------------------------------------
-- DEBUG LOGGER
------------------------------------------------
local function RC_Debug2(...)
    if not RC.debugMode then return end
    print("|cff00c6ffRaidCooldowns DEBUG:|r", ...)
end








------------------------------------------------
-- COPY TABLE
------------------------------------------------
local function CopyTable(src)
    local dst = {}
    for k, v in pairs(src or {}) do
        dst[k] = type(v) == "table" and CopyTable(v) or v
    end
    return dst
end


------------------------------------------------
-- SIMPLE TABLE SERIALIZER (EXPORT SAFE)
------------------------------------------------
SerializeTable = function(val, name, depth)

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







end



------------------------------------------------
-- SLASH COMMANDS
------------------------------------------------

-- Toggle lock / unlock
SLASH_RAIDCOOLDOWNS1 = "/raidcd"
SlashCmdList.RAIDCOOLDOWNS = function()

    RC.locked = not RC.locked

    UpdatePanelMouseState()
    UpdatePanelBackground()

    if RC.locked then
        print("RaidCooldowns locked")
    else
        print("RaidCooldowns unlocked (drag panel)")
    end

end


-- Force unlock (failsafe)
SLASH_RAIDCDUNLOCK1 = "/raidcdunlock"
SlashCmdList.RAIDCDUNLOCK = function()

    RC.locked = false

    UpdatePanelMouseState()
    UpdatePanelBackground()

    print("RaidCooldowns force-unlocked")

end


-- Options window
SLASH_RAIDCDOPTIONS1 = "/raidcdoptions"
SlashCmdList.RAIDCDOPTIONS = function()

    if not options then
        InitUI()
    end

    options:SetShown(not options:IsShown())

    if options:IsShown() then
        ShowPage("Layout")

        if UpdateLayoutPageHeight then
            UpdateLayoutPageHeight()
        end
    end

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

SLASH_RAIDCDDEBUG1 = "/raidcddebug"
SlashCmdList.RAIDCDDEBUG = function()
    RC.debugMode = not RC.debugMode
    print("RaidCooldowns Debug Mode:", RC.debugMode and "ON" or "OFF")
end

SLASH_RAIDCDREFRESH1 = "/raidcdrefresh"
SlashCmdList.RAIDCDREFRESH = function()
    RebuildOrderedList()
    UpdateLayout()
    print("RaidCooldowns refreshed")
end