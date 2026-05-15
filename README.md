# Sentry Self-Hosted — ESXi Autoinstall

Sentry self-hosted 部署在 VMware ESXi 虛擬機上，取代 `lg-laravel` MES 專案的 Laravel Telescope。  
透過 **Ubuntu Autoinstall + Seed ISO** 實現開機後全自動安裝，不需要手動進 VM 執行任何指令。

---

## 架構

```
ESXi Host (128 GB RAM / 16 core)
    └── Sentry VM (Ubuntu 22.04, 4 vCPU, 16 GB RAM)
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
| `UBUNTU_PASSWORD_HASH` | 先跑 `openssl passwd -6 'your-password'`，把輸出（含 `$6$...`）貼進來，整個值用單引號包住 |
| `SENTRY_DOMAIN` | Sentry 的 domain，例如 `sentry.example.com`（需指向這台 VM 的 IP） |
| `ADMIN_EMAIL` | Sentry 登入帳號 |
| `ADMIN_PASSWORD` | Sentry 登入密碼 |
| `SMTP_*` | 不需要 email 通知就全部留空 |

### Step 2 — 產出 seed.iso

```bash
# 在 /var/projects/sentry 目錄下執行
task
```

這個指令會自動：
1. 安裝缺少的工具（`python3`、`genisoimage`），已安裝則略過
2. 若 `.env` 不存在則建立並提示填寫，填好後再跑一次 `task`
3. 讀取 `.env` 產出 `autoinstall/user-data`
4. 打包成 `autoinstall/seed.iso`

### Step 3 — 上傳到 ESXi

將以下兩個檔案上傳到 ESXi Datastore（透過 ESXi Web UI → Storage → Datastore Browser）：
- `autoinstall/seed.iso`
- Ubuntu 22.04 Server ISO（從 [ubuntu.com/download/server](https://ubuntu.com/download/server) 下載）

### Step 4 — ESXi 建 VM

在 ESXi Web UI 建立新 VM，規格如下：

| 項目 | 設定 |
|------|------|
| OS | Ubuntu Linux (64-bit) |
| vCPU | 4 |
| RAM | 16 GB |
| 磁碟 1 | 100 GB（系統） |
| 磁碟 2 | 200 GB（資料） |
| CD-ROM 1 | Ubuntu 22.04 Server ISO |
| CD-ROM 2 | seed.iso |
| 網路 | VMXNET3（DHCP） |

### Step 5 — 開機

啟動 VM，Ubuntu 自動完成安裝並重開機，首次重開後 `sentry-bootstrap` 服務自動執行安裝（約 15～20 分鐘）。

### Step 6 — 監控進度

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
