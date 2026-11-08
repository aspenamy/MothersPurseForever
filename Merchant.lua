-------------------------------------------------------------------------------
-- Selling junk at a vendor
--
-- Blizzard's Sell All Junk button sells every grey item at once and can't be
-- told to skip any or add others. While the "Sell marked junk with Sell All
-- Junk" setting is on, Mother's Purse takes over its click: it sells what you
-- marked as junk plus the grey items Blizzard would have sold, but never your
-- favorites or auction items, 12 per click. 12 is the size of the vendor's
-- buyback tab, so anything sold by mistake can still be bought back.
--
-- With the setting off, the button is Blizzard's again, and the best we can
-- do is warn when one of your favorites is grey.
-------------------------------------------------------------------------------

local _, ns = ...

local PER_CLICK = 12

local function ItemSellPrice(itemID)
  return select(11, C_Item.GetItemInfo(itemID)) or 0
end

local function IsGrey(info)
  return info.quality == Enum.ItemQuality.Poor and not info.hasNoValue
end

-- Calls fn(bag, slot, info, price) for each item the button sells: marked
-- junk, plus grey items that aren't favorites or marked for auction.
local function EachSellable(fn)
  for bag = ns.FIRST_BAG, ns.LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and not info.hasNoValue then
        local mark = ns.GetMark(bag, slot)
        if mark == ns.JUNK or (IsGrey(info) and mark ~= ns.FAVORITE and mark ~= ns.AUCTION) then
          local price = ItemSellPrice(info.itemID)
          if price > 0 and fn(bag, slot, info, price) == false then return end
        end
      end
    end
  end
end

local function JunkSummary()
  local count, total = 0, 0
  EachSellable(function(_, _, info, price)
    count = count + 1
    total = total + price * (info.stackCount or 1)
  end)
  return count, total
end

local function ReportSale(sold, earned, left)
  if sold > 0 then
    ns.Print("sold %d for %s.%s", sold, GetMoneyString(earned, true),
      left > 0 and (" %d more, click again to keep going."):format(left) or "")
  end
end

-- Sells up to limit items.
local function SellJunk(limit)
  -- Using an item away from a vendor would equip or open it instead.
  if not MerchantFrame:IsShown() then return end
  local queue, left = {}, 0
  EachSellable(function(bag, slot, info, price)
    if info.isLocked then return end
    if limit and #queue >= limit then
      left = left + 1
      return
    end
    table.insert(queue, {
      bag = bag, slot = slot, price = price, count = info.stackCount or 1,
      guid = C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot)),
    })
  end)
  if #queue == 0 then return end

  local earned = 0
  for _, item in ipairs(queue) do
    C_Container.UseContainerItem(item.bag, item.slot)
    if item.guid then ns.ForgetGUID(item.guid) end
    earned = earned + item.price * item.count
  end
  ReportSale(#queue, earned, left)
end

-------------------------------------------------------------------------------
-- Blizzard's Sell All Junk button
-------------------------------------------------------------------------------

local junkButton = MerchantSellAllJunkButton
local blizzardOnClick
local takenOver = false

local function WantTakeOver()
  local settings = ns.Settings()
  return settings and settings.enabled and settings.sellButton
end

local function OnClick()
  GameTooltip:Hide()
  SellJunk(PER_CLICK)
end

-- Matches the button's look to what a click would sell. Blizzard sets it from
-- its own grey count in MerchantFrame_Update, so this runs right after.
local function UpdateJunkButton()
  if not junkButton then return end
  local want = WantTakeOver() and true or false
  if want ~= takenOver then
    takenOver = want
    junkButton:SetScript("OnClick", want and OnClick or blizzardOnClick)
  end
  if not MerchantFrame:IsShown() then return end
  local hasJunk
  if takenOver then
    hasJunk = JunkSummary() > 0
  else
    hasJunk = C_MerchantFrame.GetNumJunkItems() > 0
  end
  junkButton.Icon:SetDesaturated(not hasJunk)
  junkButton:SetEnabled(hasJunk)
end

local function CountGreyFavorites()
  local count = 0
  for bag = ns.FIRST_BAG, ns.LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and IsGrey(info) and ns.GetMark(bag, slot) == ns.FAVORITE then
        count = count + 1
      end
    end
  end
  return count
end

-- Blizzard's OnEnter sets the tooltip's title, so this adds to it.
local function AddToTooltip(self)
  if not GameTooltip:IsOwned(self) then return end
  if takenOver then
    local count, total = JunkSummary()
    if count > 0 then
      GameTooltip:AddLine(("%d item%s, %s"):format(count, count == 1 and "" or "s", GetMoneyString(total, true)), 1, 1, 1)
    end
    GameTooltip:AddLine(("Sells your junk marks and grey items, up to %d per click, so you can buy any of them back. "
      .. "Favorites and auction items are never sold."):format(PER_CLICK), nil, nil, nil, true)
  else
    local count = CountGreyFavorites()
    if count > 0 then
      GameTooltip:AddLine(("This also sells %d grey item%s you marked as a favorite."):format(count, count == 1 and "" or "s"),
        1, 0.3, 0.3, true)
    end
  end
  GameTooltip:Show()
end

local function OnMerchantShow()
  UpdateJunkButton()
  local sellAllJunk = C_MerchantFrame.IsSellAllJunkEnabled and C_MerchantFrame.IsSellAllJunkEnabled()
  if not takenOver and sellAllJunk then
    local count = CountGreyFavorites()
    if count > 0 then
      ns.Print("%d of your favorites %s grey, so Blizzard's Sell All Junk button would sell %s.",
        count, count == 1 and "is" or "are", count == 1 and "it" or "them")
    end
  end
end

ns.On("Loaded", function()
  if not junkButton then return end
  blizzardOnClick = junkButton:GetScript("OnClick")
  hooksecurefunc("MerchantFrame_Update", UpdateJunkButton)
  junkButton:HookScript("OnEnter", AddToTooltip)

  local ev = CreateFrame("Frame")
  ev:RegisterEvent("MERCHANT_SHOW")
  ev:RegisterEvent("BAG_UPDATE_DELAYED")
  ev:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then OnMerchantShow() else UpdateJunkButton() end
  end)
  UpdateJunkButton()
end)

ns.On("MarksChanged", UpdateJunkButton)
ns.On("SettingsChanged", UpdateJunkButton)
