# AGENTS.md

## AGENTS.md Loading Budget

- Keep this root file limited to repository-wide invariants and precise routing gates; place detailed workflows in versioned documentation or skills.
- Codex applies a combined instruction budget (32 KiB by default) across global, root, and nested guidance. Keep mandatory gates first and preserve headroom for narrower scopes.
- Do not raise `project_doc_max_bytes` as the first response to oversized guidance; remove duplication and route conditional detail first.

## Client Assets Gate (Mandatory)

Any change touching client-assets auto-installation must preserve the runtime contract below:

1. **Final install paths must remain OTC-standard**
   - `data/things/<version>/`
   - `data/sounds/<version>/`
   - runtime extras in expected runtime locations (for example `bin/*` when distributed upstream)

2. **No alternate permanent source of truth**
   - Do not move runtime loading to `client-assets/` (or any new root) as the primary runtime path.
   - Temporary/cache directories are allowed only as transient staging, never as final runtime source.

3. **Security defaults stay strict unless explicitly justified**
   - `strictManifestSha256 = true`
   - `allowRawFallbackHashMismatch = false`

4. **Cross-platform build safety**
   - Android must not require unsupported `libarchive` linkage.
   - Desktop archive extraction behavior must remain functional.

5. **Verification required in PR description**
   - Explicitly state tested install paths and expected runtime load behavior.

Reference: `docs/client-assets-auto-install.md`

## Per-Kill Hot Paths

- An area spell that kills many monsters brings, in one frame, a text message, experience, capacity and inventory counts per corpse. Handlers of those signals (`g_game.onTextMessage`, `LocalPlayer` experience/level/capacity, `g_game.updateInventoryItems`, extended opcodes sent on kills or level ups) must not redo a whole window or list each time: update once on the next frame (`scheduleEvent(fn, 1)` behind a pending flag, as `game_skills`, the stats bar and `game_actionbar` do), or only when the window is visible (`game_ascensao`).
- Validate in the browser client: 30 monsters killed together with a normal character, `g_stats` per packet type before and after; the frame of the kills must not grow with what the change adds.

## Dead Creatures in Deferred Code

- A creature looked up by id after the moment it was sent (a scheduled event, an art's tick, a `later` callback) may have died: `g_map.getCreatureById` still finds it, `isDead()` is true and `getPosition()` is nil. Never hand that nil to the engine (`g_map.getTile`, `art.particles`, `art.play`): use `layerCreaturePosition(id)` in `game_skillshot`, or check `isDead()` and the position first.
- A C++ function that throws inside a call from Lua is raised as a Lua error after its catch block (`LuaInterface::luaCppFunctionCallback`, `lua_dofile`, `lua_loadfile`, `loadFiles`); raising it inside the catch closed the Windows client (LuaJIT unwinds with SEH). Keep any new `lua_error` out of catch blocks.
- Validate in the browser client: root a monster with Raízes Errantes (`exori tera vis`) and kill it while it is held; no "Lua exception" may follow in the log.

## Browser Voice Engine (`browser/voice/mythos-voice.js`)

- It is pasted into index.html inside the emscripten shell (`cmake/VoiceShell.cmake`): never three braces in a row, `</script`, or a line starting with `#` (emscripten preprocesses the shell). `shell.html` shows the crash screen on any uncaught page error: every engine callback goes through `safe()`.
- The game thread never waits on the page: commands with `MAIN_THREAD_ASYNC_EM_ASM`, events through `otc_voice_event` into a queue drained by `g_voice.poll()`. No new synchronous `MAIN_THREAD_EM_ASM` per frame.
- `TOGGLE_FRAMEWORK_VOICE` is ON by default in the WASM build (this engine) and on Windows (the native engine below); elsewhere OFF. Keep every voice line in `luafunctions.cpp`/`graphicalapplication.cpp` under `#ifdef FRAMEWORK_VOICE`.

## Native Voice Engine (`src/framework/voice/voiceengine_native.cpp`)

- Desktop engine: libopus, OpenAL Soft capture and playback, ixwebsocket. On by default on Windows (`VOICE_NATIVE`, opus from `vcpkg.json`); on Linux only when libopus is found, else the null engine (presence only).
- Everything runs on its own voz thread; the game thread only queues commands and drains events in `g_voice.poll()`. Never block the game thread on a device, a socket or a lock held by the voz thread.
- It opens its own OpenAL device and context through `ALC_EXT_thread_local_context`: never make it the process-wide current context (the game sound owns that).
- Code that MSVC has not compiled yet is checked with MinGW (`x86_64-w64-mingw32-g++-posix -std=c++20 -fsyntax-only`, with and without `framework/pch.h`). Include every standard header you use directly; MSVC's STL pulls in fewer headers than libstdc++.
- Validate: `tools/voz-native-test` (ASan and release builds, `run-tests.sh`, own relay on 127.0.0.1:7391), `luajit tools/voz-luatest/game_voice_test.lua`, and the Windows checklist in `docs/voz-windows.md`.
- Validate: in `browser/voice/test/`, `node lint.mjs --browser`, `node worklet.mjs`, `node bridge.mjs`, `node e2e.mjs` (local relay), and `luajit tools/voz-luatest/game_voice_test.lua`.

## Our Windows Look Like Tibia's

- The owner, 2026-11-27: every window of ours looks as if it were Tibia's own. The kit is `data/styles/50-breves.otui` (`MythosWindow`, `MythosButton`, `MythosTab`, `MythosTextEdit`, `MythosComboBox`, `MythosScrollBar`, `BrevesSection`, `BrevesList`, `BrevesRow`...): the names are ours, what they draw is Tibia's (stone window, grey buttons, captioned panels, sunken lists). The references are the client's copies of Tibia's windows: `game_questlog`, `game_highscore`, `game_cyclopedia`, `game_prey`. Look at one of them before laying out a window.
- A window brings no palette of its own: text `#c0c0c0`, captions and secondary text `#909090`, the chosen thing `#ffffff`, a sunken list `#404040` with contiguous rows and the chosen row `#585858`, a dark picture box `#1b1b1b`. Colour says a state only: green `#60f860`, orange `#f7a55f`, red `#f75f5f`. Rarity grades, elements and tiers keep their own colours. No title fonts (`ttf-font`), no gold or violet trim, no badge with a coloured background.
- Layout idioms: a list and its choice side by side, each in a `BrevesSection` (the right one captioned with the chosen thing: the Quest Log); what filters a list goes under it or in a box (a combo box, `Type to search`, a check box), never as header rows inside the list; facts as `name: value` lines; a `MythosSeparator` and the `Close` button at the bottom right, no X in the title bar.
- Hunts, Bosses and Quests are the pages of the teleports: `modules.game_brevespanel.attachHub(window, id, hide)` puts the strip of pages under the title bar and grows the window by its height. The Ranking is not one of them: it shows with no strip, opened from the Tools section of the bar.
- The Mythos bar over the action bar keeps its own look (the owner, 2026-11-27: "so deixe a barra antiga"): the gold-trimmed sections, their titles and buttons in `game_brevespanel/brevespanel.otui` up to `BrevesBar` are not converted to the kit, and the colours its badges get from the modules (`setFeatureState`) stay as they were. Only the strip of pages (`BrevesHubStrip`, `BrevesHubTab`) there is of the windows.
- The login form (`client_entergame/entergame.otui`, art in `/images/brevesui`) keeps the server's own art until the owner says otherwise.
- Buttons: the kit's (`MythosButton`, `MythosTab`) write in the window's Verdana at `text-offset: 0 0`; the base `Button` has the small button font at `0 2`, which sits low in a taller button. `text-auto-resize: true` takes the height from the text too: a button as wide as its word gets its height from a vertical padding (`padding: 5 14`), and keeps `text-offset: 0 0` in `$on`/`$pressed` or it grows a pixel when chosen. A row of a menu or a box that holds a picture is a `UIButton` with a background, not a `Button`. Inside a window the font is `verdana-11px-antialised`; `verdana-11px-rounded` (outlined) is for text over the game or over a bar.
- Two widgets anchored to each other (`a.right: b.left` and `b.top: a.top`) hang the client with "recursively anchored": anchor a scroll bar to the panel, not to the list that is anchored to it.

## Narrow Rules (recurring defects)

- `AttachedEffect` reads its duration only when it is attached: `setDuration` after `tile:attachEffect` does nothing. To end a skillshot layer early, schedule `detachArt` (`game_skillshot`).
- Client text is Latin-1 in both builds (the fonts draw one glyph per byte). Convert at the boundaries only: UTF-8 to Latin-1 for browser input and paste; Latin-1 to UTF-8 for anything sent to the site or put in JSON for it (`stdext::latin1_to_utf8`, `siteText` in `httplogin.cpp`, `CharacterList.siteText`). `data/locales/pt.lua` is cp1252.
- PT-BR text in a fixed-width window that does not wrap must fit the window's content width; measure it with the font's glyph widths (rightmost filled column + 1, `spacing` and `space-width` from the `.otfont`). A widget's text is clipped to the widget's rect moved by `text-offset`, so a checkbox label wider than `width - text-offset` runs over the next widget.
- `client_updater`: a same-version repair runs only against a manifest whose `versao` equals `versao.json`; an older manifest (a stale `main/` cache, a `-SemEnviar` test build) changes nothing. Every check goes through `getJSONWithin` (a deadline, then `HTTP.cancel`): the native HTTP client has one thread for every request. A periodic check reads only `<canal>/versao.json`; the commit and the manifest only when that number goes up, never twice for the same commit.
- A request a module sends by itself when the game starts waits `g_game.spreadDelay(min, max)` (gamelib), so a login rush does not bring every client's requests in the same second; calls of one burst come `SPREAD_STEP` apart.
- `client_assets`: a missing sprite sheet offers the download but never locks the player out ("Play anyway"; still missing after a download in the same session opens the game). Only missing core files (appearances, staticdata) are required.
- Heal Bot (`game_healbot`): every part of the tick (auto attack, spells, caster, potions, food) runs through `guarded` in `engine.lua`, so a fault in one never stops a heal; keep new parts behind it. A new setting goes in `defaults()` (`merge` reads only the keys the defaults have, so old saves keep working with no version bump) and `sanitize` clamps it. `engine.lua` and `data.lua` are Latin-1; `healbot.lua` and `healbot.otui` are ASCII.
- Extended opcode 139 is the client build report (`client_updater` -> server `scripts/custom/client_version.lua`); check the server's opcode list before taking a new number.

## Short updates on the site

- A change that affects how players play (mechanics, content, rewards, balance, a fixed behaviour, a new tool of the site; in the game, the client or the site) gets one line at the top of `docker/quickstart/myaac/plugins/brevesot/data/changelog.php` of the server repository, in the same push: date, area (`jogo`, `cliente` or `site`) and one sentence of at most 90 characters in Portuguese and in English. The site lists them at the top of its home page.
- Write what changed for the player, never file, function or commit names. Visual changes get no line (look, layout, colour, animation, sprite, wording), nor do refactors, builds, deploy scripts and staff tools; a security fix says no more than "more protection". Several commits of one change are one line. The rules are repeated at the top of that file.
- The long patch notes (`data/patches.php`, also the client's Novidades window) stay for the larger releases.
- News are written by us too, in `docker/quickstart/myaac/plugins/brevesot/data/news.php` (the owner does not post in the admin panel): an opening, an event, a large release, a change of rules, a maintenance. The newest goes at the top with the next id, in Portuguese and English, in the team's voice and with the layout that file describes.
