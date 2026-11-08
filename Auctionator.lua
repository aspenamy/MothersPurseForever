-------------------------------------------------------------------------------
-- Auctionator support
--
-- Auctionator's Selling tab shows your bags as its own grid of buttons, one
-- per kind of item, each with a list of the bag slots it stands for. Marks
-- are drawn there too, so auction items glow on the Selling tab. When a
-- button covers several copies, it shows the auction mark if any of them is
-- marked for auction, and otherwise the mark on the first one. Runs behind
-- the safety switch in Hookups.lua.
-------------------------------------------------------------------------------

local _, ns = ...

local function MarkForEntry(info)
  if not (info and info.locations) then return nil end
  local first
  for i, loc in ipairs(info.locations) do
    if loc.IsBagAndSlot and loc:IsBagAndSlot() then
      local mark = ns.MarkToShow(loc:GetBagAndSlot())
      if mark == ns.AUCTION then return mark end
      if i == 1 then first = mark end
    end
  end
  return first
end

local hookup = ns.NewHookup("auctionator", "Auctionator",
  "Auctionator's Selling tab won't show marks or the auction glow")

ns.On("Loaded", function()
  if not (Auctionator and hookup:Start("Auctionator")) then return end
  local Mixin = AuctionatorGroupsViewItemMixin
  if not hookup:Require({
    { "AuctionatorGroupsViewItemMixin:SetItemInfo", Mixin and type(Mixin.SetItemInfo) == "function" },
  }) then return end

  local painted = setmetatable({}, { __mode = "k" })   -- buttons seen so far

  local function Paint(button)
    painted[button] = true
    ns.DrawMark(button, MarkForEntry(button.itemInfo))
  end

  -- The Selling tab's buttons are made the first time it opens, after this
  -- runs, so hooking the mixin covers all of them.
  hooksecurefunc(Mixin, "SetItemInfo", hookup:Guard(Paint))

  hookup:OnTurnOff(function()
    for button in pairs(painted) do ns.DrawMark(button, nil) end
  end)

  local Refresh = hookup:Guard(function()
    for button in pairs(painted) do
      if button:IsVisible() then Paint(button) end
    end
  end)
  ns.On("MarksChanged", Refresh)
  ns.On("SettingsChanged", Refresh)
end)
