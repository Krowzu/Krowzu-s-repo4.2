; =====================================================================
;  kernel.asm  --  NullCore OS : noyau x86-64 en mode texte
;
;  Charge en 0x8000 par le bootloader, deja en long mode 64 bits,
;  avec les 2 premiers Mo mappes en identite.
;  Aucune IDT n'est installee : les interruptions restent masquees et
;  le clavier est lu par scrutation (polling) du controleur 8042.
;
;  nasm -f bin kernel.asm -o kernel.bin
;  clavier francais : nasm -f bin -DAZERTY kernel.asm -o kernel.bin
; =====================================================================

BITS 64
ORG 0x8000

%define VGA_MEM     0xB8000
%define VGA_W       80

; ---- attributs VGA : (fond << 4) | texte
%define C_DEF       0x07        ; gris clair
%define C_GREY      0x08
%define C_WHITE     0x0F
%define C_CYAN      0x0B
%define C_GREEN     0x0A
%define C_RED       0x0C
%define C_YELLOW    0x0E
%define C_BLUE      0x09
%define C_MAG       0x0D

; ---- touches speciales renvoyees par getchar
; Codes internes des touches de direction. Ils doivent rester hors de
; 0x80-0xFF, sinon ils masquent les caracteres accentues du codepage 437
; (e accent aigu = 0x82), et hors de 1..26 utilises par Ctrl+lettre.
%define K_UP        0x1C
%define K_DOWN      0x1D
%define K_LEFT      0x1E
%define K_RIGHT     0x1F
%define K_DEL       0x0B          ; touche Suppr (scancode etendu 0xE0,0x53) --
                                  ; 0x0B est sous ' ', readline l'ignore donc
                                  ; sans rien y toucher. Detectee mais plus
                                  ; utilisee par aucune commande pour l'instant.
%define K_CTRLESC   0x1A          ; Ctrl+Echap : sous ' ' egalement, meme
                                  ; raison. Echap seul reste le code ASCII 27
                                  ; habituel ; ce code-ci n'existe que quand
                                  ; Ctrl est enfonce en meme temps qu'Echap.

; ---- noeuds du systeme de fichiers (32 octets chacun)
%define VN_NAME     0
%define VN_PARENT   8
%define VN_DATA     16
%define VN_TYPE     24
%define VN_NEXT     32              ; frere suivant
%define VN_SIZE     40
%define NODE_MAX    96              ; noeuds creables a chaud
%define NAME_POOL   1536
%define VT_DIR      1
%define VT_FILE     2
%define VT_EXEC     3

%define CMDLEN      128
%define HIST_MAX    8

%define E820_COUNT  0x5000
%define E820_TABLE  0x5004

%define MEM_USED_MB 1

%define MS_LINE     45              ; rythme des lignes dmesg
%define MS_HOOK     260             ; hooks de l'initramfs
%define MS_UNIT     70              ; unites systemd

; =====================================================================
;  Point d'entree
; =====================================================================
kmain:
    cli
    mov rsp, 0x90000
    mov byte [text_attr], C_DEF
    call cls
    call cursor_enable
    call vga_mode50                 ; police 8x8 -> 80x50, texte plus fin
    call mem_detect
    call cpu_detect
%ifdef QWERTY
    xor al, al
    call kbd_set
%endif
    call hw_detect
    call rtc_boot_time
    call boot_sequence
.session:
    call do_login
    call shell
    jmp .session


; =====================================================================
;  Sequence de demarrage facon dmesg + systemd
; =====================================================================
boot_sequence:
    push rbx
    mov byte [text_attr], C_DEF
    mov rbx, dmesg_table
.dm:
    mov rsi, [rbx]
    test rsi, rsi
    jz .dm_end
    call print
    mov al, 10
    call putc
    mov rcx, MS_LINE
    call sleep_ms
    add rbx, 8
    jmp .dm
.dm_end:

    ; --- ligne memoire calculee reellement
    mov byte [text_attr], C_DEF
    mov rsi, s_dm_mem
    call print
    mov rax, [mem_total_kb]
    call print_dec
    mov rsi, s_dm_mem2
    call print
    mov rax, [mem_total_kb]
    call print_dec
    mov rsi, s_dm_mem3
    call print
    mov rsi, s_dm_cpu
    call print
    mov rsi, cpu_brand
    call print
    mov al, 10
    call putc
    mov rcx, 400
    call sleep_ms

    ; --- hooks initramfs
    mov rbx, hook_table
.hk:
    mov rsi, [rbx]
    test rsi, rsi
    jz .hk_end
    mov byte [text_attr], C_CYAN
    mov rsi, s_colcol
    call print
    mov byte [text_attr], C_DEF
    mov rsi, [rbx]
    call print
    mov al, 10
    call putc
    mov rcx, MS_HOOK
    call sleep_ms
    add rbx, 8
    jmp .hk
.hk_end:

    ; --- unites systemd
    mov rbx, unit_table
.un:
    mov rsi, [rbx]
    test rsi, rsi
    jz .un_end
    call ok_line
    mov rcx, MS_UNIT
    call sleep_ms
    add rbx, 8
    jmp .un
.un_end:
    mov rcx, 700
    call sleep_ms
    pop rbx
    ret

; rsi = texte -> "[  OK  ] texte"
ok_line:
    push rsi
    mov byte [text_attr], C_DEF
    mov al, '['
    call putc
    mov byte [text_attr], C_GREEN
    mov rsi, s_ok
    call print
    mov byte [text_attr], C_DEF
    mov al, ']'
    call putc
    mov al, ' '
    call putc
    pop rsi
    call print
    mov al, 10
    call putc
    ret


; =====================================================================
;  Login
; =====================================================================
do_login:
    call cls
.retry:
    mov byte [text_attr], C_DEF
    mov rsi, s_issue
    call print

    mov rsi, s_login
    call print
    mov byte [rl_flags], 0
    mov rdi, user_buf
    mov ecx, 33
    call readline
    cmp byte [user_buf], 0
    je .retry

    mov rsi, s_passwd
    call print
    mov byte [rl_flags], 1          ; sans echo
    mov rdi, pass_buf
    mov ecx, 33
    call readline

    ; mot de passe accepte quel qu'il soit
    mov rsi, s_lastlogin
    call print
    call print_date_line
    mov rsi, s_ontty
    call print
    mov al, 10
    call putc
    mov byte [rl_flags], 0
    ret


; =====================================================================
;  Shell
; =====================================================================
shell:
    mov byte [shell_exit], 0
.loop:
    call print_prompt
    mov byte [rl_flags], 2          ; echo + historique + invite
    mov rdi, cmdline
    mov ecx, CMDLEN
    call readline
    call exec_line
    cmp byte [shell_exit], 0
    je .loop
    ret

print_prompt:
    mov byte [text_attr], C_GREY
    mov al, '['
    call putc
    ; utilisateur : rouge si root, vert sinon
    mov rsi, user_buf
    mov rdi, s_root
    call strcmp
    jne .notroot
    mov byte [text_attr], C_RED
    jmp .u
.notroot:
    mov byte [text_attr], C_GREEN
.u:
    mov rsi, user_buf
    call print
    mov byte [text_attr], C_GREY
    mov al, '@'
    call putc
    mov byte [text_attr], C_CYAN
    mov rsi, s_host
    call print
    mov byte [text_attr], C_DEF
    mov al, ' '
    call putc
    mov byte [text_attr], C_BLUE
    mov rax, [cwd_node]
    cmp rax, n_rootdir
    jne .nb
    mov rsi, s_tilde                ; ~ pour le repertoire personnel
    jmp .pd
.nb:
    mov rsi, [rax + VN_NAME]
.pd:
    call print
    mov byte [text_attr], C_GREY
    mov al, ']'
    call putc
    mov byte [text_attr], C_WHITE
    mov rsi, user_buf
    mov rdi, s_root
    call strcmp
    jne .dollar
    mov al, '#'
    jmp .p2
.dollar:
    mov al, '$'
.p2:
    call putc
    mov al, ' '
    call putc
    mov byte [text_attr], C_DEF
    ret

; ---------------------------------------------------------------------
;  Decoupe la ligne puis appelle la commande
; ---------------------------------------------------------------------
exec_line:
    push rbx
    mov rsi, cmdline
.skip:
    cmp byte [rsi], ' '
    jne .start
    inc rsi
    jmp .skip
.start:
    cmp byte [rsi], 0
    je .ret
    mov [argv0], rsi
    mov rdi, rsi
.find:
    mov al, [rdi]
    test al, al
    jz .noargs
    cmp al, ' '
    je .cut
    inc rdi
    jmp .find
.cut:
    mov byte [rdi], 0
    inc rdi
.skip2:
    cmp byte [rdi], ' '
    jne .setargs
    inc rdi
    jmp .skip2
.setargs:
    mov [argsp], rdi
    jmp .dispatch
.noargs:
    mov [argsp], rdi
.dispatch:
    mov rbx, cmd_table
.next:
    mov rsi, [rbx]
    test rsi, rsi
    jz .notfound
    mov rdi, [argv0]
    call strcmp
    je .found
    add rbx, 16
    jmp .next
.found:
    call qword [rbx + 8]
.ret:
    pop rbx
    ret
.notfound:
    mov byte [text_attr], C_DEF
    mov rsi, s_bash
    call print
    mov rsi, [argv0]
    call print
    mov rsi, s_notfound
    call print
    pop rbx
    ret


; =====================================================================
;  Commandes
; =====================================================================
cmd_help:
    mov byte [text_attr], C_DEF
    mov rsi, s_help
    call print
    ret

cmd_clear:
    call cls
    ret

cmd_print:
    mov rsi, [argsp]
    call print
    mov al, 10
    call putc
    ret


; =====================================================================
;  Systeme de fichiers : arbre de noeuds
;
;  Chaque noeud fait 32 octets :
;      +0  dq  pointeur sur le nom
;      +8  dq  pointeur sur le parent (0 pour la racine)
;      +16 dq  repertoire : liste d'enfants terminee par 0
;              fichier    : texte du contenu (0 si binaire)
;      +24 dq  type
;
;  Toute la navigation passe par vfs_resolve, qui accepte les chemins
;  absolus, relatifs, "." , ".." et "~" sur autant de niveaux qu'on veut.
; =====================================================================

; rbx = repertoire, rsi = nom -> rax = noeud enfant ou 0
vfs_child:
    push rbx
    push rcx
    push rdi
    cmp qword [rbx + VN_TYPE], VT_DIR
    jne .none
    mov rcx, [rbx + VN_DATA]
.l:
    test rcx, rcx
    jz .none
    mov rdi, [rcx + VN_NAME]
    push rcx
    call strcmp
    pop rcx
    je .found
    mov rcx, [rcx + VN_NEXT]
    jmp .l
.found:
    mov rax, rcx
    jmp .e
.none:
    xor eax, eax
.e:
    pop rdi
    pop rcx
    pop rbx
    ret

; rsi = chemin -> rax = noeud ou 0
vfs_resolve:
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    mov rbx, [cwd_node]
    cmp byte [rsi], '~'
    jne .abs
    mov rbx, n_rootdir
    inc rsi
    jmp .loop
.abs:
    cmp byte [rsi], '/'
    jne .loop
    mov rbx, n_root
.loop:
    cmp byte [rsi], '/'
    jne .comp
    inc rsi
    jmp .loop
.comp:
    cmp byte [rsi], 0
    je .done
    mov rdi, comp_buf                   ; extrait un composant
    xor ecx, ecx
.cp:
    mov al, [rsi]
    test al, al
    jz .cpe
    cmp al, '/'
    je .cpe
    cmp ecx, 30
    jae .cpskip
    mov [rdi], al
    inc rdi
    inc ecx
.cpskip:
    inc rsi
    jmp .cp
.cpe:
    mov byte [rdi], 0
    mov rdx, rsi                        ; sauve la position dans le chemin
    mov rsi, comp_buf
    mov rdi, s_dot
    call strcmp
    je .cont
    mov rsi, comp_buf
    mov rdi, s_dotdot
    call strcmp
    je .up
    mov rsi, comp_buf
    call vfs_child
    test rax, rax
    jz .fail
    mov rbx, rax
    mov rsi, rdx
    jmp .loop
.up:
    mov rax, [rbx + VN_PARENT]
    test rax, rax
    jz .cont
    mov rbx, rax
.cont:
    mov rsi, rdx
    jmp .loop
.fail:
    xor eax, eax
    jmp .ret
.done:
    mov rax, rbx
.ret:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

; rbx = noeud -> affiche son chemin absolu
vfs_print_path:
    push rax
    push rcx
    push rsi
    xor ecx, ecx
    mov rax, rbx
.up:
    push rax
    inc ecx
    mov rax, [rax + VN_PARENT]
    test rax, rax
    jnz .up
    pop rax                             ; la racine
    dec ecx
    mov rsi, [rax + VN_NAME]
    call print
    test ecx, ecx
    jz .end
.pr:
    pop rax
    mov rsi, [rax + VN_NAME]
    call print
    dec ecx
    jz .end
    mov al, '/'
    call putc
    jmp .pr
.end:
    pop rsi
    pop rcx
    pop rax
    ret

; rax = noeud -> fixe text_attr selon son type
vfs_color:
    push rdx
    mov rdx, [rax + VN_TYPE]
    cmp rdx, VT_DIR
    je .d
    cmp rdx, VT_EXEC
    je .x
    mov byte [text_attr], C_DEF
    jmp .e
.d:
    mov byte [text_attr], C_BLUE
    jmp .e
.x:
    mov byte [text_attr], C_GREEN
.e:
    pop rdx
    ret

; =====================================================================
;  Commandes de navigation
; =====================================================================
cmd_where:
    push rbx
    mov byte [text_attr], C_DEF
    mov rbx, [cwd_node]
    call vfs_print_path
    mov al, 10
    call putc
    pop rbx
    ret

; ---------------------------------------------------------------------
;  ls [-a] [-l] [chemin]
; ---------------------------------------------------------------------
; ---------------------------------------------------------------------
;  Analyse de la ligne d'arguments
;
;  parse_opts fait une premiere passe et releve les lettres d'option, de
;  sorte que "rm dossier -r" marche comme "rm -r dossier", comme dans les
;  coreutils. next_arg fait ensuite le tour des operandes.
; ---------------------------------------------------------------------
parse_opts:
    push rax
    push rsi
    mov byte [opt_a], 0
    mov byte [opt_l], 0
    mov byte [opt_r], 0
    mov byte [opt_p], 0
    mov rsi, [argsp]
.tok:
    cmp byte [rsi], ' '
    jne .t2
    inc rsi
    jmp .tok
.t2:
    cmp byte [rsi], 0
    je .e
    cmp byte [rsi], '-'
    jne .skip
    inc rsi
    cmp byte [rsi], 0
    je .e
    cmp byte [rsi], ' '
    je .tok
.letters:
    mov al, [rsi]
    cmp al, 'a'
    jne .l1
    mov byte [opt_a], 1
.l1:
    cmp al, 'l'
    jne .l2
    mov byte [opt_l], 1
.l2:
    cmp al, 'r'
    jne .l3
    mov byte [opt_r], 1
.l3:
    cmp al, 'p'
    jne .l4
    mov byte [opt_p], 1
.l4:
    inc rsi
    mov al, [rsi]
    test al, al
    jz .e
    cmp al, ' '
    jne .letters
    jmp .tok
.skip:
    cmp byte [rsi], 0
    je .e
    cmp byte [rsi], ' '
    je .tok
    inc rsi
    jmp .skip
.e:
    pop rsi
    pop rax
    ret

; rsi = position courante -> arg_buf = operande suivant, rax = 1 si trouve
next_arg:
    push rdi
.tok:
    cmp byte [rsi], ' '
    jne .t2
    inc rsi
    jmp .tok
.t2:
    cmp byte [rsi], 0
    je .none
    cmp byte [rsi], '-'
    jne .copy
    cmp byte [rsi + 1], 0               ; "-" seul est un operande
    je .copy
    cmp byte [rsi + 1], ' '
    je .copy
.skipopt:
    cmp byte [rsi], 0
    je .none
    cmp byte [rsi], ' '
    je .tok
    inc rsi
    jmp .skipopt
.copy:
    mov rdi, arg_buf
.c:
    mov al, [rsi]
    test al, al
    jz .ce
    cmp al, ' '
    je .ce
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .c
.ce:
    mov byte [rdi], 0
    mov eax, 1
    pop rdi
    ret
.none:
    mov byte [arg_buf], 0
    xor eax, eax
    pop rdi
    ret

cmd_ls:
    push rbx
    push r13
    push r14
    call parse_opts
    xor r14d, r14d
    mov rsi, [argsp]
.count:
    call next_arg
    test rax, rax
    jz .counted
    inc r14d
    jmp .count
.counted:
    test r14d, r14d
    jnz .multi
    mov byte [arg_buf], 0
    call ls_one
    jmp .done
.multi:
    mov rsi, [argsp]
.each:
    call next_arg
    test rax, rax
    jz .done
    cmp r14d, 1                         ; en-tete si plusieurs operandes
    je .noheader
    push rsi
    mov byte [text_attr], C_DEF
    mov rsi, arg_buf
    call print
    mov rsi, s_colon_nl
    call print
    pop rsi
.noheader:
    push rsi
    call ls_one
    pop rsi
    cmp r14d, 1
    je .each
    push rsi
    mov al, 10
    call putc
    pop rsi
    jmp .each
.done:
    mov byte [text_attr], C_DEF
    pop r14
    pop r13
    pop rbx
    ret

; Liste le chemin contenu dans arg_buf.
ls_one:
    push rbx
    push r13
    mov rsi, arg_buf
    call vfs_resolve
    test rax, rax
    jz .noent
    mov rbx, rax
    cmp qword [rbx + VN_TYPE], VT_DIR
    jne .single
    cmp byte [opt_l], 0
    je .entries
    call ls_total
.entries:
    cmp byte [opt_a], 0
    je .list
    mov rax, rbx                        ; -a : . et .. en tete
    mov rsi, s_dot
    call ls_show
    mov rax, [rbx + VN_PARENT]
    test rax, rax
    jnz .dd
    mov rax, rbx
.dd:
    mov rsi, s_dotdot
    call ls_show
.list:
    mov r13, [rbx + VN_DATA]
.l:
    test r13, r13
    jz .end
    mov rax, r13
    mov rsi, [rax + VN_NAME]
    cmp byte [rsi], '.'
    jne .show
    cmp byte [opt_a], 0
    je .next
.show:
    call ls_show
.next:
    mov r13, [r13 + VN_NEXT]
    jmp .l
.single:
    mov rsi, [rax + VN_NAME]
    call ls_show
.end:
    mov byte [text_attr], C_DEF
    cmp byte [cursor_x], 0
    je .ret
    mov al, 10
    call putc
.ret:
    pop r13
    pop rbx
    ret
.noent:
    mov byte [text_attr], C_DEF
    mov rsi, s_ls
    call print
    call print_quoted
    mov rsi, s_nosuch
    call print
    pop r13
    pop rbx
    ret

; "total N" : 4 blocs de 1 Kio par entree, comme sur un ext4
ls_total:
    push rax
    push rcx
    push r13
    mov byte [text_attr], C_DEF
    xor ecx, ecx
    cmp byte [opt_a], 0
    je .walk
    add ecx, 2
.walk:
    mov r13, [rbx + VN_DATA]
.l:
    test r13, r13
    jz .out
    mov rax, [r13 + VN_NAME]
    cmp byte [rax], '.'
    jne .cnt
    cmp byte [opt_a], 0
    je .nx
.cnt:
    inc ecx
.nx:
    mov r13, [r13 + VN_NEXT]
    jmp .l
.out:
    mov rsi, s_total
    call print
    mov eax, ecx
    shl eax, 2
    call print_dec
    mov al, 10
    call putc
    pop r13
    pop rcx
    pop rax
    ret

; rax = noeud, rsi = nom a afficher
ls_show:
    push rax
    push rsi
    cmp byte [opt_l], 0
    je .short
    call ls_longline
    pop rsi
    push rsi
    call vfs_color
    call print
    mov byte [text_attr], C_DEF
    mov al, 10
    call putc
    jmp .e
.short:
    cmp byte [cursor_x], 62
    jb .go
    mov al, 10
    call putc
.go:
    call vfs_color
    call print
    mov byte [text_attr], C_DEF
    call pad_col
.e:
    pop rsi
    pop rax
    ret

; rax = noeud : nombre de liens, sur 2 colonnes
ls_nlink:
    push rax
    push rcx
    push rdx
    cmp qword [rax + VN_TYPE], VT_DIR
    jne .file
    mov ecx, 2                          ; . et l'entree dans le parent
    mov rdx, [rax + VN_DATA]
.l:
    test rdx, rdx
    jz .out
    cmp qword [rdx + VN_TYPE], VT_DIR   ; chaque sous-repertoire ajoute son ..
    jne .n
    inc ecx
.n:
    mov rdx, [rdx + VN_NEXT]
    jmp .l
.file:
    mov ecx, 1
.out:
    mov eax, ecx
    mov ecx, 2
    call print_dec_w
    mov al, ' '
    call putc
    pop rdx
    pop rcx
    pop rax
    ret

; ajoute '/' apres un nom de repertoire (inutilise : Arch ne le fait pas)
ls_slash:
    cmp qword [rax + VN_TYPE], VT_DIR
    jne .e
    push rax
    mov al, '/'
    call putc
    pop rax
.e:
    ret

; rax = noeud : affiche son nom colore (+ '/' si repertoire)
; rax = noeud : nom colore. Pas de '/' ajoute : sous Arch c'est l'option
; -F qui fait ca, la couleur suffit a distinguer les repertoires.
ls_name:
    push rax
    push rsi
    call vfs_color
    mov rsi, [rax + VN_NAME]
    call print
    mov byte [text_attr], C_DEF
    pop rsi
    pop rax
    ret

; rax = noeud : "drwxr-xr-x root root  4096 Sep  6 22:10 "
ls_longline:
    push rax
    push rcx
    push rdx
    mov byte [text_attr], C_DEF
    mov rdx, [rax + VN_TYPE]
    cmp rdx, VT_DIR
    je .d
    cmp rdx, VT_EXEC
    je .x
    mov rsi, s_perm_f
    jmp .p
.d:
    mov rsi, s_perm_d
    jmp .p
.x:
    mov rsi, s_perm_x
.p:
    call print
    call ls_nlink
    mov rsi, s_owner
    call print
    cmp qword [rax + VN_TYPE], VT_DIR   ; taille
    jne .fsize
    mov eax, 4096
    jmp .psize
.fsize:
    mov rsi, [rax + VN_DATA]
    xor ecx, ecx
    test rsi, rsi
    jz .z
    call strlen
.z:
    mov eax, ecx
.psize:
    mov ecx, 6
    call print_dec_w
    mov al, ' '
    call putc
    movzx eax, byte [f_mon]             ; date figee au demarrage
    dec eax
    cmp eax, 12
    jb .m
    xor eax, eax
.m:
    mov rsi, [mon_names + rax*8]
    call print
    mov al, ' '
    call putc
    movzx eax, byte [f_day]
    mov ecx, 2
    call print_dec_w
    mov al, ' '
    call putc
    movzx eax, byte [f_hour]
    call print_dec2
    mov al, ':'
    call putc
    movzx eax, byte [f_min]
    call print_dec2
    mov al, ' '
    call putc
    pop rdx
    pop rcx
    pop rax
    ret

; affiche l'argument entre apostrophes, comme les coreutils
print_quoted:
    push rsi
    mov al, 0x27
    call putc
    mov rsi, arg_buf
    call print
    mov al, 0x27
    call putc
    pop rsi
    ret

cmd_cd:
    push rbx
    mov rsi, [argsp]
    call next_arg
    test rax, rax
    jz .home
    mov rsi, arg_buf
    mov rdi, s_dash
    call strcmp
    je .prev
    mov rsi, arg_buf
    call vfs_resolve
    test rax, rax
    jz .noent
    cmp qword [rax + VN_TYPE], VT_DIR
    jne .notdir
    mov rbx, [cwd_node]
    mov [prev_node], rbx
    mov [cwd_node], rax
    pop rbx
    ret
.home:
    mov rax, [cwd_node]
    mov [prev_node], rax
    mov qword [cwd_node], n_rootdir
    pop rbx
    ret
.prev:
    mov rax, [prev_node]
    mov rbx, [cwd_node]
    mov [cwd_node], rax
    mov [prev_node], rbx
    mov byte [text_attr], C_DEF
    mov rbx, [cwd_node]
    call vfs_print_path
    mov al, 10
    call putc
    pop rbx
    ret
.notdir:
    mov rsi, s_cd
    call print
    mov rsi, arg_buf
    call print
    mov rsi, s_notdir
    call print
    pop rbx
    ret
.noent:
    mov rsi, s_cd
    call print
    mov rsi, arg_buf
    call print
    mov rsi, s_nosuch
    call print
    pop rbx
    ret

cmd_see:
    push rbx
    mov byte [text_attr], C_DEF
    mov rsi, [argsp]
    call next_arg
    test rax, rax
    jz .missing
.loop:
    push rsi
    call cat_one
    pop rsi
    call next_arg
    test rax, rax
    jnz .loop
    pop rbx
    ret
.missing:
    mov rsi, s_cat
    call print
    mov rsi, s_missing
    call print
    pop rbx
    ret

cat_one:
    push rbx
    mov rsi, arg_buf
    call vfs_resolve
    test rax, rax
    jz .noent
    cmp qword [rax + VN_TYPE], VT_DIR
    je .isdir
    mov rbx, rax
    mov rsi, [rbx + VN_DATA]
    test rsi, rsi
    jz .e
    mov byte [text_attr], C_DEF
    call print
    mov rax, [rbx + VN_DATA]            ; /proc/cpuinfo : complete avec CPUID
    mov rcx, t_cpuinfo
    cmp rax, rcx
    jne .e
    mov rsi, cpu_brand
    call print
    mov al, 10
    call putc
    mov rsi, t_cpuinfo2
    call print
.e:
    pop rbx
    ret
.isdir:
    mov rsi, s_cat
    call print
    mov rsi, arg_buf
    call print
    mov rsi, s_isdir
    call print
    pop rbx
    ret
.noent:
    mov rsi, s_cat
    call print
    mov rsi, arg_buf
    call print
    mov rsi, s_nosuch
    call print
    pop rbx
    ret


; ---------------------------------------------------------------------
;  Creation et suppression
; ---------------------------------------------------------------------
; -> rax = noeud neuf remis a zero, ou 0 si le reservoir est plein
node_alloc:
    push rcx
    mov eax, [node_used]
    cmp eax, NODE_MAX
    jae .full
    inc dword [node_used]
    imul eax, VN_SIZE
    add rax, node_pool
    mov qword [rax + VN_NAME], 0
    mov qword [rax + VN_PARENT], 0
    mov qword [rax + VN_DATA], 0
    mov qword [rax + VN_TYPE], 0
    mov qword [rax + VN_NEXT], 0
    pop rcx
    ret
.full:
    xor eax, eax
    pop rcx
    ret

; rsi = nom -> rax = copie permanente, ou 0
name_alloc:
    push rcx
    push rdx
    push rdi
    call strlen
    mov eax, [name_used]
    mov edx, eax
    add edx, ecx
    inc edx
    cmp edx, NAME_POOL
    ja .full
    mov [name_used], edx
    mov edi, name_pool
    add rdi, rax
    push rdi                            ; strcpy se sert de al : on met
    call strcpy                         ; l'adresse de retour a l'abri
    pop rax
    pop rdi
    pop rdx
    pop rcx
    ret
.full:
    xor eax, eax
    pop rdi
    pop rdx
    pop rcx
    ret

; rbx = parent, rax = noeud : insere en respectant l'ordre alphabetique,
; comme le ferait ls -- la liste est donc toujours triee a l'affichage.
vfs_link:
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    mov r8, rax                         ; strcmp_ord renvoie dans rax :
    mov [r8 + VN_PARENT], rbx           ; le noeud est mis a l'abri dans r8
    mov qword [r8 + VN_NEXT], 0
    mov rcx, [rbx + VN_DATA]
    test rcx, rcx
    jz .head
    mov rsi, [r8 + VN_NAME]
    mov rdi, [rcx + VN_NAME]
    call strcmp_ord
    jl .head
.scan:
    mov rdx, [rcx + VN_NEXT]
    test rdx, rdx
    jz .after
    mov rsi, [r8 + VN_NAME]
    mov rdi, [rdx + VN_NAME]
    call strcmp_ord
    jl .after
    mov rcx, rdx
    jmp .scan
.after:
    mov rdx, [rcx + VN_NEXT]
    mov [r8 + VN_NEXT], rdx
    mov [rcx + VN_NEXT], r8
    jmp .e
.head:
    mov [r8 + VN_NEXT], rcx
    mov [rbx + VN_DATA], r8
.e:
    mov rax, r8
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    ret

; rbx = parent, rax = noeud : detache de la liste
vfs_unlink:
    push rcx
    push rdx
    mov rcx, [rbx + VN_DATA]
    cmp rcx, rax
    jne .scan
    mov rdx, [rax + VN_NEXT]
    mov [rbx + VN_DATA], rdx
    jmp .e
.scan:
    test rcx, rcx
    jz .e
    mov rdx, [rcx + VN_NEXT]
    cmp rdx, rax
    je .cut
    mov rcx, rdx
    jmp .scan
.cut:
    mov rdx, [rax + VN_NEXT]
    mov [rcx + VN_NEXT], rdx
.e:
    pop rdx
    pop rcx
    ret

; rsi = chemin -> rax = repertoire parent (0 si absent), comp_buf = dernier nom
; rsi = chemin -> rax = repertoire parent (0 si absent)
;              base_buf = dernier composant du chemin
; Attention : vfs_resolve se sert de comp_buf comme tampon de travail, le
; nom de base a donc son propre tampon.
vfs_parent:
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    mov rdx, rsi
    xor ecx, ecx
    xor edi, edi
.f:
    mov al, [rdx + rcx]                 ; position du dernier '/'
    test al, al
    jz .fe
    cmp al, '/'
    jne .fn
    lea rdi, [rdx + rcx]
.fn:
    inc rcx
    jmp .f
.fe:
    test rdi, rdi
    jnz .split
    mov rsi, rdx                        ; pas de '/' : parent = cwd
    mov rdi, base_buf
    call strcpy
    mov rax, [cwd_node]
    jmp .e
.split:
    push rdi
    mov rsi, rdi                        ; nom apres le dernier '/'
    inc rsi
    mov rdi, base_buf
    call strcpy
    pop rdi
    mov rsi, rdx                        ; partie repertoire, '/' compris
    mov rcx, rdi
    sub rcx, rdx
    inc rcx
    mov rdi, comp_dir
.cp:
    test rcx, rcx
    jz .cpe
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp .cp
.cpe:
    mov byte [rdi], 0
    mov rsi, comp_dir
    call vfs_resolve
.e:
    test rax, rax
    jz .out
    cmp qword [rax + VN_TYPE], VT_DIR
    je .out
    xor eax, eax
.out:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

cmd_mkdir:
    mov byte [mk_type], VT_DIR
    mov qword [mk_prog], s_mkdir
    jmp vfs_create
cmd_mkfile:
    mov byte [mk_type], VT_FILE
    mov qword [mk_prog], s_mkfile
    jmp vfs_create

vfs_create:
    push rbx
    call parse_opts
    mov byte [text_attr], C_DEF
    mov rsi, [argsp]
    call next_arg
    test rax, rax
    jz .missing
.loop:
    push rsi
    call create_one
    pop rsi
    call next_arg
    test rax, rax
    jnz .loop
    pop rbx
    ret
.missing:
    mov rsi, [mk_prog]
    call print
    mov rsi, s_missing
    call print
    pop rbx
    ret

create_one:
    push rbx
    cmp byte [mk_type], VT_DIR          ; mkdir -p : cree toute la chaine
    jne .plain
    cmp byte [opt_p], 0
    je .plain
    mov rsi, arg_buf
    call mkdir_p
    test rax, rax
    jz .noent
    pop rbx
    ret
.plain:
    mov rsi, arg_buf
    call vfs_parent
    test rax, rax
    jz .noent
    mov rbx, rax
    cmp byte [base_buf], 0
    je .noent
    mov rsi, base_buf
    call vfs_child
    test rax, rax
    jnz .exists
    call node_alloc
    test rax, rax
    jz .full
    push rax
    mov rsi, base_buf
    call name_alloc
    mov rdx, rax
    pop rax
    test rdx, rdx
    jz .full
    mov [rax + VN_NAME], rdx
    movzx ecx, byte [mk_type]
    mov [rax + VN_TYPE], rcx
    call vfs_link
    pop rbx
    ret
.exists:
    cmp byte [mk_type], VT_DIR          ; mkfile sur un fichier existant : ok
    jne .ok
    mov rsi, [mk_prog]
    call print
    mov rsi, s_cannot_create
    call print
    call print_quoted
    mov rsi, s_exists
    call print
.ok:
    pop rbx
    ret
.noent:
    mov rsi, [mk_prog]
    call print
    mov rsi, s_cannot_create
    call print
    call print_quoted
    mov rsi, s_nosuch
    call print
    pop rbx
    ret
.full:
    mov rsi, [mk_prog]
    call print
    mov rsi, s_nospace
    call print
    pop rbx
    ret

; rsi = chemin -> rax = dernier repertoire, en creant les manquants
mkdir_p:
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    mov rbx, [cwd_node]
    cmp byte [rsi], '~'
    jne .abs
    mov rbx, n_rootdir
    inc rsi
    jmp .loop
.abs:
    cmp byte [rsi], '/'
    jne .loop
    mov rbx, n_root
.loop:
    cmp byte [rsi], '/'
    jne .comp
    inc rsi
    jmp .loop
.comp:
    cmp byte [rsi], 0
    je .done
    mov rdi, comp_buf
    xor ecx, ecx
.cp:
    mov al, [rsi]
    test al, al
    jz .cpe
    cmp al, '/'
    je .cpe
    cmp ecx, 30
    jae .cpn
    mov [rdi], al
    inc rdi
    inc ecx
.cpn:
    inc rsi
    jmp .cp
.cpe:
    mov byte [rdi], 0
    mov rdx, rsi
    mov rsi, comp_buf
    mov rdi, s_dot
    call strcmp
    je .next
    mov rsi, comp_buf
    mov rdi, s_dotdot
    call strcmp
    jne .find
    mov rax, [rbx + VN_PARENT]
    test rax, rax
    jz .next
    mov rbx, rax
    jmp .next
.find:
    mov rsi, comp_buf
    call vfs_child
    test rax, rax
    jnz .have
    call node_alloc
    test rax, rax
    jz .fail
    push rax
    mov rsi, comp_buf
    call name_alloc
    mov rcx, rax
    pop rax
    test rcx, rcx
    jz .fail
    mov [rax + VN_NAME], rcx
    mov qword [rax + VN_TYPE], VT_DIR
    call vfs_link
.have:
    cmp qword [rax + VN_TYPE], VT_DIR
    jne .fail
    mov rbx, rax
.next:
    mov rsi, rdx
    jmp .loop
.done:
    mov rax, rbx
    jmp .ret
.fail:
    xor eax, eax
.ret:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

cmd_rm:
    mov qword [mk_prog], s_rm
    mov byte [mk_type], 0
    jmp vfs_remove
cmd_rmdir:
    mov qword [mk_prog], s_rmdir
    mov byte [mk_type], 1
    jmp vfs_remove

vfs_remove:
    push rbx
    call parse_opts
    mov byte [text_attr], C_DEF
    mov rsi, [argsp]
    call next_arg
    test rax, rax
    jz .missing
.loop:
    push rsi
    call remove_one
    pop rsi
    call next_arg
    test rax, rax
    jnz .loop
    pop rbx
    ret
.missing:
    mov rsi, [mk_prog]
    call print
    mov rsi, s_missing
    call print
    pop rbx
    ret

remove_one:
    push rbx
    mov rsi, arg_buf
    call vfs_resolve
    test rax, rax
    jz .noent
    mov rbx, rax
    cmp rbx, n_root
    je .busy
    cmp rbx, [cwd_node]
    je .busy
    cmp byte [mk_type], 0
    je .isrm
    cmp qword [rbx + VN_TYPE], VT_DIR   ; rmdir : repertoire vide seulement
    jne .notdir
    cmp qword [rbx + VN_DATA], 0
    jne .notempty
    jmp .unlink
.isrm:
    cmp qword [rbx + VN_TYPE], VT_DIR   ; rm : repertoire seulement avec -r
    jne .unlink
    cmp byte [opt_r], 0
    je .isdir
.unlink:
    mov rax, rbx
    mov rbx, [rax + VN_PARENT]
    test rbx, rbx
    jz .busy
    call vfs_unlink
    pop rbx
    ret
.isdir:
    mov rsi, [mk_prog]
    call print
    mov rsi, s_cannot_remove
    call print
    call print_quoted
    mov rsi, s_isdir
    call print
    pop rbx
    ret
.notdir:
    mov rsi, [mk_prog]
    call print
    mov rsi, s_failed_remove
    call print
    call print_quoted
    mov rsi, s_notdir
    call print
    pop rbx
    ret
.notempty:
    mov rsi, [mk_prog]
    call print
    mov rsi, s_failed_remove
    call print
    call print_quoted
    mov rsi, s_notempty
    call print
    pop rbx
    ret
.busy:
    mov rsi, [mk_prog]
    call print
    mov rsi, s_cannot_remove
    call print
    call print_quoted
    mov rsi, s_busy
    call print
    pop rbx
    ret
.noent:
    mov rsi, [mk_prog]
    call print
    mov rsi, s_cannot_remove
    call print
    call print_quoted
    mov rsi, s_nosuch
    call print
    pop rbx
    ret

cmd_date:
    call print_date_line
    mov al, 10
    call putc
    ret

cmd_uptime:
    mov al, ' '
    call putc
    call rtc_read                   ; -> heure/min/sec dans les variables
    movzx eax, byte [rtc_hour]
    call print_dec2
    mov al, ':'
    call putc
    movzx eax, byte [rtc_min]
    call print_dec2
    mov al, ':'
    call putc
    movzx eax, byte [rtc_sec]
    call print_dec2
    mov rsi, s_up
    call print
    call uptime_secs                ; -> rax secondes
    xor edx, edx
    mov ecx, 60
    div rcx
    push rax                        ; minutes totales
    xor edx, edx
    mov ecx, 60
    div rcx
    test rax, rax
    jz .nohour
    call print_dec
    mov rsi, s_hours
    call print
    pop rax
    xor edx, edx
    mov ecx, 60
    div rcx
    mov rax, rdx
    call print_dec
    mov rsi, s_mins
    call print
    jmp .load
.nohour:
    pop rax
    call print_dec
    mov rsi, s_mins
    call print
.load:
    mov rsi, s_loadavg
    call print
    ret

cmd_sudo:
    mov rsi, s_sudo
    call print
    ret

cmd_reboot:
    mov rsi, s_reboot
    call print
    mov rcx, 800
    call sleep_ms
    mov al, 0xFE                    ; pulse reset via le 8042
    out 0x64, al
    lidt [null_idt]                 ; sinon : triple faute
    int3
    jmp $

cmd_poweroff:
    mov rsi, s_poweroff
    call print
    mov rcx, 800
    call sleep_ms
    mov dx, 0x604                   ; ACPI QEMU
    mov ax, 0x2000
    out dx, ax
    mov dx, 0xB004                  ; Bochs
    mov ax, 0x2000
    out dx, ax
    cli
    hlt
    jmp $

cmd_exit:
    mov byte [shell_exit], 1
    ret


; =====================================================================
;  sys : informations systeme
; =====================================================================
cmd_sys:
    push rbx
    push r12
    xor r12d, r12d
.loop:
    ; --- logo ASCII : un caractere et un attribut par cellule (pas juste
    ; par ligne), pour que l'engrenage, le manche et la tete du marteau
    ; sortent chacun dans leur propre couleur.
    mov eax, r12d
    imul eax, LOGO_W
    mov ebx, eax                     ; ebx = decalage du debut de la ligne
    xor ecx, ecx
.col:
    cmp ecx, LOGO_W
    jae .padded
    mov edx, ebx
    add edx, ecx
    mov al, [logo_chars + rdx]
    cmp al, ' '
    je .blank
    mov ah, [logo_attrs + rdx]
    mov [text_attr], ah
    call putc
    jmp .nextcol
.blank:
    mov byte [text_attr], C_DEF
    call putc
.nextcol:
    inc ecx
    jmp .col
.padded:
    mov byte [text_attr], C_DEF
    mov al, ' '
    call putc
    call putc
    ; --- ligne d'information a droite
    mov rax, [info_lines + r12*8]
    test rax, rax
    jz .nl
    call rax
.nl:
    mov byte [text_attr], C_DEF
    mov al, 10
    call putc
    inc r12d
    cmp r12d, LOGO_N
    jb .loop
    mov byte [text_attr], C_DEF
    pop r12
    pop rbx
    ret

; rsi = etiquette, rdi = valeur
ff_kv:
    mov byte [text_attr], C_CYAN
    call print
    mov byte [text_attr], C_DEF
    mov rsi, rdi
    call print
    ret

ff_title:
    mov byte [text_attr], C_CYAN
    mov rsi, user_buf
    call print
    mov byte [text_attr], C_DEF
    mov al, '@'
    call putc
    mov byte [text_attr], C_CYAN
    mov rsi, s_host
    call print
    ret

; trait de la meme longueur que "user@hote"
ff_rule:
    push rbx
    mov byte [text_attr], C_DEF
    mov rsi, user_buf
    call strlen
    mov ebx, ecx
    mov rsi, s_host
    call strlen
    add ebx, ecx
    inc ebx
.l:
    mov al, '-'
    call putc
    dec ebx
    jnz .l
    pop rbx
    ret

ff_os:
    mov rsi, s_ff_os
    mov rdi, s_osname
    jmp ff_kv

ff_hostm:
    mov byte [text_attr], C_CYAN
    mov rsi, s_ff_host
    call print
    mov byte [text_attr], C_DEF
    mov rsi, host_name
    cmp byte [rsi], 0
    jne .p
    mov rsi, s_unknown
.p:
    mov ecx, 45
.l:
    lodsb
    test al, al
    jz .e
    call putc
    dec ecx
    jnz .l
.e:
    ret

ff_kernel:
    mov rsi, s_ff_kernel
    mov rdi, s_krel
    jmp ff_kv

ff_uptime:
    mov byte [text_attr], C_CYAN
    mov rsi, s_ff_uptime
    call print
    mov byte [text_attr], C_DEF
    call uptime_secs
    xor edx, edx
    mov ecx, 60
    div rcx
    push rax
    xor edx, edx
    mov ecx, 60
    div rcx
    test rax, rax
    jz .m
    call print_dec
    mov rsi, s_h
    call print
    pop rax
    xor edx, edx
    mov ecx, 60
    div rcx
    mov rax, rdx
    call print_dec
    mov rsi, s_m
    call print
    ret
.m:
    pop rax
    call print_dec
    mov rsi, s_m
    call print
    ret

ff_packages:
    mov rsi, s_ff_pkgs
    mov rdi, s_pkgs
    jmp ff_kv

ff_shell:
    mov rsi, s_ff_shell
    mov rdi, s_shellv
    jmp ff_kv

ff_display:
    mov byte [text_attr], C_CYAN
    mov rsi, s_ff_disp
    call print
    mov byte [text_attr], C_DEF
    mov rsi, s_80x
    call print
    movzx eax, byte [scr_h]
    call print_dec
    mov rsi, s_textmode
    jmp print

ff_term:
    mov rsi, s_ff_term
    mov rdi, s_termv
    jmp ff_kv

; "CPU: Intel Core i7-8550U (8) @ 1.80 GHz" -- tout est mesure ou lu
; dans CPUID, rien n'est code en dur.
ff_cpu:
    mov byte [text_attr], C_CYAN
    mov rsi, s_ff_cpu
    call print
    mov byte [text_attr], C_DEF
    push rbx
    mov eax, [cpu_cores]            ; longueur du suffixe " (N) @ X.XXGHz"
    call count_digits
    add ecx, 3
    cmp dword [cpu_mhz], 0
    je .nofreq
    add ecx, 10
.nofreq:
    mov ebx, 46                     ; colonnes libres apres "CPU: "
    sub ebx, ecx
    mov rsi, cpu_brand
.l:
    test ebx, ebx
    jz .e
    lodsb
    test al, al
    jz .e
    call putc
    dec ebx
    jmp .l
.e:
    pop rbx
    mov rsi, s_par1
    call print
    mov eax, [cpu_cores]
    call print_dec
    mov rsi, s_par2
    call print
    mov eax, [cpu_mhz]
    test eax, eax
    jz .end
    mov rsi, s_at
    call print
    mov eax, [cpu_mhz]
    call print_ghz
.end:
    ret

ff_gpu:
    mov byte [text_attr], C_CYAN
    mov rsi, s_ff_gpu
    call print
    mov byte [text_attr], C_DEF
    cmp byte [gpu_found], 0
    je .none
    mov eax, [gpu_id]
    call vendor_name
    call print
    mov rsi, s_brk1
    call print
    mov ax, [gpu_id]
    call print_hex16
    mov al, ':'
    call putc
    mov eax, [gpu_id]
    shr eax, 16
    call print_hex16
    mov rsi, s_brk2b
    jmp print
.none:
    mov rsi, s_unknown
    jmp print

ff_memory:
    mov byte [text_attr], C_CYAN
    mov rsi, s_ff_mem
    call print
    mov byte [text_attr], C_DEF
    mov rax, MEM_USED_MB
    call print_dec
    mov rsi, s_mib_slash
    call print
    mov rax, [mem_total_kb]
    shr rax, 10
    call print_dec
    mov rsi, s_mib
    call print
    ret

ff_colors1:
    xor r8d, r8d
    jmp ff_blocks
ff_colors2:
    mov r8d, 8
ff_blocks:
    xor ecx, ecx
.b:
    mov eax, ecx
    add eax, r8d
    shl eax, 4
    mov [text_attr], al
    mov al, ' '
    call putc
    call putc
    call putc
    inc ecx
    cmp ecx, 8
    jb .b
    mov byte [text_attr], C_DEF
    ret


; =====================================================================
;  Pilote ecran VGA texte
; =====================================================================
cls:
    push rax
    push rcx
    push rdi
    mov rdi, VGA_MEM
    mov ah, C_DEF
    mov al, ' '
    mov ecx, 16384                  ; toute la page texte, pas seulement les
    rep stosw                       ; lignes visibles : rien ne peut survivre
    mov byte [cursor_x], 0
    mov byte [cursor_y], 0
    call update_cursor
    pop rdi
    pop rcx
    pop rax
    ret

; al = caractere
putc:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    cmp al, 10
    je .nl
    cmp al, 13
    je .cr
    cmp al, 8
    je .bs
    movzx ebx, byte [cursor_y]
    imul ebx, VGA_W
    movzx ecx, byte [cursor_x]
    add ebx, ecx
    shl ebx, 1
    add ebx, VGA_MEM
    mov ah, [text_attr]
    mov [rbx], ax
    inc byte [cursor_x]
    cmp byte [cursor_x], VGA_W
    jb .done
    mov byte [cursor_x], 0
    jmp .down
.nl:
    mov byte [cursor_x], 0
.down:
    inc byte [cursor_y]
    mov dl, [scr_h]
    cmp [cursor_y], dl
    jb .done
    call scroll
    dec dl
    mov [cursor_y], dl
    jmp .done
.cr:
    mov byte [cursor_x], 0
    jmp .done
.bs:
    cmp byte [cursor_x], 0
    je .done
    dec byte [cursor_x]
.done:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

scroll:
    push rax
    push rcx
    push rsi
    push rdi
    movzx ecx, byte [scr_h]
    dec ecx
    mov rsi, VGA_MEM + VGA_W * 2
    mov rdi, VGA_MEM
    imul ecx, VGA_W * 2 / 8         ; 20 quadmots par ligne
    rep movsq
    movzx eax, byte [scr_h]
    dec eax
    imul eax, VGA_W * 2
    mov edi, VGA_MEM
    add edi, eax
    mov ah, C_DEF
    mov al, ' '
    mov ecx, VGA_W
    rep stosw
    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret

; rsi = chaine terminee par 0
print:
    push rax
    push rsi
.l:
    lodsb
    test al, al
    jz .e
    call putc
    jmp .l
.e:
    pop rsi
    pop rax
    ret

update_cursor:
    push rax
    push rbx
    push rdx
    movzx eax, byte [cursor_y]
    imul eax, VGA_W
    movzx ebx, byte [cursor_x]
    add eax, ebx
    mov ebx, eax
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    mov dx, 0x3D5
    mov al, bl
    out dx, al
    mov dx, 0x3D4
    mov al, 0x0E
    out dx, al
    mov dx, 0x3D5
    mov al, bh
    out dx, al
    pop rdx
    pop rbx
    pop rax
    ret

cursor_enable:
    push rax
    push rdx
    mov dx, 0x3D4
    mov al, 0x0A
    out dx, al
    mov dx, 0x3D5
    mov al, 0x0D
    out dx, al
    mov dx, 0x3D4
    mov al, 0x0B
    out dx, al
    mov dx, 0x3D5
    mov al, 0x0F
    out dx, al
    pop rdx
    pop rax
    ret


; =====================================================================
;  Clavier PS/2 (scrutation, jeu de scancodes 1)
; =====================================================================
getchar:
    push rbx
    push rcx
    push rdx
    push rsi
    call update_cursor
.poll:
    in al, 0x64
    test al, 1
    jz .poll
    test al, 0x20                   ; octet souris -> jete
    jnz .drop
    in al, 0x60
    cmp al, 0xE0
    jne .nopfx
    mov byte [kbd_ext], 1
    jmp .poll
.drop:
    in al, 0x60
    jmp .poll
.nopfx:
    test al, 0x80
    jnz .release
    cmp byte [kbd_ext], 0
    jne .extended
    cmp al, 0x2A
    je .shift_on
    cmp al, 0x36
    je .shift_on
    cmp al, 0x1D
    je .ctrl_on
    cmp al, 0x3A
    je .caps
    cmp al, 0x38
    je .poll
    cmp al, 0x58
    jae .poll
    cmp al, 0x01                     ; Echap (scancode 1), cas particulier :
    jne .notesc                      ; Ctrl+Echap a son propre code, la
    cmp byte [kbd_ctrl], 0           ; combinaison passe sous le a-z du
    je .notesc                       ; bloc Ctrl+lettre juste en dessous
    mov al, K_CTRLESC
    jmp .ret
.notesc:
    movzx ebx, al
    cmp byte [kbd_ctrl], 0
    je .normal
    mov rsi, [kbd_lo]
    mov al, [rsi + rbx]
    cmp al, 'a'
    jb .poll
    cmp al, 'z'
    ja .poll
    sub al, 'a' - 1                 ; Ctrl+A = 1 ... Ctrl+Z = 26
    jmp .ret
.normal:
    mov rsi, [kbd_lo]
    cmp byte [kbd_shift], 0
    je .tbl
    mov rsi, [kbd_hi]
.tbl:
    mov al, [rsi + rbx]
    test al, al
    jz .poll
    cmp byte [kbd_caps], 0
    je .ret
    cmp al, 'a'
    jb .ret
    cmp al, 'z'
    jbe .toupper
    cmp al, 'A'
    jb .ret
    cmp al, 'Z'
    ja .ret
    add al, 32
    jmp .ret
.toupper:
    sub al, 32
.ret:
    mov byte [kbd_ext], 0
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret
.extended:
    mov byte [kbd_ext], 0
    cmp al, 0x48
    je .up
    cmp al, 0x50
    je .down
    cmp al, 0x4B
    je .left
    cmp al, 0x4D
    je .right
    cmp al, 0x53
    je .del
    cmp al, 0x1D
    je .ctrl_on
    jmp .poll
.del:
    mov al, K_DEL
    jmp .ret
.up:
    mov al, K_UP
    jmp .ret
.down:
    mov al, K_DOWN
    jmp .ret
.left:
    mov al, K_LEFT
    jmp .ret
.right:
    mov al, K_RIGHT
    jmp .ret
.release:
    mov byte [kbd_ext], 0
    and al, 0x7F
    cmp al, 0x2A
    je .shift_off
    cmp al, 0x36
    je .shift_off
    cmp al, 0x1D
    je .ctrl_off
    jmp .poll
.shift_on:
    mov byte [kbd_shift], 1
    jmp .poll
.shift_off:
    mov byte [kbd_shift], 0
    jmp .poll
.ctrl_on:
    mov byte [kbd_ctrl], 1
    jmp .poll
.ctrl_off:
    mov byte [kbd_ctrl], 0
    jmp .poll
.caps:
    xor byte [kbd_caps], 1
    jmp .poll


; ---------------------------------------------------------------------
;  Lecture d'une ligne
;  rdi = tampon, ecx = taille max, [rl_flags] bit0 = sans echo
;                                             bit1 = historique + invite
; ---------------------------------------------------------------------
readline:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13d, ecx
    dec r13d
    xor r14d, r14d
    mov byte [r12], 0
    mov al, [hist_count]
    mov [hist_pos], al
.loop:
    call getchar
    cmp al, 10
    je .enter
    cmp al, 8
    je .backspace
    cmp al, 3
    je .ctrlc
    cmp al, 12
    je .ctrll
    cmp al, 9
    je .tab
    cmp al, K_UP
    je .histup
    cmp al, K_DOWN
    je .histdn
    cmp al, ' '                     ; laisse passer 0x80-0xFF : accents CP437
    jb .loop
    cmp r14d, r13d
    jae .loop
    mov [r12 + r14], al
    inc r14d
    mov byte [r12 + r14], 0
    test byte [rl_flags], 1
    jnz .loop
    call putc
    jmp .loop
.backspace:
    test r14d, r14d
    jz .loop
    dec r14d
    mov byte [r12 + r14], 0
    test byte [rl_flags], 1
    jnz .loop
    call bs_erase
    jmp .loop
.ctrlc:
    mov byte [text_attr], C_DEF
    mov al, '^'
    call putc
    mov al, 'C'
    call putc
    mov al, 10
    call putc
    mov byte [r12], 0
    xor r14d, r14d
    jmp .fin
.tab:
    test byte [rl_flags], 2         ; uniquement en mode shell, avec echo
    jz .loop
    test byte [rl_flags], 1
    jnz .loop
    call rl_complete
    jmp .loop
.ctrll:
    call cls
    test byte [rl_flags], 2
    jz .cl2
    call print_prompt
.cl2:
    test byte [rl_flags], 1
    jnz .loop
    mov rsi, r12
    call print
    jmp .loop
.histup:
    test byte [rl_flags], 2
    jz .loop
    cmp byte [hist_pos], 0
    je .loop
    dec byte [hist_pos]
    jmp .histload
.histdn:
    test byte [rl_flags], 2
    jz .loop
    movzx eax, byte [hist_pos]
    cmp al, [hist_count]
    jae .loop
    inc byte [hist_pos]
    movzx eax, byte [hist_pos]
    cmp al, [hist_count]
    jb .histload
    call rl_clear
    mov byte [r12], 0
    xor r14d, r14d
    jmp .loop
.histload:
    call rl_clear
    movzx eax, byte [hist_pos]
    imul eax, CMDLEN
    mov esi, hist_buf
    add rsi, rax
    mov rdi, r12
    call strcpy                     ; rcx = longueur copiee
    mov r14d, ecx
    mov rsi, r12
    call print
    jmp .loop
.enter:
    mov al, 10
    call putc
    test byte [rl_flags], 2
    jz .fin
    test r14d, r14d
    jz .fin
    call hist_add
.fin:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; ---------------------------------------------------------------------
;  Completion par Tab
;  Premier mot -> noms de commandes. Mots suivants -> entrees du systeme
;  de fichiers, chemins multi-niveaux compris (cd /usr/sh<Tab>).
;  Une seule correspondance : elle est completee. Plusieurs : elles sont
;  listees et la ligne est reaffichee, comme bash.
;  Travaille directement sur r12 (tampon), r13d (taille max) et r14d
;  (longueur) de readline.
; ---------------------------------------------------------------------
; rsi = prefixe, ecx = longueur, rdi = candidat -> ZF=1 si rdi commence par rsi
prefix_match:
    push rsi
    push rdi
    push rcx
.l:
    test ecx, ecx
    jz .yes
    mov al, [rsi]
    cmp al, [rdi]
    jne .no
    inc rsi
    inc rdi
    dec ecx
    jmp .l
.yes:
    pop rcx
    pop rdi
    pop rsi
    xor eax, eax
    ret
.no:
    pop rcx
    pop rdi
    pop rsi
    mov eax, 1
    test eax, eax
    ret

; al = caractere : l'ajoute au tampon de saisie et l'affiche
rl_putchar:
    cmp r14d, r13d
    jae .e
    mov [r12 + r14], al
    inc r14d
    mov byte [r12 + r14], 0
    call putc
.e:
    ret

; rsi = chaine a ajouter au tampon de saisie
rl_append:
    push rax
    push rsi
.l:
    mov al, [rsi]
    test al, al
    jz .e
    call rl_putchar
    inc rsi
    jmp .l
.e:
    pop rsi
    pop rax
    ret

; rsi = candidat : reduit comp_lcp au prefixe commun avec comp_first
lcp_update:
    push rax
    push rcx
    push rdi
    mov rdi, [comp_first]
    xor ecx, ecx
.l:
    cmp ecx, [comp_lcp]
    jae .e
    mov al, [rdi + rcx]
    test al, al
    jz .e
    cmp al, [rsi + rcx]
    jne .e
    inc ecx
    jmp .l
.e:
    mov [comp_lcp], ecx
    pop rdi
    pop rcx
    pop rax
    ret

; etend la saisie jusqu'au prefixe commun a toutes les correspondances
lcp_extend:
    push rax
    push rcx
    push rdx
    push rsi
    mov ecx, [comp_lcp]
    cmp ecx, r9d
    jbe .e
    mov edx, ecx
    sub edx, r9d
    mov rsi, [comp_first]
    add rsi, r9
.l:
    mov al, [rsi]
    call rl_putchar
    inc rsi
    dec edx
    jnz .l
.e:
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; complete jusqu'a la prochaine colonne multiple de 14
pad_col:
    push rax
    push rdx
    push r8
.p:
    movzx eax, byte [cursor_x]
    xor edx, edx
    mov r8d, 14
    div r8d
    test edx, edx
    jz .e
    mov al, ' '
    call putc
    jmp .p
.e:
    pop r8
    pop rdx
    pop rax
    ret

rl_complete:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    mov r8d, r14d                       ; --- debut du dernier mot
.back:
    test r8d, r8d
    jz .start_ok
    mov eax, r8d
    dec eax
    mov cl, [r12 + rax]
    cmp cl, ' '
    je .start_ok
    dec r8d
    jmp .back
.start_ok:
    mov ecx, r8d                        ; --- est-ce le premier mot ?
.chk:
    test ecx, ecx
    jz .cmdmode
    dec ecx
    cmp byte [r12 + rcx], ' '
    je .chk
    jmp .pathmode

; ---- completion des noms de commandes
.cmdmode:
    mov r9d, r14d
    sub r9d, r8d
    xor r10d, r10d
    xor r11, r11
    mov rbx, cmd_table
.c1:
    mov rdi, [rbx]
    test rdi, rdi
    jz .c1e
    mov rsi, r12
    add rsi, r8
    mov ecx, r9d
    call prefix_match
    jne .c1n
    inc r10d
    mov r11, rdi
    cmp r10d, 1
    jne .c1lcp
    mov [comp_first], rdi
    push rsi
    mov rsi, rdi
    call strlen
    mov [comp_lcp], ecx
    pop rsi
    jmp .c1n
.c1lcp:
    push rsi
    mov rsi, rdi
    call lcp_update
    pop rsi
.c1n:
    add rbx, 16
    jmp .c1
.c1e:
    test r10d, r10d
    jz .ret
    cmp r10d, 1
    je .apply_cmd
    call lcp_extend                     ; comme bash : prefixe commun d'abord
    mov al, 10
    call putc
    mov byte [text_attr], C_DEF
    mov rbx, cmd_table
.c2:
    mov rdi, [rbx]
    test rdi, rdi
    jz .c2e
    mov rsi, r12
    add rsi, r8
    mov ecx, r9d
    call prefix_match
    jne .c2n
    cmp byte [cursor_x], 62
    jb .c2w
    mov al, 10
    call putc
.c2w:
    mov rsi, rdi
    call print
    mov al, ' '
    call putc
    call pad_col
.c2n:
    add rbx, 16
    jmp .c2
.c2e:
    mov al, 10
    call putc
    call print_prompt
    mov rsi, r12
    call print
    jmp .ret
.apply_cmd:
    mov rsi, r11
    add rsi, r9
    call rl_append
    mov al, ' '
    call rl_putchar
    jmp .ret

; ---- completion des chemins
.pathmode:
    mov r10d, -1                        ; position du dernier '/'
    mov ecx, r8d
.fs:
    cmp ecx, r14d
    jae .fse
    cmp byte [r12 + rcx], '/'
    jne .fsn
    mov r10d, ecx
.fsn:
    inc ecx
    jmp .fs
.fse:
    cmp r10d, -1
    je .nodir
    mov rdi, comp_dir                   ; partie repertoire du mot
    mov ecx, r8d
.cd1:
    cmp ecx, r10d
    ja .cd1e
    mov al, [r12 + rcx]
    mov [rdi], al
    inc rdi
    inc ecx
    jmp .cd1
.cd1e:
    mov byte [rdi], 0
    mov rsi, comp_dir
    call vfs_resolve
    mov rbx, rax
    mov r8d, r10d
    inc r8d
    jmp .havedir
.nodir:
    mov rbx, [cwd_node]
.havedir:
    test rbx, rbx
    jz .ret
    cmp qword [rbx + VN_TYPE], VT_DIR
    jne .ret
    mov rdx, [rbx + VN_DATA]
    test rdx, rdx
    jz .ret
    mov r9d, r14d
    sub r9d, r8d
    xor r10d, r10d
    xor r11, r11
    mov rcx, rdx
.p1:
    test rcx, rcx
    jz .p1e
    mov rax, rcx
    mov rdi, [rax + VN_NAME]
    cmp byte [rdi], '.'                 ; entrees cachees : seulement si
    jne .p1ok                              ; le prefixe commence par un point
    test r9d, r9d
    jz .p1n
    mov al, [r12 + r8]
    cmp al, '.'
    jne .p1n
.p1ok:
    mov rsi, r12
    add rsi, r8
    push rcx
    push rax
    mov ecx, r9d
    call prefix_match
    pop rax
    pop rcx
    jne .p1n
    inc r10d
    mov r11, rax
    mov rdi, [rax + VN_NAME]
    cmp r10d, 1
    jne .p1lcp
    mov [comp_first], rdi
    push rsi
    push rcx                            ; rcx = curseur sur les enfants,
    mov rsi, rdi                        ; or strlen renvoie dans rcx
    call strlen
    mov [comp_lcp], ecx
    pop rcx
    pop rsi
    jmp .p1n
.p1lcp:
    push rsi
    push rcx
    mov rsi, rdi
    call lcp_update
    pop rcx
    pop rsi
.p1n:
    mov rcx, [rcx + VN_NEXT]
    jmp .p1
.p1e:
    test r10d, r10d
    jz .ret
    cmp r10d, 1
    je .apply_path
    call lcp_extend
    mov al, 10
    call putc
    mov rcx, rdx
.p2:
    test rcx, rcx
    jz .p2e
    mov rax, rcx
    mov rdi, [rax + VN_NAME]
    cmp byte [rdi], '.'                 ; entrees cachees : seulement si
    jne .p2ok                              ; le prefixe commence par un point
    test r9d, r9d
    jz .p2n
    mov al, [r12 + r8]
    cmp al, '.'
    jne .p2n
.p2ok:
    mov rsi, r12
    add rsi, r8
    push rcx
    push rax
    mov ecx, r9d
    call prefix_match
    pop rax
    pop rcx
    jne .p2n
    push rcx
    cmp byte [cursor_x], 62
    jb .p2w
    mov al, 10
    call putc
.p2w:
    call ls_name
    mov al, ' '
    call putc
    call pad_col
    pop rcx
.p2n:
    mov rcx, [rcx + VN_NEXT]
    jmp .p2
.p2e:
    mov byte [text_attr], C_DEF
    mov al, 10
    call putc
    call print_prompt
    mov rsi, r12
    call print
    jmp .ret
.apply_path:
    mov rsi, [r11 + VN_NAME]
    add rsi, r9
    call rl_append
    cmp qword [r11 + VN_TYPE], VT_DIR
    jne .apf
    mov al, '/'
    call rl_putchar
    jmp .ret
.apf:
    mov al, ' '
    call rl_putchar
.ret:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

bs_erase:
    push rax
    mov al, 8
    call putc
    mov al, ' '
    call putc
    mov al, 8
    call putc
    pop rax
    ret

; efface visuellement r14d caracteres
rl_clear:
    push rcx
    mov ecx, r14d
    test ecx, ecx
    jz .e
.l:
    call bs_erase
    dec ecx
    jnz .l
.e:
    pop rcx
    ret

; ajoute [r12] a l'historique
hist_add:
    push rax
    push rcx
    push rsi
    push rdi
    cmp byte [hist_count], HIST_MAX
    jb .store
    ; decale tout d'un cran
    mov esi, hist_buf + CMDLEN
    mov edi, hist_buf
    mov ecx, (HIST_MAX - 1) * CMDLEN
    rep movsb
    mov byte [hist_count], HIST_MAX - 1
.store:
    movzx eax, byte [hist_count]
    imul eax, CMDLEN
    mov edi, hist_buf
    add rdi, rax
    mov rsi, r12
    call strcpy
    inc byte [hist_count]
    mov al, [hist_count]
    mov [hist_pos], al
    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret


; =====================================================================
;  Chaines et nombres
; =====================================================================
; rsi, rdi -> ZF=1 si egales
strcmp:
    push rsi
    push rdi
    push rbx
.l:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .ne
    test al, al
    jz .eq
    inc rsi
    inc rdi
    jmp .l
.eq:
    pop rbx
    pop rdi
    pop rsi
    xor eax, eax
    ret
.ne:
    pop rbx
    pop rdi
    pop rsi
    mov eax, 1
    test eax, eax
    ret

; rsi, rdi -> eax < 0, = 0 ou > 0 selon l'ordre lexicographique
strcmp_ord:
    push rsi
    push rdi
    push rcx
    push rdx
.l:
    movzx ecx, byte [rsi]
    movzx edx, byte [rdi]
    cmp ecx, edx
    jne .diff
    test ecx, ecx
    jz .eq
    inc rsi
    inc rdi
    jmp .l
.eq:
    xor eax, eax
    jmp .e
.diff:
    sub ecx, edx
    mov eax, ecx
.e:
    pop rdx
    pop rcx
    pop rdi
    pop rsi
    test eax, eax
    ret

; rsi -> rcx = longueur
strlen:
    push rsi
    xor ecx, ecx
.l:
    cmp byte [rsi], 0
    je .e
    inc rsi
    inc ecx
    jmp .l
.e:
    pop rsi
    ret

; rsi -> rdi, renvoie rcx = longueur
strcpy:
    push rsi
    push rdi
    xor ecx, ecx
.l:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .e
    inc rsi
    inc rdi
    inc ecx
    jmp .l
.e:
    pop rdi
    pop rsi
    ret

; rax = nombre non signe
print_dec:
    push rax
    push rbx
    push rcx
    push rdx
    mov rbx, 10
    xor ecx, ecx
    test rax, rax
    jnz .conv
    mov al, '0'
    call putc
    jmp .done
.conv:
    xor edx, edx
    div rbx
    add dl, '0'
    push rdx
    inc ecx
    test rax, rax
    jnz .conv
.out:
    pop rax
    call putc
    dec ecx
    jnz .out
.done:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; rax = nombre, ecx = largeur (aligne a droite)
print_dec_w:
    push rax
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    mov r8, rax
    mov r9d, 1
    mov rbx, 10
.cnt:
    xor edx, edx
    div rbx
    test rax, rax
    jz .cd
    inc r9d
    jmp .cnt
.cd:
    sub ecx, r9d
    jle .num
.sp:
    mov al, ' '
    call putc
    dec ecx
    jnz .sp
.num:
    mov rax, r8
    call print_dec
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; eax = 0..99, affiche sur 2 chiffres
print_dec2:
    push rax
    push rbx
    push rdx
    movzx eax, al
    xor edx, edx
    mov ebx, 10
    div ebx
    push rdx
    add al, '0'
    call putc
    pop rdx
    mov al, dl
    add al, '0'
    call putc
    pop rdx
    pop rbx
    pop rax
    ret

; ---------------------------------------------------------------------
;  Attente calibree : rcx = millisecondes
;  Canal 2 du PIT programme en mode 0 (one-shot), on scrute OUT2 sur le
;  bit 5 du port 0x61. Independant de la vitesse du processeur, donc le
;  rythme du boot est le meme en TCG, en KVM et sur du vrai materiel.
; ---------------------------------------------------------------------
sleep_ms:
    push rax
    push rbx
    push rcx
    push rdx
    test rcx, rcx
    jz .end
.each:
    in al, 0x61
    and al, 0xFC                    ; gate 2 bas -> remet le compteur a zero
    out 0x61, al
    mov al, 0xB0                    ; canal 2, LSB+MSB, mode 0, binaire
    out 0x43, al
    mov ax, 1193                    ; 1193 / 1193182 Hz ~= 1 ms
    out 0x42, al
    mov al, ah
    out 0x42, al
    in al, 0x61
    and al, 0xFD                    ; haut-parleur coupe
    or  al, 0x01                    ; gate 2 haut -> demarre
    out 0x61, al
    mov rbx, 8000000                ; garde-fou anti-blocage
.wait:
    in al, 0x61
    test al, 0x20                   ; OUT2 = 1 -> fin du comptage
    jnz .next
    dec rbx
    jnz .wait
.next:
    dec rcx
    jnz .each
.end:
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret


; =====================================================================
;  CMOS / horloge temps reel
; =====================================================================
; al = registre -> al = valeur
cmos_read:
    push rdx
    or al, 0x80                     ; NMI desactive (pas d'IDT !)
    mov dx, 0x70
    out dx, al
    mov dx, 0x71
    in al, dx
    pop rdx
    ret

rtc_read:
    push rax
    push rbx
.wait:
    mov al, 0x0A
    call cmos_read
    test al, 0x80                   ; mise a jour en cours
    jnz .wait
    mov al, 0x00
    call cmos_read
    mov [rtc_sec], al
    mov al, 0x02
    call cmos_read
    mov [rtc_min], al
    mov al, 0x04
    call cmos_read
    mov [rtc_hour], al
    mov al, 0x07
    call cmos_read
    mov [rtc_day], al
    mov al, 0x08
    call cmos_read
    mov [rtc_mon], al
    mov al, 0x09
    call cmos_read
    mov [rtc_year], al
    mov al, 0x06
    call cmos_read
    mov [rtc_wday], al
    ; format BCD ?
    mov al, 0x0B
    call cmos_read
    test al, 0x04
    jnz .done                       ; deja binaire
    mov rbx, rtc_sec
    mov ecx, 6
.bcd:
    mov al, [rbx]
    mov ah, al
    and al, 0x0F
    shr ah, 4
    add ah, ah
    mov dl, ah
    shl ah, 2
    add ah, dl                      ; ah = dizaines * 10
    add al, ah
    mov [rbx], al
    inc rbx
    dec ecx
    jnz .bcd
.done:
    pop rbx
    pop rax
    ret

; secondes ecoulees depuis minuit -> rax
secs_of_day:
    push rbx
    call rtc_read
    movzx eax, byte [rtc_hour]
    mov ebx, 3600
    mul ebx
    movzx ebx, byte [rtc_min]
    imul ebx, 60
    add eax, ebx
    movzx ebx, byte [rtc_sec]
    add eax, ebx
    pop rbx
    ret

rtc_boot_time:
    call secs_of_day
    mov [boot_secs], rax
    mov al, [rtc_mon]                   ; date de reference pour ls -l
    mov [f_mon], al
    mov al, [rtc_day]
    mov [f_day], al
    mov al, [rtc_hour]
    mov [f_hour], al
    mov al, [rtc_min]
    mov [f_min], al
    ret

; uptime en secondes -> rax
uptime_secs:
    push rbx
    call secs_of_day
    mov rbx, [boot_secs]
    sub rax, rbx
    jns .ok
    add rax, 86400                  ; passage de minuit
.ok:
    pop rbx
    ret

; "Fri Sep  4 14:23:11 UTC 2026"
print_date_line:
    push rbx
    call rtc_read
    movzx eax, byte [rtc_wday]
    dec eax
    and eax, 7
    cmp eax, 7
    jb .w
    xor eax, eax
.w:
    mov rsi, [wday_names + rax*8]
    call print
    mov al, ' '
    call putc
    movzx eax, byte [rtc_mon]
    dec eax
    cmp eax, 12
    jb .m
    xor eax, eax
.m:
    mov rsi, [mon_names + rax*8]
    call print
    mov al, ' '
    call putc
    movzx eax, byte [rtc_day]
    mov ecx, 2
    call print_dec_w
    mov al, ' '
    call putc
    movzx eax, byte [rtc_hour]
    call print_dec2
    mov al, ':'
    call putc
    movzx eax, byte [rtc_min]
    call print_dec2
    mov al, ':'
    call putc
    movzx eax, byte [rtc_sec]
    call print_dec2
    mov rsi, s_utc
    call print
    movzx eax, byte [rtc_year]
    add eax, 2000
    call print_dec
    pop rbx
    ret


; =====================================================================
;  Detection materielle
; =====================================================================
; Somme des zones utilisables de la carte E820 -> mem_total_kb
mem_detect:
    push rbx
    mov ecx, [E820_COUNT]
    test ecx, ecx
    jz .fallback
    mov esi, E820_TABLE
    xor rbx, rbx                    ; total en octets
.l:
    mov eax, [rsi + 16]             ; type
    cmp eax, 1                      ; 1 = memoire utilisable
    jne .next
    mov rax, [rsi + 8]              ; longueur
    add rbx, rax
.next:
    add rsi, 24
    dec ecx
    jnz .l
    shr rbx, 10                     ; -> Kio
    mov [mem_total_kb], rbx
    test rbx, rbx
    jnz .done
.fallback:
    mov qword [mem_total_kb], 131072
.done:
    pop rbx
    ret

; Chaine du processeur via CPUID 0x80000002..4
cpu_detect:
    push rbx
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000004
    jb .unknown
    mov edi, cpu_brand
    mov eax, 0x80000002
    call .store
    mov eax, 0x80000003
    call .store
    mov eax, 0x80000004
    call .store
    mov byte [rdi], 0
    ; supprime les espaces de tete
    mov esi, cpu_brand
.trim:
    cmp byte [rsi], ' '
    jne .trimmed
    inc rsi
    jmp .trim
.trimmed:
    mov edi, cpu_brand
    cmp rsi, rdi
    je .done
    call strcpy
.done:
    pop rbx
    ret
.store:
    cpuid
    mov [rdi], eax
    mov [rdi + 4], ebx
    mov [rdi + 8], ecx
    mov [rdi + 12], edx
    add rdi, 16
    ret
.unknown:
    mov esi, s_cpu_unk
    mov edi, cpu_brand
    call strcpy
    pop rbx
    ret



; =====================================================================
;  Police et taille de l'ecran (mode 80x25 <-> 80x50)
; =====================================================================
%define FONT8_ADDR  0x6000              ; police 8x8 recuperee par le boot

; Televerse la police 8x8 dans le bloc 1 du plan 2 du VGA.
; Le bloc 0 garde la police 8x16 du BIOS, on peut donc revenir en arriere.
vga_load_font8:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    mov dx, 0x3C4                       ; --- acces lineaire au plan 2
    mov ax, 0x0100                      ; reset synchrone
    out dx, ax
    mov ax, 0x0402                      ; masque de plans = plan 2
    out dx, ax
    mov ax, 0x0704                      ; memoire etendue, odd/even off
    out dx, ax
    mov ax, 0x0300                      ; fin du reset
    out dx, ax
    mov dx, 0x3CE
    mov ax, 0x0204                      ; lecture du plan 2
    out dx, ax
    mov ax, 0x0005                      ; mode ecriture 0
    out dx, ax
    mov ax, 0x0406                      ; fenetre en 0xA0000
    out dx, ax

    mov rsi, FONT8_ADDR                 ; --- 256 glyphes, pas de 32 octets
    mov rdi, 0xA0000 + 0x4000           ; bloc de police 1
    mov ecx, 256
.glyph:
    mov rax, [rsi]
    mov [rdi], rax
    add rsi, 8
    add rdi, 32
    dec ecx
    jnz .glyph

    mov dx, 0x3C4                       ; --- retour en mode texte
    mov ax, 0x0100
    out dx, ax
    mov ax, 0x0302                      ; plans 0 et 1
    out dx, ax
    mov ax, 0x0304                      ; odd/even
    out dx, ax
    mov ax, 0x0300
    out dx, ax
    mov dx, 0x3CE
    mov ax, 0x0004
    out dx, ax
    mov ax, 0x1005
    out dx, ax
    mov ax, 0x0E06                      ; fenetre en 0xB8000, texte
    out dx, ax
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; al = hauteur de caractere en pixels (8 ou 16)
vga_charheight:
    push rax
    push rbx
    push rdx
    dec al
    mov bl, al
    mov dx, 0x3D4
    mov al, 0x09                        ; CRTC : Maximum Scan Line
    out dx, al
    inc dx
    in al, dx
    and al, 0xE0
    or  al, bl
    out dx, al
    pop rdx
    pop rbx
    pop rax
    ret

; bl = premiere ligne du curseur, bh = derniere
vga_cursor_shape:
    push rax
    push rdx
    mov dx, 0x3D4
    mov al, 0x0A
    out dx, al
    mov dx, 0x3D5
    mov al, bl
    out dx, al
    mov dx, 0x3D4
    mov al, 0x0B
    out dx, al
    mov dx, 0x3D5
    mov al, bh
    out dx, al
    pop rdx
    pop rax
    ret

vga_mode25:
    push rbx
    mov dx, 0x3C4                       ; bloc de police 0 (8x16 du BIOS)
    mov ax, 0x0003
    out dx, ax
    mov al, 16
    call vga_charheight
    mov bx, 0x0F0D
    call vga_cursor_shape
    mov byte [scr_h], 25
    call cls
    pop rbx
    ret

vga_mode50:
    push rbx
    call vga_load_font8
    mov dx, 0x3C4                       ; bloc de police 1 (8x8)
    mov ax, 0x0503
    out dx, ax
    mov al, 8
    call vga_charheight
    mov bx, 0x0706
    call vga_cursor_shape
    mov byte [scr_h], 50
    call cls
    pop rbx
    ret

; =====================================================================
;  Disposition du clavier
; =====================================================================
; al = 0 -> us, 1 -> fr
kbd_set:
    mov [kbd_layout], al
    test al, al
    jnz .fr
    mov qword [kbd_lo], kbd_us_lo
    mov qword [kbd_hi], kbd_us_hi
    ret
.fr:
    mov qword [kbd_lo], kbd_fr_lo
    mov qword [kbd_hi], kbd_fr_hi
    ret

cmd_loadkeys:
    mov rsi, [argsp]
    cmp byte [rsi], 0
    je .show
    mov rdi, s_kfr
    call strcmp
    je .fr
    mov rsi, [argsp]
    mov rdi, s_kfr2
    call strcmp
    je .fr
    mov rsi, [argsp]
    mov rdi, s_kaz
    call strcmp
    je .fr
    mov rsi, [argsp]
    mov rdi, s_kus
    call strcmp
    je .us
    mov rsi, [argsp]
    mov rdi, s_kqw
    call strcmp
    je .us
    mov rsi, s_keys_bad
    call print
    ret
.fr:
    mov al, 1
    call kbd_set
    jmp .show
.us:
    xor al, al
    call kbd_set
.show:
    mov rsi, s_keys_cur
    call print
    call print_layout
    mov al, 10
    call putc
    ret

print_layout:
    cmp byte [kbd_layout], 0
    je .us
    mov rsi, s_kfr
    jmp print
.us:
    mov rsi, s_kus
    jmp print

; =====================================================================
;  PCI (ports 0xCF8 / 0xCFC)
; =====================================================================
; r8d = bus, r9d = peripherique, r10d = fonction, eax = offset -> eax
pci_cfg:
    push rcx
    push rdx
    and eax, 0xFC
    mov ecx, r8d
    shl ecx, 16
    or  eax, ecx
    mov ecx, r9d
    shl ecx, 11
    or  eax, ecx
    mov ecx, r10d
    shl ecx, 8
    or  eax, ecx
    or  eax, 0x80000000
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in  eax, dx
    pop rdx
    pop rcx
    ret

; Cherche le premier controleur d'affichage (classe 0x03)
gpu_detect:
    push rbx
    xor r8d, r8d
.bus:
    xor r9d, r9d
.dev:
    xor r10d, r10d
    xor eax, eax
    call pci_cfg
    cmp ax, 0xFFFF
    je .next
    mov ebx, eax
    mov eax, 8
    call pci_cfg
    shr eax, 24
    cmp al, 0x03
    jne .next
    mov [gpu_id], ebx
    mov byte [gpu_found], 1
    pop rbx
    ret
.next:
    inc r9d
    cmp r9d, 32
    jb .dev
    inc r8d
    cmp r8d, 32
    jb .bus
    pop rbx
    ret

; ax = identifiant constructeur -> rsi = nom
vendor_name:
    push rbx
    mov rbx, vendor_table
.l:
    mov cx, [rbx]
    test cx, cx
    jz .unknown
    cmp cx, ax
    je .found
    add rbx, 10
    jmp .l
.found:
    mov rsi, [rbx + 2]
    pop rbx
    ret
.unknown:
    mov rsi, s_v_unk
    pop rbx
    ret

; =====================================================================
;  SMBIOS : modele reel de la machine (table type 1)
; =====================================================================
; rdi = structure -> rdi = structure suivante
smbios_next:
    push rax
    movzx eax, byte [rdi + 1]
    add rdi, rax
.s:
    cmp word [rdi], 0
    je .e
    inc rdi
    jmp .s
.e:
    add rdi, 2
    pop rax
    ret

; rsi = structure, al = index de chaine (1..n) -> rsi = chaine ou 0
smbios_str:
    test al, al
    jz .none
    push rcx
    movzx ecx, byte [rsi + 1]
    add rsi, rcx
    cmp byte [rsi], 0
    je .none2
.loop:
    dec al
    jz .found
.sk:
    cmp byte [rsi], 0
    je .sk_end
    inc rsi
    jmp .sk
.sk_end:
    inc rsi
    cmp byte [rsi], 0
    je .none2
    jmp .loop
.found:
    pop rcx
    ret
.none2:
    pop rcx
.none:
    xor esi, esi
    ret

; rsi -> rdi, s'arrete a r11 (limite) ; rdi avance
str_append:
    push rax
.l:
    cmp rdi, r11
    jae .e
    mov al, [rsi]
    test al, al
    jz .e
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .l
.e:
    pop rax
    ret

smbios_detect:
    push rbx
    mov byte [host_name], 0
    mov rsi, 0xF0000
.scan:
    cmp dword [rsi], '_SM3'
    jne .try2
    cmp byte [rsi + 4], '_'
    jne .try2
    mov rdi, [rsi + 0x10]
    jmp .start
.try2:
    cmp dword [rsi], '_SM_'
    jne .next
    mov edi, [rsi + 0x18]
    jmp .start
.next:
    add rsi, 16
    cmp rsi, 0x100000
    jb .scan
    jmp .end
.start:
    test rdi, rdi
    jz .end
    mov rax, 0x100000000                ; au-dela de 4 Gio : non mappe
    cmp rdi, rax
    jae .end
    mov ecx, 512                        ; garde-fou
.walk:
    mov al, [rdi]
    cmp al, 127                         ; fin de table
    je .end
    cmp al, 1                           ; type 1 = System Information
    je .type1
    call smbios_next
    dec ecx
    jnz .walk
    jmp .end
.type1:
    mov rbx, host_name
    mov r11, host_name + 40
    mov r8, rdi
    movzx eax, byte [r8 + 4]            ; fabricant
    mov rsi, r8
    call smbios_str
    test rsi, rsi
    jz .prod
    mov rdi, rbx
    call str_append
    mov rbx, rdi
    mov byte [rbx], ' '
    inc rbx
.prod:
    movzx eax, byte [r8 + 5]            ; nom du produit
    mov rsi, r8
    call smbios_str
    test rsi, rsi
    jz .fin
    mov rdi, rbx
    call str_append
    mov rbx, rdi
.fin:
    mov byte [rbx], 0
.end:
    pop rbx
    ret

; =====================================================================
;  Complements processeur : constructeur, coeurs, frequence
; =====================================================================
cpu_cores_detect:
    push rbx
    xor eax, eax
    cpuid
    cmp eax, 0x0B
    jb .leaf1
    mov eax, 0x0B
    mov ecx, 1
    cpuid
    and ebx, 0xFFFF
    test ebx, ebx
    jz .leaf1
    mov [cpu_cores], ebx
    pop rbx
    ret
.leaf1:
    mov eax, 1
    cpuid
    shr ebx, 16
    and ebx, 0xFF
    test ebx, ebx
    jnz .ok
    mov ebx, 1
.ok:
    mov [cpu_cores], ebx
    pop rbx
    ret

; Mesure la frequence du TSC avec le canal 2 du PIT : c'est la vraie
; frequence de base du processeur sur toutes les puces recentes.
cpu_freq_detect:
    push rbx
    rdtsc
    shl rdx, 32
    or  rax, rdx
    mov r8, rax
    mov rcx, 50
    call sleep_ms
    rdtsc
    shl rdx, 32
    or  rax, rdx
    sub rax, r8
    xor edx, edx
    mov ecx, 50000                      ; cycles / 50 ms -> MHz
    div rcx
    mov [cpu_mhz], eax
    pop rbx
    ret

; Supprime toutes les occurrences du motif rsi dans la chaine rdi
str_remove:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    mov r8, rdi
.outer:
    mov rdi, r8
.scan:
    cmp byte [rdi], 0
    je .end
    mov rbx, rdi
    mov rcx, rsi
.cmp:
    mov al, [rcx]
    test al, al
    jz .match
    cmp al, [rbx]
    jne .nomatch
    inc rbx
    inc rcx
    jmp .cmp
.nomatch:
    inc rdi
    jmp .scan
.match:
    mov rdx, rdi
.mv:
    mov al, [rbx]
    mov [rdx], al
    test al, al
    jz .outer
    inc rbx
    inc rdx
    jmp .mv
.end:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; Nettoie la chaine CPUID : retire (R), (TM), CPU et la frequence
cpu_brand_clean:
    push rbx
    mov rdi, cpu_brand
    mov rsi, s_rm_r
    call str_remove
    mov rdi, cpu_brand
    mov rsi, s_rm_tm
    call str_remove
    mov rdi, cpu_brand
    mov rsi, s_rm_tm2
    call str_remove
    mov rdi, cpu_brand
    mov rsi, s_rm_cpu
    call str_remove
    mov rdi, cpu_brand
    mov rsi, s_rm_proc
    call str_remove
    mov rsi, cpu_brand                  ; coupe a " @ "
.f:
    mov al, [rsi]
    test al, al
    jz .trim
    cmp al, '@'
    jne .n
    mov byte [rsi], 0
    jmp .trim
.n:
    inc rsi
    jmp .f
.trim:                                  ; supprime les espaces finaux
    mov rsi, cpu_brand
    call strlen
.t:
    test ecx, ecx
    jz .done
    dec ecx
    cmp byte [rsi + rcx], ' '
    jne .done
    mov byte [rsi + rcx], 0
    jmp .t
.done:
    pop rbx
    ret

hw_detect:
    call cpu_cores_detect
    call cpu_brand_clean
    call cpu_freq_detect
    call smbios_detect
    call gpu_detect
    ret


; =====================================================================
;  files : mini gestionnaire de fichiers plein ecran
;
;  r12 = repertoire affiche, r13d = index de l'entree en surbrillance.
;  Fleches haut/bas : deplacent la selection. Entree : ouvre un
;  repertoire ou affiche un fichier. Suppr : remonte au parent (le
;  parent de chaque noeud est deja connu, pas besoin d'une pile).
;  Echap : quitte et laisse le shell dans le dernier repertoire visite.
;
;  Les fichiers caches (noms commencant par un point) restent caches,
;  comme le ferait "ls" sans -a ; fm_count et fm_selected ne comptent
;  donc que les entrees visibles, exactement comme fm_draw les affiche.
; =====================================================================
cmd_files:
    push rbx
    push r12
    push r13
    mov r12, [cwd_node]
    xor r13d, r13d
    mov al, [cursor_y]               ; on demarre pile ou la commande a ete
    mov [fm_top], al                 ; tapee : pas de page a part, la barre
    jmp .redraw                      ; d'instructions reste collee en bas
.up:
    test r13d, r13d
    jz .input
    dec r13d
    jmp .redraw
.down:
    mov rbx, r12
    call fm_count
    test eax, eax
    jz .input
    lea ecx, [eax - 1]
    cmp r13d, ecx
    jge .input
    inc r13d
    jmp .redraw
.enter:
    mov rbx, r12
    call fm_selected
    test rax, rax
    jz .input
    cmp qword [rax + VN_TYPE], VT_DIR
    je .opendir
    call fm_viewfile
    jmp .redraw
.opendir:
    mov r12, rax
    xor r13d, r13d
    jmp .redraw
.updir:
    mov rax, [r12 + VN_PARENT]
    test rax, rax
    jz .input                       ; deja a la racine : ignore
    mov r12, rax
    xor r13d, r13d
.redraw:
    call fm_draw
.input:
    call getchar
    cmp al, K_UP
    je .up
    cmp al, K_DOWN
    je .down
    cmp al, 10
    je .enter
    cmp al, K_CTRLESC                ; Ctrl+Echap : quitte le gestionnaire
    je .quit
    cmp al, 27                       ; Echap seul : remonte d'un dossier
    je .updir
    jmp .input
.quit:
    mov [cwd_node], r12
    ; efface uniquement la zone qu'on a utilisee (fm_top .. bas de l'ecran),
    ; jamais ce qui est au-dessus : l'historique du terminal reste intact.
    mov al, [fm_top]
    movzx edx, byte [scr_h]
    dec dl
    call fm_clear_rows
    movzx eax, byte [fm_top]
    mov [cursor_y], al
    mov byte [cursor_x], 0
    ; une seule ligne de trace, comme le ferait n'importe quelle commande
    mov byte [text_attr], C_CYAN
    mov rsi, s_fm_hdr
    call print
    mov byte [text_attr], C_DEF
    mov rbx, r12
    call vfs_print_path
    mov al, 10
    call putc
    pop r13
    pop r12
    pop rbx
    ret

; rbx = repertoire -> eax = nombre d'entrees visibles (fichiers caches exclus)
fm_count:
    push rbx
    push rcx
    push rsi
    mov rcx, [rbx + VN_DATA]
    xor eax, eax
.l:
    test rcx, rcx
    jz .e
    mov rsi, [rcx + VN_NAME]
    cmp byte [rsi], '.'
    je .skip
    inc eax
.skip:
    mov rcx, [rcx + VN_NEXT]
    jmp .l
.e:
    pop rsi
    pop rcx
    pop rbx
    ret

; rbx = repertoire, r13d = index -> rax = noeud correspondant, ou 0
fm_selected:
    push rbx
    push rcx
    push rdx
    push rsi
    mov rcx, [rbx + VN_DATA]
    xor edx, edx
.l:
    test rcx, rcx
    jz .none
    mov rsi, [rcx + VN_NAME]
    cmp byte [rsi], '.'
    je .skip
    cmp edx, r13d
    je .found
    inc edx
.skip:
    mov rcx, [rcx + VN_NEXT]
    jmp .l
.found:
    mov rax, rcx
    jmp .ret
.none:
    xor eax, eax
.ret:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; Dessine l'ecran complet : chemin, liste des entrees (celle en
; surbrillance en video inverse), et le rappel des touches.
; Dessine uniquement sa propre zone : de [fm_top] jusqu'au bas de l'ecran.
; Tout ce qui est au-dessus (l'historique du terminal) n'est jamais touche.
; La derniere rangee de l'ecran est reservee a la barre d'instructions, qui
; reste donc fixee en bas quel que soit fm_top.
fm_draw:
    push rax
    push rbx
    push rcx
    push r14
    push r15

    movzx r15d, byte [scr_h]
    dec r15d                         ; r15d = rangee de la barre (scr_h-1)
    mov r14d, r15d
    dec r14d                         ; r14d = derniere rangee dispo pour la liste

    mov al, [fm_top]
    mov dl, r15b
    call fm_clear_rows               ; n'efface que fm_top..bas, rien au-dessus

    movzx eax, byte [fm_top]
    mov [cursor_y], al
    mov byte [cursor_x], 0

    mov byte [text_attr], C_WHITE
    mov rsi, s_fm_hdr
    call print
    mov rbx, r12
    call vfs_print_path
    mov byte [text_attr], C_DEF
    mov al, 10
    call putc
    mov byte [text_attr], C_GREY
    mov rsi, s_fm_rule
    call print

    mov rbx, r12
    mov rcx, [rbx + VN_DATA]
    xor ebx, ebx                     ; ebx = index visible (rax est libre)
    test rcx, rcx
    jnz .loop
    mov byte [text_attr], C_DEF
    mov rsi, s_fm_empty
    call print
    jmp .statusbar
.loop:
    test rcx, rcx
    jz .statusbar
    movzx eax, byte [cursor_y]
    cmp eax, r14d
    jae .statusbar                   ; plus de place avant la barre du bas
    mov rsi, [rcx + VN_NAME]         ; rcx tient le noeud : rax reste libre
    cmp byte [rsi], '.'
    je .hidden
    mov byte [text_attr], C_DEF
    mov al, ' '                      ; 'al' est le bas de 'rax' : ne JAMAIS
    call putc                        ; l'ecraser avant d'avoir fini de se
    call putc                        ; servir du pointeur de noeud dans rax
    mov rax, rcx                     ; rax = noeud, mis en place juste avant
    call vfs_color                   ; d'en avoir besoin
    cmp ebx, r13d
    jne .name
    ; ligne selectionnee : video inversee -- (fg<<4)|0, fond = couleur,
    ; texte noir. Surtout pas 'al' ici : rax tient encore le pointeur de
    ; noeud (deja fautif une fois plus haut dans cette meme fonction),
    ; dl est libre a ce point precis.
    mov dl, [text_attr]
    and dl, 0x0F
    shl dl, 4
    mov [text_attr], dl
.name:
    mov rsi, [rax + VN_NAME]         ; print et vfs_color preservent rax
    call print
    cmp qword [rax + VN_TYPE], VT_DIR
    jne .eol
    mov al, '/'
    call putc
.eol:
    mov byte [text_attr], C_DEF
    mov al, 10
    call putc
    inc ebx
.hidden:
    mov rcx, [rcx + VN_NEXT]
    jmp .loop
.statusbar:
    mov eax, r15d
    mov [cursor_y], al
    mov byte [cursor_x], 0
    mov byte [text_attr], C_CYAN
    mov rsi, s_fm_keys
    call print
    pop r15
    pop r14
    pop rcx
    pop rbx
    pop rax
    ret

; al = premiere rangee, dl = derniere rangee (incluse) : les efface toutes
; les deux, sans jamais toucher a ce qui est au-dessus ni en dessous.
; (ah aurait pu porter la derniere rangee, mais ah ne peut pas se combiner
; avec un registre r8-r15 sous REX -- dl evite le probleme.)
fm_clear_rows:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    movzx ebx, al                    ; ebx = premiere rangee
    movzx ecx, dl                    ; ecx = derniere rangee
    sub ecx, ebx
    inc ecx                          ; ecx = nombre de rangees
    imul ecx, VGA_W                  ; ecx = nombre de mots a ecrire
    mov edi, ebx
    imul edi, VGA_W
    shl edi, 1
    add edi, VGA_MEM
    mov ax, 0x0720                   ; attribut C_DEF, caractere espace
    rep stosw
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; rax = noeud fichier : l'affiche dans la meme zone que la liste (jamais
; en plein ecran), attend une touche, revient.
fm_viewfile:
    push rax
    push rbx
    push rdx
    mov rbx, rax
    mov al, [fm_top]
    movzx edx, byte [scr_h]
    dec dl
    call fm_clear_rows
    movzx eax, byte [fm_top]
    mov [cursor_y], al
    mov byte [cursor_x], 0
    mov byte [text_attr], C_WHITE
    mov rsi, [rbx + VN_NAME]
    call print
    mov al, 10
    call putc
    mov byte [text_attr], C_GREY
    mov rsi, s_fm_rule
    call print
    mov byte [text_attr], C_DEF
    mov rsi, [rbx + VN_DATA]
    test rsi, rsi
    jz .empty
    call print
    mov rax, [rbx + VN_DATA]        ; /proc/cpuinfo : complete avec CPUID
    mov rcx, t_cpuinfo
    cmp rax, rcx
    jne .eol
    mov rsi, cpu_brand
    call print
    mov al, 10
    call putc
    mov rsi, t_cpuinfo2
    call print
    jmp .eol
.empty:
    mov rsi, s_fm_fempty
    call print
.eol:
    cmp byte [cursor_x], 0
    je .noeol
    mov al, 10
    call putc
.noeol:
    mov byte [text_attr], C_GREY
    mov rsi, s_fm_rule
    call print
    mov rsi, s_fm_anykey
    call print
    call getchar                    ; touche quelconque : on l'ignore
    pop rdx
    pop rbx
    pop rax
    ret

; =====================================================================
;  Affichage hexadecimal
; =====================================================================
print_hex_nib:
    push rax
    and al, 0x0F
    cmp al, 10
    jb .d
    add al, 'a' - 10
    jmp .p
.d:
    add al, '0'
.p:
    call putc
    pop rax
    ret

print_hex16:
    push rax
    push rbx
    mov bx, ax
    mov al, bh
    shr al, 4
    call print_hex_nib
    mov al, bh
    call print_hex_nib
    mov al, bl
    shr al, 4
    call print_hex_nib
    mov al, bl
    call print_hex_nib
    pop rbx
    pop rax
    ret

; eax = valeur -> ecx = nombre de chiffres decimaux
count_digits:
    push rax
    push rbx
    push rdx
    mov ecx, 1
    mov ebx, 10
.l:
    xor edx, edx
    div ebx
    test eax, eax
    jz .e
    inc ecx
    jmp .l
.e:
    pop rdx
    pop rbx
    pop rax
    ret

; eax = MHz -> "3.79 GHz"
print_ghz:
    push rax
    push rcx
    push rdx
    xor edx, edx
    mov ecx, 1000
    div ecx
    push rdx
    call print_dec
    mov al, '.'
    call putc
    pop rax
    xor edx, edx
    mov ecx, 10
    div ecx
    call print_dec2
    mov rsi, s_ghz
    call print
    pop rdx
    pop rcx
    pop rax
    ret


; =====================================================================
;  Donnees
; =====================================================================
align 8

cursor_x:   db 0
cursor_y:   db 0
text_attr:  db C_DEF
kbd_shift:  db 0
kbd_ctrl:   db 0
kbd_caps:   db 0
kbd_ext:    db 0
rl_flags:   db 0
shell_exit: db 0
scr_h:      db 25
kbd_layout: db 1        ; azerty par defaut
gpu_found:  db 0
fm_top:     db 0
opt_a:      db 0
opt_l:      db 0
opt_r:      db 0
opt_p:      db 0
mk_type:    db 0
f_mon:      db 1
f_day:      db 1
f_hour:     db 0
f_min:      db 0
hist_count: db 0
hist_pos:   db 0
rtc_sec:    db 0
rtc_min:    db 0
rtc_hour:   db 0
rtc_day:    db 0
rtc_mon:    db 0
rtc_year:   db 0
rtc_wday:   db 0

align 8
cwd_node:       dq n_rootdir
mk_prog:        dq 0
prev_node:      dq n_root
kbd_lo:         dq kbd_fr_lo
kbd_hi:         dq kbd_fr_hi
gpu_id:         dd 0
cpu_cores:      dd 1
cpu_mhz:        dd 0
boot_secs:      dq 0
mem_total_kb:   dq 0
argv0:          dq 0
argsp:          dq 0
null_idt:       dw 0
                dq 0


; ---------------------------------------------------------------------
;  Table des commandes
; ---------------------------------------------------------------------
align 8
cmd_table:
    dq c_help,      cmd_help
    dq c_clear,     cmd_clear
    dq c_print,     cmd_print
    dq c_sys,       cmd_sys
    dq c_where,     cmd_where
    dq c_ls,        cmd_ls
    dq c_cd,        cmd_cd
    dq c_see,       cmd_see
    dq c_mkdir,     cmd_mkdir
    dq c_mkfile,    cmd_mkfile
    dq c_files,     cmd_files
    dq c_rm,        cmd_rm
    dq c_srm,       cmd_rmdir
    dq c_date,      cmd_date
    dq c_uptime,    cmd_uptime
    dq c_sudo,      cmd_sudo
    dq c_reboot,    cmd_reboot
    dq c_poweroff,  cmd_poweroff
    dq c_shutdown,  cmd_poweroff
    dq c_halt,      cmd_poweroff
    dq c_loadkeys,  cmd_loadkeys
    dq c_exit,      cmd_exit
    dq c_logout,    cmd_exit
    dq 0, 0

c_help:      db "help",0
c_clear:     db "clear",0
c_print:     db "print",0
c_sys:       db "sys",0
c_where:     db "where",0
c_ls:        db "ls",0
c_cd:        db "cd",0
c_see:       db "see",0
c_mkdir:     db "mkdir",0
c_mkfile:    db "mkfile",0
c_files:     db "files",0
c_rm:        db "rm",0
c_srm:       db "srm",0
c_date:      db "date",0
c_uptime:    db "uptime",0
c_sudo:      db "sudo",0
c_reboot:    db "reboot",0
c_poweroff:  db "poweroff",0
c_shutdown:  db "shutdown",0
c_halt:      db "halt",0
c_loadkeys:  db "loadkeys",0
c_exit:      db "exit",0
c_logout:    db "logout",0

; ---------------------------------------------------------------------
;  Systeme de fichiers simule
; ---------------------------------------------------------------------
align 8
align 8

%include "tree.inc"

t_fstab:
    db "# <file system> <dir> <type> <options> <dump> <pass>", 10
    db "/dev/sda1       /      ext4   rw,relatime  0 1", 10, 0
t_vcons:
    db "KEYMAP=fr-latin1", 10
    db "FONT=lat9w-16", 10, 0
t_meminfo:
    db "MemTotal:         130044 kB", 10
    db "MemFree:          128512 kB", 10
    db "Buffers:               0 kB", 10, 0
t_grubcfg:
    db "menuentry 'NullCore OS' {", 10
    db "    linux /boot/vmlinuz-nullcore root=/dev/sda1 rw", 10
    db "    initrd /boot/initramfs.img", 10
    db "}", 10, 0
t_memo:
    db "Penser a relire le chapitre sur les tables de pages.", 10, 0
t_kasm:
    db "; kernel.asm -- le noyau que tu es en train d'utiliser.", 10
    db "; Il n'y a pas de vrai pilote de disque, donc ce fichier", 10
    db "; n'est qu'un noeud de l'arbre en memoire.", 10, 0
t_group:
    db "root:x:0:root", 10
    db "wheel:x:10:root", 10
    db "users:x:100:", 10, 0
t_locale:
    db "LANG=fr_FR.UTF-8", 10, 0
t_shadow:
    db "root:!:19800::::::", 10, 0
t_mirror:
    db "## NullCore repository mirrorlist", 10
    db "Server = https://mirror.example.org/nullcore/$repo/os/$arch", 10, 0
t_sysconf:
    db "[Manager]", 10
    db "#LogLevel=info", 10
    db "#DefaultTimeoutStartSec=90s", 10, 0
t_idees:
    db "- ajouter une IDT et passer le clavier en IRQ1", 10
    db "- ecrire un pilote ATA PIO", 10
    db "- remplir l'arbre depuis un vrai FAT12", 10, 0
t_procup:
    db "1284.51 1201.03", 10, 0
t_hist:
    db "ls -la /etc", 10
    db "see /proc/cpuinfo", 10
    db "sys", 10, 0
t_pacmanlog:
    db "[2026-09-06T22:10:03+0200] [PACMAN] Running 'pacman -Syu'", 10
    db "[2026-09-06T22:10:07+0200] [ALPM] transaction started", 10, 0
t_bootlog:
    db "kernel: NullCore 1.0-nullcore", 10
    db "kernel: Console: colour VGA+ 80x25", 10
    db "kernel: i8042: PNP: PS/2 Controller [PNP0303:KBD]", 10
    db "systemd[1]: Reached target Multi-User System.", 10, 0

t_osrel:
    db 'NAME="NullCore OS"', 10
    db 'PRETTY_NAME="NullCore OS 1.0"', 10
    db 'ID=nullcore', 10
    db 'BUILD_ID=rolling', 10
    db 'ANSI_COLOR="38;2;23;147;209"', 10
    db 'VERSION_ID=1.0', 10
    db 'LOGO=nullcore-logo', 10, 0

t_hostn:   db "nullcore", 10, 0

t_version:
    db "NullCore 1.0-nullcore (build@nullcore) (nasm 2.16) #1 SMP", 10, 0

t_cpuinfo:
    db "processor       : 0", 10
    db "vendor_id       : GenuineIntel", 10
    db "cpu family      : 6", 10
    db "model name      : ", 0
t_cpuinfo2:
    db "cpu MHz         : 2400.000", 10
    db "cache size      : 16384 KB", 10
    db "flags           : fpu vme de pse tsc msr pae cx8 apic sep mtrr pge", 10
    db "address sizes   : 40 bits physical, 48 bits virtual", 10, 0

t_hosts:
    db "127.0.0.1   localhost", 10
    db "::1         localhost", 10
    db "127.0.1.1   nullcore.localdomain nullcore", 10, 0

t_passwd:
    db "root:x:0:0::/root:/bin/bash", 10
    db "bin:x:1:1::/:/usr/bin/nologin", 10
    db "daemon:x:2:2::/:/usr/bin/nologin", 10
    db "nobody:x:65534:65534:Nobody:/:/usr/bin/nologin", 10, 0

t_notes:
    db "TODO", 10
    db "  - installer une IDT et passer le clavier en IRQ1", 10
    db "  - allocateur de pages + heap", 10
    db "  - pilote ATA PIO pour un vrai systeme de fichiers", 10
    db "  - ordonnanceur preemptif", 10, 0

t_bashrc:
    db "# ~/.bashrc", 10
    db "[[ $- != *i* ]] && return", 10
    db "alias ls='ls --color=auto'", 10
    db "alias info='sys'", 10
    db "PS1='[\\u@\\h \\W]\\$ '", 10, 0

; ---------------------------------------------------------------------
;  Messages de demarrage
; ---------------------------------------------------------------------
align 8
dmesg_table:
    dq dm1, dm2, dm3, dm4, dm5, dm6, dm7, dm8, dm9, dm10, dm11, 0

dm1:  db "[    0.000000] NullCore 1.0-nullcore (build@nullcore) #1 SMP",0
dm2:  db "[    0.000000] Command line: root=/dev/sda2 rw loglevel=3 quiet",0
dm3:  db "[    0.008411] x86/fpu: Supporting XSAVE feature 0x001: 'x87 floating point'",0
dm4:  db "[    0.021355] BIOS-provided physical RAM map accepted",0
dm5:  db "[    0.034902] x86/PAT: Configuration [0-7]: WB  WC  UC- UC  WB  WP  UC- WT",0
dm6:  db "[    0.052117] Console: colour VGA+ 80x25",0
dm7:  db "[    0.070664] PCI: Using configuration type 1 for base access",0
dm8:  db "[    0.091238] clocksource: tsc-early: mask 0xffffffffffffffff",0
dm9:  db "[    0.113470] serial8250: ttyS0 at I/O 0x3f8 (irq = 4) is a 16550A",0
dm10: db "[    0.140026] i8042: PNP: PS/2 Controller [PNP0303:KBD]",0
dm11: db "[    0.166812] EXT4-fs (sda2): mounted filesystem with ordered data mode",0

s_dm_mem:  db "[    0.184559] Memory: ",0
s_dm_mem2: db "K/",0
s_dm_mem3: db "K available",10,0
s_dm_cpu:  db "[    0.201884] smpboot: CPU0: ",0

align 8
hook_table:
    dq hk1, hk2, hk3, hk4, 0
hk1: db "running early hook [udev]",0
hk2: db "running hook [udev]",0
hk3: db "Triggering uevents...",0
hk4: db "mounting '/dev/sda2' on real root",0

align 8
unit_table:
    dq un1, un2, un3, un4, un5, un6, un7, un8, 0
un1: db "Created slice Virtual Machine and Container Slice.",0
un2: db "Started Journal Service.",0
un3: db "Mounted /boot.",0
un4: db "Reached target Local File Systems.",0
un5: db "Started Network Time Synchronization.",0
un6: db "Started Simple Desktop Display Manager.",0
un7: db "Reached target Multi-User System.",0
un8: db "Started Getty on tty1.",0

s_ok:     db "  OK  ",0
s_colcol: db ":: ",0

; ---------------------------------------------------------------------
;  Chaines diverses
; ---------------------------------------------------------------------
s_issue:     db "NullCore OS 1.0 (tty1)",10,10,0
s_login:     db "nullcore login: ",0
s_passwd:    db "Password: ",0
s_lastlogin: db "Last login: ",0
s_ontty:     db " on tty1",10,0
s_host:      db "nullcore",0
s_root:      db "root",0
s_utc:       db " UTC ",0
s_up:        db " up ",0
s_h:         db "h ",0
s_m:         db " mins",0
s_hours:     db " hours, ",0
s_mins:      db " min",0
s_loadavg:   db ",  1 user,  load average: 0.00, 0.01, 0.05",10,0
s_bash:      db "bash: ",0
s_notfound:  db ": command not found",10,0
s_cd:        db "bash: cd: ",0
s_ls:        db "ls: cannot access ",0
s_notdir:    db ": Not a directory",10,0
s_isdir:     db ": Is a directory",10,0
s_notempty:  db ": Directory not empty",10,0
s_exists:    db ": File exists",10,0
s_busy:      db ": Device or resource busy",10,0
s_nospace:   db ": no space left on device",10,0
s_missing:   db ": missing operand",10,0
s_cannot_create: db ": cannot create ",0
s_cannot_remove: db ": cannot remove ",0
s_failed_remove: db ": failed to remove ",0
s_mkdir:     db "mkdir",0
s_mkfile:    db "mkfile",0
s_rm:        db "rm",0
s_rmdir:     db "srm",0
s_total:     db "total ",0
s_colon_nl:  db ":",10,0
s_fm_hdr:    db "Fichiers -- ",0
s_fm_rule:   db "----------------------------------------------------------------------",10,0
s_fm_empty:  db "  (dossier vide)",10,0
s_fm_fempty: db "(fichier vide)",10,0
; PAS de saut de ligne final : cette chaine est toujours imprimee sur la
; toute derniere rangee de l'ecran (scr_h-1). Un '\n' de trop y ferait
; deborder le curseur d'une rangee, ce qui declenche un defilement de
; TOUT l'ecran -- y compris l'historique au-dessus de fm_top.
s_fm_keys:   db "Entree: ouvrir   Echap: dossier parent   Ctrl+Echap: quitter",0
s_fm_anykey: db "Appuie sur une touche pour revenir...",10,0
s_perm_d:    db "drwxr-xr-x ",0
s_perm_x:    db "-rwxr-xr-x ",0
s_perm_f:    db "-rw-r--r-- ",0
s_owner:     db "root root ",0
s_dot:       db ".",0
s_dash:      db "-",0
s_nosuch:    db ": No such file or directory",10,0
s_cat:       db "see: ",0
s_cat_usage: db "see: missing operand",10,0
s_tilde:     db "~",0
s_dotdot:    db "..",0
s_krel:      db "1.0-nullcore",0
s_cpu_unk:   db "Unknown x86_64 CPU",0

s_sudo:  db "root is already root. Nothing to escalate.",10,0
s_reboot:   db "Broadcast message: The system is going down for reboot NOW!",10,0
s_poweroff: db "Broadcast message: The system is going down for poweroff NOW!",10,0

s_help:
    db 10
    db "  ls [-a] [-l] [chemin]   lister le contenu d'un repertoire",10
    db "  cd [chemin]             changer de repertoire",10
    db "  where                   afficher le repertoire courant",10
    db "  see <fichier>           afficher le contenu d'un fichier",10
    db "  mkdir [-p] <nom>        creer un repertoire",10
    db "  mkfile <nom>            creer un fichier vide",10
    db "  files                    gestionnaire de fichiers plein ecran",10
    db "  rm [-r] <nom>           supprimer un fichier ou un repertoire",10
    db "  srm <nom>               supprimer un repertoire vide",10
    db "  print <texte>           afficher du texte",10
    db "  sys                     informations sur le systeme",10
    db "  date                    date et heure courantes",10
    db "  uptime                  temps ecoule depuis le demarrage",10
    db "  clear                   effacer l'ecran",10
    db "  loadkeys <fr|us>        changer la disposition du clavier",10
    db "  reboot                  redemarrer la machine",10
    db "  poweroff                eteindre la machine",10
    db "  exit                    fermer la session",10
    db "  help                    afficher cette aide",10,10
    db "  Tab complete les commandes et les chemins.",10
    db "  Fleches haut et bas : historique.  Ctrl+C : annuler la ligne.",10,0

; ---------------------------------------------------------------------
;  sys : logo + informations materielles
; ---------------------------------------------------------------------
%include "logo.inc"

align 8
info_lines:
    dq 0
    dq ff_title, ff_rule, ff_os, ff_hostm, ff_kernel, ff_uptime
    dq ff_packages, ff_shell, ff_display, ff_term, ff_cpu, ff_gpu
    dq ff_memory, 0, ff_colors1, ff_colors2
    dq 0, 0, 0, 0

s_ff_os:      db "OS: ",0
s_ff_host:    db "Host: ",0
s_ff_kernel:  db "Kernel: ",0
s_ff_uptime:  db "Uptime: ",0
s_ff_pkgs:    db "Packages: ",0
s_ff_shell:   db "Shell: ",0
s_ff_disp:    db "Display: ",0
s_ff_term:    db "Terminal: ",0
s_ff_cpu:     db "CPU: ",0
s_ff_gpu:     db "GPU: ",0
s_ff_mem:     db "Memory: ",0

s_osname:     db "NullCore OS x86_64",0
s_pkgs:       db "231 (pacman)",0
s_shellv:     db "bash 5.2.26",0
s_termv:      db "/dev/tty1",0
s_mib_slash:  db "MiB / ",0
s_mib:        db "MiB",0

align 8
wday_names: dq wd0, wd1, wd2, wd3, wd4, wd5, wd6, wd0
wd0: db "Sun",0
wd1: db "Mon",0
wd2: db "Tue",0
wd3: db "Wed",0
wd4: db "Thu",0
wd5: db "Fri",0
wd6: db "Sat",0

align 8
mon_names: dq mo1, mo2, mo3, mo4, mo5, mo6, mo7, mo8, mo9, mo10, mo11, mo12
mo1:  db "Jan",0
mo2:  db "Feb",0
mo3:  db "Mar",0
mo4:  db "Apr",0
mo5:  db "May",0
mo6:  db "Jun",0
mo7:  db "Jul",0
mo8:  db "Aug",0
mo9:  db "Sep",0
mo10: db "Oct",0
mo11: db "Nov",0
mo12: db "Dec",0


; ---- police / ecran
; ---- clavier
s_kfr:       db "fr",0
s_kfr2:      db "fr-latin1",0
s_kaz:       db "azerty",0
s_kus:       db "us",0
s_kqw:       db "qwerty",0
s_keys_cur:  db "disposition clavier : ",0
s_keys_bad:  db "loadkeys: disposition inconnue (fr | us)",10,0

; ---- sys / materiel
s_unknown:   db "Unknown",0
s_80x:       db "80x",0
s_textmode:  db " (text mode)",0
s_par1:      db " (",0
s_par2:      db ")",0
s_at:        db " @ ",0
s_ghz:       db "GHz",0
s_brk1:      db " [",0
s_brk2:      db "]",10,0
s_brk2b:     db "]",0
s_v_unk:     db "Unknown vendor",0

; ---- nettoyage de la chaine CPUID
s_rm_r:      db "(R)",0
s_rm_tm:     db "(TM)",0
s_rm_tm2:    db "(tm)",0
s_rm_cpu:    db " CPU",0
s_rm_proc:   db " Processor",0

; ---- lscpu
; ---- constructeurs PCI (identifiants officiels)
align 8
vendor_table:
    dw 0x8086
    dq v_intel
    dw 0x1002
    dq v_amd
    dw 0x1022
    dq v_amd
    dw 0x10DE
    dq v_nvidia
    dw 0x1234
    dq v_bochs
    dw 0x1AF4
    dq v_redhat
    dw 0x1B36
    dq v_redhat
    dw 0x15AD
    dq v_vmware
    dw 0x80EE
    dq v_vbox
    dw 0x1013
    dq v_cirrus
    dw 0x1414
    dq v_ms
    dw 0x1AE0
    dq v_google
    dw 0x106B
    dq v_apple
    dw 0
    dq 0

v_intel:  db "Intel Corporation",0
v_amd:    db "AMD/ATI",0
v_nvidia: db "NVIDIA Corporation",0
v_bochs:  db "Bochs/QEMU",0
v_redhat: db "Red Hat, Inc.",0
v_vmware: db "VMware",0
v_vbox:   db "VirtualBox",0
v_cirrus: db "Cirrus Logic",0
v_ms:     db "Microsoft",0
v_google: db "Google",0
v_apple:  db "Apple",0

align 8
; ---------------------------------------------------------------------
;  Tables clavier (jeu de scancodes 1, indices 0x00..0x57)
; ---------------------------------------------------------------------
align 8
; ---- disposition francaise AZERTY (accents en codepage 437)
kbd_fr_lo:
    db 0,27,'&',0x82,'"',39,'(','-',0x8A,'_',0x87,0x85,')','=',8,9
    db 'a','z','e','r','t','y','u','i','o','p','^','$',10,0,'q','s'
    db 'd','f','g','h','j','k','l','m',0x97,0xFD,0,'*','w','x','c','v'
    db 'b','n',',',';',':','!',0,'*',0,' ',0,0,0,0,0,0
    db 0,0,0,0,0,0,0,'7','8','9','-','4','5','6','+','1'
    db '2','3','0','.',0,0,'<',0
kbd_fr_hi:
    db 0,27,'1','2','3','4','5','6','7','8','9','0',0xF8,'+',8,9
    db 'A','Z','E','R','T','Y','U','I','O','P','"',0x9C,10,0,'Q','S'
    db 'D','F','G','H','J','K','L','M','%','~',0,0xE6,'W','X','C','V'
    db 'B','N','?','.','/',0x15,0,'*',0,' ',0,0,0,0,0,0
    db 0,0,0,0,0,0,0,'7','8','9','-','4','5','6','+','1'
    db '2','3','0','.',0,0,'>',0

; ---- disposition americaine QWERTY
kbd_us_lo:
    db 0,27,'1','2','3','4','5','6','7','8','9','0','-','=',8,9
    db 'q','w','e','r','t','y','u','i','o','p','[',']',10,0,'a','s'
    db 'd','f','g','h','j','k','l',';',39,'`',0,92,'z','x','c','v'
    db 'b','n','m',',','.','/',0,'*',0,' ',0,0,0,0,0,0
    db 0,0,0,0,0,0,0,'7','8','9','-','4','5','6','+','1'
    db '2','3','0','.',0,0,0,0
kbd_us_hi:
    db 0,27,'!','@','#','$','%','^','&','*','(',')','_','+',8,9
    db 'Q','W','E','R','T','Y','U','I','O','P','{','}',10,0,'A','S'
    db 'D','F','G','H','J','K','L',':','"','~',0,'|','Z','X','C','V'
    db 'B','N','M','<','>','?',0,'*',0,' ',0,0,0,0,0,0
    db 0,0,0,0,0,0,0,'7','8','9','-','4','5','6','+','1'
    db '2','3','0','.',0,0,0,0

; ---------------------------------------------------------------------
;  Tampons
; ---------------------------------------------------------------------
align 8
cpu_brand:  times 52 db 0
host_name:  times 48 db 0
comp_buf:   times 40 db 0
comp_dir:   times 96 db 0
arg_buf:    times 96 db 0
base_buf:   times 40 db 0

; reservoirs pour les noeuds crees a chaud (mkdir / mkfile)
align 8
node_pool:  times NODE_MAX * VN_SIZE db 0
node_used:  dd 0
name_pool:  times NAME_POOL db 0
name_used:  dd 0

align 8
comp_first: dq 0
comp_lcp:   dd 0
user_buf:  times 34 db 0
pass_buf:  times 34 db 0
cmdline:   times CMDLEN db 0
hist_buf:  times HIST_MAX * CMDLEN db 0

kernel_end:
; remplissage jusqu'a 32 Kio (= KERNEL_SECTORS du bootloader)
times 32768 - ($ - $$) db 0
