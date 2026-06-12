# Sentry Self-Hosted — ESXi Autoinstall

Sentry self-hosted 部署在 VMware ESXi 虛擬機上，取代 `lg-laravel` MES 專案的 Laravel Telescope。  
透過 **Ubuntu Autoinstall + Seed ISO** 實現開機後全自動安裝，不需要手動進 VM 執行任何指令。

---

## 架構

```
ESXi Host (128 GB RAM / 16 core)
    └── Sentry VM (Ubuntu 24.04, 4 vCPU, 16 GB RAM)
            ├── /dev/sda  100 GB  → 系統碟
            ├── /dev/sdb  200 GB  → /data（Sentry 資料，獨立磁碟）
            ├── Nginx (80/443)  ← self-signed TLS
            │      └── proxy_pass → localhost:9000
            └── Docker Compose (Sentry self-hosted 26.x)
                   ├── web           :9000
                   ├── relay         :3000
                   ├── worker / cron
                   ├── postgres      → /data/sentry-postgres
                   ├── redis         → /data/sentry-redis
                   ├── kafka         → /data/sentry-kafka
                   └── clickhouse    → /data/sentry-clickhouse
```

---

## 事前準備

安裝 **Task**（唯一需要手動安裝的工具，其餘全部由 `task` 自動處理）：

```bash
sh -c "$(curl -ssL https://taskfile.dev/install.sh)" -- -d -b /tmp && sudo mv /tmp/task /usr/local/bin/task && task --version
```

---

## 快速開始

### Step 1 — 填入設定

```bash
cd autoinstall
vim .env   # 第一次執行 task 時會自動建立此檔案
```

需要填的欄位：

| 欄位 | 說明 |
|------|------|
| `SENTRY_DOMAIN` | Sentry 的 domain，例如 `sentry.example.com`（需指向這台 VM 的 IP） |
| `ADMIN_EMAIL` | Sentry 登入帳號 |
| `ADMIN_PASSWORD` | Sentry 登入密碼 |
| `SMTP_*` | 不需要 email 通知就全部留空 |

### Step 2 — 匯入 SSH Public Key

```bash
task generate-ssh-key
```

這個指令會把你本機的 `~/.ssh/id_ed25519.pub`（或 `id_rsa.pub`）複製到 `cert/`。之後 SSH 進 VM 不需要打任何密碼。

> 若還沒有 SSH key，請先執行 `ssh-keygen -t ed25519` 產生。

### Step 3 — 產出 seed.iso

```bash
# 在 /var/projects/sentry 目錄下執行
task seed-iso
```

這個指令會自動：
1. 讀取 `autoinstall/.env` 與 `cert/` 裡的 SSH public key
2. 產出 `autoinstall/user-data`
3. 打包成 `autoinstall/seed.iso`

### Step 4 — 下載 Ubuntu 24.04 Server ISO

前往官網下載 ISO（約 2.5 GB）：

```
https://ubuntu.com/download/server
```

選 **Ubuntu Server 24.04 LTS** → 下載 `ubuntu-24.04.4-live-server-amd64.iso`，**放到 repo 根目錄**：

```
sentry/
└── ubuntu-24.04.4-live-server-amd64.iso   ← 放這裡（已 gitignore，不會 commit）
```

> **Ubuntu ISO 只需要下載一次，之後建新 VM 可以重複使用。**  
> 只有 `seed.iso` 在修改設定後才需要重新產出。

### Step 4.5 — （選用）本機 QEMU 測試

不需要 ESXi，在本機用 QEMU 跑完整 autoinstall 流程驗證設定：

```bash
task test
```

這個指令會自動安裝 QEMU、建一顆暫時的虛擬磁碟，然後開機跑 Ubuntu autoinstall。  
確認安裝流程無誤後再上傳到 ESXi，省去反覆重建 VM 的時間。

---

### Step 5 — 上傳 ISO 到 ESXi Datastore

1. 瀏覽器開 `https://<ESXi IP>` 登入
2. 左側 **Storage** → 選你的 Datastore → 右上角 **Datastore Browser**
3. 點 **Upload**，分別上傳：
   - `ubuntu-24.04.4-live-server-amd64.iso`
   - `autoinstall/seed.iso`

---

### Step 6 — ESXi 建 VM

**Create / Register VM** → 填入以下規格：

| 項目 | 設定 |
|------|------|
| Name | `sentry` |
| OS | Ubuntu Linux (64-bit) |
| vCPU | 4 |
| RAM | 16 GB |
| 磁碟 1 | 100 GB（系統碟） |
| 磁碟 2 | 新增第二顆 200 GB（資料碟） |
| CD-ROM 1 | `ubuntu-24.04.4-live-server-amd64.iso` |
| CD-ROM 2 | 新增第二個 CD-ROM → `seed.iso` |
| 網路介面卡 | VMXNET3 |

---

### Step 7 — 開機與自動安裝

啟動 VM 後，整個過程**完全自動，不會出現任何需要你回答的提示**。

以下是開機後的自動流程：

```
開機
 └── Ubuntu installer 讀取 seed.iso 裡的 user-data
       └── 自動分割磁碟、安裝 Ubuntu（約 3~5 分鐘）
             └── 自動重開機
                   └── sentry-bootstrap 服務啟動
                         ├── 安裝 Docker
                         ├── 格式化 /dev/sdb → 掛載 /data
                         ├── clone sentry self-hosted
                         ├── 執行 install.sh（資料庫 migration 等）
                         ├── 設定 Nginx + self-signed TLS
                         └── 啟動 Sentry（約 15~20 分鐘）
```

> 如果看到 Ubuntu installer 的文字介面停在某個畫面，**不需要操作**，稍等幾秒它會自動繼續。

### Step 8 — 監控進度

```bash
ssh ubuntu@<VM_IP>
sudo journalctl -u sentry-bootstrap -f
```

看到以下訊息代表完成：

```
=== Bootstrap complete. Sentry X.X.X running at https://sentry.yourdomain.com ===
```

---

## 連接 Laravel

### 安裝 SDK

```bash
composer require sentry/sentry-laravel
```

### 取得 DSN

登入 Sentry → **Settings → Projects → \<project\> → Client Keys (DSN)**

1. 瀏覽器開 `https://sentry.yourdomain.com` 登入
2. 左上角 **Projects** → **Create Project** → 選 **PHP** → 建立
3. 建立後進入該 project → 左側選單 **Settings → Client Keys (DSN)**
4. 頁面上會顯示完整 DSN，格式如下，直接複製整串：

```
https://a1b2c3d4e5f6g7h8@sentry.yourdomain.com/2
        ────────────────                        ─
             key（公鑰）                    project ID
```

> **不需要手動拼接**，直接把複製到的整串貼進 `.env` 的 `SENTRY_LARAVEL_DSN` 即可。

### 加入 .env

```ini
SENTRY_LARAVEL_DSN=https://<key>@sentry.yourdomain.com/<project-id>
SENTRY_TRACES_SAMPLE_RATE=0.1
SENTRY_PROFILES_SAMPLE_RATE=0.1
SENTRY_SEND_DEFAULT_PII=false
```

### 移除 Telescope

```bash
composer remove laravel/telescope
php artisan migrate
```

移除 `TelescopeServiceProvider`（`bootstrap/providers.php` 或 `config/app.php`）。

---

## 目錄結構

```
sentry/
├── Taskfile.yml                     # task default / task seed-iso
├── README.md
├── CLAUDE.md
├── autoinstall/
│   ├── .env.example                 # 設定範本（commit）
│   ├── .env                         # 實際設定（gitignored）
│   ├── .gitignore
│   ├── user-data.tpl                # Ubuntu Autoinstall 模板
│   ├── meta-data                    # cloud-init 必要檔（固定不變）
│   ├── generate.sh                  # .env → user-data
│   └── build-seed-iso.sh            # generate.sh + 打包 seed.iso
├── config/
│   └── laravel-sentry.env.example   # Laravel .env 範例片段
└── scripts/
    └── bootstrap.sh.tpl             # 參考用（已內嵌至 user-data.tpl）
```

---

## 常見問題

**Q: VM 開機後停在 Ubuntu 安裝畫面，沒有自動跑？**  
A: 確認 CD-ROM 2 有掛 seed.iso，且 seed.iso 的 volume label 是 `cidata`。

**Q: bootstrap 跑到一半失敗？**  
A: 查看完整 log：`sudo cat /var/log/sentry-bootstrap.log`


**Q: 更新 Sentry 版本？**  
```bash
ssh ubuntu@<VM_IP>
cd /opt/sentry
git fetch --tags && git checkout <new-version>
docker compose pull
bash install.sh --skip-user-creation --no-user-prompt
systemctl restart sentry
```

---

## 防火牆（UFW）

Bootstrap 自動設定好以下規則，只允許內網（`192.168.0.0/24`）存取：

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.0.0/24 to any port 2222   # SSH
sudo ufw allow from 192.168.0.0/24 to any port 443    # HTTPS
sudo ufw --force enable
```

確認狀態：

```bash
sudo ufw status
```

正確輸出：

```
Status: active

To                         Action      From
--                         ------      ----
2222                       ALLOW       192.168.0.0/24
443                        ALLOW       192.168.0.0/24
```

---

## 建立新使用者並移除預設帳號

Ubuntu 安裝後預設帳號為 `ubuntu`。建議建立自訂帳號後將其刪除。

### Step 1 — SSH 登入 VM

```bash
ssh ubuntu@<VM_IP> -p <SSH_PORT>
```

### Step 2 — 建立新使用者

```bash
sudo useradd -m -s /bin/bash <NEW_USER>
```

- `-m`：自動建立家目錄 `/home/<NEW_USER>`
- `-s /bin/bash`：預設 shell 設為 bash

### Step 3 — 設定密碼

```bash
sudo passwd <NEW_USER>
```

輸入兩次新密碼即完成。

### Step 4 — 加入 sudo 群組

```bash
sudo usermod -aG sudo <NEW_USER>
```

確認新帳號有 sudo 權限：

```bash
sudo -u <NEW_USER> sudo -l
```

輸出包含 `(ALL : ALL) ALL` 代表設定成功。

### Step 5 — 複製 SSH 金鑰（若使用 key 登入）

```bash
sudo mkdir -p /home/<NEW_USER>/.ssh
sudo cp ~/.ssh/authorized_keys /home/<NEW_USER>/.ssh/authorized_keys
sudo chown -R <NEW_USER>:<NEW_USER> /home/<NEW_USER>/.ssh
sudo chmod 700 /home/<NEW_USER>/.ssh
sudo chmod 600 /home/<NEW_USER>/.ssh/authorized_keys
```

#### 確認 .ssh 權限

SSH 對權限非常嚴格，設錯會直接拒絕 key 登入，不會有任何提示。

用 `ls -ld` 檢查：

```bash
ls -ld /home/<NEW_USER>/.ssh
ls -l  /home/<NEW_USER>/.ssh/authorized_keys
```

正確輸出應長這樣：

```
drwx------ 2 <NEW_USER> <NEW_USER>  29 Jun 11 12:00 /home/<NEW_USER>/.ssh
-rw------- 1 <NEW_USER> <NEW_USER> 572 Jun 11 12:00 /home/<NEW_USER>/.ssh/authorized_keys
```

| 項目 | 正確權限 | chmod | 說明 |
|------|----------|-------|------|
| `.ssh/` 目錄 | `700` (`drwx------`) | `chmod 700 ~/.ssh` | 只有擁有者可讀寫進入，其他人完全不能碰 |
| `authorized_keys` | `600` (`-rw-------`) | `chmod 600 ~/.ssh/authorized_keys` | 只有擁有者可讀寫，其他人不能讀 |

權限開太大（例如 `755` 或 `644`）時，SSH daemon 會認為這個檔案不安全而拒絕使用，key 登入就會失效並 fallback 要求密碼。

若出問題，一次修正：

```bash
sudo chown -R <NEW_USER>:<NEW_USER> /home/<NEW_USER>/.ssh
sudo chmod 700 /home/<NEW_USER>/.ssh
sudo chmod 600 /home/<NEW_USER>/.ssh/authorized_keys
```

### Step 6 — 以新帳號重新登入並確認

開另一個終端機視窗，確認新帳號能正常登入且 sudo 可用，**不要關閉原來的 session**：

```bash
ssh <NEW_USER>@<VM_IP> -p <SSH_PORT>
whoami        # 應輸出 <NEW_USER>
sudo whoami   # 應輸出 root（確認 sudo 權限正常）
```

### Step 7 — 刪除原 ubuntu 帳號

**確認你現在是用新帳號的 SSH session 操作**（不是 ubuntu）。

由於安裝時設定了 tty1 autologin，ubuntu 會被自動登入到 tty1，必須先把 autologin 換成新帳號再重啟 getty，否則 `userdel` 會報錯：

```bash
# 把 tty1 autologin 換成新帳號（$USER 即當前登入帳號）
sudo sed -i "s/--autologin ubuntu/--autologin $USER/" \
  /etc/systemd/system/getty@tty1.service.d/autologin.conf

# 套用設定並重啟（ubuntu 的 tty1 session 會結束）
sudo systemctl daemon-reload
sudo systemctl restart getty@tty1

# 確認 ubuntu 已無 process（只剩 grep 那行才算乾淨）
ps aux | grep ubuntu

# 刪除帳號與家目錄
sudo userdel -r ubuntu
```

確認已刪除：

```bash
id ubuntu   # 應回傳 no such user
```
