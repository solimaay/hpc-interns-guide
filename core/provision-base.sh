#!/usr/bin/env bash
# provision-base.sh - base setup for one lab VM (Rocky Linux 9).
#
# The Vagrantfile runs this as root on every node. The node names and IP addresses are in
# nodes.txt; the shared folder and the lab password are set just below.
#
# What it does: hostname and /etc/hosts, swap, packages, time sync, firewall and SELinux
# settings, SSH password login, shared storage (NFS), lab users, and the lab tools.
# It does NOT install Slurm (chapter 7) and does NOT create SSH keys (chapter 3).
#
# Safe to run more than once.
set -euo pipefail

# ---- settings: edit here ----------------------------------------------------
SHARED=/shared
PASSWORD=hpclab
# -----------------------------------------------------------------------------

LAB_ROOT=/vagrant                 # this folder, shared into the VM by Vagrant
CORE_DIR="$LAB_ROOT/core"
NODES="$(grep -vE '^\s*(#|$)' "$LAB_ROOT/nodes.txt" | awk '{print $1"="$2}' | tr '\n' ' ')"

# This node: its name is the hostname Vagrant set; the node called "login" is the login node.
LAB_NODE="$(hostname -s)"
LAB_ROLE=compute; [ "$LAB_NODE" = login ] && LAB_ROLE=login
for pair in $NODES; do
  if [ "${pair%%=*}" = "$LAB_NODE" ]; then LAB_IP="${pair#*=}"; fi
done
: "${LAB_IP:?$LAB_NODE is not listed in nodes.txt}"
SUBNET="${LAB_IP%.*}.0/24"

log() { echo "[$LAB_NODE] $*"; }

# ---- hostname and /etc/hosts ------------------------------------------------
hostnamectl set-hostname "$LAB_NODE"
# Some boxes map the node's own name to 127.0.x.1, which breaks cluster software.
sed -i -E "/^127\.0\.[01]\.1[[:space:]]+${LAB_NODE}([[:space:]]|\$)/d" /etc/hosts
sed -i '/# BEGIN hpc-lab/,/# END hpc-lab/d' /etc/hosts
{
  echo "# BEGIN hpc-lab"
  for pair in $NODES; do echo "${pair#*=} ${pair%%=*}"; done
  echo "# END hpc-lab"
} >> /etc/hosts
log "hostname and /etc/hosts set"

# ---- swap: 1 GB of RAM is tight while software installs ---------------------
if [ -z "$(swapon --show --noheadings)" ]; then
  dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  echo '/swapfile none swap defaults 0 0' >> /etc/fstab
  log "1 GiB swap file enabled"
fi

# ---- packages ---------------------------------------------------------------
# Upgrade OpenSSH first. Installing packages upgrades openssl, and an older sshd that is
# still running would then reject new connections.
log "installing packages (needs internet access)"
dnf -y upgrade openssh openssh-clients openssh-server >/dev/null
systemctl restart sshd
dnf -y install nfs-utils chrony cronie rsync tar gzip vim-enhanced nano tree lsof strace \
  psmisc procps-ng bind-utils iproute iputils net-tools bash-completion man-db quota python3 >/dev/null
systemctl enable --now crond chronyd >/dev/null 2>&1

# ---- SELinux and firewall ---------------------------------------------------
setsebool -P use_nfs_home_dirs 1   # lets users log in with NFS home directories
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --zone=trusted --add-source="$SUBNET" >/dev/null
  firewall-cmd --reload >/dev/null
fi

# ---- SSH: password login, so learners can set up keys themselves in chapter 3 ----
printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/01-lab.conf
systemctl reload sshd

# ---- shared storage: the login node exports /shared, compute nodes mount it ----
if [ "$LAB_ROLE" = login ]; then
  mkdir -p "$SHARED/home" "$SHARED/scratch" "$SHARED/project/proj-a"
  chmod 755 "$SHARED" "$SHARED/home" "$SHARED/project"
  chmod 1777 "$SHARED/scratch"
  sed -i '\|# hpc-lab export|d' /etc/exports
  echo "$SHARED $SUBNET(rw,sync,no_subtree_check) # hpc-lab export" >> /etc/exports
  systemctl enable --now nfs-server
  exportfs -ra
  log "exporting $SHARED"
else
  mkdir -p "$SHARED"
  sed -i '\|# hpc-lab mount|d' /etc/fstab
  echo "login:$SHARED $SHARED nfs defaults,_netdev 0 0 # hpc-lab mount" >> /etc/fstab
  systemctl enable remote-fs.target >/dev/null 2>&1   # otherwise /shared is missing after a reboot
  systemctl daemon-reload
  until mountpoint -q "$SHARED"; do   # the login node may still be installing
    mount "$SHARED" 2>/dev/null || { log "waiting for login:$SHARED ..."; sleep 5; }
  done
  log "mounted $SHARED from login"
fi

# ---- lab groups and users (same IDs on every node; the lab has no LDAP) -----
getent group hpc-users >/dev/null || groupadd -g 2000 hpc-users
getent group proj-a    >/dev/null || groupadd -g 2100 proj-a
for entry in alice:2001:proj-a bob:2002:proj-a carol:2003:hpc-users; do
  IFS=: read -r user uid group <<< "$entry"
  if ! id "$user" >/dev/null 2>&1; then
    # only the login node creates the home directory (-m); the others see it over NFS
    [ "$LAB_ROLE" = login ] && create_home=-m || create_home=-M
    useradd -u "$uid" -g hpc-users -G "$group" -d "$SHARED/home/$user" "$create_home" -s /bin/bash "$user"
  fi
  echo "$user:$PASSWORD" | chpasswd
done
if [ "$LAB_ROLE" = login ]; then
  chown root:proj-a "$SHARED/project/proj-a"
  chmod 2770 "$SHARED/project/proj-a"
fi
log "lab users ready: alice, bob, carol (password: $PASSWORD)"

# ---- lab tools: everything in core/bin and modules/*/bin, without the .sh ---
for f in "$CORE_DIR"/bin/* "$LAB_ROOT"/modules/*/bin/*; do
  install -m 0755 "$f" "/usr/local/bin/$(basename "${f%.sh}")"
done
# RHEL's sudo ignores /usr/local/bin by default; 'sudo inject-fault' needs it.
echo 'Defaults secure_path = /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' > /etc/sudoers.d/90-lab-path
chmod 440 /etc/sudoers.d/90-lab-path

# ---- remember what this node is (lab-verify, slurm-verify and the Slurm provisioner read this file) --
cat > /etc/hpc-lab-release <<EOT
LAB_NODE=$LAB_NODE
LAB_ROLE=$LAB_ROLE
LAB_IP=$LAB_IP
LAB_NODES=${NODES// /,}
LAB_SHARED=$SHARED
EOT

log "base setup complete. Check with: lab-verify"
