-- RaidCooldowns_ClientPlugin.lua
-- Install this only if you are not running the full RaidCooldowns tracker addon.
-- It silently broadcasts your tracked cooldown casts to the tracker.

local PREFIX_SPELLS = "RAIDCOOLDOWNS"
local PREFIX_HANDSHAKE = "RAIDCD_SENDER"
local ADDON_ID = "raidcooldowns_clientplugin"
local VERSION = "1.2.0"

local TRACKED = {
    -- Druid
    [740] = true,
    [33891] = true,
    [29166] = true,
    [20484] = true,

    -- Shaman
    [114052] = true,
    [108280] = true,
    [98008] = true,
    [207399] = true,
    [192077] = true,
    [2825] = true,

    -- Priest
    [64843] = true,
    [47788] = true,
    [33206] = true,
    [62618] = true,
    [271466] = true,
    [472433] = true,
    [421453] = true,

    -- Monk
    [115310] = true,
    [388615] = true,
    [443028] = true,

    -- Paladin
    [31821] = true,
    [31884] = true,

    -- Evoker
    [359816] = true,
    [363534] = true,
    [374227] = true,
    [390386] = true,

    -- Death Knight
    [51052] = true,
    [61999] = true,

    -- Hunter
    [272678] = true,
    [186265] = true,

    -- Mage
    [80353] = true,

    -- Warrior
    [97462] = true,
    [23920] = true,

    -- Demon Hunter
    [196718] = true,

    -- Warlock
    [20707] = true,
}

local HEALER_ONLY = {
    [740] = true,
    [29166] = true,
    [33891] = true,
    [108280] = true,
    [114052] = true,
    [98008] = true,
    [207399] = true,
    [64843] = true,
    [62618] = true,
    [271466] = true,
    [47788] = true,
    [33206] = true,
    [472433] = true,
    [421453] = true,
    [31821] = true,
    [359816] = true,
    [363534] = true,
    [374227] = true,
    [115310] = true,
    [388615] = true,
    [443028] = true,
}

local ALWAYS_VISIBLE = {
    [51052] = true,
    [61999] = true,
    [20484] = true,
    [20707] = true,
}

local NON_HEALER_SPELL_SPECS = {
    [2825] = { [262] = true, [263] = true, [264] = true },
    [80353] = { [62] = true, [63] = true, [64] = true },
    [196718] = { [577] = true, [581] = true },
    [51052] = { [250] = true },
    [20707] = { [265] = true, [266] = true, [267] = true },
    [390386] = { [1467] = true, [1468] = true, [1473] = true },
    [272678] = { [253] = true, [254] = true, [255] = true },
    [186265] = { [253] = true, [254] = true, [255] = true },
    [97462] = { [71] = true, [72] = true, [73] = true },
    [23920] = { [71] = true, [72] = true, [73] = true },
    [31884] = { [65] = true, [66] = true, [70] = true },
    [192077] = { [262] = true, [263] = true, [264] = true },
}

local SPEC_FILTER = {
    -- Priest
    [64843] = { [257] = true },
    [62618] = { [256] = true },
    [271466] = { [257] = true },
    [47788] = { [257] = true },
    [33206] = { [256] = true },
    [472433] = { [256] = true },
    [421453] = { [256] = true },

    -- Druid
    [740] = { [105] = true },
    [33891] = { [105] = true },
    [29166] = { [105] = true },

    -- Shaman
    [108280] = { [264] = true },
    [98008] = { [264] = true },
    [114052] = { [264] = true },
    [207399] = { [264] = true },

    -- Paladin
    [31821] = { [65] = true },

    -- Monk
    [115310] = { [270] = true },
    [388615] = { [270] = true },
    [443028] = { [270] = true },

    -- Evoker
    [359816] = { [1467] = true },
    [363534] = { [1467] = true },
    [374227] = { [1467] = true },
}

local SPELL_CLASS = {
    [740] = "DRUID",
    [33891] = "DRUID",
    [29166] = "DRUID",
    [20484] = "DRUID",
    [114052] = "SHAMAN",
    [108280] = "SHAMAN",
    [98008] = "SHAMAN",
    [207399] = "SHAMAN",
    [192077] = "SHAMAN",
    [2825] = "SHAMAN",
    [64843] = "PRIEST",
    [47788] = "PRIEST",
    [33206] = "PRIEST",
    [62618] = "PRIEST",
    [271466] = "PRIEST",
    [472433] = "PRIEST",
    [421453] = "PRIEST",
    [115310] = "MONK",
    [388615] = "MONK",
    [443028] = "MONK",
    [31821] = "PALADIN",
    [31884] = "PALADIN",
    [359816] = "EVOKER",
    [363534] = "EVOKER",
    [374227] = "EVOKER",
    [390386] = "EVOKER",
    [51052] = "DEATHKNIGHT",
    [61999] = "DEATHKNIGHT",
    [272678] = "HUNTER",
    [186265] = "HUNTER",
    [80353] = "MAGE",
    [97462] = "WARRIOR",
    [23920] = "WARRIOR",
    [196718] = "DEMONHUNTER",
    [20707] = "WARLOCK",
}

local function GetPlayerClassAndSpec()
    local playerClass = nil
    if UnitClass then
        _, playerClass = UnitClass("player")
    end

    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo and GetSpecializationInfo(specIndex) or nil

    return playerClass, specID
end

local function PlayerKnowsTrackedSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID then
        return false
    end

    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID) then
        return true
    end

    if IsPlayerSpell and IsPlayerSpell(spellID) then
        return true
    end

    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
        local index = 1
        while true do
            local info = C_SpellBook.GetSpellBookItemInfo(index, Enum.SpellBookSpellBank.Player)
            if not info then
                break
            end

            if tonumber(info.spellID) == spellID then
                return true
            end

            index = index + 1
        end
    elseif GetSpellBookItemInfo then
        local index = 1
        while true do
            local skillType, knownSpellID = GetSpellBookItemInfo(index, BOOKTYPE_SPELL)
            if not skillType then
                break
            end

            if tonumber(knownSpellID) == spellID then
                return true
            end

            index = index + 1
        end
    end

    return false
end

local function IsSpellAllowedForCurrentSpec(spellID, playerClass, specID)
    if SPELL_CLASS[spellID] ~= playerClass then
        return false
    end

    if ALWAYS_VISIBLE[spellID] then
        return true
    end

    if HEALER_ONLY[spellID] then
        return SPEC_FILTER[spellID] and specID and SPEC_FILTER[spellID][specID] or false
    end

    if NON_HEALER_SPELL_SPECS[spellID] then
        return specID and NON_HEALER_SPELL_SPECS[spellID][specID] or false
    end

    return false
end

local function PickChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid() then
        return "RAID"
    end
    if IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function EnsurePrefixes()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_SPELLS)
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_HANDSHAKE)
        return
    end

    if RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX_SPELLS)
        RegisterAddonMessagePrefix(PREFIX_HANDSHAKE)
    end
end

local function Send(prefix, msg, channel, target)
    if not channel then
        return
    end

    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
        return
    end

    if SendAddonMessage then
        SendAddonMessage(prefix, msg, channel, target)
    end
end

local function ComputeHash()
    local playerClass, specID = GetPlayerClassAndSpec()
    local ids = {}

    for spellID in pairs(TRACKED) do
        if IsSpellAllowedForCurrentSpec(spellID, playerClass, specID) and PlayerKnowsTrackedSpell(spellID) then
            ids[#ids + 1] = spellID
        end
    end

    table.sort(ids)

    local csv = table.concat(ids, ",")
    if csv == "" then
        return "EMPTY"
    end

    return csv
end

local function BroadcastHello()
    local channel = PickChannel()
    if not channel then
        return
    end

    Send(PREFIX_HANDSHAKE, "HELLO;" .. VERSION .. ";" .. ComputeHash() .. ";" .. ADDON_ID, channel)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        EnsurePrefixes()
        C_Timer.After(1.0, BroadcastHello)
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        C_Timer.After(0.25, BroadcastHello)
        return
    end

    if event == "SPELLS_CHANGED" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
        C_Timer.After(0.25, BroadcastHello)
        return
    end

    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix ~= PREFIX_HANDSHAKE or type(msg) ~= "string" then
            return
        end

        local cmd = strsplit(";", msg)
        if cmd == "PING" and sender and sender ~= "" then
            Send(PREFIX_HANDSHAKE, "PONG;" .. VERSION .. ";" .. ComputeHash(), "WHISPER", sender)
        end
        return
    end

    local unit, _, spellID = ...
    if unit ~= "player" then
        return
    end

    spellID = tonumber(spellID)
    if not spellID or not TRACKED[spellID] then
        return
    end

    local channel = PickChannel()
    Send(PREFIX_SPELLS, tostring(spellID), channel)
end)
