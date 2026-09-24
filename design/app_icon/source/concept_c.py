"""Concept C — "Afterburner": chase-camera rear view at dusk over mountains, twin burners lit."""
import random
from shapely.geometry import Polygon
from shapely.ops import unary_union
from shapely import affinity
from jet import rear_view

S = 70          # px per metre
CX, CY = 512, 488
BANK = -9      # degrees


def P(g):
    g = affinity.scale(g, xfact=S, yfact=-S, origin=(0, 0))
    g = affinity.rotate(g, BANK, origin=(0, 0))
    return affinity.translate(g, CX, CY)


def ridge(base_y, peaks, color_seed=0):
    pts = [(-40, 1100), (-40, base_y)]
    pts += peaks
    pts += [(1064, base_y), (1064, 1100)]
    return Polygon(pts)


def build():
    j = rear_view()
    body = P(j['body'])
    stabs = P(j['stabs']).difference(body)
    nozzles = P(j['nozzles'])
    burn = P(j['burn_outer'])
    core = P(j['burn_core'])
    canopy = P(j['canopy'])

    far = ridge(760, [(60, 700), (170, 640), (250, 690), (360, 600), (470, 675), (560, 630),
                      (660, 690), (770, 610), (880, 665), (980, 620)])
    near = ridge(860, [(40, 820), (150, 770), (240, 815), (330, 760), (440, 830), (560, 790),
                       (690, 845), (800, 780), (900, 820), (1000, 790)])

    return {
        'name': 'Afterburner',
        'fill': ('#161A4A', '#F28A3E'),
        'dark_fill': ('#07081A', '#5A2A1A'),
        'groups': [
            {'name': 'Terrain', 'glass': False, 'specular': False, 'translucency': False, 'layers': [
                {'file': '01_ridge_far.svg', 'geom': far, 'color': '#5B3A78', 'dark': {'color': '#2A1C3A'}},
                {'file': '02_ridge_near.svg', 'geom': near, 'color': '#2C2150', 'dark': {'color': '#140F24'}},
            ]},
            {'name': 'Jet', 'translucency_value': 0.15, 'lighting': 'combined', 'layers': [
                {'file': '03_stabilators.svg', 'geom': stabs, 'color': '#4A5470'},
                {'file': '04_airframe.svg', 'geom': body, 'color': '#2A3146'},
                {'file': '05_canopy.svg', 'geom': canopy, 'color': '#59647F'},
                {'file': '06_nozzles.svg', 'geom': nozzles, 'color': '#141826'},
            ]},
            {'name': 'Burners', 'translucency_value': 0.1, 'layers': [
                {'file': '07_burner.svg', 'geom': burn, 'color': '#FF7A1A'},
                {'file': '08_burner_core.svg', 'geom': core, 'color': '#FFE7A3'},
            ]},
        ],
    }
