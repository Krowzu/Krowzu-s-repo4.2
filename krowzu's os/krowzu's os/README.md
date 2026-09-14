# NullCore OS — noyau x86-64 en assembleur, en mode texte

Terminal texte plein écran, sans aucune partie graphique. Tout est écrit en NASM.

## Compiler et lancer

```sh
./build.sh              # clavier AZERTY (défaut)
./build.sh us           # clavier QWERTY

qemu-system-x86_64 -drive file=nullcore.img,format=raw,if=floppy \
                   -display gtk,zoom-to-fit=off
```

Sur une vraie machine / clé USB :

```sh
sudo dd if=nullcore.img of=/dev/sdX bs=1M conv=fsync
```

## Taille des caractères

Le noyau démarre maintenant en **80x50** : il téléverse la police 8x8 du BIOS
dans le bloc 1 du plan 2 du VGA et règle la hauteur de caractère du CRTC à 8
pixels. Les lettres font donc la moitié de leur hauteur d'origine.

Pour revenir aux gros caractères, remplace `call vga_mode50` par `call vga_mode25`
dans `kmain` (les deux fonctions sont dans `kernel.asm`).

Côté QEMU, `-display gtk,zoom-to-fit=off` affiche à la résolution native
(720x400). Sans ça, ou avec `-full-screen`, l'image est étirée sur toute la dalle
et les caractères redeviennent énormes quelle que soit la police.

## Commandes

```
ls [-a] [-l] [chemin]   lister le contenu d'un répertoire
cd [chemin]             changer de répertoire
where                   afficher le répertoire courant
see <fichier>           afficher le contenu d'un fichier
mkdir [-p] <nom>        créer un répertoire
mkfile <nom>            créer un fichier vide
rm [-r] <nom>           supprimer un fichier ou un répertoire
srm <nom>               supprimer un répertoire vide
files                   gestionnaire de fichiers plein écran
print <texte>           afficher du texte
sys                     informations sur le système
date                    date et heure courantes
uptime                  temps écoulé depuis le démarrage
clear                   effacer l'écran
loadkeys <fr|us>        changer la disposition du clavier
reboot                  redémarrer la machine
poweroff                éteindre la machine
exit                    fermer la session
help                    afficher cette aide
```

Le login accepte n'importe quel mot de passe ; le nom saisi devient celui de
l'invite. Tape `root` pour avoir l'invite rouge et le `#`.

## Navigation

L'arborescence est un arbre de nœuds de 40 octets — nom, parent, contenu, type,
frère suivant — parcouru en liste chaînée. Toute la résolution de chemin passe
par une seule fonction, `vfs_resolve`, et l'objectif est que le comportement soit
indiscernable de celui d'Arch.

```
cd /usr/src            absolu, autant de niveaux qu'on veut
cd ../../etc           relatif
cd ~                   répertoire personnel
cd -                   revenir au précédent
ls                     trié, répertoires en bleu, exécutables en vert
ls -a                  y compris . .. et les fichiers cachés
ls -l                  droits, liens, propriétaire, taille, date
ls /etc /tmp           plusieurs chemins, avec en-têtes
see a b c              plusieurs fichiers à la suite
mkdir -p a/b/c         crée toute la chaîne
rm -r dossier          suppression récursive
```

Les détails qui font que ça ressemble vraiment à Arch :

- Les entrées sont **triées** alphabétiquement. Plutôt que trier à l'affichage,
  `vfs_link` insère au bon endroit — la liste est donc toujours triée, ce qui
  profite d'un coup à `ls` et à la complétion.
- **Pas de `/`** ajouté après les répertoires : sous Arch c'est l'option `-F` qui
  fait ça, l'alias par défaut est `ls --color=auto` et seule la couleur distingue.
- `ls -l` affiche le **compteur de liens** (2 plus le nombre de sous-répertoires
  pour un répertoire, 1 pour un fichier) et une ligne `total` en blocs de 1 Kio.
- Les **options peuvent être placées n'importe où** : `rm dossier -r` marche comme
  `rm -r dossier`, parce qu'une première passe relève les options avant que la
  seconde ne traite les opérandes.

Les messages d'erreur reprennent le format exact de bash et des coreutils :

```
bash: cd: /foo: No such file or directory
srm: failed to remove 'projet': Directory not empty
mkdir: cannot create '/etc/x/y': No such file or directory
rm: cannot remove 'a': Is a directory
see: /etc: Is a directory
```

Le chaînage permet de **modifier** l'arbre à chaud : `mkdir`, `mkfile`, `rm` et
`srm` allouent depuis un réservoir de 96 nœuds et 1,5 Kio de noms. Ça reste en
RAM et disparaît au redémarrage, faute de pilote disque.

**Tab complète.** Premier mot : les noms de commandes. Mots suivants : les
entrées du système de fichiers, y compris à travers un chemin (`cd /us<Tab>`
donne `cd /usr/`). Une seule correspondance : elle est complétée, avec un `/`
ajouté pour un répertoire. Plusieurs : la saisie est étendue jusqu'au préfixe
commun puis les candidats sont listés, comme bash. Les fichiers cachés
n'apparaissent que si le préfixe commence par un point.

L'arborescence est décrite en Python dans `gentree.py`, qui produit `tree.inc`.
Pour ajouter des répertoires ou des fichiers, modifie la structure en haut du
script et relance `python3 gentree.py && ./build.sh`.

## `files` — gestionnaire de fichiers

`files` ouvre un navigateur façon gestionnaire de bureau, mais **dans le
fil du terminal** — pas de page à part, pas d'écran alternatif. La liste
s'affiche juste après la ligne de commande, exactement comme le ferait `ls`,
et une barre d'instructions reste fixée tout en bas de l'écran pendant toute
la navigation :

```
Flèches haut/bas   déplacer la sélection
Entrée             ouvrir un dossier, ou afficher un fichier
Échap              remonter au dossier parent
Ctrl+Échap         quitter, et rester dans le dernier dossier visité
```

L'historique au-dessus (tes commandes précédentes) n'est jamais touché :
chaque redessin n'efface et ne réécrit que sa propre zone, entre la ligne où
`files` a été tapé et le bas de l'écran. En quittant, cette zone est effacée
à son tour et remplacée par une seule ligne de trace (le dossier où tu as
fini) — comme n'importe quelle commande qui laisse une ligne derrière elle —
et le shell continue juste en dessous.

La sélection est en vidéo inversée (fond de la couleur du type, texte noir),
et suit le même code couleur que `ls` : bleu pour les dossiers, vert pour les
exécutables. Les fichiers cachés restent cachés, comme avec `ls` sans `-a`.

Techniquement, remonter au parent ne demande pas de pile de navigation :
chaque nœud connaît déjà son parent (`VN_PARENT`), donc `Suppr` est un simple
`current = current->parent`.

Échap seul reste le code ASCII 27 habituel. Ctrl+Échap est une combinaison
qui n'existait pas avant : le clavier ne renvoyait jusque-là un code spécial
que pour Ctrl+lettre (Ctrl+A à Ctrl+Z, pour Ctrl+C et Ctrl+L). Détecter
Ctrl+Échap a demandé un cas particulier dans le pilote clavier, avant le
bloc générique Ctrl+lettre, sans quoi la combinaison était simplement
avalée (ignorée en silence).

Piège rencontré en le construisant : la barre du bas est toujours imprimée
sur la toute dernière rangée de l'écran. Si sa chaîne se terminait par un
saut de ligne (habitude reprise d'ailleurs dans le code), ce saut de ligne
faisait déborder le curseur d'une rangée — ce qui déclenche un défilement de
**tout** l'écran, historique compris, le décalant silencieusement d'une
ligne à chaque redessin.

## Clavier## Clavier

AZERTY par défaut. Les deux tables sont dans le binaire ; `loadkeys fr` et
`loadkeys us` basculent à chaud. `./build.sh us` change seulement celle chargée
au démarrage.

Attention : QEMU envoie les scancodes de la touche **physique**. Sur un clavier
QWERTY, la table AZERTY donnera donc de l'AZERTY — c'est le comportement correct.

Les accents passent par le codepage 437 du VGA : `é è ç à ù ² µ £ § °`
s'affichent correctement.

## Le logo de `sys`

Le logo est maintenant un engrenage barré d'un marteau en diagonale, en
ASCII : trois caractères, trois couleurs — `#` gris pour l'engrenage, `=`
brun pour le manche, `@` blanc pour la tête. Contrairement à l'ancien anneau
(une couleur par ligne), c'est une couleur par **cellule** : `logo.inc`
contient deux tables parallèles, `logo_chars` (le caractère de chaque
cellule) et `logo_attrs` (son attribut VGA), et `cmd_sys` les lit case par
case.

Pour changer de logo à partir d'un fichier texte (colonnes alignées, `#`/`=`/`@`
pour les trois couleurs, espace pour le fond) :

```sh
python3 convert_logo.py mon_logo.txt && ./build.sh
```

`genlogo.py` est l'ancien script, celui de l'anneau à une couleur par ligne —
il ne produit plus le bon format et sert seulement de référence pour dessiner
un logo par géométrie plutôt qu'à partir d'un fichier texte existant.

## Logo

Le logo est en ASCII : un anneau barré en diagonale, le symbole « null ».
`genlogo.py` dessine la forme géométriquement, échantillonne chaque cellule en
3x3 et choisit un caractère selon la densité de couverture, dans la rampe
` .:-=+*#%@`. Chaque ligne reçoit une couleur, ce qui donne le dégradé blanc vers
cyan vers bleu.

Attention à l'aspect : en 80x50 une cellule fait 9x8 pixels écran. Un dessin fait
sur une grille carrée sort donc ovale. `genlogo.py` travaille en coordonnées
écran et convertit à la fin ; le logo fait 20 cellules sur 20 lignes, soit
180x160 pixels — un anneau rond et pas un œuf.

Pour changer de logo, modifie les formes dans `genlogo.py` et relance :

```sh
python3 genlogo.py && ./build.sh
```

Le script affiche un aperçu en caractères avant d'écrire `logo.inc`. Si tu changes
le nombre de lignes, `LOGO_N` suit automatiquement mais il faut ajuster la table
`info_lines` de `kernel.asm`, qui doit avoir autant d'entrées.

## Dossiers de `/root`

En plus de `builds/` et `notes.txt`, `/root` contient maintenant six dossiers
façon bureau : `Documents`, `Telechargements`, `Installation`, `Musique`,
`Videos`, `Images` — tous vides pour l'instant. Pas d'accents dans ces noms :
ils sont écrits en dur dans le binaire par `gentree.py`, qui produit du texte
UTF-8, alors que la police VGA attend le codepage 437 (un octet par lettre,
et pas le même octet) : un `é` littéral s'afficherait comme deux
caractères incorrects. `Installation` est un dossier vide en attente : à
garder en tête pour un futur gestionnaire de paquets ou d'installation.

## Ce qui a changé dans le bootloader

Ton bootloader était correct sur le passage en long mode, mais il ne chargeait
que 4 secteurs (2 Kio), ce qui est trop petit pour un shell.

| Point | Avant | Maintenant |
|---|---|---|
| Taille chargée | 4 secteurs | 64 secteurs (32 Kio) |
| Lecture disque | 1 seul `int 13h`, CHS figé | boucle LBA→CHS, gère le changement de piste/tête |
| Erreur disque | `jc $` (blocage muet) | 5 tentatives + reset + message |
| Porte A20 | `or al,2` seul | bit 0 remis à 0 (sinon risque de reset) |
| Mode vidéo | hérité du BIOS | mode 3 forcé + clignotement désactivé |
| Mémoire | inconnue | carte E820 rangée en `0x5000` |
| Police 8x8 | — | récupérée du BIOS vers `0x6000` |
| Identity mapping | 2 Mo (1 page) | 4 Gio (2048 pages de 2 Mo) |
| `esp`/`rsp` | jamais initialisé | pile explicite en `0x90000` |

Le mapping de 4 Gio n'est pas cosmétique : les tables SMBIOS et l'espace de
configuration PCI sont souvent placés très haut par le BIOS. Avec 2 Mo mappés, y
accéder provoquait une faute de page — donc une triple faute, puisqu'il n'y a pas
d'IDT.

## Architecture du noyau

Pas d'IDT : les interruptions restent masquées et le clavier est lu par
**scrutation** du contrôleur 8042. C'est ce qui permet de tenir en 32 Kio sans
gestionnaire d'exceptions. Conséquence : la moindre exception CPU = triple faute.

| Sous-système | Détail |
|---|---|
| Écran | VGA texte en `0xB8000`, 80x50, défilement par `rep movsq`, curseur via `0x3D4`/`0x3D5` |
| Clavier | scancodes set 1, Shift / Caps Lock / Ctrl, préfixe `0xE0`, octets souris filtrés |
| Ligne de commande | écho, historique de 8 entrées (↑/↓), complétion Tab, `Ctrl+L`, `Ctrl+C` |
| Système de fichiers | arbre chaîné en mémoire, création et suppression à chaud |
| Horloge | CMOS/RTC (`0x70`/`0x71`), conversion BCD auto, NMI masqué |
| Temporisation | canal 2 du PIT en mode 0, scrutation de OUT2 sur `0x61` bit 5 |
| CPU | marque via `CPUID 0x80000002..4`, cœurs via feuille `0x0B` |
| Fréquence CPU | mesurée : delta `RDTSC` sur une fenêtre PIT de 50 ms |
| Mémoire | somme des zones de type 1 de la carte E820 |
| Carte graphique | balayage PCI par `0xCF8`/`0xCFC`, classe 0x03 |
| Modèle machine | table SMBIOS type 1, ancre cherchée entre `0xF0000` et `0xFFFFF` |

## Ce qui est réellement lu sur ta machine

`sys` ne contient aucune valeur en dur pour le matériel :

```
Host: ASUSTeK COMPUTER INC. PRIME B550M-A      <- SMBIOS type 1
CPU: AMD Ryzen 5 5600X (12) @ 3.70GHz          <- CPUID + mesure PIT/TSC
GPU: NVIDIA Corporation [10de:2489]            <- balayage PCI
Memory: 1MiB / 32695MiB                        <- carte E820 du BIOS
```

Restent inventés : le nombre de paquets, la version du noyau et le shell. Le
« used » de la mémoire est l'empreinte réelle du noyau, environ 1 Mio.

## Limites connues

- Le système de fichiers est en RAM : tout ce que tu crées disparaît au reboot.
- `rm` ne supprime pas récursivement (pas de `-r`), et rien n'est vraiment libéré.
- Pas de multitâche, pas d'allocateur général, pas de pilote disque après le boot.
- Le SMBIOS n'est lu que si sa table tient sous les 4 Gio mappés.

## Pistes pour la suite

1. IDT + PIC 8259 remappé → clavier en IRQ1 au lieu de la scrutation.
2. Handler d'exceptions (au moins #GP, #PF) pour ne plus tripler-fauter en silence.
3. Allocateur de pages basé sur la carte E820.
4. Pilote ATA PIO + FAT12 : l'arbre chaîné est déjà prêt à être rempli depuis un
   disque au lieu d'être généré à la compilation.
