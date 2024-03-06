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
consumables.tea_nord = {name = "Nordanaar Herbal Tea", have = false, needs_update = true, cd_expired = false, bag_slot = {b = nil, s = nil}}
consumables.tea_sugar = {name = "Tea with Sugar", have = false, needs_update = true, cd_expired = false, bag_slot = {b = nil, s = nil}}
consumables.potion = {name = "Major Mana Potion", have = false, needs_update = true, cd_expired = false, bag_slot = {b = nil, s = nil}}
consumables.rejuv = {name = "Major Rejuvenation Potion", have = false, needs_update = true, cd_expired = false, bag_slot = {b = nil, s = nil}}
consumables.flask = {name = "Flask of Distilled Wisdom", have = false, needs_update = true, cd_expired = false, bag_slot = {b = nil, s = nil}}

-- We can't search by item id on 1.12, sad
local tea_nord,tea_sugar = "Nordanaar Herbal Tea","Tea with Sugar"
local potion = "Major Mana Potion"
local rejuv = "Major Rejuvenation Potion"
local alchstone = "Alchemists' Stone"
local flask = "Flask of Distilled Wisdom"


local function hasAlchStone()
  return ItemLinkToName(GetInventoryItemLink("player",13)) == alchstone
      or ItemLinkToName(GetInventoryItemLink("player",14)) == alchstone or false
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

-- taken from supermacros
local function UseItemByName(item)
	local bag,slot = FindItem(item);
	if ( not bag ) then return; end;
	if ( slot ) then
		UseContainerItem(bag,slot); -- use, equip item in bag
		return bag, slot;
	else
		UseInventoryItem(bag); -- unequip from body
		return bag;
	end
end

-- taken from supermacros
local function FindItem(item)
	if ( not item ) then return; end
	item = string.lower(ItemLinkToName(item));
	local link;
	-- for i = 1,23 do
	-- 	link = GetInventoryItemLink("player",i);
	-- 	if ( link ) then
	-- 		if ( item == string.lower(ItemLinkToName(link)) )then
	-- 			return i, nil, GetInventoryItemTexture('player', i), GetInventoryItemCount('player', i);
	-- 		end
	-- 	end
	-- end
	local count, bag, slot, texture;
	local totalcount = 0;
	for i = 0,NUM_BAG_FRAMES do
		for j = 1,MAX_CONTAINER_ITEMS do
			link = GetContainerItemLink(i,j);
			if ( link ) then
				if ( item == string.lower(ItemLinkToName(link))) then
					bag, slot = i, j;
					texture, count = GetContainerItemInfo(i,j);
					totalcount = totalcount + count;
				end
			end
		end
	end
	return bag, slot, texture, totalcount;
end

-- taken from supermacros
local function GetItemCooldown(item)
	local bag, slot = FindItem(item);
	if ( slot ) then
		return GetContainerItemCooldown(bag, slot);
	elseif ( bag ) then
		return GetInventoryItemCooldown('player', bag);
	end
end

-- taken from supermacros
local function ItemLinkToName(link)
	if ( link ) then
   	return gsub(link,"^.*%[(.*)%].*$","%1");
	end
end

local function updateConsume(k)
  local bag, slot = FindItem(k.name)
  if ( slot ) then
    k.have = true
    k.bag_slot.b = bag
    k.bag_slot.s = slot
    local s,d,b = GetContainerItemCooldown(bag, slot)
    k.cd_expired = d and (d - (GetTime() - s) < 0)
    debug_print(k.name)
    debug_print(tostring(k.have))
    debug_print(tostring(k.cd_expired))
    return success
  else
    k.have = false
    return failure
  end
end

local function tryConsume(con)
  if con.have and con.cd_expired then
    UseContainerItem(con.bag_slot.b,con.bag_slot.s)
    oom = false
    return success
  end
end

local function rdyConsume(k)
  updateConsume(k)
  return (k.have and k.cd_expired)
end

function AutoMana(macro_body)
    local p = "player"
    if AutoManaSettings.enabled
      and (UnitAffectingCombat(p) or not AutoManaSettings.combat_only)
      and (max(1,max(GetNumRaidMembers(),GetNumPartyMembers())) >= AutoManaSettings.min_group_size) then
      local has_stone = hasAlchStone()
      local missing_mana = abs (UnitMana(p) - UnitManaMax(p))
      local missing_health = abs (UnitHealth(p) - UnitHealthMax(p))
      local tea = (updateConsume(consumables.tea_nord) and consumables.tea_nord) or (updateConsume(consumables.tea_sugar) and consumables.tea_sugar)

      -- This is ugly but when I tried an if-fallthrough version the game didn't fire off the consumes consistently.
      if AutoManaSettings.use_tea and (missing_mana > 1750) and (tea and tea.cd_expired) then
        debug_print("Trying Tea")
        tryConsume(tea)
      elseif AutoManaSettings.use_rejuv and (missing_health > (has_stone and 2340 or 1760)) and rdyConsume(consumables.rejuv) then
        debug_print("Trying Rejuv")
        tryConsume(consumables.rejuv)
      elseif AutoManaSettings.use_potion and (missing_mana > (has_stone and 2992 or 2250)) and rdyConsume(consumables.potion)then
        debug_print("Trying Potion")
        tryConsume(consumables.potion)
      elseif AutoManaSettings.use_flask and oom and rdyConsume(consumables.flask)then
        debug_print("Trying Flask")
        tryConsume(consumables.flask)
      else
        RunBody(macro_body)
      end
    else
      RunBody(macro_body)
    end
end

-------------------------------------------------

local AutoMana = CreateFrame("FRAME")

local function OnEvent()
--   if event == "BAG_UPDATE" then
    -- checkConsumes()
  if event == "UI_ERROR_MESSAGE" and arg1 == "Not enough mana" then
    if AutoManaSettings.use_flask then oom = true end
  elseif event == "ADDON_LOADED" then
    AutoMana:UnregisterEvent("ADDON_LOADED")
    if not AutoManaSettings
      then AutoManaSettings = defaults -- initialize default settings
      else -- or check that we only have the current settings format
        local s = {}
        for k,v in pairs(defaults) do
          if AutoManaSettings[k] == nil -- specifically nil
            then s[k] = defaults[k]
            else s[k] = AutoManaSettings[k] end
        end
        AutoManaSettings = s
    end
  end
end

local function handleCommands(msg,editbox)
  local args = {};
  for word in string.gfind(msg,'%S+') do table.insert(args,word) end
  if args[1] == "tea" then
    AutoManaSettings.use_tea = not AutoManaSettings.use_tea
    amprint("Use Tea: "..showOnOff(AutoManaSettings.use_tea))
  elseif args[1] == "pot" then
    AutoManaSettings.use_potion = not AutoManaSettings.use_potion
    amprint("Use Major Mana Potion: "..showOnOff(AutoManaSettings.use_potion))
  elseif args[1] == "rejuv" then
    AutoManaSettings.use_rejuv = not AutoManaSettings.use_rejuv
    amprint("Use Major Rejuvenation Potion: "..showOnOff(AutoManaSettings.use_rejuv))
  elseif args[1] == "flask" then
    AutoManaSettings.use_flask = not AutoManaSettings.use_flask
    amprint("Use Flask of Distilled Wisdom: "..showOnOff(AutoManaSettings.use_flask))
  elseif args[1] == "size" then
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
  elseif args[1] == "enabled" then
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
-- AutoMana:RegisterEvent("BAG_UPDATE")
AutoMana:RegisterEvent("ADDON_LOADED")
AutoMana:SetScript("OnEvent", OnEvent)
  
SLASH_AUTOMANA1 = "/automana";
SlashCmdList["AUTOMANA"] = handleCommands
