# Genere le bloc NASM de l'arborescence : chaque noeud pointe sur son
# premier enfant et sur son frere suivant (liste chainee), ce qui permet
# d'inserer et de supprimer a chaud.
T = ('/', 'dir', None, [
 ('bin','dir',None,[('bash','exec',None),('ls','exec',None),('mkdir','exec',None),
                    ('mkfile','exec',None),('nasm','exec',None),('rm','exec',None),
                    ('see','exec',None),('srm','exec',None),('sys','exec',None),
                    ('vim','exec',None),('where','exec',None)]),
 ('boot','dir',None,[('grub','dir',None,[('grub.cfg','file','t_grubcfg')]),
                     ('initramfs-nullcore.img','file',None),('vmlinuz-nullcore','file',None)]),
 ('dev','dir',None,[('null','file',None),('random','file',None),('sda','file',None),
                    ('sda1','file',None),('tty1','file',None),('zero','file',None)]),
 ('etc','dir',None,[('pacman.d','dir',None,[('mirrorlist','file','t_mirror')]),
                    ('systemd','dir',None,[('system.conf','file','t_sysconf')]),
                    ('fstab','file','t_fstab'),('group','file','t_group'),
                    ('hostname','file','t_hostn'),('hosts','file','t_hosts'),
                    ('locale.conf','file','t_locale'),('os-release','file','t_osrel'),
                    ('passwd','file','t_passwd'),('shadow','file','t_shadow'),
                    ('vconsole.conf','file','t_vcons')]),
 ('home','dir',None,[('user','dir',None,[
        ('projets','dir',None,[('idees.txt','file','t_idees')]),
        ('.bashrc','file','t_bashrc'),('memo.txt','file','t_memo')])]),
 ('proc','dir',None,[('cpuinfo','file','t_cpuinfo'),('meminfo','file','t_meminfo'),
                     ('uptime','file','t_procup'),('version','file','t_version')]),
 ('root','dir',None,[('builds','dir',None,[('bootloader.asm','file',None),
                                           ('kernel.asm','file','t_kasm')]),
                     ('.bash_history','file','t_hist'),('.bashrc','file','t_bashrc'),
                     ('notes.txt','file','t_notes'),
                     # dossiers "bureau" -- sans accent : les caracteres
                     # accentues ecrits par ce script seraient en UTF-8, pas
                     # dans le codepage 437 attendu par la police VGA, et
                     # s'afficheraient mal. Installation est prevu pour un
                     # futur gestionnaire de paquets / installateur.
                     ('Documents','dir',None,[]),
                     ('Telechargements','dir',None,[]),
                     ('Installation','dir',None,[]),
                     ('Musique','dir',None,[]),
                     ('Videos','dir',None,[]),
                     ('Images','dir',None,[])]),
 ('tmp','dir',None,[]),
 ('usr','dir',None,[('bin','dir',None,[]),('include','dir',None,[]),
                    ('lib','dir',None,[]),('share','dir',None,[]),('src','dir',None,[])]),
 ('var','dir',None,[('cache','dir',None,[]),
                    ('log','dir',None,[('boot.log','file','t_bootlog'),
                                       ('pacman.log','file','t_pacmanlog')]),
                    ('tmp','dir',None,[])]),
])

TY = {'dir':'VT_DIR','file':'VT_FILE','exec':'VT_EXEC'}
nodes, names = [], {}
def nm(s):
    if s not in names:
        names[s] = "vn_%d" % len(names)
    return names[s]

def walk(node, parent):
    name, kind, data = node[0], node[1], node[2]
    kids = node[3] if len(node) > 3 else []
    lbl = "n_%d" % len(nodes)
    nodes.append(None)
    first = 0
    if kind == 'dir':
        kids = sorted(kids, key=lambda k: k[0])     # ls trie par octet
        childlbls = [walk(k, lbl) for k in kids]
        for i, c in enumerate(childlbls):
            nodes[int(c[2:])] = nodes[int(c[2:])][:5] + (
                childlbls[i+1] if i+1 < len(childlbls) else '0',)
        first = childlbls[0] if childlbls else '0'
    nodes[int(lbl[2:])] = (lbl, nm(name), parent, first if kind=='dir' else (data or '0'),
                           TY[kind], '0')
    return lbl

walk(T, '0')
# alias stables utilises par le noyau
root_lbl = nodes[0][0]
home_lbl = [n[0] for n in nodes if n[2] == root_lbl and n[1] == names['root']][0]
out = ["; Arborescence -- genere par gentree.py",
       "n_root    equ %s" % root_lbl,
       "n_rootdir equ %s" % home_lbl,
       "align 8"]
w = max(len(n[0]) for n in nodes)
for n in nodes:
    out.append("%-*s dq %-8s %-6s %-12s %-8s %s" %
               (w+1, n[0]+":", n[1]+",", n[2]+",", n[3]+",", n[4]+",", n[5]))
out.append("")
for s, l in names.items():
    out.append('%-8s db "%s",0' % (l+":", s))
open("tree.inc","w").write("\n".join(out) + "\n")
print("%d noeuds, %d noms" % (len(nodes), len(names)))
print("racine =", root_lbl, "  /root =", home_lbl)
