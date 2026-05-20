#!/usr/bin/env bash
DONE_FLAG=/var/log/first-boot-user-setup.done
[ -f "$DONE_FLAG" ] && exit 0

clear
echo "============================================="
echo "     Sentry Server - 首次使用者設定"
echo "============================================="
echo ""
echo "請建立你的管理員帳號（將取代預設 ubuntu 帳號）"
echo ""

while true; do
  read -p "使用者名稱: " NEW_USER
  [[ -n "$NEW_USER" ]] && break
  echo "使用者名稱不能為空"
done

while true; do
  read -s -p "密碼: " NEW_PASS; echo
  read -s -p "確認密碼: " NEW_PASS2; echo
  [[ "$NEW_PASS" == "$NEW_PASS2" && -n "$NEW_PASS" ]] && break
  echo "密碼不一致或為空，請重試"
done

sudo useradd -m -s /bin/bash "$NEW_USER"
echo "$NEW_USER:$NEW_PASS" | sudo chpasswd
sudo usermod -aG sudo,docker "$NEW_USER"

# 把整個 .ssh 移給新使用者
sudo cp -r /home/ubuntu/.ssh "/home/$NEW_USER/.ssh"
sudo chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
sudo chmod 700 "/home/$NEW_USER/.ssh"
sudo chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"

# 撤銷 ubuntu 的 SSH 登入權限
sudo rm -f /home/ubuntu/.ssh/authorized_keys

# 鎖定 ubuntu 帳號
sudo passwd -l ubuntu

sudo touch "$DONE_FLAG"

PORT=$(grep '^SSH_PORT=' /etc/sentry-install.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
IP=$(hostname -I | awk '{print $1}')

echo ""
echo "帳號 $NEW_USER 建立完成，ubuntu 已鎖定。"
echo ""
echo "SSH 連線方式："
echo "  ssh -i ~/.ssh/sentry_server_key -p ${PORT:-22} $NEW_USER@$IP"
echo ""
echo "確認 SSH 可登入後，執行以下指令清除 ubuntu 帳號："
echo "  sudo deluser --remove-home ubuntu"
echo "  sudo rm /etc/sudoers.d/99-ubuntu-nopasswd"
