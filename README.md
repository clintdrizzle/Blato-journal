# Bláto Journal

A World of Warcraft addon for **WoW Forever**, made for a party of three friends who level together.
A character journal and every party feature in one window, each feature a button.

## What it does

The **Bláto Journal** window (minimap button or `/blato`) looks like WoW Forever's own windows (the options also offer a parchment page and a classic look) and has these tabs:

| Tab | What is on it |
|---|---|
| **Commands** | Every party feature as a button: tonight's statistics (including who was AFK and for how long), quest sharing, arrows to trainers and vendors, a meeting point, alert cards, the Group Check before a dungeon, threat, auction house and crafting helpers, bets, the "One more quest?" vote and the options. Switches have a check box; hovering a button shows what it does and its command. |
| **Dungeons** | The addon **Dungeon Journal** by Exehn (CurseForge): bosses, loot, quests and maps, shown right inside the journal window. It is installed on its own, see below. |
| **Journey** | What the three of you have done together: time, shared quests, dungeons (runs, clears, bosses) and the firsts you shared. Below that, your own character's path, level by level. |
| Places | The zones and dungeons you have visited. |
| **Quests** | The quests you handed in, and for each one who of the three of you has done it (✓), has not (✗) or is not known yet (?). On top: quests your friends have done and you have not. |
| Notes | Notes with reminders ("when I enter Undercity"). |

Most party features come alive when all three of you run the addon. Your party mates are the two players you have spent the most time grouped with.

## Install

1. Download the latest `BlatoJournal_vX.Y.Z.zip` from [Releases](../../releases).
2. Unzip it into the `Interface/AddOns` folder of your WoW Forever installation (this gives `Interface/AddOns/BlatoJournal`).
3. For the Dungeons tab, install **Dungeon Journal** by Exehn from CurseForge separately (the edition for Forever). Its code is not in this repository: it has no license that would allow that.
4. Type `/reload` in the game.

## Commands

- `/blato` opens the Commands tab
- `/blato sleep` starts the "One more quest?" / "Bed time" vote
- `/blato help` lists every party command
- `/bj` or `/journal` opens the journal, `/note` writes a quick note

## Where it comes from

Bláto Journal joins two addons and changes them:

- **ForeverJournal** by Ugge Zen (MIT, see [LICENSES/ForeverJournal-MIT.txt](LICENSES/ForeverJournal-MIT.txt)): the journal, its window and tabs (`BlatoJournal/Journal`, `Media`, `Art`, `Setup`).
- **One More Quest** by MadDadVibe (GPL-3.0): the party features (`BlatoJournal/Party`). It uses data from [Questie / QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0) and the skill-up thresholds of [SkillUp Forever](https://github.com/cjber/skillup-forever) by cjber (GPL-3.0).

Changes from the originals:

- a new **Commands** tab with buttons for every party feature (`BlatoJournal/Blato.lua`, `BJ.RenderCommands` in `Journal/UI.lua`);
- a classic look as an extra style (`UI.Chrome` in `Journal/UI.lua`, its own parchment `Media/Parchment.tga`);
- a **Dungeons** tab that shows the separately installed Dungeon Journal inside the journal window;
- a Journey about the party of three (`J.Together` in `Journal/Fellowship.lua`) and, on the Quests page, who has done each quest (`Together.lua`, messages JQD/JQH/JQA);
- no Goals and no Fellowship tab (party mates are still recorded);
- "Time AFK" in tonight's statistics;
- left out from One More Quest: automatic quest accepting and turn-in, Shift-click heals, the Dad UI, the chat filter and the guided tour;
- renamed globals, saved variables and commands (`/blato`, `/bj`), so Bláto Journal can be installed next to the originals;
- the simulator (`/blato sim`) starts with 2 party mates and never sends real mail.

## License

GPL-3.0, see [LICENSE](LICENSE). The parts from ForeverJournal are under the MIT license, whose text is in [LICENSES/ForeverJournal-MIT.txt](LICENSES/ForeverJournal-MIT.txt).
