# Bláto Journal

A World of Warcraft addon for **WoW Forever**, made for a party of three friends who level together.
Deník postavy a všechny „partové" funkce v jednom okně – každá funkce je tlačítko.

## Co umí

Okno **Bláto Journal** (ikonka u minimapy nebo `/blato`) má klasický vzhled starého WoW (dialogový rámeček, pergamen; v nastavení jde přepnout na moderní) a tyto záložky:

| Záložka | Co tam je |
|---|---|
| **Commands** | Všechny funkce party jako tlačítka: statistiky večera (i kdo byl jak dlouho AFK), sdílení questů, šipky k trenérům a vendorům, místo srazu, alert karty, Group Check před dungeonem, threat, aukce a crafting, sázky, hlasování „One more quest?" a nastavení. Přepínače mají zaškrtávátko, najetí myší ukáže, co tlačítko dělá a jaký je to příkaz. |
| **Dungeons** | Addon **Dungeon Journal** od Exehn (CurseForge) (bossové, loot, questy, mapy) přímo v okně journalu. Instaluje se zvlášť, viz níže. |
| **Journey** | Co jste dokázali vy tři spolu: čas, společné questy, dungeony (runy, dokončení, bossové) a společné „poprvé“. Pod tím vlastní cesta postavy po levelech. |
| Places | Navštívené zóny a dungeony. |
| **Quests** | Odevzdané questy a u každého, kdo z vás tří ho splnil (✓), nesplnil (✗) nebo se ještě neví (?). Nahoře questy, které kamarádi mají a ty ne. |
| Notes | Poznámky s připomínkami („až vejdu do Undercity“). |

Většina funkcí party ožije, až když addon mají všichni tři. Spoluhráči jsou ti dva, se kterými máš nejvíc společného času ve skupině.

## Instalace

1. Stáhni nejnovější `BlatoJournal_vX.Y.Z.zip` z [Releases](../../releases).
2. Rozbal ho do složky `Interface/AddOns` instalace WoW Forever (vznikne `Interface/AddOns/BlatoJournal`).
3. Pro záložku Dungeons si zvlášť nainstaluj **Dungeon Journal** od Exehn z CurseForge (edici pro Forever). Jeho kód v tomhle repu není, protože nemá licenci, která by to dovolila.
4. Ve hře `/reload`.

## Příkazy

- `/blato` – otevře záložku Commands
- `/blato vote` – hlasování „One more quest?“ / „Bed time“
- `/blato help` – všechny příkazy party
- `/bj` nebo `/journal` – otevře deník, `/note` – rychlá poznámka

## Odkud to je

Bláto Journal spojuje dva addony a upravuje je:

- **ForeverJournal** od Ugge Zen (MIT, viz [LICENSES/ForeverJournal-MIT.txt](LICENSES/ForeverJournal-MIT.txt)) – deník, okno a jeho záložky (`BlatoJournal/Journal`, `Media`, `Art`, `Setup`).
- **One More Quest** od MadDadVibe (GPL-3.0) – funkce party (`BlatoJournal/Party`). Používá data z [Questie / QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0) a prahy skill-upů ze [SkillUp Forever](https://github.com/cjber/skillup-forever) od cjber (GPL-3.0).

Změny proti originálům:

- nová záložka **Commands** s tlačítky pro všechny funkce party (`BlatoJournal/Blato.lua`, `RenderBlato` v `Journal/UI.lua`);
- klasický vzhled (`UI.Chrome` v `Journal/UI.lua`, vlastní pergamen `Media/Parchment.tga`);
- záložka **Dungeons**, která zobrazí samostatně nainstalovaný Dungeon Journal v okně journalu;
- Journey o party tří (`J.Together` v `Journal/Fellowship.lua`) a u questů, kdo je splnil (`Together.lua`, zprávy JQD/JQH/JQA);
- bez záložek Goals a Fellowship (data o spoluhráčích se dál sbírají);
- statistika „Time AFK“ v Tonight in numbers;
- vynechané „pohodlí“ z One More Quest: automatické přijímání a odevzdávání questů, Shift-klik heal, Dad UI, chat filtr a průvodce;
- přejmenované globální názvy, uložená data a příkazy (`/blato`, `/bj`), takže Bláto Journal může být nainstalovaný vedle originálů;
- simulátor (`/blato sim`) má výchozí 2 spoluhráče a nikdy neposílá skutečnou poštu.

## Licence

GPL-3.0, viz [LICENSE](LICENSE). Části z ForeverJournal jsou pod MIT licencí, jejíž text je v [LICENSES/ForeverJournal-MIT.txt](LICENSES/ForeverJournal-MIT.txt).
