# CLAUDE.md — Sentry Self-Hosted (ESXi Autoinstall)

Ubuntu Autoinstall + Seed ISO 方式，在 VMware ESXi 上自動部署 Sentry self-hosted，取代 `lg-laravel` MES 專案的 Laravel Telescope。

---

## 這個 repo 做什麼

- 透過 **Seed ISO（cidata）** 讓 Ubuntu 24.04 Server 全自動安裝，不需要人工互動。
- 首次重開機後，`sentry-bootstrap` systemd service 自動安裝 Docker、Sentry self-hosted、Nginx、Let's Encrypt TLS。
- 所有持久資料（Postgres、Redis、Kafka、ClickHouse）存在第二顆磁碟 `/dev/sdb`，掛載為 `/data`，VM 重建不會遺失資料。

---

## 目錄結構

```
Taskfile.yml                       # 唯一入口：task → 裝依賴 + 產 seed.iso
autoinstall/
  .env.example                     # 設定範本（commit）
  .env                             # 實際設定（gitignored）
  user-data.tpl                    # Autoinstall 模板，placeholder 用 __VAR__ 格式
  meta-data                        # cloud-init 必要檔，固定不變
  generate.sh                      # set -a; source .env → envsubst → user-data
  build-seed-iso.sh                # generate.sh + genisoimage → seed.iso
config/
  laravel-sentry.env.example       # 貼到 lg-laravel .env 的範例片段
scripts/
  bootstrap.sh.tpl                 # 參考用原稿，實際內嵌在 user-data.tpl
```

> `.tf` 檔（modules/、environments/ 等）是早期 AWS OpenTofu 版本的殘留，目前未使用。

---

## 常用指令

```bash
# 產出 seed.iso（第一次會裝 python3 + genisoimage）
task

# 只初始化 .env（從 .env.example 複製）
task init

# 只產 seed.iso（已裝好依賴、.env 已填）
task seed-iso
```

```bash
# 在 VM 上監控 bootstrap 進度
sudo journalctl -u sentry-bootstrap -f
sudo cat /var/log/sentry-bootstrap.log
```

```bash
# 升級 Sentry 版本（SSH 進 VM 後執行）
cd /opt/sentry
git fetch --tags && git checkout <new-version>
docker compose pull
bash install.sh --skip-user-creation --no-user-prompt
systemctl restart sentry
```

---

## 設計決策

- **ESXi VM 不用 K8s** — Sentry self-hosted 官方只支援 docker-compose，裝進既有 K8s 需要大量客製化。
- **Seed ISO 不改 Ubuntu ISO 本體** — Ubuntu ISO 只上傳一次重複使用，seed.iso 只有 ~400KB，改設定重新產出即可。
- **`__VAR__` 替換格式** — 用 Python `str.replace()` 而非 `envsubst`，避免 user-data.tpl 內嵌的 bash 變數（`$DOMAIN` 等）被誤替換。
- **`set -a` in generate.sh** — `source .env` 不會自動 export，加 `set -a` 才能讓 Python subprocess 透過 `os.environ` 讀到變數。
- **errors-only compose profile** — 需要 16 GB RAM。`feature-complete` 需 32 GB，增加 replays、profiling、metrics，目前 MES 用不到。

---

## 連接 lg-laravel

```bash
composer require sentry/sentry-laravel
composer remove laravel/telescope
```

DSN 從 Sentry UI → Settings → Projects → Client Keys 取得，加入 `lg-laravel/.env`：

```ini
SENTRY_LARAVEL_DSN=https://<key>@sentry.yourdomain.com/<project-id>
SENTRY_TRACES_SAMPLE_RATE=0.1
SENTRY_SEND_DEFAULT_PII=false
```

---

## 下一步：OpenTelemetry 橋接

Sentry 支援透過 **OpenTelemetry（OTel）** 接收 traces，可以讓 lg-laravel 統一用 OTel SDK 送資料，而不直接依賴 Sentry SDK。

待辦：
- 在 Sentry self-hosted 啟用 OTel ingest（`OTEL_` 相關設定）
- lg-laravel 安裝 `open-telemetry/opentelemetry-php` + Sentry exporter
- 設定 OTLP exporter 指向 `https://sentry.yourdomain.com/api/<project>/envelope/`
- 確認 Temporal workflow traces 能正確送進 Sentry
