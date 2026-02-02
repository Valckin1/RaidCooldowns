------------------------------------------------
-- RaidCooldowns.lua (CLEAN / STABLE TEMPLATE BASE)
------------------------------------------------

------------------------------------------------
-- SAVED VARIABLES
------------------------------------------------
RaidCooldownsDB = RaidCooldownsDB or {}
RaidCooldownsDB.layout = RaidCooldownsDB.layout or {}
RaidCooldownsDB.settings = RaidCooldownsDB.settings or {

    barWidth   = 180,
    barHeight  = 18,
    barSpacing = 6,
    centerBars = true,
    template   = "BAR_ONLY", -- future use
}

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
        local bar = CreateFrame("Frame", nil, panel)
        bar.spellID = spellID
        bar.class = data.class

        -- Icon
        local icon = bar:CreateTexture(nil, "OVERLAY")
        icon:SetPoint("LEFT", 0, 0)
        bar.icon = icon

        -- Fill
        local fill = CreateFrame("StatusBar", nil, bar)
        fill:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
        fill:SetMinMaxValues(0, 1)
        fill:SetValue(1)
        bar.fill = fill

        -- Label
        local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", fill, "LEFT", 4, 0)
        label:SetText(data.name)
        bar.label = label

        RC.spells[spellID] = {
            spellID = spellID,
            name    = data.name,
            class   = data.class,
            bar     = bar,
            owners  = {},
            hasOwners = false,
        }

        table.insert(RC.ordered, RC.spells[spellID])
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

    local function CheckUnit(unit)
        for spellID, group in pairs(RC.spells) do
            if IsSpellKnown(spellID, unit) then
                local name = UnitName(unit)
                if name then
                    group.owners[name] = true
                    group.hasOwners = true
                end
            end
        end
    end

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
-- UPDATE PANEL MOUSE STATE
------------------------------------------------
local function UpdatePanelMouseState()
    if RC.locked then
        panel:EnableMouse(false)
    else
        panel:EnableMouse(true)
    end
end



------------------------------------------------
-- UPDATE LAYOUT (GLOBAL / SHARED)
------------------------------------------------
local function UpdateLayout()
    if not panel then return end

    local s = RaidCooldownsDB.settings
    local panelW = panel:GetWidth()
    local panelH = panel:GetHeight()

    local startX = s.centerBars
        and math.floor((panelW - s.barWidth) / 2)
        or 16

    local rowSpacing = s.barHeight + s.barSpacing
    local totalHeight = (#RC.ordered - 1) * rowSpacing + s.barHeight
    local startY = -math.floor((panelH - totalHeight) / 2)

    for i, group in ipairs(RC.ordered) do
        local bar = group.bar
        bar:SetSize(s.barWidth, s.barHeight)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", panel, startX, startY - ((i - 1) * rowSpacing))

        bar.icon:SetSize(s.barHeight, s.barHeight)
        bar.icon:SetTexture(C_Spell.GetSpellTexture(group.spellID))

        bar.fill:ClearAllPoints()
        bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", s.barHeight + ICON_GAP, 0)
        bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 0)

        local color = RAID_CLASS_COLORS[group.class]
        if color then
            bar.fill:SetStatusBarColor(color.r * 0.85, color.g * 0.85, color.b * 0.85)
        else
            bar.fill:SetStatusBarColor(0.7, 0.7, 0.7)
        end

        bar:Show()
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





local reset = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
reset:SetSize(140, 24)
reset:SetPoint("BOTTOM", options, "BOTTOM", 0, 16)
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






------------------------------------------------
-- EVENTS
------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")

ev:SetScript("OnEvent", function(_, event, addon)
if event == "ADDON_LOADED" and addon == "RaidCooldowns" then
    CreateGroups()
    UpdateOwners()
    UpdateLayout()
    UpdatePanelMouseState()
end

end)


panel:SetScript("OnSizeChanged", function(self)
    local s = RaidCooldownsDB.settings

    s.panelWidth  = math.floor(self:GetWidth())
    s.panelHeight = math.floor(self:GetHeight())

    UpdateLayout()
end)


------------------------------------------------
-- SLASH COMMANDS
------------------------------------------------
SLASH_RAIDCOOLDOWNS1 = "/raidcd"
SlashCmdList.RAIDCOOLDOWNS = function()
    RC.locked = not RC.locked
    print(RC.locked and "RaidCooldowns locked" or "RaidCooldowns unlocked")
end

SLASH_RAIDCDRESET1 = "/raidcdreset"
SlashCmdList.RAIDCDRESET = function()
    RaidCooldownsDB.layout = {}
    ReloadUI()
end
SLASH_RAIDCDOPTIONS1 = "/raidcdoptions"
SlashCmdList.RAIDCDOPTIONS = function()
    options:SetShown(not options:IsShown())
	SLASH_RAIDCDCONFIG1 = "/rcd"
SlashCmdList.RAIDCDCONFIG = SlashCmdList.RAIDCDOPTIONS

SLASH_RAIDCDUNLOCK1 = "/raidcdunlock"
SlashCmdList.RAIDCDUNLOCK = function()
    RC.locked = false
    bg:SetColorTexture(0, 0, 0, 0.25)
    print("RaidCooldowns force-unlocked")
end

end
