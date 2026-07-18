# Steam upload (Plunk demo)

- **Demo App ID:** 4692020
- **Windows Depot ID:** 4692021

## 1. Build the Windows binary

From the repo root (needs the Windows export templates installed in Godot 4.6):

```
godot --headless --export-release "Windows Desktop"
```

This writes `builds/windows/Plunk.exe` (+ `Plunk.pck`). Both files must ship
together unless you enable "Embed PCK" in the export preset.

## 2. Upload with SteamPipe

Grab the Steamworks SDK and use the `steamcmd` it ships
(`sdk/tools/ContentBuilder/builder*/steamcmd`). steamcmd runs on macOS too, so
you can upload straight from this machine:

```
steamcmd +login <steamworks_account> \
         +run_app_build /Users/kjbrown/src/pleenko/steam/app_build_4692020.vdf \
         +quit
```

(First login prompts for Steam Guard.)

## 3. Set the build live

Steamworks → app 4692020 → **SteamPipe → Builds** → set the new build live on
the **Default** branch → **Publish**.

## 4. Launch option

Steamworks → **Installation → General** → add a launch option pointing at
`Plunk.exe` for Windows. Without this Steam won't know what to run.

> Paths in the `.vdf` files are absolute to this checkout. If the repo moves,
> update `contentroot` / `ContentRoot` / `buildoutput` accordingly.
