; =====================================================================
;  bootloader.asm  --  MBR 512 octets
;  16 bits reel -> mode protege 32 bits -> long mode 64 bits
;  Charge le noyau en 0x8000 puis saute dedans en 64 bits.
;
;  Modifie par rapport a la version d'origine :
;    * charge KERNEL_SECTORS secteurs (et plus seulement 4)
;    * boucle de lecture CHS correcte (gere le passage de piste/tete)
;    * 5 tentatives + reset disque en cas d'erreur
;    * mode texte 80x25 force + desactivation du clignotement
;    * police 8x8 du BIOS recopiee pour le mode 80x50 du noyau
;    * carte memoire BIOS E820 recuperee pour le noyau
;    * identity mapping de 4 Gio (et non 2 Mo) : indispensable pour lire
;      les tables SMBIOS et l'espace de configuration PCI
;    * porte A20 ouverte proprement (bit 0 du port 0x92 laisse a 0)
;
;  nasm -f bin bootloader.asm -o boot.bin
; =====================================================================

BITS 16
ORG 0x7C00

KERNEL_SECTORS  equ 64          ; 64 * 512 = 32 Kio de noyau
KERNEL_LOAD     equ 0x8000      ; adresse de chargement du noyau
SPT             equ 18          ; secteurs par piste (disquette 1.44 Mo)
HEADS           equ 2           ; nombre de tetes

E820_COUNT      equ 0x5000      ; dword : nb d'entrees E820
E820_TABLE      equ 0x5004      ; entrees de 24 octets
FONT8_ADDR      equ 0x6000      ; police 8x8 du BIOS (2048 octets)

PML4_ADDR       equ 0x1000
PDPT_ADDR       equ 0x2000
PD_ADDR         equ 0x20000     ; 4 repertoires contigus = 4 Gio

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    mov [boot_drive], dl        ; le BIOS met le disque de boot dans DL

    ; ---- mode texte 80x25 couleur, ecran efface
    mov ax, 0x0003
    int 0x10

    ; ---- desactive le bit "clignotement" : 16 couleurs de fond utilisables
    mov ax, 0x1003
    xor bx, bx
    int 0x10

    call grab_font8             ; police 8x8 -> 0x6000
    call do_e820                ; carte memoire -> 0x5000

    ; ---- chargement du noyau, secteur logique 1 et suivants
    mov bx, KERNEL_LOAD
    mov word [lba], 1
    mov cx, KERNEL_SECTORS
.read_loop:
    push cx
    call read_sector
    pop cx
    add bx, 512
    inc word [lba]
    loop .read_loop

    ; ---- ouverture de la porte A20 (fast gate)
    in al, 0x92
    test al, 2
    jnz .a20_ok
    or  al, 2
    and al, 0xFE                ; surtout ne pas armer le reset
    out 0x92, al
.a20_ok:

    ; ---- mode protege 32 bits
    lgdt [gdt.desc]
    mov eax, cr0
    or  eax, 1
    mov cr0, eax
    jmp 0x08:pm32

; ---------------------------------------------------------------------
;  Lit le secteur logique [lba] vers ES:BX  (LBA -> CHS)
; ---------------------------------------------------------------------
read_sector:
    mov si, 5                   ; 5 tentatives
.try:
    mov ax, [lba]
    xor dx, dx
    mov cx, SPT
    div cx                      ; ax = lba/SPT   dx = lba%SPT
    inc dx
    mov cl, dl                  ; CL = secteur (1..18)
    xor dx, dx
    mov di, HEADS
    div di                      ; ax = cylindre  dx = tete
    mov ch, al                  ; CH = cylindre
    mov dh, dl                  ; DH = tete
    mov dl, [boot_drive]
    mov ax, 0x0201              ; AH=02 lecture, AL=1 secteur
    int 0x13
    jnc .ok
    xor ax, ax                  ; reset puis on retente
    int 0x13
    dec si
    jnz .try
    mov si, msg_err
    call bios_print
    cli
    hlt
.ok:
    ret

; ---------------------------------------------------------------------
;  Police 8x8 du BIOS -> FONT8_ADDR (2048 octets)
;  Seul le mode reel peut la demander ; le noyau la televersera ensuite
;  dans le plan 2 du VGA pour basculer en 80x50.
; ---------------------------------------------------------------------
grab_font8:
    mov ax, 0x1130
    mov bh, 0x03                ; 03h = police 8x8
    int 0x10                    ; -> ES:BP
    push es
    pop ds                      ; DS = segment de la police
    mov si, bp
    xor ax, ax
    mov es, ax
    mov di, FONT8_ADDR
    mov cx, 2048
    rep movsb
    mov ds, ax                  ; DS remis a 0
    ret

; ---------------------------------------------------------------------
;  Carte memoire BIOS : int 15h / EAX=E820
; ---------------------------------------------------------------------
do_e820:
    mov di, E820_TABLE
    xor ebx, ebx
    xor bp, bp
.loop:
    mov eax, 0xE820
    mov edx, 0x534D4150         ; 'SMAP'
    mov ecx, 24
    mov dword [es:di+20], 1     ; force l'attribut ACPI 3.0 a "valide"
    int 0x15
    jc .done
    cmp eax, 0x534D4150
    jne .done
    mov ecx, [es:di+8]          ; longueur nulle -> entree ignoree
    or  ecx, [es:di+12]
    jz .skip
    inc bp
    add di, 24
.skip:
    test ebx, ebx
    jnz .loop
.done:
    movzx eax, bp
    mov [E820_COUNT], eax
    ret

; ---------------------------------------------------------------------
;  Affichage BIOS (teletype) : DS:SI = chaine terminee par 0
; ---------------------------------------------------------------------
bios_print:
    mov ah, 0x0E
    xor bx, bx
.next:
    lodsb
    test al, al
    jz .end
    int 0x10
    jmp .next
.end:
    ret

; =====================================================================
BITS 32
pm32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax

    ; ---- PML4 et PDPT a zero, puis PML4[0] -> PDPT
    mov edi, PML4_ADDR
    xor eax, eax
    mov ecx, 2048               ; 8 Kio / 4
    rep stosd
    mov dword [PML4_ADDR], PDPT_ADDR | 3

    ; ---- PDPT[0..3] -> 4 repertoires de pages
    mov edi, PDPT_ADDR
    mov eax, PD_ADDR | 3
    mov ecx, 4
.pdpt:
    mov [edi], eax
    add eax, 0x1000
    add edi, 8
    loop .pdpt

    ; ---- 4 repertoires a zero
    mov edi, PD_ADDR
    xor eax, eax
    mov ecx, 4096               ; 16 Kio / 4
    rep stosd

    ; ---- 2048 pages de 2 Mo en identite = 4 Gio
    mov edi, PD_ADDR
    mov eax, 0x83               ; presente, RW, page de 2 Mo
    mov ecx, 2048
.pd:
    mov [edi], eax
    add eax, 0x200000
    add edi, 8
    loop .pd

    mov eax, cr4
    or  eax, 1 << 5             ; PAE
    mov cr4, eax

    mov eax, PML4_ADDR
    mov cr3, eax

    mov ecx, 0xC0000080         ; EFER
    rdmsr
    or  eax, 1 << 8             ; LME
    wrmsr

    mov eax, cr0
    or  eax, 1 << 31            ; PG
    mov cr0, eax

    jmp 0x18:lm64

; =====================================================================
BITS 64
lm64:
    mov ax, 0x20
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x90000
    jmp KERNEL_LOAD

; =====================================================================
;  GDT
; =====================================================================
gdt:
    dq 0                                    ; 0x00 null
    dw 0xFFFF, 0                            ; 0x08 code 32 bits
    db 0, 10011010b, 11001111b, 0
    dw 0xFFFF, 0                            ; 0x10 data 32 bits
    db 0, 10010010b, 11001111b, 0
    dw 0, 0                                 ; 0x18 code 64 bits (L=1)
    db 0, 10011010b, 00100000b, 0
    dw 0, 0                                 ; 0x20 data 64 bits
    db 0, 10010010b, 0, 0
.desc:
    dw $ - gdt - 1
    dd gdt

boot_drive: db 0
lba:        dw 0
msg_err:    db "DISK ERR", 0

times 510-($-$$) db 0
dw 0xAA55
