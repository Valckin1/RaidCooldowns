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

local function ComputeHash()
  local ids = {}
  for id, enabled in pairs(TRACKED) do
    if enabled then ids[#ids+1] = tonumber(id) end
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

local function Send(prefix, msg, chan)
  if not chan then return end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(prefix, msg, chan)
  elseif SendAddonMessage then
    SendAddonMessage(prefix, msg, chan)
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

  if event == "CHAT_MSG_ADDON" then
    local prefix, msg, channel, sender = ...
    if prefix ~= PREFIX_HANDSHAKE then return end
    if type(msg) ~= "string" then return end
    local cmd = strsplit(";", msg)
    if cmd == "PING" then
      local chan = PickChannel()
      Send(PREFIX_HANDSHAKE, "PONG;1.1.0;"..ComputeHash(), chan)
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
