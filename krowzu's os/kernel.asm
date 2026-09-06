; =====================================================================
;  kernel.asm  --  ArchNasm : noyau x86-64 en mode texte facon Arch Linux
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
%define VGA_H       25

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
%define K_UP        0x81
%define K_DOWN      0x82
%define K_LEFT      0x83
%define K_RIGHT     0x84

%define CMDLEN      128
%define HIST_MAX    8

%define E820_COUNT  0x5000
%define E820_TABLE  0x5004

%define MEM_USED_MB 12

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
    call mem_detect
    call cpu_detect
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
    movzx eax, byte [cwd]
    mov rsi, [dir_disp + rax*8]
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

cmd_echo:
    mov rsi, [argsp]
    call print
    mov al, 10
    call putc
    ret

cmd_whoami:
    mov rsi, user_buf
    call print
    mov al, 10
    call putc
    ret

cmd_hostname:
    mov rsi, s_host
    call print
    mov al, 10
    call putc
    ret

cmd_id:
    mov rsi, s_id
    call print
    ret

cmd_ps:
    mov rsi, s_ps
    call print
    ret

cmd_pwd:
    movzx eax, byte [cwd]
    mov rsi, [dir_paths + rax*8]
    call print
    mov al, 10
    call putc
    ret

cmd_uname:
    mov rsi, [argsp]
    mov rdi, s_dasha
    call strcmp
    je .all
    mov rsi, [argsp]
    mov rdi, s_dashr
    call strcmp
    je .rel
    mov rsi, s_linux
    call print
    mov al, 10
    call putc
    ret
.rel:
    mov rsi, s_krel
    call print
    mov al, 10
    call putc
    ret
.all:
    mov rsi, s_uname_a
    call print
    ret

cmd_ls:
    movzx eax, byte [cwd]
    mov rsi, [dir_lists + rax*8]
.loop:
    mov al, [rsi]
    test al, al
    jz .end
    inc rsi
    ; couleur selon le type
    cmp al, 1
    je .dir
    cmp al, 3
    je .exe
    mov byte [text_attr], C_DEF
    jmp .name
.dir:
    mov byte [text_attr], C_BLUE
    jmp .name
.exe:
    mov byte [text_attr], C_GREEN
.name:
    ; retour a la ligne si la colonne ne tient pas
    cmp byte [cursor_x], 66
    jb .noc
    mov al, 10
    call putc
.noc:
    push rsi
    call print
    pop rsi
.skipname:
    lodsb
    test al, al
    jnz .skipname
    ; complete jusqu'a un multiple de 14 colonnes
    mov byte [text_attr], C_DEF
.pad:
    movzx eax, byte [cursor_x]
    xor edx, edx
    mov ecx, 14
    div ecx
    test edx, edx
    jz .loop
    mov al, ' '
    call putc
    jmp .pad
.end:
    mov byte [text_attr], C_DEF
    cmp byte [cursor_x], 0
    je .done
    mov al, 10
    call putc
.done:
    ret

cmd_cd:
    mov rsi, [argsp]
    cmp byte [rsi], 0
    je .home
    mov rdi, s_tilde
    call strcmp
    je .home
    mov rsi, [argsp]
    mov rdi, s_dotdot
    call strcmp
    je .up
    ; recherche dans la table des repertoires
    xor ecx, ecx
.look:
    cmp ecx, 4
    jae .nodir
    mov rsi, [argsp]
    mov rdi, [dir_paths + rcx*8]
    push rcx
    call strcmp
    pop rcx
    je .setcwd
    mov rsi, [argsp]
    mov rdi, [dir_disp + rcx*8]
    push rcx
    call strcmp
    pop rcx
    je .setcwd
    inc ecx
    jmp .look
.setcwd:
    mov [cwd], cl
    ret
.home:
    mov byte [cwd], 1
    ret
.up:
    mov byte [cwd], 0
    ret
.nodir:
    mov byte [text_attr], C_DEF
    mov rsi, s_bashcd
    call print
    mov rsi, [argsp]
    call print
    mov rsi, s_nosuch
    call print
    ret

cmd_cat:
    mov rsi, [argsp]
    cmp byte [rsi], 0
    je .usage
    mov rbx, file_table
.next:
    mov rsi, [rbx]
    test rsi, rsi
    jz .nofile
    mov rdi, [argsp]
    call strcmp
    je .found
    add rbx, 16
    jmp .next
.found:
    mov byte [text_attr], C_DEF
    mov rsi, [rbx + 8]
    call print
    mov rax, [rbx + 8]
    mov rcx, t_cpuinfo
    cmp rax, rcx
    jne .ret
    mov rsi, cpu_brand
    call print
    mov al, 10
    call putc
    mov rsi, t_cpuinfo2
    call print
.ret:
    ret
.nofile:
    mov rsi, s_cat
    call print
    mov rsi, [argsp]
    call print
    mov rsi, s_nosuch
    call print
    ret
.usage:
    mov rsi, s_cat_usage
    call print
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

cmd_free:
    mov rsi, s_free_hdr
    call print
    mov rsi, s_free_mem
    call print
    mov rax, [mem_total_kb]
    shr rax, 10                     ; -> Mio
    mov [tmp_total_mb], rax
    mov ecx, 13
    call print_dec_w
    mov rax, MEM_USED_MB
    mov ecx, 12
    call print_dec_w
    mov rax, [tmp_total_mb]
    sub rax, MEM_USED_MB
    mov ecx, 12
    call print_dec_w
    mov rsi, s_free_tail
    call print
    mov rsi, s_free_swap
    call print
    xor eax, eax
    mov ecx, 13
    call print_dec_w
    xor eax, eax
    mov ecx, 12
    call print_dec_w
    xor eax, eax
    mov ecx, 12
    call print_dec_w
    mov al, 10
    call putc
    ret

cmd_lscpu:
    mov rsi, s_lscpu1
    call print
    mov rsi, cpu_brand
    call print
    mov al, 10
    call putc
    mov rsi, s_lscpu2
    call print
    ret

cmd_pacman:
    mov rsi, [argsp]
    mov rdi, s_pq
    call strcmp
    je .query
    mov rsi, [argsp]
    mov rdi, s_psyu
    call strcmp
    je .syu
    mov rsi, s_pacman_use
    call print
    ret
.query:
    mov rsi, s_pkglist
    call print
    ret
.syu:
    mov byte [text_attr], C_CYAN
    mov rsi, s_colcol
    call print
    mov byte [text_attr], C_WHITE
    mov rsi, s_syu1
    call print
    mov byte [text_attr], C_DEF
    mov rsi, s_syu2
    call print
    mov rcx, 450
    call sleep_ms
    mov byte [text_attr], C_CYAN
    mov rsi, s_colcol
    call print
    mov byte [text_attr], C_WHITE
    mov rsi, s_syu3
    call print
    mov byte [text_attr], C_DEF
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
;  fastfetch
; =====================================================================
cmd_fastfetch:
    push rbx
    push r12
    xor r12d, r12d
.loop:
    ; --- logo a gauche, en cyan
    mov byte [text_attr], C_CYAN
    mov rsi, [logo_lines + r12*8]
    call print
.pad:
    cmp byte [cursor_x], 40
    jae .padded
    mov al, ' '
    call putc
    jmp .pad
.padded:
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

; trait de la meme longueur que "user@hote", comme le vrai fastfetch
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
    mov rsi, s_ff_host
    mov rdi, s_machine
    jmp ff_kv

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
    mov rsi, s_ff_disp
    mov rdi, s_dispv
    jmp ff_kv

ff_term:
    mov rsi, s_ff_term
    mov rdi, s_termv
    jmp ff_kv

ff_cpu:
    mov byte [text_attr], C_CYAN
    mov rsi, s_ff_cpu
    call print
    mov byte [text_attr], C_DEF
    mov rsi, cpu_brand
    mov ecx, 33                     ; tronque pour tenir dans 80 colonnes
.l:
    lodsb
    test al, al
    jz .e
    call putc
    dec ecx
    jnz .l
.e:
    ret

ff_gpu:
    mov rsi, s_ff_gpu
    mov rdi, s_gpuv
    jmp ff_kv

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
    mov ecx, VGA_W * VGA_H
    rep stosw
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
    cmp byte [cursor_y], VGA_H
    jb .done
    call scroll
    mov byte [cursor_y], VGA_H - 1
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
    mov rsi, VGA_MEM + VGA_W * 2
    mov rdi, VGA_MEM
    mov ecx, VGA_W * (VGA_H - 1) * 2 / 8
    rep movsq
    mov rdi, VGA_MEM + VGA_W * (VGA_H - 1) * 2
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
    movzx ebx, al
    cmp byte [kbd_ctrl], 0
    je .normal
    mov rsi, kbd_lower
    mov al, [rsi + rbx]
    cmp al, 'a'
    jb .poll
    cmp al, 'z'
    ja .poll
    sub al, 'a' - 1                 ; Ctrl+A = 1 ... Ctrl+Z = 26
    jmp .ret
.normal:
    mov rsi, kbd_lower
    cmp byte [kbd_shift], 0
    je .tbl
    mov rsi, kbd_upper
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
    cmp al, 0x1D
    je .ctrl_on
    jmp .poll
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
    cmp al, K_UP
    je .histup
    cmp al, K_DOWN
    je .histdn
    cmp al, 0x80
    jae .loop
    cmp al, ' '
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
cwd:        db 1
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
boot_secs:      dq 0
mem_total_kb:   dq 0
tmp_total_mb:   dq 0
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
    dq c_echo,      cmd_echo
    dq c_fastfetch, cmd_fastfetch
    dq c_neofetch,  cmd_fastfetch
    dq c_ff,        cmd_fastfetch
    dq c_uname,     cmd_uname
    dq c_whoami,    cmd_whoami
    dq c_hostname,  cmd_hostname
    dq c_id,        cmd_id
    dq c_ps,        cmd_ps
    dq c_pwd,       cmd_pwd
    dq c_ls,        cmd_ls
    dq c_cd,        cmd_cd
    dq c_cat,       cmd_cat
    dq c_date,      cmd_date
    dq c_uptime,    cmd_uptime
    dq c_free,      cmd_free
    dq c_lscpu,     cmd_lscpu
    dq c_pacman,    cmd_pacman
    dq c_sudo,      cmd_sudo
    dq c_reboot,    cmd_reboot
    dq c_poweroff,  cmd_poweroff
    dq c_shutdown,  cmd_poweroff
    dq c_halt,      cmd_poweroff
    dq c_exit,      cmd_exit
    dq c_logout,    cmd_exit
    dq 0, 0

c_help:      db "help",0
c_clear:     db "clear",0
c_echo:      db "echo",0
c_fastfetch: db "fastfetch",0
c_neofetch:  db "neofetch",0
c_ff:        db "ff",0
c_uname:     db "uname",0
c_whoami:    db "whoami",0
c_hostname:  db "hostname",0
c_id:        db "id",0
c_ps:        db "ps",0
c_pwd:       db "pwd",0
c_ls:        db "ls",0
c_cd:        db "cd",0
c_cat:       db "cat",0
c_date:      db "date",0
c_uptime:    db "uptime",0
c_free:      db "free",0
c_lscpu:     db "lscpu",0
c_pacman:    db "pacman",0
c_sudo:      db "sudo",0
c_reboot:    db "reboot",0
c_poweroff:  db "poweroff",0
c_shutdown:  db "shutdown",0
c_halt:      db "halt",0
c_exit:      db "exit",0
c_logout:    db "logout",0

; ---------------------------------------------------------------------
;  Systeme de fichiers simule
; ---------------------------------------------------------------------
align 8
dir_paths: dq p_root, p_home, p_etc, p_usr
dir_disp:  dq d_root, d_home, d_etc, d_usr
dir_lists: dq ls_root, ls_home, ls_etc, ls_usr

p_root: db "/",0
p_home: db "/root",0
p_etc:  db "/etc",0
p_usr:  db "/usr",0
d_root: db "/",0
d_home: db "~",0
d_etc:  db "etc",0
d_usr:  db "usr",0

; type : 1 = repertoire, 2 = fichier, 3 = executable, 0 = fin
ls_root:
    db 1,"bin",0,   1,"boot",0,  1,"dev",0,   1,"etc",0
    db 1,"home",0,  1,"lib",0,   1,"mnt",0,   1,"opt",0
    db 1,"proc",0,  1,"root",0,  1,"run",0,   1,"sbin",0
    db 1,"srv",0,   1,"sys",0,   1,"tmp",0,   1,"usr",0
    db 1,"var",0,   0

ls_home:
    db 1,".cache",0, 1,".config",0, 1,".local",0
    db 2,".bash_history",0, 2,".bashrc",0
    db 1,"builds",0, 2,"notes.txt",0, 3,"hello",0
    db 0

ls_etc:
    db 2,"fstab",0, 2,"group",0, 2,"hostname",0, 2,"hosts",0
    db 2,"locale.conf",0, 2,"os-release",0, 2,"pacman.conf",0
    db 2,"passwd",0, 2,"shadow",0, 2,"vconsole.conf",0
    db 1,"pacman.d",0, 1,"systemd",0, 0

ls_usr:
    db 1,"bin",0, 1,"include",0, 1,"lib",0, 1,"local",0
    db 1,"share",0, 1,"src",0, 0

align 8
file_table:
    dq f_osrel1,  t_osrel
    dq f_osrel2,  t_osrel
    dq f_hostn1,  t_hostn
    dq f_hostn2,  t_hostn
    dq f_version, t_version
    dq f_cpuinfo, t_cpuinfo
    dq f_cpuinfo2, t_cpuinfo
    dq f_hosts1,  t_hosts
    dq f_hosts2,  t_hosts
    dq f_passwd1, t_passwd
    dq f_passwd2, t_passwd
    dq f_notes1,  t_notes
    dq f_notes2,  t_notes
    dq f_bashrc1, t_bashrc
    dq f_bashrc2, t_bashrc
    dq 0, 0

f_osrel1:  db "/etc/os-release",0
f_osrel2:  db "os-release",0
f_hostn1:  db "/etc/hostname",0
f_hostn2:  db "hostname",0
f_version: db "/proc/version",0
f_cpuinfo:  db "/proc/cpuinfo",0
f_cpuinfo2: db "cpuinfo",0
f_hosts1:  db "/etc/hosts",0
f_hosts2:  db "hosts",0
f_passwd1: db "/etc/passwd",0
f_passwd2: db "passwd",0
f_notes1:  db "/root/notes.txt",0
f_notes2:  db "notes.txt",0
f_bashrc1: db "/root/.bashrc",0
f_bashrc2: db ".bashrc",0

t_osrel:
    db 'NAME="Arch Linux"', 10
    db 'PRETTY_NAME="Arch Linux"', 10
    db 'ID=arch', 10
    db 'BUILD_ID=rolling', 10
    db 'ANSI_COLOR="38;2;23;147;209"', 10
    db 'HOME_URL="https://archlinux.org/"', 10
    db 'LOGO=archlinux-logo', 10, 0

t_hostn:   db "archlinux", 10, 0

t_version:
    db "Linux version 6.9.3-arch1-1 (linux@archlinux) (gcc 14.1.1) #1 SMP", 10, 0

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
    db "127.0.1.1   archlinux.localdomain archlinux", 10, 0

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
    db "alias ff='fastfetch'", 10
    db "PS1='[\\u@\\h \\W]\\$ '", 10, 0

; ---------------------------------------------------------------------
;  Messages de demarrage
; ---------------------------------------------------------------------
align 8
dmesg_table:
    dq dm1, dm2, dm3, dm4, dm5, dm6, dm7, dm8, dm9, dm10, dm11, 0

dm1:  db "[    0.000000] Linux version 6.9.3-arch1-1 (linux@archlinux) #1 SMP",0
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
s_issue:     db "Arch Linux 6.9.3-arch1-1 (tty1)",10,10,0
s_login:     db "archlinux login: ",0
s_passwd:    db "Password: ",0
s_lastlogin: db "Last login: ",0
s_ontty:     db " on tty1",10,0
s_host:      db "archlinux",0
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
s_bashcd:    db "bash: cd: ",0
s_nosuch:    db ": No such file or directory",10,0
s_cat:       db "cat: ",0
s_cat_usage: db "usage: cat <fichier>",10,0
s_tilde:     db "~",0
s_dotdot:    db "..",0
s_dasha:     db "-a",0
s_dashr:     db "-r",0
s_linux:     db "Linux",0
s_krel:      db "6.9.3-arch1-1",0
s_uname_a:   db "Linux archlinux 6.9.3-arch1-1 #1 SMP x86_64 GNU/Linux",10,0
s_id:        db "uid=0(root) gid=0(root) groups=0(root)",10,0
s_cpu_unk:   db "Unknown x86_64 CPU",0

s_ps:
    db "    PID TTY          TIME CMD",10
    db "      1 ?        00:00:01 systemd",10
    db "    218 ?        00:00:00 systemd-journald",10
    db "    412 tty1     00:00:00 login",10
    db "    418 tty1     00:00:00 bash",10
    db "    433 tty1     00:00:00 ps",10,0

s_free_hdr:
    db "               total        used        free      shared  buff/cache",10,0
s_free_mem:  db "Mem:  ",0
s_free_tail: db "           0           3",10,0
s_free_swap: db "Swap: ",0

s_lscpu1:
    db "Architecture:            x86_64",10
    db "  CPU op-mode(s):        32-bit, 64-bit",10
    db "  Address sizes:         40 bits physical, 48 bits virtual",10
    db "  Byte Order:            Little Endian",10
    db "CPU(s):                  1",10
    db "Model name:              ",0
s_lscpu2:
    db "  Thread(s) per core:    1",10
    db "  Core(s) per socket:    1",10
    db "  Socket(s):             1",10
    db "Virtualization features:",10
    db "  Hypervisor vendor:     KVM",10
    db "  Virtualization type:   full",10,0

s_pq:        db "-Q",0
s_psyu:      db "-Syu",0
s_pacman_use:
    db "usage:  pacman <operation> [...]",10
    db "operations:",10
    db "    pacman -Q     liste les paquets installes",10
    db "    pacman -Syu   met le systeme a jour",10,0
s_pkglist:
    db "bash 5.2.026-5",10
    db "coreutils 9.5-1",10
    db "filesystem 2024.04.07-1",10
    db "gcc-libs 14.1.1-2",10
    db "glibc 2.39-4",10
    db "linux 6.9.3.arch1-1",10
    db "nasm 2.16.03-1",10
    db "pacman 6.1.0-3",10
    db "systemd 255.7-1",10
    db "util-linux 2.40.1-1",10,0
s_syu1: db "Synchronizing package databases...",10,0
s_syu2:
    db " core is up to date",10
    db " extra is up to date",10,0
s_syu3: db "Starting full system upgrade...",10," there is nothing to do",10,0

s_sudo:  db "root is already root. Nothing to escalate.",10,0
s_reboot:   db "Broadcast message: The system is going down for reboot NOW!",10,0
s_poweroff: db "Broadcast message: The system is going down for poweroff NOW!",10,0

s_help:
    db "Commandes internes du shell ArchNasm :",10,10
    db "  fastfetch / neofetch / ff   informations systeme",10
    db "  help                        cette aide",10
    db "  clear        (Ctrl+L)       efface l'ecran",10
    db "  echo <texte>                affiche du texte",10
    db "  ls / cd / pwd / cat         navigation dans le systeme de fichiers",10
    db "  uname [-a|-r]               version du noyau",10
    db "  whoami / id / hostname      identite",10
    db "  ps / free / lscpu           etat du systeme",10
    db "  date / uptime               horloge temps reel (CMOS)",10
    db "  pacman -Q | -Syu            gestionnaire de paquets",10
    db "  reboot / poweroff           redemarrage / extinction",10
    db "  exit                        ferme la session",10,10
    db "Fleches haut/bas : historique.  Ctrl+C : annule la ligne.",10,0

; ---------------------------------------------------------------------
;  fastfetch : logo + informations
; ---------------------------------------------------------------------
align 8
logo_lines:
    dq lg0,  lg1,  lg2,  lg3,  lg4,  lg5,  lg6,  lg7,  lg8,  lg9
    dq lg10, lg11, lg12, lg13, lg14, lg15, lg16, lg17, lg18
LOGO_N equ 19

lg0:  db '                   -`',0
lg1:  db '                  .o+`',0
lg2:  db '                 `ooo/',0
lg3:  db '                `+oooo:',0
lg4:  db '               `+oooooo:',0
lg5:  db '               -+oooooo+:',0
lg6:  db '             `/:-:++oooo+:',0
lg7:  db '            `/++++/+++++++:',0
lg8:  db '           `/++++++++++++++:',0
lg9:  db '          `/+++ooooooooooooo/`',0
lg10: db '         ./ooosssso++osssssso+`',0
lg11: db '        .oossssso-````/ossssss+`',0
lg12: db '       -osssssso.      :ssssssso.',0
lg13: db '      :osssssss/        osssso+++.',0
lg14: db '     /ossssssss/        +ssssooo/-',0
lg15: db '   `/ossssso+/:-        -:/+osssso+-',0
lg16: db '  `+sso+:-`                 `.-/+oso:',0
lg17: db ' `++:.                           `-/+/',0
lg18: db ' .`                                 `/',0

align 8
info_lines:
    dq 0, ff_title, ff_rule, ff_os, ff_hostm, ff_kernel, ff_uptime
    dq ff_packages, ff_shell, ff_display, ff_term, ff_cpu, ff_gpu
    dq ff_memory, 0, ff_colors1, ff_colors2, 0, 0

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

s_osname:     db "Arch Linux x86_64",0
s_machine:    db "QEMU Standard PC (i440FX)",0
s_pkgs:       db "231 (pacman)",0
s_shellv:     db "bash 5.2.26",0
s_dispv:      db "80x25 (text mode)",0
s_termv:      db "/dev/tty1",0
s_gpuv:       db "VGA compatible controller",0
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

; ---------------------------------------------------------------------
;  Tables clavier (jeu de scancodes 1, indices 0x00..0x57)
; ---------------------------------------------------------------------
align 8
%ifdef AZERTY
; ---- disposition francaise AZERTY (accents en codepage 437)
kbd_lower:
    db 0,27,'&',0x82,'"',39,'(','-',0x8A,'_',0x87,0x85,')','=',8,9
    db 'a','z','e','r','t','y','u','i','o','p','^','$',10,0,'q','s'
    db 'd','f','g','h','j','k','l','m',0x97,0xFD,0,'*','w','x','c','v'
    db 'b','n',',',';',':','!',0,'*',0,' ',0,0,0,0,0,0
    db 0,0,0,0,0,0,0,'7','8','9','-','4','5','6','+','1'
    db '2','3','0','.',0,0,'<',0
kbd_upper:
    db 0,27,'1','2','3','4','5','6','7','8','9','0',0xF8,'+',8,9
    db 'A','Z','E','R','T','Y','U','I','O','P','"',0x9C,10,0,'Q','S'
    db 'D','F','G','H','J','K','L','M','%','~',0,0xE6,'W','X','C','V'
    db 'B','N','?','.','/',0x15,0,'*',0,' ',0,0,0,0,0,0
    db 0,0,0,0,0,0,0,'7','8','9','-','4','5','6','+','1'
    db '2','3','0','.',0,0,'>',0
%else
; ---- disposition americaine QWERTY (par defaut)
kbd_lower:
    db 0,27,'1','2','3','4','5','6','7','8','9','0','-','=',8,9
    db 'q','w','e','r','t','y','u','i','o','p','[',']',10,0,'a','s'
    db 'd','f','g','h','j','k','l',';',39,'`',0,92,'z','x','c','v'
    db 'b','n','m',',','.','/',0,'*',0,' ',0,0,0,0,0,0
    db 0,0,0,0,0,0,0,'7','8','9','-','4','5','6','+','1'
    db '2','3','0','.',0,0,0,0
kbd_upper:
    db 0,27,'!','@','#','$','%','^','&','*','(',')','_','+',8,9
    db 'Q','W','E','R','T','Y','U','I','O','P','{','}',10,0,'A','S'
    db 'D','F','G','H','J','K','L',':','"','~',0,'|','Z','X','C','V'
    db 'B','N','M','<','>','?',0,'*',0,' ',0,0,0,0,0,0
    db 0,0,0,0,0,0,0,'7','8','9','-','4','5','6','+','1'
    db '2','3','0','.',0,0,0,0
%endif

; ---------------------------------------------------------------------
;  Tampons
; ---------------------------------------------------------------------
align 8
cpu_brand: times 52 db 0
user_buf:  times 34 db 0
pass_buf:  times 34 db 0
cmdline:   times CMDLEN db 0
hist_buf:  times HIST_MAX * CMDLEN db 0

kernel_end:
; remplissage jusqu'a 32 Kio (= KERNEL_SECTORS du bootloader)
times 32768 - ($ - $$) db 0
