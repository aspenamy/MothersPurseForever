# Mother's Purse Forever

A World of Warcraft: Forever addon for ARPG/Diablo-style item marking in your
bags: hover an item and press a key. This is the Forever build of
[Mother's Purse](https://github.com/aspenamy/MothersPurse), which is for retail
WoW. Install the one that matches the game you play.

## What it does

- **Space marks the item under your mouse.** Each press steps through junk,
  favorite and back to regular. Shift+Space sets the item aside for the
  auction house, or takes it back off.
- **Marks show on the item.** Junk is greyed out with a torn slash across it,
  favorites get a blue bookmark in the top left corner, and auction items a
  gold coin in the top right.
- **The tooltip says what the key will do.** Hovering shows a line at the
  bottom of the tooltip like "Mark as junk" or "Unmark item".
- **Auction only where it makes sense.** Soulbound, account-bound and quest items
  can't be marked for auction. While the auction house is open, auction items
  glow in your bags and on Auctionator's Selling tab.
- **Grey items count as junk** unless you mark them as something else.
- **Space still jumps.** The key is only borrowed while your mouse is on a bag
  item and you're out of combat.
- **Blizzard's Sell All Junk sells your junk.** The vendor's Sell All Junk
  button sells what you marked as junk along with the grey items it always
  sells, 12 per click, so anything sold by mistake is still on the buyback
  tab. Favorites and auction items are never sold.
- **Exact items.** Gear is marked per copy, so marking one ring leaves an
  identical second ring alone. Stackable items like herbs are marked by type.
- **Settings page** under Options > AddOns > Mother's Purse Forever, or `/purse config`.
  Lets you pick a different key and turn each feature off.
- **Old marks are forgotten slowly.** Marks on gear you haven't had in your bags
  or bank for 90 days are dropped (adjustable, or never). Marks on stackable
  items like herbs are kept for good, so the next ones you pick up are marked
  too.

## Works with

- Blizzard's bags (combined or separate), bank and Warband bank.
- **Baganator.** Marks are drawn through a corner widget named Mother's Purse, so
  keep it in one of the corners under Baganator's icon settings. Mother's Purse is
  also a Baganator junk plugin, so Baganator's junk coin, grey icons and junk
  category follow your marks.
- **Bagnon**, for your own character's bags and bank.
- **Auctionator.** Marks also show on the Selling tab, so auction items glow
  there as well as in your bags.

Except for Baganator, these addons have no official way for other addons to do
this, so Mother's Purse works with their internals. If one of them updates and
something no longer matches, that hookup turns itself off and says so in chat
instead of misbehaving. Each one can also be turned off under Other addons on
the settings page, and `/purse retry` turns them back on.

Mother's Purse Forever hasn't been tested in game yet, and neither has its
support for Baganator, Bagnon and Auctionator on Forever, so if anything looks
wrong, please let us know. BetterBags support from the retail version is left
out because BetterBags doesn't have a Forever version.

## Commands

| Command | Effect |
|---|---|
| `/purse` | Show help and how many items are marked |
| `/purse config` | Open the settings page |
| `/purse toggle` | Turn marking on or off |
| `/purse clear junk / fav / auction / all` | Remove marks |
| `/purse retry` | Turn hookups back on after they switched themselves off |
