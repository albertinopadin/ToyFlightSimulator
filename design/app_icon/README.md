# App icon

The shipping icon is `ToyFlightSimulator Shared/AssetPipeline/AppIcon.icon`, an Icon Composer bundle.

- **Targets:** it builds into the **macOS** and **iOS** targets. Both targets already set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
- **Excluded targets:** the project file lists it as a membership exception for **tvOS**, because Icon Composer doesn't support tvOS. That target keeps its `tvOS App Icon & Top Shelf Image` brand assets. It is also excluded from **ToyFlightSimulatorTests**, the same way `Assets.xcassets` is.
- **Why the exceptions matter:** `ToyFlightSimulator Shared` is a synchronized folder, so keep both exceptions when you move or rename the bundle.

This folder is not part of any target. It holds:

| File | What it is |
|---|---|
| `AppIcon-FlightPath.icon` | Alternate B: a HUD flight-path marker over a banked horizon |
| `AppIcon-Afterburner.icon` | Alternate C: a chase-camera view at dusk over mountains |
| `*-flat-1024.png` | Unmasked, effect-free 1024 px renders of all three designs, for READMEs and store mockups |
| `source/` | The Python scripts that generate every layer SVG and `icon.json` |

To switch to an alternate, replace the contents of `AssetPipeline/AppIcon.icon` with it. Keep the bundle name `AppIcon.icon`.

## Regenerating

```sh
pip install shapely cairosvg
cd design/app_icon/source
python3 build_all.py   # writes dist/ToyFlightSimulator-AppIcon/*.icon
```

- Colors and layer grouping live in `concept_a.py` (the shipping icon), `concept_b.py` and `concept_c.py`.
- The stylized fighter geometry, in metres, is in `jet.py`.
- The layer SVGs use flat fills only. The background gradient, the Dark fill and the Liquid Glass settings are in `icon.json`, so Icon Composer can still adjust them.
