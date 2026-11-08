-------------------------------------------------------------------------------
-- Mother's Purse Forever
--
-- The World of Warcraft: Forever build of Mother's Purse. Forever runs on the
-- same interface code as retail, so this is the retail addon with Forever's
-- bag numbers (see below) and without the BetterBags hookup, since BetterBags
-- has no Forever version.
--
-- Diablo-style item marking for your bags:
--   1. Hover an item and press Space to cycle it through junk, favorite and
--      back to regular. Shift+Space sets it aside for the auction house.
--   2. Marked items get a visual (Bags.lua): junk is greyed with a torn
--      slash, favorites get a blue bookmark, auction items a coin that glows
--      while the auction house is open. Works in Blizzard's bags and bank,
--      Baganator, Bagnon and Auctionator (one file each, all behind the
--      safety switch in Hookups.lua).
--   3. Blizzard's Sell All Junk button sells what you marked (Merchant.lua).
--      Grey items count as junk unless you mark them otherwise.
--
-- Space is only taken over while the mouse is on a bag item and you're out
-- of combat, so it jumps as normal everywhere else.
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

ns.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"

-- Marks stored per item. Anything not in the table is regular. REGULAR is
-- only stored to keep a grey item from being treated as junk automatically.
ns.JUNK, ns.FAVORITE, ns.AUCTION, ns.REGULAR = "junk", "fav", "auction", "regular"
ns.MARK_LABELS = { junk = "Junk", fav = "Favorite", auction = "Auction" }

-- Space steps through these in order, then back to regular.
local CYCLE = { ns.JUNK, ns.FAVORITE }

-- Backpack, the four bags and the reagent bag. Selling only looks here.
ns.FIRST_BAG = Enum.BagIndex.Backpack
ns.LAST_BAG = Enum.BagIndex.ReagentBag or NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5
-- Marks also work in the character bank and Warband bank tabs. Forever has 9
-- of each (bags 6 to 14 and 15 to 23), where retail has 6 and 5, so this
-- takes the last tab the client knows about. The keyring (bag -1) is left out:
-- keys can't be sold or put up for auction.
ns.LAST_BANK_BAG = Enum.BagIndex.AccountBankTab_9 or Enum.BagIndex.AccountBankTab_5 or ns.LAST_BAG

local DEFAULTS = {
  enabled    = true,
  key        = "SPACE",
  sellButton = true,
  hints      = true,   -- key hint lines at the bottom of bag item tooltips
  autoJunk   = true,   -- grey items count as junk unless marked otherwise
  sound      = true,   -- a sound when marking
  ahGlow     = true,   -- auction items glow while the auction house is open
  forgetDays = 90,     -- forget marks on gear not seen in this many days, 0 = never
}

local db
ns.callbacks = {}   -- name -> list of functions, filled by the other files

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

function ns.Print(msg, ...)
  if select("#", ...) > 0 then msg = msg:format(...) end
  print("|cff33ff99Mother's Purse|r: " .. msg)
end

function ns.On(name, fn)
  ns.callbacks[name] = ns.callbacks[name] or {}
  table.insert(ns.callbacks[name], fn)
end

-- An error in one callback is reported as usual but doesn't stop the rest,
-- so a problem in one addon's hookup can't take the others down with it.
local function Fire(name, ...)
  local n, args = select("#", ...), { ... }
  for _, fn in ipairs(ns.callbacks[name] or {}) do
    xpcall(function() fn(unpack(args, 1, n)) end, geterrorhandler())
  end
end

function ns.Settings() return db end

function ns.IsPlayerBag(bag)
  return type(bag) == "number" and bag >= ns.FIRST_BAG and bag <= ns.LAST_BAG
end

-- Bags plus the bank tabs.
function ns.IsMarkableBag(bag)
  return type(bag) == "number" and bag >= ns.FIRST_BAG and bag <= ns.LAST_BANK_BAG
end

-------------------------------------------------------------------------------
-- Which item a mark belongs to
--
-- Gear and other one-of-a-kind items are marked by GUID, so marking one ring
-- leaves an identical second ring alone, the way D4 does it. Stackable items
-- (herbs, potions) are marked by item ID, because splitting or merging a
-- stack can hand it a new GUID.
-------------------------------------------------------------------------------

local function ItemKey(bag, slot)
  local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
  if not (loc and loc:IsValid() and C_Item.DoesItemExist(loc)) then return nil end
  local itemID = C_Item.GetItemID(loc)
  if not itemID then return nil end

  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
  local equippable = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
  if not equippable then
    local maxStack = C_Item.GetItemMaxStackSizeByID(itemID)
    if not maxStack or maxStack > 1 then return "i:" .. itemID end
  end

  local guid = C_Item.GetItemGUID(loc)
  return guid and ("g:" .. guid) or ("i:" .. itemID)
end
ns.ItemKey = ItemKey

-- Grey items a vendor will buy are junk until you say otherwise.
local function AutoMark(bag, slot)
  if not db.autoJunk then return nil end
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
    return ns.JUNK
  end
end

function ns.GetMark(bag, slot)
  if not db then return nil end
  local key = ItemKey(bag, slot)
  if not key then return nil end
  local mark = db.marks[key]
  if mark == ns.REGULAR then return nil end
  return mark or AutoMark(bag, slot)
end

local function Today()
  return math.floor(time() / 86400)
end

local function StoreMark(bag, slot, mark)
  local key = ItemKey(bag, slot)
  if not key then return end
  if mark == nil and AutoMark(bag, slot) then
    mark = ns.REGULAR   -- remember that this grey item was unmarked on purpose
  end
  db.marks[key] = mark
  db.seen[key] = mark and Today() or nil
end

-- Pass nil for regular.
function ns.SetMark(bag, slot, mark)
  StoreMark(bag, slot, mark)
  Fire("MarksChanged")
end

-- Bag UIs that show several bag slots on one button (merged stacks) can add
-- a linker: fn(bag, slot) returns the other { bag, slot } pairs on
-- the same button, so marking the button marks all of them.
local slotLinkers = {}
function ns.AddSlotLinker(fn)
  table.insert(slotLinkers, fn)
end

local function LinkedSlots(bag, slot)
  local slots = { { bag, slot } }
  for _, fn in ipairs(slotLinkers) do
    for _, other in ipairs(fn(bag, slot) or {}) do
      if other[1] ~= bag or other[2] ~= slot then table.insert(slots, other) end
    end
  end
  return slots
end

-- Drop the mark once a one-of-a-kind item is gone for good (sold), so the
-- saved list doesn't keep every GUID ever marked. Marks by item ID stay.
function ns.ForgetGUID(guid)
  db.marks["g:" .. guid] = nil
  db.seen["g:" .. guid] = nil
end

-------------------------------------------------------------------------------
-- Forgetting old marks
--
-- Marks on gear belong to one copy, so once that copy is gone (mailed away,
-- disenchanted, traded, sold some other way) its mark would sit in the saved
-- file forever. Each mark remembers the last day it was seen in your bags or
-- bank, and marks on gear not seen for forgetDays are dropped. That's slow on
-- purpose: an item sitting on an alt, in the mail or on the auction house
-- keeps its mark until it's been gone that long.
--
-- Marks on stackable items (by item ID) are never forgotten. They mean "this
-- kind of item", so the next one you pick up is marked too.
-------------------------------------------------------------------------------

-- Note today against every marked item that's in your bags, or in the bank
-- while it's open.
local function NoteSeen()
  local today = Today()
  for bag = ns.FIRST_BAG, ns.LAST_BANK_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local key = C_Container.GetContainerItemID(bag, slot) and ItemKey(bag, slot)
      if key and db.marks[key] then db.seen[key] = today end
    end
  end
end

-- Once a day at most, on login.
local function ForgetOldMarks()
  local today = Today()
  if db.forgetDays <= 0 or db.lastForget == today then return end
  db.lastForget = today
  local forgotten = 0
  for key in pairs(db.marks) do
    if key:sub(1, 2) == "g:" then
      local seen = db.seen[key]
      if not seen then
        db.seen[key] = today   -- marked before this existed: start counting now
      elseif today - seen > db.forgetDays then
        db.marks[key], db.seen[key] = nil, nil
        forgotten = forgotten + 1
      end
    end
  end
  for key in pairs(db.seen) do
    if db.marks[key] == nil then db.seen[key] = nil end
  end
  if forgotten > 0 then
    ns.Print("forgot the marks on %d piece%s of gear you haven't had in %d days.",
      forgotten, forgotten == 1 and "" or "s", db.forgetDays)
  end
end

-- Bound items (soulbound, account-bound, quest items) can't go on the auction
-- house, so they can't be marked for it.
local UNTRADEABLE_BINDS = {
  [Enum.ItemBind.OnAcquire] = true,
  [Enum.ItemBind.Quest] = true,
  [Enum.ItemBind.ToWoWAccount] = true,
  [Enum.ItemBind.ToBnetAccount] = true,
  [Enum.ItemBind.ToBnetAccountUntilEquipped] = true,
}

function ns.CanAuction(bag, slot)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not info or info.isBound then return false end
  local bindType = select(14, C_Item.GetItemInfo(info.itemID))
  return not UNTRADEABLE_BINDS[bindType]
end

function ns.CountMarks()
  local counts = { junk = 0, fav = 0, auction = 0 }
  for _, mark in pairs(db.marks) do
    if counts[mark] then counts[mark] = counts[mark] + 1 end
  end
  return counts
end

function ns.ClearMarks(which)
  for key, mark in pairs(db.marks) do
    if which == nil or mark == which then db.marks[key], db.seen[key] = nil, nil end
  end
  Fire("MarksChanged")
end

-------------------------------------------------------------------------------
-- Marking the hovered item
-------------------------------------------------------------------------------

local function NextInCycle(mark)
  for i, m in ipairs(CYCLE) do
    if m == mark then return CYCLE[i + 1] end   -- nil after the last = regular
  end
  return CYCLE[1]   -- regular or auction start the cycle over at junk
end

local hovered   -- { bag = n, slot = n } while the tooltip shows a bag item

local function ShowError(msg)
  if UIErrorsFrame.AddExternalErrorMessage then
    UIErrorsFrame:AddExternalErrorMessage(msg)
  else
    UIErrorsFrame:AddMessage(msg, 1, 0.1, 0.1)
  end
end

local function MarkHovered(toggleAuction)
  if not hovered or InCombatLockdown() then return end
  local bag, slot = hovered.bag, hovered.slot
  local mark = ns.GetMark(bag, slot)
  if toggleAuction then
    -- Taking an auction mark off always works, even if the item has since bound.
    if mark ~= ns.AUCTION and not ns.CanAuction(bag, slot) then
      ShowError("That item can't be sold on the auction house.")
      return
    end
    mark = (mark ~= ns.AUCTION) and ns.AUCTION or nil
  else
    mark = NextInCycle(mark)
  end
  for _, other in ipairs(LinkedSlots(bag, slot)) do
    if mark ~= ns.AUCTION or ns.CanAuction(other[1], other[2]) then
      StoreMark(other[1], other[2], mark)
    end
  end
  Fire("MarksChanged")

  -- A coin for auction marks and a gem pickup for everything else.
  if db.sound and SOUNDKIT then
    PlaySound(mark == ns.AUCTION and SOUNDKIT.IG_BACKPACK_COIN_SELECT or SOUNDKIT.PICK_UP_GEMS)
  end

  -- Redraw the tooltip so its hint lines match the new mark.
  if GameTooltip:IsShown() and GameTooltip.RebuildFromTooltipInfo then
    pcall(GameTooltip.RebuildFromTooltipInfo, GameTooltip)
  end
end

-------------------------------------------------------------------------------
-- Hint lines at the bottom of the tooltip, like D4's "Mark as Junk"
-------------------------------------------------------------------------------

local SPACE_KEY_ICON = "|T" .. ns.MEDIA .. "SpaceKey:14:28|t"
local HINT_R, HINT_G, HINT_B = 0.85, 0.85, 0.85

local function KeyText()
  if db.key == "SPACE" then return SPACE_KEY_ICON end
  return "|cffffffff[" .. GetBindingText(db.key) .. "]|r"
end

local function AddHints(tooltip, bag, slot)
  local mark = ns.GetMark(bag, slot)
  local nextMark = NextInCycle(mark)
  local action = nextMark and ("Mark as " .. ns.MARK_LABELS[nextMark]:lower()) or "Unmark item"
  tooltip:AddLine(" ")
  tooltip:AddLine(KeyText() .. "  " .. action, HINT_R, HINT_G, HINT_B)
  if mark == ns.AUCTION then
    tooltip:AddLine("Shift + " .. KeyText() .. "  Remove auction mark", HINT_R, HINT_G, HINT_B)
  elseif ns.CanAuction(bag, slot) then
    tooltip:AddLine("Shift + " .. KeyText() .. "  Mark for auction", HINT_R, HINT_G, HINT_B)
  end
  -- Sell All Junk skips favorites, but a right-click at a vendor still sells
  -- them, so say so while one is open.
  if mark == ns.FAVORITE and MerchantFrame and MerchantFrame:IsShown() then
    tooltip:AddLine("Favorite. Right-clicking will still sell it.", 1, 0.3, 0.3, true)
  end
end

-- The override binding clicks this button. LeftButton is the cycle key,
-- RightButton is the same key with Shift held.
-- It has no size or anchor, so it never shows on screen.
local clicker = CreateFrame("Button", "MothersPurseClickButton", UIParent)
clicker:RegisterForClicks("AnyDown")   -- fire once per press, not on both down and up
clicker:SetScript("OnClick", function(_, mouseButton)
  MarkHovered(mouseButton == "RightButton")
end)

-------------------------------------------------------------------------------
-- Borrowing the key
--
-- While the tooltip shows an item in your bags, the key (Space by default)
-- and Shift+key are pointed at the clicker. The moment the tooltip clears or
-- hides, or combat starts, they go back to whatever they were. Bindings can't
-- change in combat, so marking is off until combat ends.
-------------------------------------------------------------------------------

local bindOwner = CreateFrame("Frame")
local bound = false

local function Release()
  hovered = nil
  if bound and not InCombatLockdown() then
    ClearOverrideBindings(bindOwner)
    bound = false
  end
end

local function Borrow()
  if bound or InCombatLockdown() then return end
  SetOverrideBindingClick(bindOwner, true, db.key, clicker:GetName(), "LeftButton")
  SetOverrideBindingClick(bindOwner, true, "SHIFT-" .. db.key, clicker:GetName(), "RightButton")
  bound = true
end

-- Ask the button under the tooltip which bag slot it shows. Each bag UI
-- names this differently:
--   Blizzard bank tabs  GetBankTabID / GetContainerSlotID
--   Bagnon              GetBag / GetID, and IsCached for other characters
--   Blizzard bags and Baganator  GetBagID / GetID
local function OwnerBagSlot(owner)
  if not owner then return end
  if owner.GetBankTabID and owner.GetContainerSlotID then
    return owner:GetBankTabID(), owner:GetContainerSlotID()
  end
  if owner.GetBag and owner.IsCached then
    if owner:IsCached() then return end
    return owner:GetBag(), owner:GetID()
  end
  if owner.GetBagID and owner.GetID then
    return owner:GetBagID(), owner:GetID()
  end
end

-- Find which bag slot the tooltip is describing, falling back to the item's
-- GUID. The item there has to match the tooltip, so a cached view of another
-- character's bags never marks the wrong thing.
local function TooltipBagSlot(tooltip, data)
  local ok, bag, slot = pcall(OwnerBagSlot, tooltip:GetOwner())
  if not (ok and ns.IsMarkableBag(bag) and slot) and data and data.guid then
    local found, loc = pcall(C_Item.GetItemLocation, data.guid)
    if found and loc and loc:IsBagAndSlot() then
      bag, slot = loc:GetBagAndSlot()
    end
  end
  if not (ns.IsMarkableBag(bag) and slot) then return end
  local itemID = C_Container.GetContainerItemID(bag, slot)
  if not itemID or (data and data.id and data.id ~= itemID) then return end
  return bag, slot
end

local function OnItemTooltip(tooltip, data)
  if tooltip ~= GameTooltip or not db or not db.enabled or InCombatLockdown() then return end
  local bag, slot = TooltipBagSlot(tooltip, data)
  if not bag then return end
  hovered = { bag = bag, slot = slot }
  Borrow()
  if db.hints then AddHints(tooltip, bag, slot) end
end

-- A tooltip refresh clears and refills it within the same frame, so wait a
-- frame before giving the key back. That avoids rebinding on every refresh.
local releasePending = false
local function OnTooltipCleared()
  hovered = nil
  if releasePending then return end
  releasePending = true
  C_Timer.After(0, function()
    releasePending = false
    if not hovered then Release() end
  end)
end

-------------------------------------------------------------------------------
-- Saved variables
-------------------------------------------------------------------------------

local function InitDB()
  MothersPurseForeverDB = MothersPurseForeverDB or {}
  db = MothersPurseForeverDB
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then db[k] = v end
  end
  if type(db.marks) ~= "table" then db.marks = {} end
  if type(db.seen) ~= "table" then db.seen = {} end       -- mark key -> day last seen
  if type(db.hookups) ~= "table" then db.hookups = {} end -- hookup id -> state (Hookups.lua)
  if type(db.key) ~= "string" or db.key == "" then db.key = DEFAULTS.key end
  if type(db.forgetDays) ~= "number" then db.forgetDays = DEFAULTS.forgetDays end
end

-- Called by the options page when a setting changes.
function ns.ApplySetting(key)
  if key == "key" or key == "enabled" then Release() end
  Fire("SettingsChanged", key)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local handlers = {}

handlers.ADDON_LOADED = function(name)
  if name ~= ADDON_NAME then return end
  InitDB()
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
  GameTooltip:HookScript("OnTooltipCleared", OnTooltipCleared)
  GameTooltip:HookScript("OnHide", Release)
  Fire("Loaded")
  if not db.shownWelcome then
    db.shownWelcome = true
    ns.Print("loaded. Hover an item in your bags and press %s to mark it as junk or a favorite, Shift+%s for auction. /purse for more.",
      GetBindingText(db.key), GetBindingText(db.key))
  end
end

-- Fires just before combat lockdown starts, the last chance to hand the key back.
handlers.PLAYER_REGEN_DISABLED = Release

-- Bags can still be filling in right after login, so wait a moment.
handlers.PLAYER_LOGIN = function()
  C_Timer.After(5, function()
    NoteSeen()
    ForgetOldMarks()
  end)
end

handlers.BANKFRAME_OPENED = function()
  C_Timer.After(1, NoteSeen)
end

-- Auction items glow while the auction house is open, Auctionator or not.
handlers.AUCTION_HOUSE_SHOW = function()
  ns.atAuctionHouse = true
  Fire("MarksChanged")
end
handlers.AUCTION_HOUSE_CLOSED = function()
  ns.atAuctionHouse = false
  Fire("MarksChanged")
end

local ev = CreateFrame("Frame")
for event in pairs(handlers) do ev:RegisterEvent(event) end
ev:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if h then h(...) end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function ShowHelp()
  local version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "?"
  local counts = ns.CountMarks()
  ns.Print("v%s. Hover a bag item: %s cycles junk, favorite, regular. Shift+%s toggles auction.",
    version, GetBindingText(db.key), GetBindingText(db.key))
  print(("  marked: %d junk, %d favorite, %d auction"):format(counts.junk, counts.fav, counts.auction))
  print("  /purse config - open the settings page")
  print("  /purse toggle - turn marking on or off")
  print("  /purse clear junk | fav | auction | all - remove marks")
  print("  /purse retry - turn hookups back on after they switched themselves off")
  for _, hookup in ipairs(ns.hookups) do
    if hookup.present then
      print(("  %s hookup: %s"):format(hookup.label, hookup:StatusText()))
    end
  end
end

SLASH_MOTHERSPURSE1 = "/purse"
SLASH_MOTHERSPURSE2 = "/motherspurse"
SlashCmdList.MOTHERSPURSE = function(input)
  local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  if cmd == "config" or cmd == "options" then
    ns.OpenOptions()
  elseif cmd == "toggle" then
    db.enabled = not db.enabled
    ns.ApplySetting("enabled")
    ns.Print("marking %s.", db.enabled and "on" or "off")
  elseif cmd == "retry" then
    ns.RetryHookups()
  elseif cmd == "clear" then
    local which = ({ junk = ns.JUNK, fav = ns.FAVORITE, favorite = ns.FAVORITE, auction = ns.AUCTION })[arg]
    if which then
      ns.ClearMarks(which)
      ns.Print("cleared %s marks.", ns.MARK_LABELS[which]:lower())
    elseif arg == "all" then
      ns.ClearMarks(nil)
      ns.Print("cleared all marks.")
    else
      ns.Print("use /purse clear junk, fav, auction or all.")
    end
  else
    ShowHelp()
  end
end
