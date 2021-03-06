# Run the text based installer to see dependency info in screenshots
text
logging --level=debug

#version=DEVEL
install

lang en_US.UTF-8
keyboard us
rootpw  --iscrypted $1$DZprqvCu$mhqFBjfLTH/PVvZIompVP/

authconfig --enableshadow --passalgo=sha512
selinux --enforcing
timezone --isUtc America/New_York

bootloader --location=mbr --driveorder=vda --append="crashkernel=auto rhgb quiet net.ifnames=0 biosdevname=0 console=tty0 console=ttyS0,115200n8"

# disk layout
zerombr
clearpart --all --drives=vda

part pv.0  --ondrive=vda --size=1    --grow
part /boot --ondrive=vda --size=300 --fstype=xfs

volgroup VG_UCI --pesize=4096 pv.0

logvol /                     --name=lv_os             --vgname=VG_UCI --size=5120  --fstype=xfs --grow
logvol /var/log              --name=lv_var_log        --vgname=VG_UCI --size=1024  --fstype=xfs
logvol /tmp                  --name=lv_tmp            --vgname=VG_UCI --size=1024  --fstype=xfs
logvol swap                  --name=lv_swap           --vgname=VG_UCI --size=2048  

network --bootproto=dhcp --device=link --activate --onboot=on --noipv6

reboot

%packages
@base --nodefaults
@virtualization-hypervisor
podman
cloud-init

# Exclude firmware
-aic*-firmware
-ivtv-firmware
-iwl*-firmware

# Misc other things we do not need.
-gcc-gfortran
-dracut-fips

%end

%post --log=/root/anaconda-post.log

exec < /dev/tty3 > /dev/tty3
chvt 3
set -x

# For some reason, DEBUG is set but empty in the kickstart.
unset DEBUG

systemctl enable libvirtd

# Link ctrl-alt-del.target to /dev/null to prevent reboot from console
ln -sf /dev/null /etc/systemd/system/ctrl-alt-del.target

# Create the journal directory to enable persistant logging
mkdir /var/log/journal

# On the appliances we expect eth0, so remove all the ifcfg-en<whatever> device configurations 
# and write a config for eth0 allowing the 'network' service to come up cleanly.
rm -f /etc/sysconfig/network-scripts/ifcfg-en*

cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Ethernet
USERCTL=no
DEFROUTE=yes
EOF

# Disable zeroconfig to allow access to meta-data service by cloud-init
cat >> /etc/sysconfig/network << EOF
NETWORKING=yes
NOZEROCONF=yes
EOF

# make sure there is a new line at the end of sshd_config
echo "" >> /etc/ssh/sshd_config

# Pull the latest UCI Image
podman pull docker.io/manageiq/v2v-conversion-host:latest

# Remove linux-firmware, installed by default
yum -C -y --noplugins remove linux-firmware

# Clean yum repodata
yum --noplugins clean all

# Create /var/lib/uci and /var/log/uci directories
mkdir /var/lib/uci
mkdir /var/log/uci

# Zero out spaces
# TODO: Figure out how to make `fstrim` work on build machine so we can drop
#       this hack.
dd if=/dev/zero of=/tmp_file bs=1M
rm -f /tmp_file

chvt 1

%end
