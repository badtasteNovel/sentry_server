#!/usr/bin/env bash
DONE_FLAG=/var/log/first-boot-user-setup.done
[ -f "$DONE_FLAG" ] && exit 0

clear
echo "============================================="
echo "     Sentry Server - First-boot user setup"
echo "============================================="
echo ""
echo "Create your admin account (replaces the default ubuntu account)"
echo ""

while true; do
  read -p "Username: " NEW_USER
  [[ -n "$NEW_USER" ]] && break
  echo "Username cannot be empty"
done

while true; do
  read -s -p "Password: " NEW_PASS; echo
  read -s -p "Confirm password: " NEW_PASS2; echo
  [[ "$NEW_PASS" == "$NEW_PASS2" && -n "$NEW_PASS" ]] && break
  echo "Passwords do not match or are empty, please try again"
done

sudo useradd -m -s /bin/bash "$NEW_USER"
echo "$NEW_USER:$NEW_PASS" | sudo chpasswd
sudo usermod -aG sudo,docker "$NEW_USER"

sudo cp -r /home/ubuntu/.ssh "/home/$NEW_USER/.ssh"
sudo chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
sudo chmod 700 "/home/$NEW_USER/.ssh"
sudo chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"

sudo rm -f /home/ubuntu/.ssh/authorized_keys
sudo passwd -l ubuntu

sudo touch "$DONE_FLAG"

PORT=$(grep '^SSH_PORT=' /etc/sentry-install.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
IP=$(hostname -I | awk '{print $1}')

echo ""
echo "Account $NEW_USER created, ubuntu locked."
echo ""
echo "SSH connection:"
echo "  ssh -i ~/.ssh/sentry_server_key -p ${PORT:-22} $NEW_USER@$IP"
echo ""
echo "After confirming SSH works, remove the ubuntu account:"
echo "  sudo deluser --remove-home ubuntu"
echo "  sudo rm /etc/sudoers.d/99-ubuntu-nopasswd"
