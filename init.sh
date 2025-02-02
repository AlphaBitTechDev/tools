#!/bin/bash

# Run as root or with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

# Variables (customize these)
NEW_USER="node"           # New non-root user
SSH_PORT="2222"            # Custom SSH port
ALLOWED_SSH_USERS="$NEW_USER"  # Users allowed to SSH

# Step 1: Update System
apt update && apt upgrade -y
apt dist-upgrade -y
apt autoremove -y

# Step 2: Create Non-Root User
if ! id -u "$NEW_USER" &>/dev/null; then
  adduser --gecos "" "$NEW_USER"
  usermod -aG sudo "$NEW_USER"
  echo "Created user: $NEW_USER"
else
  echo "User $NEW_USER already exists."
fi

# Step 2.5: Add Current User's SSH Public Key to New User
CURRENT_USER_SSH_KEY="/home/${SUDO_USER:-$USER}/.ssh/authorized_keys"

if [ -f "$CURRENT_USER_SSH_KEY" ]; then
  mkdir -p "/home/$NEW_USER/.ssh"
  cp "$CURRENT_USER_SSH_KEY" "/home/$NEW_USER/.ssh/authorized_keys"
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
  chmod 700 "/home/$NEW_USER/.ssh"
  chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
  echo "Copied SSH public key from ${SUDO_USER:-$USER} to $NEW_USER."
else
  echo "ERROR: No SSH key found in $CURRENT_USER_SSH_KEY. Set up SSH keys first!"
  exit 1
fi

# Step 3: Secure SSH
sed -i "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
echo "AllowUsers $ALLOWED_SSH_USERS" >> /etc/ssh/sshd_config
systemctl restart ssh

# Step 4: Enable UFW
apt install ufw -y
ufw default deny outgoing
ufw default deny incoming
ufw allow "$SSH_PORT/tcp"
#ufw allow 80/tcp
#ufw allow 443/tcp
#ufw --force enable

# Step 5: Install Fail2Ban
apt install fail2ban -y
systemctl enable fail2ban --now

# Step 6: Enable Automatic Updates
apt install unattended-upgrades -y
echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades

# Step 7: Remove Unused Services
apt purge snapd telnet rsh-client rsh-redone-client -y

# Step 8: Harden Shared Memory
if ! grep -q "/run/shm" /etc/fstab; then
  echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0" >> /etc/fstab
  mount -a
fi

# Step 9: Install Monitoring Tools
apt install auditd logwatch rkhunter -y

# Step 10: Enable AppArmor
systemctl enable apparmor --now

echo "
✅ Server hardening complete!
--------------------------------
- SSH Port: $SSH_PORT
- Non-root user: $NEW_USER
- SSH root login: DISABLED
- Password authentication: DISABLED
--------------------------------
⚠️ Critical: Keep this session open until you verify:
1. Test SSH access with: ssh -p $SSH_PORT $NEW_USER@$(hostname -I | awk '{print $1}')
2. Confirm you can log in via SSH key.
"