"""Concept B — "Flight Path": HUD flight-path marker over a banked horizon (attitude indicator)."""
import math
from shapely.geometry import Point, LineString, Polygon, box
from shapely.ops import unary_union
from shapely import affinity

BANK = -16  # degrees; negative = right wing down as seen by the pilot


def build():
    cx, cy = 512, 512
    # Ground: everything below a tilted horizon line through (cx, cy+70)
    hy = cy + 40
    ground = Polygon([(-600, hy), (1624, hy), (1624, 2000), (-600, 2000)])
    ground = affinity.rotate(ground, BANK, origin=(cx, hy))

    # Pitch ladder rung (+10°) parallel to horizon, split for the marker
    rung_y = hy - 262
    t = 30
    left = box(cx - 330, rung_y - t / 2, cx - 150, rung_y + t / 2).union(box(cx - 330, rung_y - t / 2, cx - 330 + t, rung_y + 70))
    right = box(cx + 150, rung_y - t / 2, cx + 330, rung_y + t / 2).union(box(cx + 330 - t, rung_y - t / 2, cx + 330, rung_y + 70))
    ladder = affinity.rotate(unary_union([left, right]), BANK, origin=(cx, hy))
    ladder = ladder.buffer(6, join_style=1).buffer(-6, join_style=1)

    # Flight-path marker ("velocity vector"): ring + wings + tail, level with the aircraft
    R, w = 112, 40
    ring = Point(cx, cy).buffer(R, 128).difference(Point(cx, cy).buffer(R - w, 128))
    wing_len = 170
    wings = unary_union([
        LineString([(cx - R + 4, cy), (cx - R - wing_len, cy)]).buffer(w / 2, cap_style=1),
        LineString([(cx + R - 4, cy), (cx + R + wing_len, cy)]).buffer(w / 2, cap_style=1),
    ])
    tail = LineString([(cx, cy - R + 4), (cx, cy - R - 92)]).buffer(w / 2, cap_style=1)
    fpm = unary_union([ring, wings, tail])

    return {
        'name': 'Flight Path',
        'fill': ('#0E4FB8', '#5DB8FF'),
        'dark_fill': ('#04142F', '#0E2C57'),
        'groups': [
            {'name': 'Ground', 'glass': False, 'specular': False, 'layers': [
                {'file': '01_ground.svg', 'geom': ground, 'color': '#8A5A34', 'dark': {'color': '#3A2616'}},
            ]},
            {'name': 'HUD', 'translucency_value': 0.25, 'layers': [
                {'file': '02_pitch_ladder.svg', 'geom': ladder, 'color': '#6CFFA0', 'opacity': 0.75},
                {'file': '03_flight_path_marker.svg', 'geom': fpm, 'color': '#6CFFA0'},
            ]},
        ],
    }
