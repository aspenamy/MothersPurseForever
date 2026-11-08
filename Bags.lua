-------------------------------------------------------------------------------
-- Marks drawn on item buttons
--
-- ns.PaintButton draws a mark on any item button, given the bag and slot it
-- shows. This file wires it into Blizzard's bags and bank, and Baganator.lua and
-- Bagnon.lua wire it into those addons.
--
-- Blizzard's bags redraw their slots in UpdateItems and the bank in each
-- button's Refresh, so the marks are drawn right after those. Blizzard also
-- resets the icon's grey when an item is locked or unlocked, so junk icons
-- get greyed again after each of those.
-------------------------------------------------------------------------------

local _, ns = ...

local DIM_ALPHA = 0.55
local SLASH_ALPHA = 0.85
local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"

-- parent defaults to the button. Baganator hands us a corner frame to hang
-- the overlay from, so the overlay hides whenever Baganator hides it.
function ns.GetOverlay(button, parent)
  local o = button.MothersPurseOverlay
  if o then return o end

  o = CreateFrame("Frame", nil, parent or button)
  o:SetAllPoints(button)
  o:SetFrameLevel(button:GetFrameLevel() + 2)   -- above the cooldown swipe

  o.dim = o:CreateTexture(nil, "ARTWORK")
  o.dim:SetAllPoints()
  o.dim:SetColorTexture(0, 0, 0, DIM_ALPHA)

  o.slash = o:CreateTexture(nil, "OVERLAY")
  o.slash:SetTexture(ns.MEDIA .. "Slash")
  o.slash:SetAllPoints()
  o.slash:SetAlpha(SLASH_ALPHA)

  o.bookmark = o:CreateTexture(nil, "OVERLAY")
  o.bookmark:SetTexture(ns.MEDIA .. "Bookmark")
  o.bookmark:SetSize(10, 10)
  o.bookmark:SetPoint("TOPLEFT", 1, 0)

  o.coin = o:CreateTexture(nil, "OVERLAY")
  o.coin:SetTexture(COIN)
  o.coin:SetSize(12, 12)
  o.coin:SetPoint("TOPRIGHT", -2, -2)

  -- Gold edge that breathes on auction items while the auction house is open.
  o.glow = o:CreateTexture(nil, "OVERLAY", nil, -1)
  o.glow:SetTexture(ns.MEDIA .. "Glow")
  o.glow:SetBlendMode("ADD")
  o.glow:SetPoint("TOPLEFT", -4, 4)
  o.glow:SetPoint("BOTTOMRIGHT", 4, -4)
  o.pulse = o.glow:CreateAnimationGroup()
  o.pulse:SetLooping("BOUNCE")
  local fade = o.pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.35)
  fade:SetDuration(0.8)
  fade:SetSmoothing("IN_OUT")

  button.MothersPurseOverlay = o
  return o
end

-- The mark to show for the item at bag/slot, or nil.
function ns.MarkToShow(bag, slot)
  local settings = ns.Settings()
  if settings and settings.enabled and bag and slot and ns.IsMarkableBag(bag) then
    return ns.GetMark(bag, slot)
  end
end

-- Draw (or clear) the mark for the item at bag/slot on this button. Pass a
-- nil bag for buttons that don't show a live item, like another character's
-- bags.
function ns.PaintButton(button, bag, slot)
  ns.DrawMark(button, ns.MarkToShow(bag, slot), bag, slot)
end

-- Draw a given mark on a button. bag and slot are optional and only used to
-- put the icon's grey back the way Blizzard had it.
function ns.DrawMark(button, mark, bag, slot)
  local settings = ns.Settings()
  local wasJunk = button.MothersPurseMark == ns.JUNK
  button.MothersPurseMark = mark

  if not mark and not button.MothersPurseOverlay then return end
  local o = ns.GetOverlay(button)
  o:SetFrameLevel(button:GetFrameLevel() + 2)
  local junk = mark == ns.JUNK
  o.dim:SetShown(junk)
  o.slash:SetShown(junk)
  o.bookmark:SetShown(mark == ns.FAVORITE)
  o.coin:SetShown(mark == ns.AUCTION)

  local glow = mark == ns.AUCTION and ns.atAuctionHouse and settings.ahGlow
  o.glow:SetShown(glow)
  if glow and not o.pulse:IsPlaying() then
    o.pulse:Play()
  elseif not glow then
    o.pulse:Stop()
  end

  local icon = GetItemButtonIconTexture(button)
  if icon then
    if junk then
      icon:SetDesaturated(true)
    elseif wasJunk then
      -- Back to however Blizzard had it.
      local info = bag and slot and C_Container.GetContainerItemInfo(bag, slot)
      icon:SetDesaturated(info and info.isLocked or false)
    end
  end
end

-------------------------------------------------------------------------------
-- Blizzard's bags
-------------------------------------------------------------------------------

local function PaintBagFrame(frame)
  if not frame.EnumerateValidItems then return end
  for _, button in frame:EnumerateValidItems() do
    ns.PaintButton(button, button:GetBagID(), button:GetID())
  end
end

local function EachContainerFrame(fn)
  if ContainerFrameCombinedBags then fn(ContainerFrameCombinedBags) end
  for i = 1, NUM_CONTAINER_FRAMES or 13 do
    local frame = _G["ContainerFrame" .. i]
    if frame then fn(frame) end
  end
end

-------------------------------------------------------------------------------
-- Blizzard's bank: character tabs and Warband tabs share one panel
-------------------------------------------------------------------------------

local function PaintBankButton(button)
  ns.PaintButton(button, button:GetBankTabID(), button:GetContainerSlotID())
end

local function RefreshShown()
  EachContainerFrame(function(frame)
    if frame:IsShown() then PaintBagFrame(frame) end
  end)
  if BankPanel and BankPanel:IsShown() and BankPanel.EnumerateValidItems then
    for button in BankPanel:EnumerateValidItems() do
      PaintBankButton(button)
    end
  end
end

ns.On("Loaded", function()
  EachContainerFrame(function(frame)
    if frame.UpdateItems then hooksecurefunc(frame, "UpdateItems", PaintBagFrame) end
  end)

  -- Bank buttons come from a pool and are created the first time the bank
  -- opens, so hooking the mixin now covers all of them.
  if BankPanelItemButtonMixin and BankPanelItemButtonMixin.Refresh then
    hooksecurefunc(BankPanelItemButtonMixin, "Refresh", PaintBankButton)
  end

  -- Locking an item (picking it up, a trade, a vendor sale in progress)
  -- un-greys its icon. Grey it again if it's marked junk.
  hooksecurefunc("SetItemButtonDesaturated", function(button)
    if button and button.MothersPurseMark == ns.JUNK then
      local icon = GetItemButtonIconTexture(button)
      if icon then icon:SetDesaturated(true) end
    end
  end)
end)

ns.On("MarksChanged", RefreshShown)
ns.On("SettingsChanged", RefreshShown)
