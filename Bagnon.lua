-------------------------------------------------------------------------------
-- Bagnon support
--
-- Bagnon is built on BagBrother, which has no plugin API for item visuals, so
-- the marks are drawn right after BagBrother updates each item. Items from
-- another character's bags (cached) don't get marks, since they aren't
-- really in your bags. Runs behind the safety switch in Hookups.lua.
-------------------------------------------------------------------------------

local _, ns = ...

local hookup = ns.NewHookup("bagnon", "Bagnon", "Bagnon won't show marks")

ns.On("Loaded", function()
  if not (BagBrother and hookup:Start("BagBrother")) then return end
  local Item = BagBrother.ContainerItem
  if not hookup:Require({
    { "BagBrother.ContainerItem:Update", Item and type(Item.Update) == "function" },
    { "BagBrother.ContainerItem:GetBag", Item and type(Item.GetBag) == "function" },
    { "BagBrother.ContainerItem:IsCached", Item and type(Item.IsCached) == "function" },
  }) then return end

  local painted = setmetatable({}, { __mode = "k" })   -- buttons seen so far

  local function Paint(button)
    painted[button] = true
    if button:IsCached() then
      ns.PaintButton(button, nil, nil)
    else
      ns.PaintButton(button, button:GetBag(), button:GetID())
    end
  end

  hooksecurefunc(Item, "Update", hookup:Guard(Paint))

  hookup:OnTurnOff(function()
    for button in pairs(painted) do ns.PaintButton(button, nil, nil) end
  end)

  local Refresh = hookup:Guard(function()
    for button in pairs(painted) do
      if button:IsVisible() then Paint(button) end
    end
  end)
  ns.On("MarksChanged", Refresh)
  ns.On("SettingsChanged", Refresh)
end)
