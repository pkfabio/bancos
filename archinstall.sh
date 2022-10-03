#!/usr/bin/env bash

root_passwd=""
user_passwd=""
kernel="linux-lts"
hostname="bancos"
username="bancos"
locale="pt_BR"
timezone="America/Sao_Paulo"
keyboard="br-abnt2"

echo ":: Atualizando relogio do sistema.."
timedatectl set-ntp true 2&>1

echo ":: Montando partições.."
mount /dev/sda2 /mnt 2&>1
mkdir /mnt/{boot,home} 2&>1
mount /dev/sda1 /mnt/boot 2&>1
mount /dev/sda3 /mnt/home 2&>1

echo ":: Instalando pacotes base do ArchLinux.."
pacstrap /mnt base base-devel $kernel $kernel-headers linux-firmware networkmanager wget git reflector sudo bash-completion cronie xorg-server xorg-xinit 2&>1

echo ":: Gerando o fstab.."
genfstab -U /mnt >> /mnt/etc/fstab 2&>1

rootID=$(lsblk -no UUID /dev/sda2)

echo ":: Copiando git de instalação para o sistema novo.."
cp -r $(pwd) /mnt/root/

echo ":: Entrando em modo chroot.."
arch-chroot /mnt /bin/bash <<EOF

echo ":: chroot~> Configurando novo sitema.."

echo ":: chroot~> Setando relógio do sistema.."
ln -sf /usr/share/zoneinfo/$timezone /mnt/localtime 2&>1
hwclock --systohc --localtime 2&>1

echo ":: chroot~> Setando os locales.."
echo "$locale.UTF-8 UTF-8" >> /etc/locale.gen 2&>1
echo "LANG=$locale.UTF-8" >> /etc/locale.conf 2&>1
echo "LC_COLLATE=C" >> /etc/locale.conf 2&>1
locale-gen 2&>1

echo ":: chroot~> Configurando telcado.."
echo "KEYMAP=$keyboard" > /etc/vconsole.conf 2&>1

echo ":: chroot~> Setando o hostname.."
echo $hostname > /etc/hostname 2&>1

echo ":: chroot~> Setando senha de root.."
echo -en "$root_passwd\n$root_passwd" | passwd 2&>1

echo ":: chroot~> Criando novo usuário.."
useradd -m -G wheel -s /bin/bash $username 2&>1
usermod -a -G video $username 2&>1
echo -en "$user_passwd\n$user_passwd" | passwd $username 2&>1

echo ":: chroot~> Gerando initramfs.."
mkinitcpio -p $kernel 2&>1

echo ":: chroot~> Configurando boot do sytemd.."
bootctl --path=/boot install 2&>1
echo "" > /boot/loader/loader.conf 2&>1
tee -a /boot/loader/loader.conf << END
default arch
timeout 1
editor 0
END
touch /boot/loader/entries/arch.conf 
tee -a /boot/loader/entries/arch.conf << END
title ArchLinux
linux /vmlinuz-$kernel
initrd /intel-ucode.img
initrd /initramfs-$kernel.img
options root=UUID=$rootID rw
END

echo ":: chroot~> Configurando hook para updates do systemd-boot.."
mkdir -p /etc/pacman.d/hooks/
touch /etc/pacman.d/hooks/systemd-boot.hook
tee -a /etc/pacman.d/hooks/systemd-boot.hook << END
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = systemd-boot update
When = PostTransaction
Exec = /usr/bin/bootctl update
END

echo ":: chroot~> Atualizando a lista de mirrors.."
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.BAK 2&>1
reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist 2&>1
echo ":: chroot~> Configurando hook para updates da lista de mirrors.." 
touch /etc/pacman.d/hooks/mirrors-update.hook 
tee -a /etc/pacman.d/hooks/mirrors-update.hook << END
[Trigger]
Operation = Upgrade
Type = Package
Target = pacman-mirrorlist

[Action]
Description = Atualizando lista de mirrors com reflector
When = PostTransaction
Depends = reflector
Exec = /bin/sh -c "reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist"
END

echo ":: chroot~> Habilitando periodic TRIM..."
systemctl enable fstrim.timer 2&>1

echo ":: chroot~> Habilitando NetworkManager..."
systemctl enable NetworkManager 2&>1

echo ":: chroot~> Adicionando usuário como sudoer"
echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo
echo ":: chroot~> Novo sistema configurado.."

echo ":: chroot~> Habilitando login automático para $username
touch /etc/systemd/system/getty@tty1.service.d/autologin.conf
tee -a /etc/systemd/system/getty@tty1.service.d/autologin.conf << END
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin $username %I $TERM
Type=simple
Environment=XDG_SESSION_TYPE=x11
END

echo ":: chroot~> Saindo do modo chroot.."

EOF
echo
echo ":: Desmontando partições.."
umount -R /mnt 2&>1

echo ""
echo ":: ArchLinux instaldo.."
