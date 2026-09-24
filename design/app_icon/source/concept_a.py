"""Concept A — "Raptor Climb": top-down stealth fighter banking up-right, twin contrails sweeping in."""
import math
from shapely.ops import unary_union
from shapely.geometry import Point
from shapely import affinity
from iconlib import place, ribbon, bezier, round_convex
from jet import planform

SCALE = 37.0      # px per metre
ANGLE = 42        # degrees clockwise from straight up
CX, CY = 566, 462  # where the jet's midpoint lands


def build():
    j = planform()

    def P(g):
        g = affinity.translate(g, 0, -j['length'] / 2)
        return place(g, SCALE, ANGLE, CX, CY)

    def pt(x, y):
        return list(P(Point(x, y)).coords)[0]

    body, tails, canopy, shade = P(j['body']), P(j['tails']), P(j['canopy']), P(j['shade'])

    # unit vectors in screen space
    a = math.radians(ANGLE)
    fwd = (math.sin(a), -math.cos(a))
    back = (-fwd[0], -fwd[1])

    # Afterburner flames behind each nozzle (in local coords, then placed)
    flames, cores, trails = [], [], []
    from shapely.geometry import Polygon as _Poly
    def teardrop(nx, y0, r, length):
        head = Point(nx, y0 + r * 0.6).buffer(r, 64)
        tail = _Poly([(nx - r * 0.93, y0 + r * 0.95), (nx + r * 0.93, y0 + r * 0.95), (nx, y0 + length)])
        return round_convex(unary_union([head, tail]), r * 0.25)
    for (nx, ny) in j['nozzles']:
        flames.append(P(teardrop(nx, ny - 0.1, 0.66, 3.2)))
        cores.append(P(teardrop(nx, ny + 0.05, 0.34, 1.95)))
        # contrail: starts just behind the flame, sweeps back and curves toward the bottom edge
        sx, sy = pt(nx, ny + 3.05)
        p0 = (sx, sy)
        p1 = (sx + back[0] * 200, sy + back[1] * 200)
        p2 = (sx + back[0] * 340 + 30, sy + back[1] * 340 + 200)
        p3 = (sx + back[0] * 360 + 80, sy + 860)
        trails.append(ribbon(bezier(p0, p1, p2, p3, 160), 16, 92))
    flames = unary_union(flames).difference(body)
    cores = unary_union(cores).difference(body)
    trails = unary_union(trails).difference(body.buffer(6))

    spec = {
        'name': 'Raptor Climb',
        'fill': ('#0B2F73', '#3A9BF0'),
        'dark_fill': ('#050B1C', '#10254A'),
        'groups': [
            {'name': 'Contrails', 'translucency_value': 0.5, 'layers': [
                {'file': '01_contrails.svg', 'geom': trails, 'color': '#FFFFFF', 'opacity': 0.6,
                 'dark': {'opacity': 0.34}},
            ]},
            {'name': 'Airframe', 'translucency_value': 0.2, 'lighting': 'combined', 'layers': [
                {'file': '02_afterburner.svg', 'geom': flames, 'color': '#FF7A1A'},
                {'file': '03_afterburner_core.svg', 'geom': cores, 'color': '#FFD35C'},
                {'file': '04_airframe.svg', 'geom': body, 'color': '#EEF2F7', 'dark': {'color': '#C9D2DE'}},
                {'file': '05_airframe_shade.svg', 'geom': shade, 'color': '#B7C3D1', 'dark': {'color': '#93A0B1'}},
                {'file': '06_tails.svg', 'geom': tails, 'color': '#7D8C9F', 'dark': {'color': '#66758A'}},
            ]},
            {'name': 'Canopy', 'translucency_value': 0.3, 'layers': [
                {'file': '07_canopy.svg', 'geom': canopy, 'color': '#F4B340'},
            ]},
        ],
    }
    return spec
