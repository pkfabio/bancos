#!/usr/bin/env bash

#################
### Variáveis ### 
#################

root_passwd=""
user_passwd=""
disk="/dev/sda"
kernel="linux-lts"
hostname="bancos"
username="bancos"
locale="pt_BR"
timezone="America/Sao_Paulo"
keyboard="br-abnt2"

############################
### Script de instalação ###
############################

echo "arch~> Atualizando relogio do sistema.."
timedatectl set-ntp true 

echo "arch~> Criando partições.."
parted -s $disk \
    mklabel gpt \
    mkpart primary fat32 1 301 \
    -- mkpart primary ext4 301 -0 \
    set 1 esp on
mkfs.fat -F32 -n "Boot" $disk\1 1>/dev/null
mkfs.ext4 $disk\2 -L Root 1>/dev/null

echo "arch~> Montando partições.."
rootID=$(lsblk -no UUID $disk\2)
mount $disk\2 /mnt 
mkdir /mnt/boot
mount $disk\1 /mnt/boot

echo "arch~> Instalando pacotes base do ArchLinux.."
pacstrap /mnt base base-devel $kernel $kernel-headers linux-firmware networkmanager wget git reflector sudo bash-completion cronie xorg-server xorg-xinit numlockx virtualbox-guest-utils 

echo "arch~> Gerando o fstab.."
genfstab -U /mnt >> /mnt/etc/fstab 

echo "arch~> Copiando git de instalação para o sistema novo.."
cp -r $(pwd) /mnt/root/

echo "arch~> Entrando em modo chroot.."
arch-chroot /mnt /bin/bash <<EOF

echo "arch/chroot~> Verificando atualizações do novo sitema.."
pacman -Syyu --noconfirm 

echo "arch/chroot~> Configurando novo sitema.."

echo "arch/chroot~> Setando timezone.."
ln -sf /usr/share/zoneinfo/$timezone /mnt/localtime 

echo "arch/chroot~> Setando relógio do sistema.."
timedatectl set-ntp true 
hwclock --systohc --localtime 

echo "arch/chroot~> Setando os locales.."
echo "$locale.UTF-8 UTF-8" >> /etc/locale.gen 
echo "LANG=$locale.UTF-8" >> /etc/locale.conf 
echo "LC_COLLATE=C" >> /etc/locale.conf 
locale-gen 

echo "arch/chroot~> Setando teclado.."
echo "KEYMAP=$keyboard" > /etc/vconsole.conf 

echo "arch/chroot~> Setando o hostname.."
echo $hostname > /etc/hostname 

echo "arch/chroot~> Setando senha de root.."
echo -en "$root_passwd\n$root_passwd" | passwd 

echo "arch/chroot~> Criando novo usuário.."
useradd -m -G wheel -s /bin/bash $username 
usermod -a -G video $username 

echo "arch/chroot~> Setando senha de $username.."
echo -en "$user_passwd\n$user_passwd" | passwd $username 

echo "arch/chroot~> Gerando initramfs.."
mkinitcpio -p $kernel 

echo "arch/chroot~> Configurando boot do sytemd.."
bootctl --path=/boot install 
echo "" > /boot/loader/loader.conf
tee -a /boot/loader/loader.conf << END
default arch
timeout 0
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

echo "arch/chroot~> Configurando hook para updates do systemd-boot.."
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

echo "arch/chroot~> Atualizando a lista de mirrors.."
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.BAK 
reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist 

echo "arch/chroot~> Configurando hook para updates da lista de mirrors.." 
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

echo "arch/chroot~> Habilitando periodic TRIM..."
systemctl enable fstrim.timer 

echo "arch/chroot~> Habilitando NetworkManager..."
systemctl enable NetworkManager 

echo "arch/chroot~> Adicionando usuário como sudoer"
echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo

echo "arch/chroot~> Instalando AUR Helper (paru).."
git clone https://aur.archlinux.org/paru.git 
cd paru
makepkg -si 
cd ..

echo "arch/chroot~> Instalando gerenciador de janelas, menu dinamico e terminal.."
git clone https://git.suckless.org/dwm 
git clone https://git.suckless.org/dmenu 
git clone https://git.suckless.org/st 
cd dwm
cp ../dwm.c . 
cp ../config.def.h . 
make clean install 
cd ../dmenu
make clean install 
cd ../st
make clean install 
cd ..

echo "arch/chroot~> Instalando browser Librewolf e warsaw.."
paru -S librewolf-bin 
paru -S warsaw-bin 
cp certificado /home/$username
chown $username /home/$username/certificado 

echo "arch/chroot~> Setando inicialização do ambiente visual..."
su - $username -c echo "exec dwm" > /home/$username/.xinitrc
su - $username -c mkdir -p /home/$username/.config/dwm/
su - $username -c touch /home/$username/.config/dwm/autostart.sh
su - $username -c tee -a /home/$username/.config/dwm/autostart.sh << END
numlockx &
VBoxClient-All &
xrandr --output 1600x900 --pos 0x0 --rotate normal &
librewolf
shutdown -h now
END
su - $username -c chmod +x /home/$username/.config/dwm/autostart.sh
su - $username -c localectl set-x11-keymap br abnt2

echo "arch/chroot~> Habilitando login automático para $username
touch /etc/systemd/system/getty@tty1.service.d/autologin.conf
tee -a /etc/systemd/system/getty@tty1.service.d/autologin.conf << END
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin $username %I $TERM
Type=simple
Environment=XDG_SESSION_TYPE=x11
END

echo "arch/chroot~> Habilitando serviços na inicialização.."
systemctl enable vboxservice.service 
systemctl enable warsaw.service 

echo "arch/chroot~> Novo sistema configurado, saindo do modo chroot.."

EOF
echo
echo "arch~> Desmontando partições.."
umount -R /mnt 

echo "arch~> ArchLinux instalado.."
