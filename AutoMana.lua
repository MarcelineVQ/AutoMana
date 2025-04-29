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
  use_healthstone = true,
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

-- Finds an item by either its numeric ID or its name, using string.find
-- @param consume     Optional table: { bag = b, slot = s } to check first
-- @param identifier  Number or string: item ID (e.g. 51916) or item name (e.g. "Healthstone")
-- @param bag         Optional bag index to search first (0‑4)
-- @return table { bag = b, slot = s } or nil
function AMFindItem(consume, identifier, bag)
  if not identifier then return end

  local searchID   = tonumber(identifier)
  local searchName = nil
  if not searchID then
    searchName = identifier
  end

  -- Helper: does this item link match our ID or name?
  local function linkMatches(link)
    -- extract item ID via string.find captures
    local _, _, idStr = string.find(link, "item:(%d+)")
    local id = idStr and tonumber(idStr)

    if searchID then
      return id == searchID
    else
      -- extract item name in brackets via string.find captures
      local _, _, name = string.find(link, "%[(.-)%]")
      -- exact match? partial?
      return name == searchName or (name and string.find(name, identifier))
    end
  end

  -- 1) check the consume slot if provided
  if consume and consume.bag and consume.slot then
    local link = GetContainerItemLink(consume.bag, consume.slot)
    if link and linkMatches(link) then
      return consume
    end
  end

  -- 2) scan a single bag
  local function SearchBag(b)
    for slot = 1, GetContainerNumSlots(b) do
      local link = GetContainerItemLink(b, slot)
      if link and linkMatches(link) then
        return { bag = b, slot = slot }
      end
    end
  end

  -- 3) search the specified bag first
  if bag then
    local result = SearchBag(bag)
    if result then return result end
  end

  -- 4) search all other bags
  for b = 0, 4 do
    if b ~= bag then
      local result = SearchBag(b)
      if result then return result end
    end
  end
end

function FindItemById(consume, item_id, bag)
  if not item_id then return end

  if consume then
    local link = GetContainerItemLink(consume.bag, consume.slot)
    if link then
      local _, _, id = string.find(link, "item:(%d+)")
      if id == item_id then
        return consume
      end
    end
  end

  -- Function to search a single bag for the item
  local function SearchBag(b)
    for slot = 1, GetContainerNumSlots(b) do
      local link = GetContainerItemLink(b, slot)
      if link then
        local _, _, id = string.find(link, "item:(%d+)")
        if id == item_id then
          return { bag = b, slot = slot }
        end
      end
    end
  end

  -- Search the specified bag first
  local result = bag and SearchBag(bag)
  if result then return result end

  -- Search other bags if not found
  for b = 0, 4 do
    if b ~= bag then
      result = SearchBag(b)
      if result then return result end
    end
  end
end

function consumeReady(which)
  if not which then return false end
  local start,dur = GetContainerItemCooldown(which.bag,which.slot)
  return GetTime() > start + dur
end

local last_fired = 0
function AutoMana(macro_body,fn)
  local fn = fn or RunBody
  local p = "player"
  local now = GetTime()
  local gcd_done = now > last_fired + 1.5 -- delay after item use before using another one or client gets unhappy, even if items have no gcd
  -- local gcd_done = true

  if AutoManaSettings.enabled and gcd_done
    and (UnitAffectingCombat(p) or not AutoManaSettings.combat_only)
    and (max(1,max(GetNumRaidMembers(),GetNumPartyMembers())) >= AutoManaSettings.min_group_size) then

    local hp = UnitHealth(p)
    local hp_max = UnitHealthMax(p)
    local missing_mana = abs (UnitMana(p) - UnitManaMax(p))
    local missing_health = abs (hp - hp_max)
    local health_perc = hp / hp_max
    local healthstone_threshold = (hp_max <= 5000 and health_perc < 0.5) or health_perc < 0.3

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
    elseif AutoManaSettings.use_healthstone and healthstone_threshold and consumeReady(consumables.healthstone) then
      debug_print("Trying Healthstone")
      UseContainerItem(consumables.healthstone.bag,consumables.healthstone.slot)
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
      fn(macro_body)
    end
  else
    fn(macro_body)
  end
end

-------------------------------------------------

local AutoManaFrame = CreateFrame("FRAME")

function AM_CastSpellByName(spell,a2,a3,a4,a5,a6,a7,a8,a9,a10)
  AutoMana(spell,function () AutoManaFrame.orig_CastSpellByName(spell,a2,a3,a4,a5,a6,a7,a8,a9,a10) end)
end

function AM_CastSpell(spell,a2,a3,a4,a5,a6,a7,a8,a9,a10)
  AutoMana(spell,function () AutoManaFrame.orig_CastSpell(spell,a2,a3,a4,a5,a6,a7,a8,a9,a10) end)
end

-- action bar buttons are spells too
function AM_UseAction(slot,a2,a3,a4,a5,a6,a7,a8,a9,a10)
  if AutoManaFrame.cachedSpells[GetActionTexture(slot)] then
    AutoMana(slot,function () AutoManaFrame.orig_UseAction(slot,a2,a3,a4,a5,a6,a7,a8,a9,a10) end)
  else
    AutoManaFrame.orig_UseAction(slot,a2,a3,a4,a5,a6,a7,a8,a9,a10)
  end
end

local orig_CastSpell = CastSpell
local orig_CastSpellByName = CastSpellByName
local orig_UseAction = UseAction

local function HookCasts(unhook)
  if unhook then -- not neccesary really
    CastSpell = orig_CastSpell
    CastSpellByName = orig_CastSpellByName
    UseAction = orig_UseAction
  else
    AutoManaFrame.orig_CastSpell = orig_CastSpell
    AutoManaFrame.orig_CastSpellByName = orig_CastSpellByName
    AutoManaFrame.orig_UseAction = orig_UseAction
    CastSpell = AM_CastSpell
    CastSpellByName = AM_CastSpellByName
    UseAction = AM_UseAction
  end
end
HookCasts() -- hook right now in case another addon does further hooks

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
    consumables.tea = AMFindItem(consumables.tea, "61675", arg1)
    if not consumables.tea then
      consumables.tea = AMFindItem(consumables.tea, "15723", arg1)
    end
    consumables.potion = AMFindItem(consumables.potion, "13444", arg1)
    consumables.rejuv = AMFindItem(consumables.rejuv, "18253", arg1)
    consumables.healthstone = AMFindItem(consumables.healthstone, "Healthstone", arg1)
    consumables.flask = AMFindItem(consumables.flask, "13511", arg1)
  elseif event == "PLAYER_ENTERING_WORLD" then -- spell cache
    AutoManaFrame.cachedSpells = {}
    -- Loop through the spellbook and cache player spells
    local function CacheSpellTextures(bookType)
      local i = 1
      while true do
        local spellTexture = GetSpellTexture(i, bookType)
        if not spellTexture then break end
        AutoManaFrame.cachedSpells[spellTexture] = true
        i = i + 1
      end
  end

  CacheSpellTextures(BOOKTYPE_SPELL)
  CacheSpellTextures(BOOKTYPE_PET)
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
  elseif args[1] == "stone" or args[1] == "healthstone" then
    AutoManaSettings.use_healthstone = not AutoManaSettings.use_healthstone
    amprint("Use Healthstone: "..showOnOff(AutoManaSettings.use_healthstone))
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
    amprint('AutoMana: Automatically use mana consumes.')
    amprint('- Addon '..colorize("enable",amcolor.green)..'d [' .. showOnOff(AutoManaSettings.enabled) .. ']')
    amprint('- Active in ' .. colorize("combat",amcolor.green)..' only [' .. showOnOff(AutoManaSettings.combat_only) .. ']')
    amprint('- Active at minimum group ' .. colorize("size",amcolor.green) .. ' [' .. AutoManaSettings.min_group_size .. ']')
    amprint('- Use ' .. colorize("tea",amcolor.green) .. ' [' .. showOnOff(AutoManaSettings.use_tea) .. ']')
    amprint('- Use Major Mana '.. colorize("pot",amcolor.green) .. 'ion [' .. showOnOff(AutoManaSettings.use_potion) .. ']')
    amprint('- Use Major ' .. colorize("rejuv",amcolor.green) .. 'enation Potion [' .. showOnOff(AutoManaSettings.use_rejuv) .. ']')
    amprint('- Use Health' .. colorize("stone",amcolor.green) .. ' [' .. showOnOff(AutoManaSettings.use_healthstone) .. ']')
    amprint('- Use ' ..colorize("flask",amcolor.green) ..' of Distilled Wisdom [' .. showOnOff(AutoManaSettings.use_flask) .. ']')
  end
end

AutoManaFrame:RegisterEvent("UI_ERROR_MESSAGE")
AutoManaFrame:RegisterEvent("BAG_UPDATE")
AutoManaFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
AutoManaFrame:RegisterEvent("ADDON_LOADED")
AutoManaFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
AutoManaFrame:SetScript("OnEvent", OnEvent)
  
SLASH_AUTOMANA1 = "/automana";
SlashCmdList["AUTOMANA"] = handleCommands
