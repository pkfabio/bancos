#!/usr/bin/env bash

root_passwd=""
user_passwd=""
kernel="linux"
hostname="arch-lunar"
username="pk"
locale="pt_BR"
timezone="America/Sao_Paulo"
keyboard="br-abnt2"

echo ":: Atualizando relogio do sistema.."
timedatectl set-ntp true

echo ":: Montando partições.."
mount /dev/sda2 /mnt
mkdir /mnt/{boot,home}
mount /dev/sda1 /mnt/boot
mount /dev/sda3 /mnt/home

echo ":: Instalando o ArchLinux.."
pacstrap /mnt base base-devel $kernel $kernel-headers linux-firmware intel-ucode networkmanager wget git reflector sudo bash-completion cronie

echo ":: Gerando o fstab.."
genfstab -U /mnt >> /mnt/etc/fstab

rootID=$(lsblk -no UUID /dev/sda2)

echo ":: Entrando em modo chroot.."
arch-chroot /mnt /bin/bash <<EOF

echo ":: chroot~> Configurando novo sitema.."

echo ":: chroot~> Setando relógio do sistema.."
ln -sf /usr/share/zoneinfo/$timezone /mnt/localtime
hwclock --systohc --localtime

echo ":: chroot~> Setando os locales.."
echo "$locale.UTF-8 UTF-8" >> /etc/locale.gen
echo "LANG=$locale.UTF-8" >> /etc/locale.conf
echo "LC_COLLATE=C" >> /etc/locale.conf
locale-gen

echo ":: chroot~> Configurando telcado.."
echo "KEYMAP=$keyboard" > /etc/vconsole.conf

echo ":: chroot~> Setando o hostname.."
echo $hostname > /etc/hostname

echo ":: chroot~> Setando senha de root.."
echo -en "$root_passwd\n$root_passwd" | passwd

echo ":: chroot~> Criando novo usuário.."
useradd -m -G wheel -s /bin/bash $username
usermod -a -G video $username
echo -en "$user_passwd\n$user_passwd" | passwd $username

echo ":: chroot~> Gerando initramfs.."
mkinitcpio -p $kernel

echo ":: chroot~> Configurando boot do sytemd.."
bootctl --path=/boot install
echo "" > /boot/loader/loader.conf
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
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.BAK
reflector --latest 200 --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
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
Exec = /bin/sh -c "reflector --latest 200 --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist"
END

echo ":: chroot~> Habilitando periodic TRIM..."
systemctl enable fstrim.timer

echo ":: chroot~> Habilitando NetworkManager..."
systemctl enable NetworkManager

echo ":: chroot~> Adicionando usuário como sudoer"
echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo
echo ":: chroot~> Novo sistema configurado.."

echo ":: chroot~> Saindo do modo chroot.."

EOF
echo
echo ":: Desmontando partições.."
umount -R /mnt

echo ":: ArchLinux instaldo. Você pode reiniciar agora!"
