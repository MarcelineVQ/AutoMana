-- Name: AutoMana
-- License: LGPL v2.1

local DEBUG_MODE = false

local success = true
local failure = nil

local amcolor = {
  blue = format("|c%02X%02X%02X%02X", 1, 41,146,255),
  red = format("|c%02X%02X%02X%02X",1, 255, 0, 0),
  green = format("|c%02X%02X%02X%02X",1, 22, 255, 22),
  yellow = format("|c%02X%02X%02X%02X",1, 255, 255, 0),
  orange = format("|c%02X%02X%02X%02X",1, 255, 146, 24),
  red = format("|c%02X%02X%02X%02X",1, 255, 0, 0),
  gray = format("|c%02X%02X%02X%02X",1, 187, 187, 187),
  gold = format("|c%02X%02X%02X%02X",1, 255, 255, 154),
  blizzard = format("|c%02X%02X%02X%02X",1, 180,244,1),
}

local function colorize(msg,color)
  local c = color or ""
  return c..msg..FONT_COLOR_CODE_CLOSE
end

local function showOnOff(setting)
  local b = "d"
  return setting and colorize("On",amcolor.blue) or colorize("Off",amcolor.red)
end

local function amprint(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local function debug_print(text)
    if DEBUG_MODE == true then DEFAULT_CHAT_FRAME:AddMessage(text) end
end

-- Did an oom event fire
local oom = false

-- User Options
local defaults =
{
  enabled = true,
  combat_only = true,
  min_group_size = 10,
  use_tea = true,
  use_potion = false,
  use_rejuv = false,
  use_flask = false,
}

local consumables = {}

-- taken from supermacros
local function ItemLinkToName(link)
	if ( link ) then
    return gsub(link,"^.*%[(.*)%].*$","%1");
	end
end

local function hasAlchStone()
  return ItemLinkToName(GetInventoryItemLink("player",13)) == "Alchemists' Stone"
      or ItemLinkToName(GetInventoryItemLink("player",14)) == "Alchemists' Stone" or false
end

-- adapted from supermacros
local function RunLine(...)
	for k=1,arg.n do
		local text=arg[k];
        ChatFrameEditBox:SetText(text);
        ChatEdit_SendText(ChatFrameEditBox);
	end
end

-- adapted from supermacros
local function RunBody(text)
	local body = text;
	local length = strlen(body);
	for w in string.gfind(body, "[^\n]+") do
		RunLine(w);
	end
end

function FindItemById(item_id)
	if not item_id then return end
	for bag = 0,NUM_BAG_FRAMES do
		for slot = 1,MAX_CONTAINER_ITEMS do
			local link = GetContainerItemLink(bag,slot);
			if link then
        local _,_,id = string.find(link,"item:(%d+)")
				if id == item_id then
					return { bag = bag, slot = slot}
				end
			end
		end
	end
end

function consumeReady(which)
  if not which then return false end
  local start,dur = GetContainerItemCooldown(which.bag,which.slot)
  return GetTime() > start + dur
end

local last_fired = 0
function AutoMana(macro_body)
    local p = "player"
    local now = GetTime()
    local gcd_done = now > last_fired + 1.4 -- delay after item use or client gets real unhappy

    if not gcd_done then
      debug_print("On GCD Delay")
      return
    end

    if AutoManaSettings.enabled and gcd_done
      and (UnitAffectingCombat(p) or not AutoManaSettings.combat_only)
      and (max(1,max(GetNumRaidMembers(),GetNumPartyMembers())) >= AutoManaSettings.min_group_size) then

      local missing_mana = abs (UnitMana(p) - UnitManaMax(p))
      local missing_health = abs (UnitHealth(p) - UnitHealthMax(p))

      if AutoManaSettings.use_tea and (missing_mana > 1350) and consumeReady(consumables.tea) then
        debug_print("Trying Tea")
        UseContainerItem(consumables.tea.bag,consumables.tea.slot)
        oom = false
        last_fired = now
      elseif AutoManaSettings.use_rejuv and (missing_health > (consumables.has_alchstone and 2340 or 1760)) and consumeReady(consumables.rejuv) then
        debug_print("Trying Rejuv")
        UseContainerItem(consumables.rejuv.bag,consumables.rejuv.slot)
        oom = false
        last_fired = now
      elseif AutoManaSettings.use_potion and (missing_mana > (consumables.has_alchstone and 2992 or 2250)) and consumeReady(consumables.potion) then
        debug_print("Trying Potion")
        UseContainerItem(consumables.potion.bag,consumables.potion.slot)
        oom = false
        last_fired = now
      elseif AutoManaSettings.use_flask and oom and consumeReady(consumables.flask) then
        debug_print("Trying Flask")
        UseContainerItem(consumables.flask.bag,consumables.flask.slot)
        oom = false
        last_fired = now
      else
        debug_print("Running body")
        RunBody(macro_body)
      end
    else
      RunBody(macro_body)
    end
end

-------------------------------------------------

local AutoMana = CreateFrame("FRAME")

local function OnEvent()
  if event == "UI_ERROR_MESSAGE" and arg1 == "Not enough mana" then
    if AutoManaSettings.use_flask then oom = true end
  elseif event == "ADDON_LOADED" then
    if not AutoManaSettings
      then AutoManaSettings = defaults -- initialize default settings
      else -- or check that we only have the current settings format
        local s = {}
        for k,v in pairs(defaults) do
          s[k] = (AutoManaSettings[k] == nil) and defaults[k] or AutoManaSettings[k]
        end
        AutoManaSettings = s
    end
  elseif event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then -- alch stone
    consumables.has_alchstone = hasAlchStone()
  elseif event == "BAG_UPDATE" then -- consume slot update
    -- this should only actually search for the missing item
    consumables.tea = FindItemById("61675")
    if not consumables.tea then
      consumables.tea = FindItemById("15723")
    end
    consumables.potion = FindItemById("13444")
    consumables.rejuv = FindItemById("18253")
    consumables.flask = FindItemById("13511")
  end
end

local function handleCommands(msg,editbox)
  local args = {};
  for word in string.gfind(msg,'%S+') do table.insert(args,word) end
  if args[1] == "tea" then
    AutoManaSettings.use_tea = not AutoManaSettings.use_tea
    amprint("Use Tea: "..showOnOff(AutoManaSettings.use_tea))
  elseif args[1] == "pot" or args[1] == "potion" then
    AutoManaSettings.use_potion = not AutoManaSettings.use_potion
    amprint("Use Major Mana Potion: "..showOnOff(AutoManaSettings.use_potion))
  elseif args[1] == "rejuv" or args[1] == "rejuvenation" then
    AutoManaSettings.use_rejuv = not AutoManaSettings.use_rejuv
    amprint("Use Major Rejuvenation Potion: "..showOnOff(AutoManaSettings.use_rejuv))
  elseif args[1] == "flask" then
    AutoManaSettings.use_flask = not AutoManaSettings.use_flask
    amprint("Use Flask of Distilled Wisdom: "..showOnOff(AutoManaSettings.use_flask))
  elseif args[1] == "size" or args[1] == "group" then
    local n = tonumber(args[2])
    if n and n >= 0 then
      AutoManaSettings.min_group_size = n
      amprint("Active at minimum group size: "..n)
    else
      amprint("Usage: /automana size <non-negative number>")
    end
  elseif args[1] == "combat" then
    AutoManaSettings.combat_only = not AutoManaSettings.combat_only
    amprint("Use only in combat: "..showOnOff(AutoManaSettings.combat_only))
  elseif args[1] == "enabled" or args[1] == "enable" or args[1] == "toggle" then
    AutoManaSettings.enabled = not AutoManaSettings.enabled
    amprint("Addon enabled: "..showOnOff(AutoManaSettings.enabled))
  else -- make group size color by if you're in a big enough group currently
    amprint('AutoMana: Wrap a macro with AutoMana('..colorize("macro",amcolor.yellow)..') to auto-use consumes.')
    amprint('- Addon '..colorize("enable",amcolor.green)..'d [' .. showOnOff(AutoManaSettings.enabled) .. ']')
    amprint('- Active in ' .. colorize("combat",amcolor.green)..' only [' .. showOnOff(AutoManaSettings.combat_only) .. ']')
    amprint('- Active at minimum group ' .. colorize("size",amcolor.green) .. ' [' .. AutoManaSettings.min_group_size .. ']')
    amprint('- Use ' .. colorize("tea",amcolor.green) .. ' [' .. showOnOff(AutoManaSettings.use_tea) .. ']')
    amprint('- Use '.. colorize("pot",amcolor.green) .. 'ions at all [' .. showOnOff(AutoManaSettings.use_potion) .. ']')
    amprint('- Use Major ' .. colorize("rejuv",amcolor.green) .. 'enation Potion [' .. showOnOff(AutoManaSettings.use_rejuv) .. ']')
    amprint('- Use ' ..colorize("flask",amcolor.green) ..' of Distilled Wisdom [' .. showOnOff(AutoManaSettings.use_flask) .. ']')
  end
end

AutoMana:RegisterEvent("UI_ERROR_MESSAGE")
AutoMana:RegisterEvent("BAG_UPDATE")
AutoMana:RegisterEvent("UNIT_INVENTORY_CHANGED")
AutoMana:RegisterEvent("ADDON_LOADED")
AutoMana:SetScript("OnEvent", OnEvent)
  
SLASH_AUTOMANA1 = "/automana";
SlashCmdList["AUTOMANA"] = handleCommands
