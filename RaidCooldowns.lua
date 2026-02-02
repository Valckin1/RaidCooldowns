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
-- FORWARD DECLARATIONS
------------------------------------------------
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
        local bar = CreateFrame("Frame", nil, panel)
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
		fill:SetHeight(RaidCooldownsDB.settings.barHeight - 4)
        bar.fill = fill

        -- Label
       local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetText(data.name)
label:SetDrawLayer("OVERLAY", 2)
bar.label = label

		-- Owners text block (SPELL_OWNERS template only)
local ownersText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ownersText:SetJustifyH("LEFT")
ownersText:SetJustifyV("TOP")
ownersText:Hide()
bar.ownersText = ownersText


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
    if RC.locked then
        panel:EnableMouse(false)
    else
        panel:EnableMouse(true)
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
-- UPDATE LAYOUT
------------------------------------------------
local LayoutHandlers = {}

-- LAYOUT DISPATCHER & TEMPLATE HANDLERS
LayoutHandlers.COLUMN_LIST = function()
    local s = RaidCooldownsDB.settings

    local paddingX = 16
    local paddingY = -16
    local colGap   = 24

    local barH = s.barHeight + s.barSpacing
    local panelW = panel:GetWidth()

    -- How many bars fit vertically
    local maxRows = math.floor(
        (panel:GetHeight() - 32) / barH
    )
    if maxRows < 1 then maxRows = 1 end

    local col = 0
    local row = 0

    for _, group in ipairs(RC.ordered) do
        local bar = group.bar
        bar:Show()

        bar:SetSize(s.barWidth, s.barHeight)
        bar:ClearAllPoints()

        local totalWidth = (col + 1) * s.barWidth + col * colGap
local startX

if s.centerBars then
    startX = (panel:GetWidth() - totalWidth) / 2
else
    startX = paddingX
end

local x = startX + col * (s.barWidth + colGap)

        local y = paddingY - row * barH

        bar:SetPoint("TOPLEFT", panel, x, y)

        -- Icon
        bar.icon:Show()
        bar.icon:SetSize(s.barHeight, s.barHeight)
        bar.icon:ClearAllPoints()
        bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

        -- Fill
        bar.fill:Show()
        bar.fill:ClearAllPoints()
        bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 6, 0)
        bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 0)
        ApplyClassColor(bar, group.class)

        -- Label
        bar.label:Show()
        bar.label:ClearAllPoints()
        bar.label:SetPoint("LEFT", bar.fill, "LEFT", 4, 0)

        -- Advance row / column
        row = row + 1
        if row >= maxRows then
            row = 0
            col = col + 1
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


local function UpdateLayout()
    local template = RaidCooldownsDB.settings.template
    local handler = LayoutHandlers[template]

    if handler then
        handler()
    end
end

------------------------------------------------
-- LAYOUT HANDLERS
------------------------------------------------

LayoutHandlers.ICON_BAR = function()
    local s = RaidCooldownsDB.settings
    local y = -16

    for _, group in ipairs(RC.ordered) do
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

        bar.fill:Show()
        bar.fill:ClearAllPoints()
        bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 6, 0)
        bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 0)

        ApplyClassColor(bar, group.class)

        bar.label:Show()
        bar.label:ClearAllPoints()
       bar.label:ClearAllPoints()
bar.label:SetPoint("LEFT", bar.icon, "RIGHT", 8, 0)
bar.label:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
-- STEP 3: lock label size & behavior
bar.label:SetJustifyH("LEFT")
bar.label:SetJustifyV("MIDDLE")
bar.label:SetWordWrap(false)
bar.label:SetMaxLines(1)

-- hard width cap (prevents overlap)
bar.label:SetWidth(
    s.barWidth - s.barHeight - 14
)

bar.label:SetJustifyH("LEFT")
bar.label:SetJustifyV("MIDDLE")
bar.label:SetWordWrap(false)
bar.label:SetMaxLines(1)
bar.label:SetDrawLayer("OVERLAY")
bar.label:SetJustifyH("LEFT")
bar.label:SetWordWrap(false)


        y = y - s.barHeight - s.barSpacing
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
                UIDropDownMenu_SetText(templateDrop, BAR_TEMPLATES[id])
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
    CreateGroups()
    UpdatePanelMouseState()

    -- 🧪 TEST: force ICON_BAR layout
    RaidCooldownsDB.settings.template = "ICON_BAR"
    UpdateLayout()
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
