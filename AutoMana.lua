-- Name: AutoMana
-- License: LGPL v2.1

local amcolor = {
  blue = format("|c%02X%02X%02X%02X", 1, 41,146,255),
  red = format("|c%02X%02X%02X%02X",1, 255, 0, 0),
  green = format("|c%02X%02X%02X%02X",1, 22, 255, 22)
}

local function colorize(msg,color)
  local c = color or ""
  return c..msg..FONT_COLOR_CODE_CLOSE
end

function showOnOff(setting)
  local b = "d"
  return setting and colorize("On",amcolor["blue"]) or colorize("Off",amcolor["red"])
end

local function amprint(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- Did an oom event fire
local oom = false

-- User Options
local defaults =
{
  combat_only = true,
  min_group_size = 10,
  use_potion = false,
  use_rejuv = false,
  use_flask = false,
}

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
	for i = 1,23 do
		link = GetInventoryItemLink("player",i);
		if ( link ) then
			if ( item == string.lower(ItemLinkToName(link)) )then
				return i, nil, GetInventoryItemTexture('player', i), GetInventoryItemCount('player', i);
			end
		end
	end
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

-- /run AutoMana("/cast Healing Wave")
-- Macro code:
function AutoMana(macro_body)
  local p = "player"
  if (UnitAffectingCombat(p) or not AutoManaSettings["combat_only"]) and (max(GetNumRaidMembers(),GetNumPartyMembers()) >= AutoManaSettings["min_group_size"]) then
    local has_stone = hasAlchStone()
    local missing_mana = abs (UnitMana(p) - UnitManaMax(p))
    local psb,pss,_ = FindItem(potion)
    local s1,d1,_ = GetContainerItemCooldown(psb,pss)
    local tsb,tss,_ = FindItem(tea_nord)
    if not tsb and not tss then tsb,tss,_ = FindItem(tea_sugar) end
    local s2,d2,_ = tss and GetContainerItemCooldown(tsb,tss)

    -- prefer tea first
    if (d2 and (d2-(GetTime()-s2) < 0)) and (missing_mana > 1750) then
      UseContainerItem(tsb,tss)
      oom = false
    elseif AutoManaSettings["use_potion"] and (d1 and (d1-(GetTime()-s1) < 0)) then
      local missing_health = abs (UnitHealth(p) - UnitHealthMax(p))
      -- prefer rejuv use for health
      -- This hp value is pro
      if AutoManaSettings["use_rejuv"] and (missing_health > (has_stone and 2340 or 1760)) then
        print("used rejuv")
        -- UseItemByName(rejuv)
        oom = false
      elseif (missing_mana > (has_stone and 2992 or 2250)) then
        -- UseContainerItem(psb,pss)
        print("used major mana")
        oom = false
      else -- no pot use? run the macro
        RunBody(macro_body)
      end
    elseif oom then
      UseItemByName("Flask of Distilled Wisdom")
      oom = false
    else
      RunBody(macro_body)
    end
  else
    RunBody(macro_body)
  end
end

local AutoMana = CreateFrame("FRAME")

local function OnEvent()
  if event == "UI_ERROR_MESSAGE" and arg1 == "Not enough mana" then
    if AutoManaSettings["use_flask"] then oom = true end
  elseif event == "ADDON_LOADED" then
    AutoMana:UnregisterEvent("ADDON_LOADED")
    -- initialize default settings
    if not AutoManaSettings then AutoManaSettings = defaults end
  end
end

local function handleCommands(msg,editbox)
  local args = {};
  for word in string.gfind(msg,'%S+') do table.insert(args,word) end

  if args[1] == "pot" then
    AutoManaSettings["use_potion"] = not AutoManaSettings["use_potion"]
    amprint("Use Major Man Potion: "..showOnOff(AutoManaSettings["use_potion"]))
  elseif args[1] == "rejuv" then
    AutoManaSettings["use_rejuv"] = not AutoManaSettings["use_rejuv"]
    amprint("Use Major Rejuvenation Potion: "..showOnOff(AutoManaSettings["use_rejuv"]))
  elseif args[1] == "flask" then
    AutoManaSettings["use_flask"] = not AutoManaSettings["use_flask"]
    amprint("Use Flask of Distilled Wisdom: "..showOnOff(AutoManaSettings["use_flask"]))
  elseif args[1] == "size" then
    local n = tonumber(args[2])
    if n and n >= 0 then
      AutoManaSettings["min_group_size"] = n
      amprint("Active at minimum group size: "..n)
    else
      amprint("Usage: /automana size <non-negative number>")
    end
  elseif args[1] == "combat" then
    AutoManaSettings["combat_only"] = not AutoManaSettings["combat_only"]
    amprint("Use only in combat: "..showOnOff(AutoManaSettings["combat_only"]))
  else -- make group size show number and also color by if you're in a big enough group currently
    amprint('AutoMana: Wrap a macro with AutoMana('..colorize("macro",amcolor["green"])..') to auto-use consumes.')
    amprint('- Active in combat only [' .. showOnOff(AutoManaSettings["combat_only"]) .. ']')
    amprint('- Active at minimum group size [' .. AutoManaSettings["min_group_size"] .. ']')
    amprint('- Use potions at all [' .. showOnOff(AutoManaSettings["use_potion"]) .. ']')
    amprint('- Use Major Rejuvenation Potion [' .. showOnOff(AutoManaSettings["use_rejuv"]) .. ']')
    amprint('- Use Flask of Distilled Wisdom [' .. showOnOff(AutoManaSettings["use_flask"]) .. ']')
  end
end

AutoMana:RegisterEvent("UI_ERROR_MESSAGE")
AutoMana:RegisterEvent("ADDON_LOADED")
AutoMana:SetScript("OnEvent", OnEvent)
  
SLASH_AUTOMANA1 = "/automana";
SlashCmdList["AUTOMANA"] = handleCommands
  