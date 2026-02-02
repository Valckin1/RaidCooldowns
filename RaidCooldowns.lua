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
-- HEALING COOLDOWNS (SOURCE OF TRUTH)
------------------------------------------------
local HEALING_COOLDOWNS = {
    [740]    = { name = "Tranquility", class = "DRUID" },
    [108280] = { name = "Healing Tide Totem", class = "SHAMAN" },
    [98008]  = { name = "Spirit Link Totem", class = "SHAMAN" },
    [64843]  = { name = "Divine Hymn", class = "PRIEST" },
    [62618]  = { name = "Power Word: Barrier", class = "PRIEST" },
    [115310] = { name = "Revival", class = "MONK" },
    [31821]  = { name = "Aura Mastery", class = "PALADIN" },
    [363534] = { name = "Rewind", class = "EVOKER" },
}

------------------------------------------------
-- HELPERS
------------------------------------------------
local function GetClassColor(class)
    local c = RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.7, 0.7, 0.7
end

------------------------------------------------
-- MAIN PANEL
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
-- CREATE SPELL GROUPS + BARS
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
            owners  = {},     -- Step 4 data
            hasOwners = false,
        }

        table.insert(RC.ordered, RC.spells[spellID])
    end
end

------------------------------------------------
-- STEP 4 — OWNER COLLECTION (NO VISUALS)
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
-- STEP 5.2 — TEMPLATE DISPATCHER (STUB)
------------------------------------------------
local function RenderSpellGroup(group, index)
    local template = RaidCooldownsDB.settings.template

    -- No visuals yet — dispatcher only
    if template == "BAR_ONLY" then
        return
    elseif template == "BAR_WITH_NAMES" then
        return
    elseif template == "SPELL_HEADER" then
        return
    end
end

------------------------------------------------
-- UPDATE LAYOUT
------------------------------------------------
local function UpdateLayout()
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

        local r, g, b = GetClassColor(group.class)
        bar.fill:SetStatusBarColor(r * 0.8, g * 0.8, b * 0.8)

        bar:Show()

        -- dispatcher hook (safe)
        RenderSpellGroup(group, i)
    end
end



------------------------------------------------
-- OPTIONS PANEL (LEGACY / GUARANTEED WORKING)
------------------------------------------------
local function CreateOptionsPanel()
    if RC.optionsCreated then return end
    RC.optionsCreated = true

    local s = RaidCooldownsDB.settings

    local opt = CreateFrame("Frame", "RaidCooldownsOptions", UIParent)
    opt.name = "RaidCooldowns"

    ------------------------------------------------
    -- TITLE
    ------------------------------------------------
    local title = opt:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("RaidCooldowns")

    local subtitle = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Raid cooldown visibility")
------------------------------------------------
-- BAR WIDTH
------------------------------------------------
local barWidth = CreateFrame("Slider", nil, opt, "OptionsSliderTemplate")
barWidth:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -40)
barWidth:SetMinMaxValues(120, 320)
barWidth:SetValueStep(5)
barWidth:SetValue(s.barWidth)
barWidth.Text:SetText("Bar Width")
barWidth.Low:SetText("120")
barWidth.High:SetText("320")

barWidth:SetScript("OnValueChanged", function(_, v)
    s.barWidth = math.floor(v)
    UpdateLayout()
end)

------------------------------------------------
-- BAR HEIGHT
------------------------------------------------
local barHeight = CreateFrame("Slider", nil, opt, "OptionsSliderTemplate")
barHeight:SetPoint("TOPLEFT", barWidth, "BOTTOMLEFT", 0, -55)
barHeight:SetMinMaxValues(12, 40)
barHeight:SetValueStep(1)
barHeight:SetValue(s.barHeight)
barHeight.Text:SetText("Bar Height")
barHeight.Low:SetText("12")
barHeight.High:SetText("40")

barHeight:SetScript("OnValueChanged", function(_, v)
    s.barHeight = math.floor(v)
    UpdateLayout()
end)

------------------------------------------------
-- BAR SPACING
------------------------------------------------
local barSpacing = CreateFrame("Slider", nil, opt, "OptionsSliderTemplate")
barSpacing:SetPoint("TOPLEFT", barHeight, "BOTTOMLEFT", 0, -55)
barSpacing:SetMinMaxValues(2, 20)
barSpacing:SetValueStep(1)
barSpacing:SetValue(s.barSpacing)
barSpacing.Text:SetText("Bar Spacing")
barSpacing.Low:SetText("2")
barSpacing.High:SetText("20")

barSpacing:SetScript("OnValueChanged", function(_, v)
    s.barSpacing = v
    UpdateLayout()
end)

------------------------------------------------
-- PANEL WIDTH
------------------------------------------------
local panelWidth = CreateFrame("Slider", nil, opt, "OptionsSliderTemplate")
panelWidth:SetPoint("TOPLEFT", barSpacing, "BOTTOMLEFT", 0, -55)
panelWidth:SetMinMaxValues(240, 800)
panelWidth:SetValueStep(10)
panelWidth:SetValue(s.panelWidth or 360)
panelWidth.Text:SetText("Panel Width")
panelWidth.Low:SetText("240")
panelWidth.High:SetText("800")

panelWidth:SetScript("OnValueChanged", function(_, v)
    s.panelWidth = math.floor(v)
    panel:SetWidth(s.panelWidth)
    UpdateLayout()
end)

------------------------------------------------
-- PANEL HEIGHT
------------------------------------------------
local panelHeight = CreateFrame("Slider", nil, opt, "OptionsSliderTemplate")
panelHeight:SetPoint("TOPLEFT", panelWidth, "BOTTOMLEFT", 0, -55)
panelHeight:SetMinMaxValues(150, 600)
panelHeight:SetValueStep(10)
panelHeight:SetValue(s.panelHeight or 300)
panelHeight.Text:SetText("Panel Height")
panelHeight.Low:SetText("150")
panelHeight.High:SetText("600")

panelHeight:SetScript("OnValueChanged", function(_, v)
    s.panelHeight = math.floor(v)
    panel:SetHeight(s.panelHeight)
    UpdateLayout()
end)



    ------------------------------------------------
    -- CENTER BARS
    ------------------------------------------------
   local center = CreateFrame("CheckButton", nil, opt, "InterfaceOptionsCheckButtonTemplate")
center:SetPoint("TOPLEFT", panelHeight, "BOTTOMLEFT", 0, -30)
center.Text:SetText("Center Bars")
center:SetChecked(s.centerBars)

center:SetScript("OnClick", function(self)
    s.centerBars = self:GetChecked()
    UpdateLayout()
end)


    local category = Settings.RegisterCanvasLayoutCategory(opt, "RaidCooldowns")
    Settings.RegisterAddOnCategory(category)
end


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
        CreateOptionsPanel()
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
