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
;    * carte memoire BIOS E820 recuperee pour le noyau
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

    ; ---- desactive le bit "clignotement" pour avoir 16 couleurs de fond
    mov ax, 0x1003
    xor bx, bx
    int 0x10

    ; ---- carte memoire BIOS (E820) rangee en 0x5000 pour le noyau
    call do_e820

    ; ---- chargement du noyau
    mov si, msg_load
    call bios_print

    xor ax, ax
    int 0x13                    ; reset controleur disque

    mov bx, KERNEL_LOAD
    mov word [lba], 1           ; le noyau commence au secteur logique 1
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
    jmp $
.ok:
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
    push ax
    push bx
    mov ah, 0x0E
    xor bx, bx
.next:
    lodsb
    test al, al
    jz .end
    int 0x10
    jmp .next
.end:
    pop bx
    pop ax
    ret

; =====================================================================
BITS 32
pm32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x7C00

    ; ---- tables de pagination : identity mapping des 2 premiers Mo
    mov dword [0x1000], 0x2003      ; PML4[0] -> PDPT
    mov dword [0x1004], 0
    mov dword [0x2000], 0x3003      ; PDPT[0] -> PD
    mov dword [0x2004], 0
    mov dword [0x3000], 0x83        ; PD[0] : page de 2 Mo, presente, RW
    mov dword [0x3004], 0

    mov eax, cr4
    or  eax, 1 << 5                 ; PAE
    mov cr4, eax

    mov eax, 0x1000
    mov cr3, eax

    mov ecx, 0xC0000080             ; EFER
    rdmsr
    or  eax, 1 << 8                 ; LME
    wrmsr

    mov eax, cr0
    or  eax, 1 << 31                ; PG
    mov cr0, eax

    jmp 0x18:lm64

; =====================================================================
BITS 64
lm64:
    mov ax, 0x20
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
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
msg_load:   db "Loading Arch...", 13, 10, 0
msg_err:    db "DISK ERROR", 13, 10, 0

times 510-($-$$) db 0
dw 0xAA55
