"""Stylized 5th-gen fighter geometry (F-22-inspired, simplified). Units: metres.
Top view: nose at y=0 pointing toward -y, tail toward +y, x lateral.
Rear view: x lateral, y up (converted to SVG y-down by the caller)."""
from shapely.ops import unary_union
from shapely.geometry import Polygon, Point
from shapely import affinity
from iconlib import sym, pair, round_convex, round_concave


def planform():
    fuselage = sym([
        (0.0, 0.0),
        (0.28, 0.9),
        (0.55, 2.1),
        (0.82, 3.5),
        (0.98, 4.7),
        (1.35, 5.25),
        (1.9, 5.9),
        (2.0, 7.2),
        (2.05, 10.5),
        (1.9, 14.0),
        (1.7, 17.4),
        (1.62, 18.9),
        (0.22, 18.9),
        (0.0, 18.55),
    ])
    wings = pair([(1.7, 7.3), (2.05, 7.55), (6.78, 11.85), (6.78, 12.6), (2.4, 13.95), (1.7, 13.95)])
    stabs = pair([(1.6, 14.25), (2.0, 14.2), (4.45, 16.45), (4.45, 17.15), (1.6, 18.0)])
    body = unary_union([fuselage, wings, stabs])
    body = round_concave(body, 0.10)
    body = round_convex(body, 0.07)

    tails = pair([(1.72, 12.55), (2.98, 13.85), (2.98, 15.25), (1.72, 16.95)])
    tails = round_convex(tails, 0.06)

    # Canopy: teardrop
    canopy = sym([(0.0, 3.05), (0.24, 3.4), (0.42, 4.1), (0.5, 4.9), (0.47, 5.8), (0.33, 6.6), (0.0, 7.15)])
    canopy = round_convex(canopy, 0.05)

    # Shaded (left) half of the body for a two-tone faceted look
    right_half = Polygon([(20, -5), (0, -5), (0, 25), (20, 25)])
    shade = body.intersection(right_half)

    nozzles = [(-0.9, 18.9), (0.9, 18.9)]  # exhaust centres
    return dict(body=body, tails=tails, canopy=canopy, shade=shade, nozzles=nozzles, length=18.9)


def rear_view():
    """Rear (chase-camera) view, stylised with exaggerated thickness so it survives small sizes. y up."""
    def P(pts):
        return Polygon(pts)

    def mir(g):
        return unary_union([g, affinity.scale(g, xfact=-1, yfact=1, origin=(0, 0))])

    wing_r = P([(1.5, 0.45), (6.6, -0.05), (6.75, -0.28), (6.6, -0.5), (1.5, -0.55)])
    tail_r = P([(1.28, 0.55), (1.95, 0.55), (3.25, 3.0), (3.05, 3.2), (2.6, 3.2)])
    fuselage = P([(-2.0, 0.55), (-1.25, 1.05), (1.25, 1.05), (2.0, 0.55), (2.1, -0.4),
                  (1.6, -1.15), (-1.6, -1.15), (-2.1, -0.4)])
    spine = Point(0, 1.0).buffer(1.0, 64)
    spine = affinity.scale(spine, xfact=0.95, yfact=0.42, origin=(0, 1.0))
    body = unary_union([mir(wing_r), fuselage, mir(tail_r), spine])
    body = round_convex(round_concave(body, 0.12), 0.07)

    stab_r = P([(1.9, -0.45), (4.6, -0.78), (4.72, -0.98), (4.6, -1.16), (1.9, -1.12)])
    stabs = round_convex(mir(stab_r), 0.06)

    canopy = Point(0, 1.12).buffer(1.0, 64)
    canopy = affinity.scale(canopy, xfact=0.5, yfact=0.5, origin=(0, 1.12))
    canopy = canopy.intersection(P([(-2, 1.12), (2, 1.12), (2, 3), (-2, 3)]))

    noz = mir(P([(0.18, 0.12), (1.5, 0.12), (1.5, -0.98), (0.18, -0.98)]))
    noz = round_convex(noz, 0.16)
    burn_outer = mir(P([(0.36, -0.04), (1.32, -0.04), (1.32, -0.82), (0.36, -0.82)]))
    burn_outer = round_convex(burn_outer, 0.2)
    burn_core = mir(affinity.scale(Point(0.84, -0.43).buffer(0.25, 48), xfact=1.35, yfact=1.0,
                                   origin=(0.84, -0.43)))
    return dict(body=body, stabs=stabs, canopy=canopy, nozzles=noz, burn_outer=burn_outer, burn_core=burn_core)
