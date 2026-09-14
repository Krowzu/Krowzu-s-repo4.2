# ATTENTION : ce script correspond a l'ancien logo (anneau "null") et genere
# un logo.inc a une seule couleur par LIGNE (logo_lines / logo_cols).
#
# Le logo actuel (engrenage + marteau, cmd_sys) vient de convert_logo.py, qui
# lit un fichier .txt et produit un logo.inc a une couleur par CELLULE
# (logo_chars / logo_attrs). Les deux formats ne sont PAS compatibles : ne
# lance pas ce script sans adapter aussi la boucle de rendu de cmd_sys dans
# kernel.asm (voir convert_logo.py pour le format actuellement utilise).
#
# Conserve a titre d'exemple pour dessiner un logo par geometrie plutot qu'en
# partant d'un fichier texte existant.
import math

W, N = 20, 20
CW, CH = 9, 8
SW, SH = W * CW, N * CH

RAMP = " .:-=+*#%@"

def ring(fx, fy, cx, cy, r_out, r_in):
    r = math.hypot(fx - cx, fy - cy)
    return r_in <= r <= r_out

def seg(fx, fy, ax, ay, bx, by, w):
    dx, dy = bx - ax, by - ay
    t = ((fx - ax) * dx + (fy - ay) * dy) / float(dx * dx + dy * dy)
    t = min(max(t, 0.0), 1.0)
    return (fx - (ax + t * dx)) ** 2 + (fy - (ay + t * dy)) ** 2 <= w * w

CX, CY = SW / 2.0, SH / 2.0
def inside(fx, fy):
    return (ring(fx, fy, CX, CY, 74, 50) or
            seg(fx, fy, CX - 52, CY + 52, CX + 52, CY - 52, 9))

rows = []
for r in range(N):
    line = ""
    for c in range(W):
        hits = 0
        for sy in range(3):
            for sx in range(3):
                fx = c * CW + (sx + 0.5) * CW / 3.0
                fy = r * CH + (sy + 0.5) * CH / 3.0
                if inside(fx, fy):
                    hits += 1
        line += RAMP[min(hits * (len(RAMP) - 1) // 9, len(RAMP) - 1)]
    rows.append(line.rstrip())

def color(r):
    t = r / float(N - 1)
    return 0x0F if t < 0.30 else (0x0B if t < 0.70 else 0x09)

for r, line in enumerate(rows):
    print("  |%-*s|" % (W, line))
