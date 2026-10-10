# Domination Dynasty: Turn-Based, tutorial notes

Research notes from one session of play (Google Play Games build, 2026-10-09): the opening
tutorial, the quest chain that follows, the flags tutorial and one round replay. Nothing beyond the
first hours is covered: no multiplayer, no city founding, no real combat outcomes. Numbers are
early-game values and may be inflated, discounted or scripted.

## Turn model
- Rounds are real-time and simultaneous: "Next Round: 54m 47s" counts down in the top-right, the
  round counter reads 15.
- Move orders are queued, not applied. The game says the move "will be executed simultaneously with
  the moves of all other players in the next round".
- Unit card shows a "Movement priority" number (2084 for a spearman), so resolution order is an
  explicit per-unit value. Same idea as Hexfare's priority-then-id.
- Between rounds you spend time on cities, research and expeditions, all of which are
  real-time timers that run alongside the round clock.

## Map and units
- Hex terrain. Resource and luxury tiles are cultivated to boost cities. Territory grows with
  city population.
- Unit card: tier, role tag (e.g. Anti-Cavalry), HP (800), attack (130), defence (130), range (1),
  movement (2), movement priority.
- Tapping a unit highlights reachable hexes in orange; tapping an enemy in range queues the attack.
- Neutral camps (skull + HP bar, 1000/1000) and "mystic ruins" sit near the capital as PvE targets.
- Barracks roster: Settler, Scout, Tribal Chief, Spearman, Archer, Collector, plus more below.
  Several are locked behind techs.
- Settler: civil, tier 1, 2 movement. Costs 1 crown and 1 round to train. The next one costs 15,
  so city count is gated by a steeply escalating currency.

## Economy
- Top bar: iron, horses (strategic), gold, gems (premium), science, crowns.
- City stockpiles are wood and stone, capped (10k each in the tutorial) and filling passively.
  Production is quoted per hour (Farm 200/h -> 400/h).
- City has a level and a "next citizen" bar (19/100). Food drives population growth.
- Buildings: Farm, Lumberjack, Stonemason, Storage, Market, Academy, Horse Stable, Blacksmith,
  Barracks, Harbor, and a fortress unlocked at level 5.
- Building upgrades cost wood + stone (Farm L1: 400/200, Barracks L1: 1000/500), deducted
  immediately, then run on a timer in a 5-slot queue. Queue entries can be cancelled or finished
  instantly for gems.
- Build-speed bonuses stack from research, flags, Golden Pass and morale (10% shown).
- Every building and tech level adds "Power", a score-like stat (+10 per building level, +12 for a
  treasure-hunter level).

## Research
- Branching tree of levelled techs (0/3, 0/5, 1/10) instead of one-shot techs. Units unlock as
  techs: Archery, Spear Fighter, Mining, Rams Spur, Transport Ships, Hand Axe, Farming,
  Treasure Hunter, Military Discipline.
- Each level costs gold + science and a timer (4s in the tutorial), with a gem "Finish" button.
- Queue shows several slots.

## PvE: mystic ruins and treasure hunters
- Ruins are expedition sites. One random chest of five tiers (wood, silver, gold, epic,
  legendary) is awarded. The loot table shows per-item chances (wood and stone 100%, science
  50%, gold 20%, crystals 20%, one unknown item).
- Treasure hunters are named units (Lumberjack Bob, level 1, +0% loot) who run a timed expedition
  (1m) and return with loot.

## Post-tutorial play (second pass, same session)
The round did not resolve during this part of the session. The round-resolution findings are in
the "Replay mode" section below.

### Quests and progressive UI
- Finishing the scripted tutorial opens a quest list (Challenges and Quests tabs). Main quests
  chain: claiming one reveals the next (barracks L1, farm L1, lumberjack L1, "explore a ruin 10
  times"). Each pays wood, stone, gold or food and has a GO button that jumps to the right screen.
- The HUD unlocks in stages: quest list, chat, research, cards, shop, chests, Golden Pass, then a
  menu with Profile, Inventory, Dynasty (clan or alliance) and Ranking.
- Buildings unlock by progression too (the Lumberjack appeared only after the earlier quests).
- Lumberjack L1: wood 500/h -> 1000/h for 150 wood + 300 stone, 4s timer, +10 Power.

### Combat preview (queued attack)
- Selecting a queued attack opens a preview: attacker total (spearman 189), strength breakdown
  (130 ranged strength, +65 against cavalry, a small forest penalty), defender HP (scout 165),
  damage dealt back (0, "is being bombed") and both movement priorities (mine 2084, scout 4796).
- Orders are drawn on the map (red arc for an attack, white chevrons for a move) and each has
  a cancel button next to a pause button.
- Attacks are labelled "ranged" even for a spearman at range 1.

### Collector
- Civil unit, no self-defence, tier 1, 2 movement, gives gold, wood and stone per hour
  (165 / 330 / 82). The map flags a unit standing on a tile with no resource ("NO RESOURCE").
- Priority 2088, right next to the spearman's 2084.

### Ruins, treasure hunters, Forge
- Ruin variants differ in loot: "Lost Palace" paid 7+ wood and stone, "Shadow Ruins" 14+.
- Treasure hunters have a level and XP (Bob 0/600 to level 2). A finished hunter waits until you
  collect, then can be restarted straight from the result dialog. The quest counter ticks per
  expedition.
- Chests go to an inventory called the Forge with three tabs: materials, chests, equipment.
  A Wood Chest gave 15 wood, 17 stone, 3 science, 1 Ruby Crystal and a Stone Spear.
- Equipment: 8 slots (helmet, gloves, chest, belt, weapon, legs, necklace, boots). Items have a
  rarity (Stone Spear: Common, 1 of 5 stars) and sit in a 5-tier line. Bonuses are class based
  (+5% melee strength for cavalry and anti-cavalry, +5% ranged strength for others). Items can
  be destroyed. A duplicate of an equal or higher item converts to materials. Materials upgrade
  items or add bonuses.

## Flags (third pass)
- Flags are a global collectible pool, equipped one per city. The screen is a grid: each row is
  an effect (pickaxe: wood and stone, then tower, horn, book, money bag, and more below), each
  column a rarity or colour tier (10 columns, the dull ones are locked or unowned), with an owned
  count under each flag.
- The lowest tier is a small flat percentage (green pickaxe: +2% wood and stone).
- Equipping takes a click on the flag, a click on the city's slot, then a confirm dialog. The
  dialog warns the city can't change flags for 24 hours, and the slot then shows a countdown
  (23h 59m). Equipping removes one from the pool (7 -> 6).
- Flags come from rewards, conquering cities, founding cities and progression.
- Flags add to the building-speed bonus panel ("Flags 0%") and the quest list tracked it
  ("Assign a flag to your city").
- Three more tabs sit on the same screen: Buildings (all-cities building levels and stockpiles),
  Units (per-city units, army size 3/8) and Crowns (craft crowns from stockpiles, with a slider
  for how much each city keeps back). All three are locked behind a Premium Membership.
- Observation (not tested): the city view showed "next citizen 1549/100" with a level 1 city,
  so growth looked blocked by something I didn't find.

## Replay mode (round resolution, fourth pass)
After a round resolves the next login opens in "REPLAY MODE" (header: round shown as 15/16, then
tick 1/6), with a tutorial ("your moves from the last round were executed as planned").
- The replay rewinds to the round's starting state and steps forward with a right arrow (and a
  left arrow back). The header shows the round and a tick counter. Round 16 resolved in 6 ticks.
  The tutorial round (15) showed 1 tick. What sets the tick count is a guess (possibly the longest move chain), unconfirmed.
- Each tick is a visible sub-step: units move hexes, labels appear over units ("COLLECTING IRON"
  on the collector at a mountain tile), and so on. Stepping past the last tick returns to PLAY MODE
  with the new round and a fresh countdown (58m after round 16, so rounds are about an hour).
- Between the pre-round state and the end of the replay: the enemy scout I had queued an attack on
  was gone, the collector sat on a mountain tile collecting iron, and my scout moved one hex per
  tick toward the north-east. The neutral camp was untouched (1000/1000), since I'd given it no
  order.
- The city's territory border grew by two hexes. A flag icon on the city banner is the trained
  settler, ready in the city after its 1-round training (not an equipped flag).
- Numbers before and after (not all from the round, since the user was also at the game):
  iron 171 -> 257, horses 176 -> 179, gold 3848 -> 3937, science 860 -> 868, Power 980 -> 1380,
  city value 876 -> 1277.
- What I did not see: the damage numbers of my attack, how same-hex conflicts are decided, or
  what ordering the priority numbers produce. The replay shows positions, not a combat log, so
  those need a round with an actual fight watched tick by tick.
- Worth borrowing: a replay that re-runs the stored orders tick by tick would be cheap in
  Hexfare, since resolution is deterministic and orders are saved. It doubles as a debugging tool.

## Onboarding style
- Two narrators (a builder woman for economy, a legionary for military), speech bubbles, a green
  arrow on the exact next control, and everything else blocked ("Easy there, cowboy! Finish the
  Tutorial first.").
- Early waits are shortened to seconds and the first gem-finish is free.
- Ends by handing off to a quest list with reward chests.

## Monetization hooks seen
- Gem "Finish" on research, construction and expeditions; Golden Pass in the bonus panel;
  1595 gems given at start.

## Things worth borrowing for Hexfare
- Per-unit movement priority as a visible number.
- Reachable-hex highlight, with attack targets selected in the same tap flow.
- Multi-level techs where a unit unlock is a tech.
- A queue panel with explicit slots.
- A combat preview that shows damage, retaliation, modifiers and priority before committing.
- A quest chain that doubles as the post-tutorial teaching path.
- Flags: a collectible per-city modifier pool with a re-equip cooldown. A natural fit for data in
  `data/*.json`, since each flag is only an effect and a tier.

## Things to avoid
- Gem-gated speed-ups (decided: Hexfare will not have them).

## Real-time rounds (decided)
- Hexfare will use real-time round timers like this game. The current manual turn advance is for
  testing only. Rounds must stay deterministic: the timer only decides *when* `resolve_turn`
  runs, never what it computes.
- Timers (decided: same as the game): construction and research run on wall-clock time, unit
  training is counted in rounds. Wall-clock timers need a deterministic rule for when they
  complete relative to round resolution (e.g. completion is evaluated at the round boundary).
