"""Compose preview SVGs (flat and faux-glass) and Icon Composer bundles from one spec."""
import json, os, math, shutil
from shapely.geometry import box
CLIP = box(-4, -4, 1028, 1028)
from iconlib import to_path_d, layer_svg, squircle_d, hex_to_icon_color, CANVAS

MASK_D = squircle_d()


def _lum(h):
    h = h.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _grad_def(gid, stops, x1=0.5, y1=0.0, x2=0.5, y2=1.0):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return (f'<linearGradient id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{s}</linearGradient>')


def layer_color(layer, appearance):
    if appearance == 'dark' and 'dark' in layer:
        return layer['dark'].get('color', layer['color']), layer['dark'].get('opacity', layer.get('opacity', 1))
    return layer['color'], layer.get('opacity', 1)


def preview_svg(spec, appearance='default', glass=True, size=1024, uid='p', tint='#3F8CFF', wallpaper=None):
    """appearance: default | dark | clear-light | clear-dark | tinted-light | tinted-dark"""
    fid = f"{uid}_{appearance}"
    defs = []
    bg = spec['fill'] if appearance != 'dark' else spec.get('dark_fill', spec['fill'])
    mono = appearance.startswith('clear') or appearance.startswith('tinted')
    if not mono:
        defs.append(_grad_def(f"bg_{fid}", [(0, bg[0]), (1, bg[1])], 0.5, 0, 0.5, spec.get('fill_stop', 1.0)))
        bg_fill = f"url(#bg_{fid})"
    # Filters for a light-touch Liquid Glass impression (preview only; the real effect comes from the OS)
    defs.append(f'''<filter id="glass_{fid}" x="-10%" y="-10%" width="120%" height="120%" color-interpolation-filters="sRGB">
  <feGaussianBlur in="SourceAlpha" stdDeviation="14" result="blur"/>
  <feOffset in="blur" dx="0" dy="14" result="off"/>
  <feComponentTransfer in="off" result="shadow"><feFuncA type="linear" slope="0.38"/></feComponentTransfer>
  <feMorphology in="SourceAlpha" operator="erode" radius="3" result="er"/>
  <feOffset in="er" dx="3" dy="4" result="erOff"/>
  <feComposite in="SourceAlpha" in2="erOff" operator="out" result="rim"/>
  <feGaussianBlur in="rim" stdDeviation="1.6" result="rimB"/>
  <feFlood flood-color="#ffffff" flood-opacity="0.85"/>
  <feComposite in2="rimB" operator="in" result="spec"/>
  <feMerge><feMergeNode in="shadow"/><feMergeNode in="SourceGraphic"/><feMergeNode in="spec"/></feMerge>
</filter>''')
    defs.append(f'<clipPath id="mask_{fid}"><path d="{MASK_D}"/></clipPath>')
    body = []
    if mono:
        dark = appearance.endswith('dark')
        tinted = appearance.startswith('tinted')
        if tinted:
            base = '#1c1c1e' if dark else '#f2f2f7'
            body.append(f'<rect width="1024" height="1024" fill="{base}"/>')
            if not dark:
                body.append(f'<rect width="1024" height="1024" fill="{tint}" fill-opacity="0.22"/>')
            else:
                body.append(f'<rect width="1024" height="1024" fill="{tint}" fill-opacity="0.10"/>')
        else:
            body.append(f'<rect width="1024" height="1024" fill="{"#000" if dark else "#fff"}" fill-opacity="{0.34 if dark else 0.30}"/>')
    else:
        body.append(f'<rect width="1024" height="1024" fill="{bg_fill}"/>')
    for gi, group in enumerate(spec['groups']):
        gshapes = []
        for layer in group['layers']:
            color, op = layer_color(layer, appearance)
            if mono:
                lum = _lum(color)
                # map luminance to a grey (clear) or a tint shade (tinted) so internal detail survives
                k = 0.45 + 0.55 * lum
                if appearance.startswith('tinted'):
                    th = tint.lstrip('#')
                    tr, tg, tb = (int(th[i:i + 2], 16) for i in (0, 2, 4))
                    mix = lambda ch: int(ch * (0.55 + 0.45 * k) + 255 * max(0.0, k - 0.8) * 1.2)
                    color = '#%02x%02x%02x' % tuple(min(255, mix(ch)) for ch in (tr, tg, tb))
                else:
                    g = int(255 * k)
                    color = '#%02x%02x%02x' % (g, g, g)
                op = op * 0.92
            d = to_path_d(layer['geom'].intersection(CLIP))
            gshapes.append(f'<path d="{d}" fill="{color}" fill-opacity="{op:.3f}" fill-rule="evenodd"/>')
        filt = f' filter="url(#glass_{fid})"' if glass and group.get('glass', True) else ''
        body.append(f'<g{filt}>' + "".join(gshapes) + '</g>')
    wall = ''
    if wallpaper:
        wall = wallpaper
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 1024 1024">'
           f'<defs>{"".join(defs)}</defs>{wall}<g clip-path="url(#mask_{fid})">{"".join(body)}</g></svg>')
    return svg


def write_layers(spec, outdir):
    os.makedirs(outdir, exist_ok=True)
    for group in spec['groups']:
        for layer in group['layers']:
            with open(os.path.join(outdir, layer['file']), 'w') as f:
                f.write(layer_svg([(layer['geom'].intersection(CLIP), layer['color'], 1.0)]))


def icon_json(spec):
    fill = {
        "linear-gradient": [hex_to_icon_color(spec['fill'][0], 'display-p3'),
                            hex_to_icon_color(spec['fill'][1], 'display-p3')],
        "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": spec.get('fill_stop', 1.0)}},
    }
    manifest = {}
    if 'dark_fill' in spec:
        dark = {
            "linear-gradient": [hex_to_icon_color(spec['dark_fill'][0], 'display-p3'),
                                hex_to_icon_color(spec['dark_fill'][1], 'display-p3')],
            "orientation": fill["orientation"],
        }
        manifest["fill-specializations"] = [{"value": fill}, {"appearance": "dark", "value": dark}]
    else:
        manifest["fill"] = fill
    groups = []
    # Icon Composer lists groups top (front) to bottom (back)
    for group in reversed(spec['groups']):
        layers = []
        for layer in reversed(group['layers']):
            L = {
                "image-name": layer['file'],
                "name": os.path.splitext(layer['file'])[0],
                "glass": layer.get('glass_layer', True),
                "position": {"scale": 1, "translation-in-points": [0, 0]},
            }
            if layer.get('opacity', 1) < 1:
                L["opacity"] = layer['opacity']
            if 'dark' in layer:
                dk = layer['dark']
                if 'color' in dk:
                    L["fill-specializations"] = [
                        {"value": "automatic"},
                        {"appearance": "dark", "value": {"solid": hex_to_icon_color(dk['color'], 'display-p3')}},
                    ]
                if 'opacity' in dk:
                    L["opacity-specializations"] = [
                        {"value": layer.get('opacity', 1)},
                        {"appearance": "dark", "value": dk['opacity']},
                    ]
                    L.pop("opacity", None)
            layers.append(L)
        g = {
            "name": group['name'],
            "layers": layers,
            "shadow": {"kind": group.get('shadow', 'neutral'), "opacity": group.get('shadow_opacity', 0.5)},
            "translucency": {"enabled": group.get('translucency', True), "value": group.get('translucency_value', 0.4)},
            "specular": group.get('specular', True),
        }
        if 'blur' in group:
            g["blur-material"] = group['blur']
        if 'lighting' in group:
            g["lighting"] = group['lighting']
        groups.append(g)
    manifest["groups"] = groups
    manifest["supported-platforms"] = {"squares": "shared"}
    return manifest


def write_bundle(spec, bundle_dir):
    if os.path.exists(bundle_dir):
        shutil.rmtree(bundle_dir)
    assets = os.path.join(bundle_dir, 'Assets')
    write_layers(spec, assets)
    with open(os.path.join(bundle_dir, 'icon.json'), 'w') as f:
        json.dump(icon_json(spec), f, indent=2)
