-- RaidCooldowns_ClientPlugin.lua
-- INSTALL THIS ONLY if you are NOT running the full RaidCooldowns tracker addon.
-- It silently sends your cooldown casts to the tracker (no chat spam).
-- If you already have the full RaidCooldowns addon enabled, you do NOT need this plugin.
--

local PREFIX_SPELLS = "RAIDCOOLDOWNS"
local PREFIX_HANDSHAKE = "RAIDCD_SENDER"

local ADDON_ID = "raidcooldowns_clientPlugin"
local TRACKED = {
  [740] = true,
  [2825] = true,
  [20484] = true,
  [20707] = true,
  [29166] = true,
  [31821] = true,
  [33206] = true,
  [33891] = true,
  [47788] = true,
  [51052] = true,
  [61999] = true,
  [62618] = true,
  [64843] = true,
  [80353] = true,
  [98008] = true,
  [108280] = true,
  [114052] = true,
  [115310] = true,
  [196718] = true,
  [363534] = true,
  [388615] = true,
  [421453] = true,
}


local function PlayerKnowsTrackedSpell(spellID)
  spellID = tonumber(spellID)
  if not spellID then return false end

  -- Best retail path: includes override/replacement spells.
  if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID) then
    return true
  end

  -- Older/simple path.
  if IsPlayerSpell and IsPlayerSpell(spellID) then
    return true
  end

  -- Spellbook scan fallback.
  if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
    local i = 1
    while true do
      local info = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
      if not info then break end
      local sbSpellID = info.spellID
      if sbSpellID and tonumber(sbSpellID) == spellID then
        return true
      end
      i = i + 1
    end
  elseif GetSpellBookItemInfo then
    local i = 1
    while true do
      local skillType, sbSpellID = GetSpellBookItemInfo(i, BOOKTYPE_SPELL)
      if not skillType then break end
      if tonumber(sbSpellID) == spellID then
        return true
      end
      i = i + 1
    end
  end

  return false
end

local function PickChannel()
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    return "INSTANCE_CHAT"
  elseif IsInRaid() then
    return "RAID"
  elseif IsInGroup() then
    return "PARTY"
  end
  return nil
end

local HEALER_ONLY = {
  [740] = true,
  [29166] = true,
  [108280] = true,
  [114052] = true,
  [98008] = true,
  [64843] = true,
  [62618] = true,
  [47788] = true,
  [33206] = true,
  [31821] = true,
  [363534] = true,
  [115310] = true,
  [388615] = true,
}

local ALWAYS_VISIBLE = {
  [51052] = true, -- Anti-Magic Zone
  [61999] = true, -- Raise Ally
  [20484] = true, -- Rebirth
  [20707] = true, -- Soulstone
}

local NON_HEALER_SPELL_SPECS = {
  [2825]   = { [262]=true, [263]=true, [264]=true }, -- Bloodlust
  [80353]  = { [62]=true, [63]=true, [64]=true },    -- Time Warp
  [196718] = { [577]=true, [581]=true },             -- Darkness
  [51052]  = { [250]=true },                         -- AMZ
  [20707]  = { [265]=true, [266]=true, [267]=true },-- Soulstone
}

local SPEC_FILTER = {
  [64843]  = { [257] = true }, -- Divine Hymn
  [62618]  = { [256] = true }, -- Barrier
  [47788]  = { [257] = true }, -- Guardian Spirit
  [33206]  = { [256] = true }, -- Pain Suppression
  [740]    = { [105] = true }, -- Tranquility
  [29166]  = { [105] = true }, -- Innervate
  [108280] = { [264] = true }, -- Healing Tide
  [98008]  = { [264] = true }, -- Spirit Link
  [114052] = { [264] = true }, -- Ascendance
  [31821]  = { [65]  = true }, -- Aura Mastery
  [115310] = { [270] = true }, -- Revival
  [388615] = { [270] = true }, -- Restoral
  [363534] = { [1467]= true }, -- Rewind (Preservation)
  [421453] = { [256] = true }, -- Ultimate Penitence (Disc)
  [33891]  = { [105] = true }, -- Incarnation: Tree of Life
}

local SPELL_CLASS = {
  [740]    = "DRUID",
  [33891]  = "DRUID",
  [29166]  = "DRUID",
  [20484]  = "DRUID",
  [114052] = "SHAMAN",
  [108280] = "SHAMAN",
  [98008]  = "SHAMAN",
  [2825]   = "SHAMAN",
  [64843]  = "PRIEST",
  [47788]  = "PRIEST",
  [33206]  = "PRIEST",
  [62618]  = "PRIEST",
  [421453] = "PRIEST",
  [115310] = "MONK",
  [388615] = "MONK",
  [31821]  = "PALADIN",
  [363534] = "EVOKER",
  [51052]  = "DEATHKNIGHT",
  [61999]  = "DEATHKNIGHT",
  [80353]  = "MAGE",
  [196718] = "DEMONHUNTER",
  [20707]  = "WARLOCK",
}

local function ComputeHash()
  local _, playerClass = nil, nil
  if UnitClass then
    _, playerClass = UnitClass("player")
  end
  local ids = {}

  for spellID, enabled in pairs(TRACKED) do
    if enabled and SPELL_CLASS[spellID] == playerClass then
      if PlayerKnowsTrackedSpell(spellID) then
        ids[#ids+1] = tonumber(spellID)
      end
    end
  end

  table.sort(ids)
  local s = table.concat(ids, ",")
  return s == "" and "EMPTY" or s
end

local function EnsurePrefixes()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_SPELLS)
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_HANDSHAKE)
  elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(PREFIX_SPELLS)
    RegisterAddonMessagePrefix(PREFIX_HANDSHAKE)
  end
end

local function Send(prefix, msg, chan, target)
  if not chan then return end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(prefix, msg, chan, target)
  elseif SendAddonMessage then
    SendAddonMessage(prefix, msg, chan, target)
  end
end

local function Hello()
  local chan = PickChannel()
  if not chan then return end
  Send(PREFIX_HANDSHAKE, "HELLO;1.1.0;"..ComputeHash()..";"..ADDON_ID, chan)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

f:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_LOGIN" then
    EnsurePrefixes()
    C_Timer.After(1.0, Hello)
    return
  end

  if event == "GROUP_ROSTER_UPDATE" then
    C_Timer.After(0.25, Hello)
    return
  end

  if event == "SPELLS_CHANGED" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
    C_Timer.After(0.25, Hello)
    return
  end

  if event == "CHAT_MSG_ADDON" then
    local prefix, msg, channel, sender = ...
    if prefix ~= PREFIX_HANDSHAKE then return end
    if type(msg) ~= "string" then return end
    local cmd = strsplit(";", msg)
    if cmd == "PING" then
      if sender and sender ~= "" then
        Send(PREFIX_HANDSHAKE, "PONG;1.1.0;"..ComputeHash(), "WHISPER", sender)
      end
    end
    return
  end

  local unit, castGUID, spellID = ...
  if unit ~= "player" then return end
  spellID = tonumber(spellID)
  if not spellID or not TRACKED[spellID] then return end
  local chan = PickChannel()
  Send(PREFIX_SPELLS, tostring(spellID), chan)
end)
