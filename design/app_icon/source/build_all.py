import sys, os, json, shutil, cairosvg
sys.path.insert(0, '.')
from compose import write_bundle, icon_json, preview_svg
import concept_a, concept_b, concept_c
OUT = 'dist'
if os.path.exists(OUT): shutil.rmtree(OUT)
os.makedirs(OUT)
bundles = {'AppIcon.icon': concept_a, 'AppIcon-FlightPath.icon': concept_b, 'AppIcon-Afterburner.icon': concept_c}
for name, mod in bundles.items():
    spec = mod.build()
    write_bundle(spec, os.path.join(OUT, 'ToyFlightSimulator-AppIcon', name))
    # flat 1024 PNG fallback of the default appearance (no glass), useful for README / App Store previews
    svg = preview_svg(spec, 'default', glass=False, uid='flat')
    # full-bleed square (unmasked) for asset-catalog style fallback
    sq = svg.replace('clip-path="url(#mask_flat_default)"', '')
    cairosvg.svg2png(bytestring=sq.encode(), write_to=os.path.join(OUT, 'ToyFlightSimulator-AppIcon', name.replace('.icon', '-flat-1024.png')), output_width=1024, output_height=1024)
print(os.listdir(os.path.join(OUT, 'ToyFlightSimulator-AppIcon')))
