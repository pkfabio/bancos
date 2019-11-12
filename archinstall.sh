#!/usr/bin/env bash

linux="linux"
root_passwd="140182"
user_passwd="140182"
hostname="arch"
username="pk"
locale="pt_BR"
timezone="America/Sao_Paulo"
keyboard="br-abnt2"

echo ":: Atualizando relogio do sistema..."
timedatectl set-ntp true

echo ":: Montando partições..."
mount /dev/sda2 /mnt
mkdir /mnt/{boot,home}
mount /dev/sda1 /mnt/boot
mount /dev/sda3 /mnt/home

echo ":: Instalando o ArchLinux..."
pacstrap /mnt base base-devel $linux $linux-headers linux-firmware intel-ucode networkmanager wget git reflector sudo bash-completion cronie

echo ":: Gerando o fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

rootID=$(lsblk -no UUID /dev/sda2)

echo ":: Configurando novo sitema..."
arch-chroot /mnt /bin/bash <<EOF
echo ">> Setando relógio do sistema..."
ln -sf /usr/share/zoneinfo/$timezone /mnt/localtime
hwclock --systohc --localtime

echo ">> Setando os locales..."
echo "$locale.UTF-8 UTF-8" >> /etc/locale.gen
echo "LANG=$locale.UTF-8" >> /etc/locale.conf
echo "LC_COLLATE=C" >> /etc/locale.conf
locale-gen

echo ">> Configurando telcado..."
echo "KEYMAP=$keyboard" > /etc/vconsole.conf

echo ">> Setando o hostname..."
echo $hostname > /etc/hostname

echo ">> Setando senha de root..."
echo -en "$root_passwd\n$root_passwd" | passwd

echo ">> Criando novo usuário..."
useradd -m -G wheel -s /bin/bash $username
usermod -a -G video $username
echo -en "$user_passwd\n$user_passwd" | passwd

echo ">> Gerando initramfs..."
mkinitcpio -p $linux

echo ">> Configurando boot do sytemd..."
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
linux /vmlinuz-$linux
initrd /intel-ucode.img
initrd /initramfs-$linux.img
options root=UUID=$rootID rw
END

echo ">> Configurando hook para updates do systemd-boot..."
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

echo ">> Atualizando a lista de mirrors..."
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.BAK
reflector --latest 200 --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
echo ">> Configurando hook para updates da lista de mirrors..."
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

echo ">> Habilitando periodic TRIM..."
systemctl enable fstrim.timer

echo "Habilitando NetworkManager..."
systemctl enable NetworkManager

echo ">> Adicionando usuário como sudoer"
echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo

EOF

echo ":: Desmontando partições..."
umount -R /mnt

echo ":: ArchLinux instaldo. Você pode reiniciar agora!"
