"""Small helpers for building Icon Composer-ready layer SVGs with shapely geometry."""
import math
from shapely.geometry import Polygon, MultiPolygon, Point, LineString
from shapely.ops import unary_union
from shapely import affinity

CANVAS = 1024


def mirror_x(coords):
    """Given right-half outline points (x>=0) from top to bottom, return a closed full outline."""
    left = [(-x, y) for (x, y) in reversed(coords) if x != 0]
    return coords + left


def poly(coords):
    return Polygon(coords)


def sym(coords):
    """Polygon built from right-half coords mirrored across x=0 (coords listed top->bottom)."""
    return Polygon(mirror_x(coords))


def pair(coords):
    """A right-side polygon and its mirror image, unioned."""
    right = Polygon(coords)
    left = affinity.scale(right, xfact=-1, yfact=1, origin=(0, 0))
    return unary_union([right, left])


def round_convex(g, r):
    return g.buffer(-r, join_style=1).buffer(r, join_style=1)


def round_concave(g, r):
    return g.buffer(r, join_style=1).buffer(-r, join_style=1)


def place(g, scale, rotate_deg, tx, ty):
    """Scale about origin, rotate about origin (degrees, clockwise in SVG space), translate."""
    g = affinity.scale(g, xfact=scale, yfact=scale, origin=(0, 0))
    g = affinity.rotate(g, rotate_deg, origin=(0, 0))
    return affinity.translate(g, tx, ty)


def _ring_d(coords):
    pts = list(coords)
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    s = "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in pts) + " Z"
    return s


def to_path_d(g):
    if g.is_empty:
        return ""
    geoms = g.geoms if hasattr(g, "geoms") else [g]
    parts = []
    for p in geoms:
        if p.geom_type != "Polygon":
            continue
        parts.append(_ring_d(p.exterior.coords))
        for hole in p.interiors:
            parts.append(_ring_d(hole.coords))
    return " ".join(parts)


def ribbon(points, w0, w1, cap_round=True):
    """A tapered ribbon polygon along a polyline, width w0 at start to w1 at end."""
    n = len(points)
    left, right = [], []
    for i, (x, y) in enumerate(points):
        if i == 0:
            dx, dy = points[1][0] - x, points[1][1] - y
        elif i == n - 1:
            dx, dy = x - points[i - 1][0], y - points[i - 1][1]
        else:
            dx, dy = points[i + 1][0] - points[i - 1][0], points[i + 1][1] - points[i - 1][1]
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        t = i / (n - 1)
        w = (w0 + (w1 - w0) * t) / 2
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    g = Polygon(left + list(reversed(right))).buffer(0)
    if cap_round:
        g = unary_union([g, Point(points[0]).buffer(w0 / 2, 32)])
    return g


def bezier(p0, p1, p2, p3, n=80):
    pts = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t ** 2
        d = t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def layer_svg(shapes):
    """shapes: list of (geometry, fill_hex, opacity). Returns a 1024x1024 SVG string (flat fills only)."""
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">']
    for g, fill, op in shapes:
        d = to_path_d(g)
        if not d:
            continue
        o = f' fill-opacity="{op}"' if op is not None and op < 1 else ""
        out.append(f'  <path d="{d}" fill="{fill}"{o} fill-rule="evenodd"/>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def superellipse_d(size=CANVAS, n=5.0, steps=720):
    """Approximation of Apple's continuous-corner icon mask (for previews only)."""
    a = size / 2
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = a + a * math.copysign(abs(c) ** (2 / n), c)
        y = a + a * math.copysign(abs(s) ** (2 / n), s)
        pts.append((x, y))
    return "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in pts) + " Z"


def hex_to_icon_color(h, space="srgb", alpha=1.0):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"{space}:{r:.5f},{g:.5f},{b:.5f},{alpha:.5f}"

def squircle_d(size=CANVAS, r=None):
    """Apple-style continuous-corner rounded square (preview mask only)."""
    s = size
    r = r if r is not None else 0.2237 * s
    a, b, c, d, e = 1.52866483 * r, 1.08849323 * r, 0.86840689 * r, 0.66993427 * r, 0.06549600 * r
    k1, k2 = 0.4119 * r, 0.1507 * r
    def corner(px, py, ux, uy, vx, vy):
        # corner at (px,py); u = direction along incoming edge toward corner, v = direction of outgoing edge
        P = lambda along_u, along_v: (px - ux * along_u + vx * along_v, py - uy * along_u + vy * along_v)
        seg = []
        seg.append(("L", [P(a, 0)]))
        seg.append(("C", [P(b, 0), P(c, 0), P(d, e)]))
        seg.append(("C", [P(k1, k2), P(k2, k1), P(e, d)]))
        seg.append(("C", [P(0, c), P(0, b), P(0, a)]))
        return seg
    segs = []
    segs += corner(s, 0, 1, 0, 0, 1)
    segs += corner(s, s, 0, 1, -1, 0)
    segs += corner(0, s, -1, 0, 0, -1)
    segs += corner(0, 0, 0, -1, 1, 0)
    out = f"M{a:.2f},0 "
    for cmd, pts in segs:
        out += cmd + " ".join(f"{x:.2f},{y:.2f}" for x, y in pts) + " "
    return out + "Z"
