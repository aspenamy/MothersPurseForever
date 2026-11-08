-------------------------------------------------------------------------------
-- Baganator support
--
-- Baganator lets other addons hook in two ways, and Mother's Purse uses both:
--   * A corner widget, which Baganator calls whenever it draws an item. It
--     draws the marks the same way as in Blizzard's bags. It shows up as
--     "Mother's Purse" in Baganator's icon corner settings and has to stay in one
--     of the corners for the marks to show.
--   * A junk plugin, so Baganator's own junk features (grey icons, junk coin,
--     junk category and sorting) follow your marks. Favorites are never junk.
--     Pick it under Baganator's settings if another junk plugin is active.
--
-- Baganator can't unregister either one, so if the safety switch in
-- Hookups.lua turns this off, both just stop answering.
-------------------------------------------------------------------------------

local _, ns = ...

local ID, LABEL = "motherspurse", "Mother's Purse"

local hookup = ns.NewHookup("baganator", "Baganator",
  "Baganator won't show marks or use them for its junk features")

ns.On("Loaded", function()
  if not (Baganator and hookup:Start("Baganator")) then return end
  local API = Baganator.API
  if not hookup:Require({
    { "Baganator.API.RegisterCornerWidget", API and type(API.RegisterCornerWidget) == "function" },
    { "Baganator.API.RegisterJunkPlugin", API and type(API.RegisterJunkPlugin) == "function" },
    { "Baganator.API.RequestItemButtonsRefresh", API and type(API.RequestItemButtonsRefresh) == "function" },
  }) then return end

  -- The widget itself is an empty frame that holds the overlay, so when
  -- Baganator hides it (an emptied slot, a cached view) the marks go too.
  local function OnInit(itemButton)
    local holder = CreateFrame("Frame", nil, itemButton)
    holder:SetSize(1, 1)
    holder.mothersPurseButton = itemButton
    hookup:Safely(ns.GetOverlay, itemButton, holder)
    return holder
  end

  -- details.itemLocation only exists for live items, never for another
  -- character's bags. Returning false hides the holder, true shows it.
  local function Paint(holder, details)
    local loc = details and details.itemLocation
    local button = holder.mothersPurseButton
    if loc and loc.bagID then
      ns.PaintButton(button, loc.bagID, loc.slotIndex)
    else
      ns.PaintButton(button, nil, nil)
    end
    return button.MothersPurseMark ~= nil
  end

  local function OnUpdate(holder, details)
    local ok, show = hookup:Safely(Paint, holder, details)
    return ok and show or false
  end

  API.RegisterCornerWidget(LABEL, ID, OnUpdate, OnInit, { corner = "top_left", priority = 1 }, true)

  API.RegisterJunkPlugin(LABEL, ID, function(bagID, slotID)
    local ok, mark = hookup:Safely(ns.MarkToShow, bagID, slotID)
    return ok and mark == ns.JUNK
  end)

  local function Refresh()
    hookup:Safely(API.RequestItemButtonsRefresh)
  end
  hookup:OnTurnOff(function() API.RequestItemButtonsRefresh() end)
  ns.On("MarksChanged", Refresh)
  ns.On("SettingsChanged", Refresh)
end)
