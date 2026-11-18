# Game bridge (Live mode)

`SolverBridge.gd` runs inside Buckshot Roulette and, on the player's turn,
sends the position to the solver server (`live.php`). The solver page
(with **Live** checked) follows the game automatically, and a short hint is
shown at the bottom of the game window. **F8** toggles the bridge.

- **Single-player only.** The bridge looks for the single-player
  `RoundManager`; multiplayer uses different scripts, so it stays idle there.
- **Only what the player knows is sent:** remaining live / blank counts, items,
  health, handcuffs, the saw, and what the player learned with their own
  Magnifying Glass / Burner Phone / Inverter. The hidden shell order is never
  read for the hint.
- **No game files are in this repository.** You build the patched game data
  from your own copy of the game.

## Building the patched game data

Tested with the Steam version (Godot 4.1.1) and
[GDRE Tools](https://github.com/GDRETools/gdsdecomp) v2.8.

1. Recover the project scripts from your copy of the game with GDRE Tools
   (`--recover`, `--scripts-only` is enough).
2. Copy `SolverBridge.gd` into the recovered `scripts/` folder.
3. Add two lines to the recovered scripts:
   - `scripts/GlobalVariables.gd`, first line of `_ready()`:
     ```gdscript
     add_child(load("res://scripts/SolverBridge.gd").new())
     ```
   - `scripts/BurnerPhone.gd`, in `SendDialogue()` right after the line that
     picks the text for the revealed shell type (inside `if (len != 1):`):
     ```gdscript
     sh.set_meta("solver_phone", [randindex, sequence[randindex]])
     ```
4. Build a separate PCK next to the game exe (the original exe is not modified):
   ```
   gdre_tools.exe --headless --pck-patch="<game>/Buckshot Roulette.exe"
     --output="<game>/Buckshot Roulette (solver).pck"
     --patch-file="<recovered>/scripts/SolverBridge.gd=res://scripts/SolverBridge.gd"
     --patch-file="<recovered>/scripts/BurnerPhone.gd=res://scripts/BurnerPhone.gd"
     --patch-file="<recovered>/scripts/GlobalVariables.gd=res://scripts/GlobalVariables.gd"
   ```
   Do not use an `.exe` output name without `--embed`: the output is a plain PCK.
5. Run the game with it (Steam must be running), e.g. via Steam launch options:
   ```
   --main-pack "Buckshot Roulette (solver).pck"
   ```
   or use `play_with_solver.bat` from the repository root.

After a game update, rebuild the PCK from the new exe.

## Server address

The bridge connects to `http://127.0.0.1:8000/live.php`. Start the PHP server
on `127.0.0.1` (not `localhost`): on Windows `localhost` may bind to IPv6 only.
