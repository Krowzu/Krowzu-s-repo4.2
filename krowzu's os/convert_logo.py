# Convertit un fichier .txt ASCII (caracteres '#','=','@' pour l'engrenage,
# le manche et la tete du marteau, ' ' pour le fond) en logo.inc pour
# NullCore OS -- une couleur par CELLULE, pas par ligne.
#
# Usage : python3 convert_logo.py mon_logo.txt
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "logo-source.txt"
lines = open(path).read().split("\n")
while lines and lines[-1] == "":
    lines.pop()
W = max(len(l) for l in lines)
N = len(lines)
lines = [l.ljust(W) for l in lines]

COLOR = {'#': 0x07, '=': 0x06, '@': 0x0F}   # engrenage gris, manche brun, tete blanc

with open("logo.inc", "w") as f:
    f.write("; Logo ASCII : engrenage + marteau, importe depuis %s\n" % path)
    f.write("; Chaque cellule porte un caractere (logo_chars) et un attribut VGA\n")
    f.write("; (logo_attrs) -- une couleur par matiere, pas par ligne.\n")
    f.write("LOGO_W equ %d\nLOGO_N equ %d\n\n" % (W, N))
    f.write("align 8\nlogo_chars:\n")
    for l in lines:
        f.write("    db '%s'\n" % l.replace("'", "''"))
    f.write("\nlogo_attrs:\n")
    for l in lines:
        row = ",".join("0x%02X" % COLOR.get(ch, 0) for ch in l)
        f.write("    db " + row + "\n")

print("LOGO_W=%d LOGO_N=%d -> logo.inc" % (W, N))
