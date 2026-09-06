# ArchNasm — noyau x86-64 en assembleur, façon Arch Linux

Terminal texte plein écran, sans aucune partie graphique. Tout est écrit en NASM.

## Compiler et lancer

```sh
./build.sh              # clavier QWERTY (défaut)
./build.sh azerty       # clavier AZERTY français

qemu-system-x86_64 -drive file=archnasm.img,format=raw,if=floppy -full-screen
```

Sans `-full-screen`, QEMU affiche déjà le 80x25 complet ; le plein écran ne fait
qu'agrandir la fenêtre.

Sur une vraie machine / clé USB :

```sh
sudo dd if=archnasm.img of=/dev/sdX bs=1M conv=fsync
```

## Ce qui a changé dans le bootloader

Ton bootloader était correct sur le passage en long mode, mais il ne chargeait
que 4 secteurs (2 Kio), ce qui est trop petit pour un shell. Modifications :

| Point | Avant | Maintenant |
|---|---|---|
| Taille chargée | 4 secteurs | 64 secteurs (32 Kio) |
| Lecture disque | 1 seul `int 13h`, CHS figé | boucle LBA→CHS, gère le changement de piste/tête |
| Erreur disque | `jc $` (blocage muet) | 5 tentatives + reset + message |
| Porte A20 | `or al,2` seul | bit 0 remis à 0 (sinon risque de reset) |
| Mode vidéo | hérité du BIOS | mode 3 forcé + clignotement désactivé (16 couleurs de fond) |
| Mémoire | inconnue | carte E820 rangée en `0x5000` pour le noyau |
| `esp`/`rsp` | jamais initialisé | pile explicite en `0x90000` |

Le reste (GDT, PAE, PML4/PDPT/PD en `0x1000`/`0x2000`/`0x3000`, EFER.LME, CR0.PG)
est inchangé.

## Architecture du noyau

Pas d'IDT : les interruptions restent masquées et le clavier est lu par
**scrutation** du contrôleur 8042 (ports `0x60`/`0x64`). C'est ce qui permet de
tenir en 32 Kio sans gestionnaire d'exceptions. Conséquence : la moindre
exception CPU = triple faute, donc pas de division par zéro dans le code.

| Sous-système | Détail |
|---|---|
| Écran | VGA texte en `0xB8000`, 80x25, défilement par `rep movsq`, curseur matériel via `0x3D4`/`0x3D5` |
| Clavier | scancodes set 1, Shift / Caps Lock / Ctrl, préfixe `0xE0` pour les flèches, octets souris filtrés |
| Ligne de commande | écho, retour arrière, historique de 8 entrées (↑/↓), `Ctrl+L`, `Ctrl+C` |
| Horloge | CMOS/RTC (`0x70`/`0x71`), conversion BCD auto, NMI masqué |
| Temporisation | canal 2 du PIT en mode 0, scrutation de OUT2 sur le bit 5 de `0x61` — même rythme en TCG, en KVM et sur du vrai matériel |
| CPU | chaîne de marque via `CPUID 0x80000002..4` |
| Mémoire | somme des zones de type 1 de la carte E820 |

## Commandes

```
fastfetch / neofetch / ff   logo Arch + infos système (les vraies : CPUID, E820, RTC)
help                        aide
clear          (Ctrl+L)     efface l'écran
echo <texte>
ls / cd / pwd / cat         arborescence simulée (/, /root, /etc, /usr)
uname [-a|-r]
whoami / id / hostname
ps / free / lscpu
date / uptime               horloge réelle
pacman -Q | -Syu
sudo
reboot / poweroff / halt
exit / logout               ferme la session, retour au login
```

Le login accepte n'importe quel mot de passe ; le nom saisi devient celui de
l'invite et de `whoami`. Tape `root` pour avoir l'invite rouge et le `#`.

Fichiers lisibles avec `cat` : `/etc/os-release`, `/etc/hostname`, `/etc/hosts`,
`/etc/passwd`, `/proc/version`, `/proc/cpuinfo`, `/root/notes.txt`,
`/root/.bashrc` (le nom court marche aussi : `cat os-release`).

## Disposition clavier

QEMU envoie les scancodes de la touche *physique*. Un clavier AZERTY donne donc
du QWERTY par défaut. Recompile avec `./build.sh azerty` pour la table française
(accents en codepage 437, `é è ç à ù ²` inclus).

## Limites connues

- Pas de vrai système de fichiers : l'arborescence est une table statique.
- `cd ..` remonte toujours à `/`.
- Pas de multitâche, pas d'allocateur, pas de pilote disque après le boot.
- La quantité de RAM « utilisée » dans `free` et `fastfetch` est une constante.

## Pistes pour la suite

1. IDT + PIC 8259 remappé → clavier en IRQ1 au lieu de la scrutation.
2. Handler d'exceptions (au moins #GP, #PF) pour ne plus tripler-fauter en silence.
3. Pagination sur plus de 2 Mo, allocateur de pages basé sur la carte E820.
4. Pilote ATA PIO + un FAT12 simple pour lire de vrais fichiers depuis l'image.
