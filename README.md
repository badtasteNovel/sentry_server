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
            ├── Nginx (80/443)  ← TLS via Let's Encrypt
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
                         ├── 設定 Nginx + Let's Encrypt TLS
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

**Q: Let's Encrypt 憑證申請失敗？**  
A: 確認 `SENTRY_DOMAIN` 的 DNS A record 已指向這台 VM 的 IP，且 port 80 對外開放。

**Q: 更新 Sentry 版本？**  
```bash
ssh ubuntu@<VM_IP>
cd /opt/sentry
git fetch --tags && git checkout <new-version>
docker compose pull
bash install.sh --skip-user-creation --no-user-prompt
systemctl restart sentry
```
