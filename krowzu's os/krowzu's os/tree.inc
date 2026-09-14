; Arborescence -- genere par gentree.py
n_root    equ n_0
n_rootdir equ n_50
align 8
n_0:  dq vn_72,   0,     n_1,         VT_DIR,  0
n_1:  dq vn_11,   n_0,   n_2,         VT_DIR,  n_13
n_2:  dq vn_0,    n_1,   0,           VT_EXEC, n_3
n_3:  dq vn_1,    n_1,   0,           VT_EXEC, n_4
n_4:  dq vn_2,    n_1,   0,           VT_EXEC, n_5
n_5:  dq vn_3,    n_1,   0,           VT_EXEC, n_6
n_6:  dq vn_4,    n_1,   0,           VT_EXEC, n_7
n_7:  dq vn_5,    n_1,   0,           VT_EXEC, n_8
n_8:  dq vn_6,    n_1,   0,           VT_EXEC, n_9
n_9:  dq vn_7,    n_1,   0,           VT_EXEC, n_10
n_10: dq vn_8,    n_1,   0,           VT_EXEC, n_11
n_11: dq vn_9,    n_1,   0,           VT_EXEC, n_12
n_12: dq vn_10,   n_1,   0,           VT_EXEC, 0
n_13: dq vn_16,   n_0,   n_14,        VT_DIR,  n_18
n_14: dq vn_13,   n_13,  n_15,        VT_DIR,  n_16
n_15: dq vn_12,   n_14,  t_grubcfg,   VT_FILE, 0
n_16: dq vn_14,   n_13,  0,           VT_FILE, n_17
n_17: dq vn_15,   n_13,  0,           VT_FILE, 0
n_18: dq vn_23,   n_0,   n_19,        VT_DIR,  n_25
n_19: dq vn_17,   n_18,  0,           VT_FILE, n_20
n_20: dq vn_18,   n_18,  0,           VT_FILE, n_21
n_21: dq vn_19,   n_18,  0,           VT_FILE, n_22
n_22: dq vn_20,   n_18,  0,           VT_FILE, n_23
n_23: dq vn_21,   n_18,  0,           VT_FILE, n_24
n_24: dq vn_22,   n_18,  0,           VT_FILE, 0
n_25: dq vn_37,   n_0,   n_26,        VT_DIR,  n_39
n_26: dq vn_24,   n_25,  t_fstab,     VT_FILE, n_27
n_27: dq vn_25,   n_25,  t_group,     VT_FILE, n_28
n_28: dq vn_26,   n_25,  t_hostn,     VT_FILE, n_29
n_29: dq vn_27,   n_25,  t_hosts,     VT_FILE, n_30
n_30: dq vn_28,   n_25,  t_locale,    VT_FILE, n_31
n_31: dq vn_29,   n_25,  t_osrel,     VT_FILE, n_32
n_32: dq vn_31,   n_25,  n_33,        VT_DIR,  n_34
n_33: dq vn_30,   n_32,  t_mirror,    VT_FILE, 0
n_34: dq vn_32,   n_25,  t_passwd,    VT_FILE, n_35
n_35: dq vn_33,   n_25,  t_shadow,    VT_FILE, n_36
n_36: dq vn_35,   n_25,  n_37,        VT_DIR,  n_38
n_37: dq vn_34,   n_36,  t_sysconf,   VT_FILE, 0
n_38: dq vn_36,   n_25,  t_vcons,     VT_FILE, 0
n_39: dq vn_43,   n_0,   n_40,        VT_DIR,  n_45
n_40: dq vn_42,   n_39,  n_41,        VT_DIR,  0
n_41: dq vn_38,   n_40,  t_bashrc,    VT_FILE, n_42
n_42: dq vn_39,   n_40,  t_memo,      VT_FILE, n_43
n_43: dq vn_41,   n_40,  n_44,        VT_DIR,  0
n_44: dq vn_40,   n_43,  t_idees,     VT_FILE, 0
n_45: dq vn_48,   n_0,   n_46,        VT_DIR,  n_50
n_46: dq vn_44,   n_45,  t_cpuinfo,   VT_FILE, n_47
n_47: dq vn_45,   n_45,  t_meminfo,   VT_FILE, n_48
n_48: dq vn_46,   n_45,  t_procup,    VT_FILE, n_49
n_49: dq vn_47,   n_45,  t_version,   VT_FILE, 0
n_50: dq vn_60,   n_0,   n_51,        VT_DIR,  n_63
n_51: dq vn_49,   n_50,  t_hist,      VT_FILE, n_52
n_52: dq vn_38,   n_50,  t_bashrc,    VT_FILE, n_53
n_53: dq vn_50,   n_50,  0,           VT_DIR,  n_54
n_54: dq vn_51,   n_50,  0,           VT_DIR,  n_55
n_55: dq vn_52,   n_50,  0,           VT_DIR,  n_56
n_56: dq vn_53,   n_50,  0,           VT_DIR,  n_57
n_57: dq vn_54,   n_50,  0,           VT_DIR,  n_58
n_58: dq vn_55,   n_50,  0,           VT_DIR,  n_59
n_59: dq vn_58,   n_50,  n_60,        VT_DIR,  n_62
n_60: dq vn_56,   n_59,  0,           VT_FILE, n_61
n_61: dq vn_57,   n_59,  t_kasm,      VT_FILE, 0
n_62: dq vn_59,   n_50,  t_notes,     VT_FILE, 0
n_63: dq vn_61,   n_0,   0,           VT_DIR,  n_64
n_64: dq vn_66,   n_0,   n_65,        VT_DIR,  n_70
n_65: dq vn_11,   n_64,  0,           VT_DIR,  n_66
n_66: dq vn_62,   n_64,  0,           VT_DIR,  n_67
n_67: dq vn_63,   n_64,  0,           VT_DIR,  n_68
n_68: dq vn_64,   n_64,  0,           VT_DIR,  n_69
n_69: dq vn_65,   n_64,  0,           VT_DIR,  0
n_70: dq vn_71,   n_0,   n_71,        VT_DIR,  0
n_71: dq vn_67,   n_70,  0,           VT_DIR,  n_72
n_72: dq vn_70,   n_70,  n_73,        VT_DIR,  n_75
n_73: dq vn_68,   n_72,  t_bootlog,   VT_FILE, n_74
n_74: dq vn_69,   n_72,  t_pacmanlog, VT_FILE, 0
n_75: dq vn_61,   n_70,  0,           VT_DIR,  0

vn_0:    db "bash",0
vn_1:    db "ls",0
vn_2:    db "mkdir",0
vn_3:    db "mkfile",0
vn_4:    db "nasm",0
vn_5:    db "rm",0
vn_6:    db "see",0
vn_7:    db "srm",0
vn_8:    db "sys",0
vn_9:    db "vim",0
vn_10:   db "where",0
vn_11:   db "bin",0
vn_12:   db "grub.cfg",0
vn_13:   db "grub",0
vn_14:   db "initramfs-nullcore.img",0
vn_15:   db "vmlinuz-nullcore",0
vn_16:   db "boot",0
vn_17:   db "null",0
vn_18:   db "random",0
vn_19:   db "sda",0
vn_20:   db "sda1",0
vn_21:   db "tty1",0
vn_22:   db "zero",0
vn_23:   db "dev",0
vn_24:   db "fstab",0
vn_25:   db "group",0
vn_26:   db "hostname",0
vn_27:   db "hosts",0
vn_28:   db "locale.conf",0
vn_29:   db "os-release",0
vn_30:   db "mirrorlist",0
vn_31:   db "pacman.d",0
vn_32:   db "passwd",0
vn_33:   db "shadow",0
vn_34:   db "system.conf",0
vn_35:   db "systemd",0
vn_36:   db "vconsole.conf",0
vn_37:   db "etc",0
vn_38:   db ".bashrc",0
vn_39:   db "memo.txt",0
vn_40:   db "idees.txt",0
vn_41:   db "projets",0
vn_42:   db "user",0
vn_43:   db "home",0
vn_44:   db "cpuinfo",0
vn_45:   db "meminfo",0
vn_46:   db "uptime",0
vn_47:   db "version",0
vn_48:   db "proc",0
vn_49:   db ".bash_history",0
vn_50:   db "Documents",0
vn_51:   db "Images",0
vn_52:   db "Installation",0
vn_53:   db "Musique",0
vn_54:   db "Telechargements",0
vn_55:   db "Videos",0
vn_56:   db "bootloader.asm",0
vn_57:   db "kernel.asm",0
vn_58:   db "builds",0
vn_59:   db "notes.txt",0
vn_60:   db "root",0
vn_61:   db "tmp",0
vn_62:   db "include",0
vn_63:   db "lib",0
vn_64:   db "share",0
vn_65:   db "src",0
vn_66:   db "usr",0
vn_67:   db "cache",0
vn_68:   db "boot.log",0
vn_69:   db "pacman.log",0
vn_70:   db "log",0
vn_71:   db "var",0
vn_72:   db "/",0
