# GoFilm

自托管影视站，包含 Web 前台、管理后台，以及用 Flutter 实现的 Android 手机 / Android TV 客户端，并提供局域网一键部署脚本。

> 本项目基于 [ProudMuBai/GoFilm](https://github.com/ProudMuBai/GoFilm)（MIT License）二次开发。在保留原有采集、后台管理和 Web 播放能力的基础上，新增了多端 API、Flutter 客户端、TV 扫码登录、多设备会话、签名媒体代理和局域网部署方案。

## 功能特性

- **Web 前台**：Vue 3 + Element Plus + xgplayer，支持 HLS 播放、分类浏览、搜索和播放列表。
- **管理后台**：`/manage` 登录后可管理采集站点、定时同步、影片分类、影片信息、图片同步和站点配置。
- **多端 API（v1）**：独立于旧版 Web API，提供注册 / 登录 / 刷新、设备会话、历史与收藏同步、首页 / 导航 / 详情 / 播放 / 搜索 / 分类等接口。
- **手机 + TV 客户端**：同一套 Flutter 代码，支持 `APP_TARGET=phone|tv`；包含登录注册、扫码登录、搜索、收藏、历史、播放进度同步，登录页可手动切换服务器地址（局域网 / 公网）。
- **TV 扫码登录**：TV 展示二维码，手机扫码后在 H5 页面确认，TV 自动登录。
- **签名媒体代理**：m3u8 / 图片 / 资源统一走签名 URL；上游域名白名单与内网地址拦截共同提供 SSRF 防护，并对 m3u8 地址做重写。
- **局域网部署**：Windows PowerShell / Linux systemd 脚本一键拉起 MySQL、Redis 与后端；数据库与 Redis 只绑定 `127.0.0.1`，密码随机生成。
- **采集与定时同步**：colly + cron，支持多站点资源采集与定时入库。

## 技术栈

| 层 | 技术 |
| --- | --- |
| 后端 | Go 1.25、Gin、GORM、go-redis、gocolly、robfig/cron、JWT |
| Web 前台 / 后台 | Vue 3、Vite、TypeScript、Element Plus、xgplayer |
| 移动端 | Flutter / Dart 3.5+、video_player、qr_flutter、mobile_scanner |
| 存储 | MySQL 8.4、Redis 7 |
| 部署 | Docker Compose、systemd、PowerShell |

## 仓库结构

```text
.
├─ server/                  Go 后端（旧版 Web API + /api/v1 多端 API）
├─ client/                  Vue 3 Web 前台与管理后台
├─ client_flutter/          Flutter Android 手机 / TV 客户端
├─ film/                    上游提供的 Docker 部署模板（可选）
├─ scripts/lan/             局域网部署脚本与 MySQL/Redis 编排文件
├─ docker-compose.local.yml 本地开发用 MySQL + Redis
└─ README.md
```

更多说明见 [server/README.md](server/README.md)、[client/README.md](client/README.md)、[film/README.md](film/README.md)。

## 快速开始（本地开发）

依赖：Go 1.25+、Node.js 20.19+（或 22+）、Flutter 3.24+（Dart 3.5+）、Docker。

1. 启动 MySQL 与 Redis（端口 3610 / 3620，密码 `root`，仅用于本地开发）：

```bash
docker compose -f docker-compose.local.yml up -d
```

2. 启动后端（需要在 `server/` 目录内运行，静态目录按相对路径创建）：

```bash
cd server
go run .
```

后端监听 `http://127.0.0.1:3601`，健康检查：`GET /api/v1/health`。启动时会等待 MySQL 约 20 秒；首次运行会建表并创建默认管理员 `admin / admin`。

3. 启动 Web 前台与管理后台：

```bash
cd client
npm install
npm run dev
```

访问 `http://127.0.0.1:3600`，管理后台为 `http://127.0.0.1:3600/manage`。开发服务器已把 `/api` 代理到后端 `3601`。

4. 运行 Flutter 客户端：

```bash
cd client_flutter
flutter pub get

# 模拟器（10.0.2.2 指向宿主机）
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3601

# 手机 APK
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.10:3601

# Android TV APK
flutter build apk --release --dart-define=APP_TARGET=tv --dart-define=API_BASE_URL=http://192.168.1.10:3601
```

登录页始终保留“手动填写服务器地址”入口，因此即使 APK 内置了默认地址，也可以在运行时切换。默认使用调试签名，正式分发前请配置自己的 Android 签名（`key.properties`、`*.jks` 已被忽略）。

## 局域网部署

适合在家里或小型局域网内长期运行。数据库与 Redis 由 Docker 托管且只绑定回环地址，唯一对局域网开放的端口是后端 `3601`。

Windows（Docker Desktop）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\lan\deploy-lan.ps1
powershell -ExecutionPolicy Bypass -File scripts\lan\deploy-lan.ps1 -LanIp 192.168.1.10 -InstallAutostart
powershell -ExecutionPolicy Bypass -File scripts\lan\deploy-lan.ps1 -Status
powershell -ExecutionPolicy Bypass -File scripts\lan\deploy-lan.ps1 -Stop
```

Linux（Docker + systemd）：

```bash
./scripts/lan/deploy-lan.sh --lan-ip 192.168.1.10
sudo ./scripts/lan/deploy-lan.sh --install-service   # 开机自启
./scripts/lan/deploy-lan.sh --status
./scripts/lan/deploy-lan.sh --stop
```

脚本会自动生成 `scripts/lan/.env`（随机数据库 / Redis / 代理密钥，已加入 `.gitignore`），并打印手机和 TV 应填写的服务器地址。脚本同时支持独立安装包布局：把预编译的二进制放在 `bin/` 下即可跳过本机 Go 编译。

- 局域网端口：`3601`（后端，唯一对外）
- 本机回环端口：`3611`（MySQL）、`3621`（Redis）
- 全新数据库会自动创建 `admin / admin`，请首次登录后立即修改密码
- 建议为服务器保留固定 DHCP 地址，IP 变化后重新执行部署脚本以更新扫码链接

## API 概览

所有 v1 接口以 `/api/v1` 为前缀，响应体统一为 `{ "code": 0, "data": ..., "msg": "ok" }`；需要登录的接口使用 `Authorization: Bearer <accessToken>`。

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/v1/health` | 健康检查 |
| GET | `/api/v1/config`、`/nav`、`/index` | 站点配置、导航、首页数据 |
| GET | `/api/v1/search`、`/classify`、`/classify/search` | 搜索与分类 |
| GET | `/api/v1/films/:mid`、`/films/:mid/play` | 影片详情与播放地址 |
| GET | `/api/v1/proxy/m3u8`、`/proxy/image`、`/proxy/resource` | 签名媒体代理 |
| POST | `/api/v1/auth/register`、`/login`、`/refresh` | 注册、登录、刷新令牌 |
| POST | `/api/v1/auth/logout`、`/logout-all` | 退出当前设备 / 全部设备 |
| GET | `/api/v1/auth/me`、`/auth/devices` | 当前用户与设备会话 |
| DELETE | `/api/v1/auth/devices/:deviceId` | 下线指定设备 |
| POST | `/api/v1/auth/qr/create` | TV 申请扫码登录 |
| GET | `/api/v1/auth/qr/info`、`/auth/qr/poll` | 二维码信息与轮询结果 |
| POST | `/api/v1/auth/qr/scan`、`/auth/qr/confirm` | 手机扫码 / 确认登录（需登录） |
| GET | `/qr` | 手机相机打开的扫码确认页 |
| GET / POST | `/api/v1/me/history`、`/me/favorites` | 历史 / 收藏同步 |

## 配置项

后端支持通过环境变量覆盖默认配置：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MYSQL_HOST` / `MYSQL_PORT` | `127.0.0.1` / `3610` | MySQL 地址 |
| `MYSQL_USER` / `MYSQL_PASSWORD` | `root` / `root` | 仅建议本地开发使用 |
| `MYSQL_DBNAME` | `FilmSite` | 数据库名 |
| `REDIS_HOST` / `REDIS_PORT` | `127.0.0.1` / `3620` | Redis 地址 |
| `REDIS_PASSWORD` | `root` | Redis 密码 |
| `GOFILM_PUBLIC_BASE_URL` | 空 | 对外访问地址，用于生成扫码链接与代理地址，例如 `http://192.168.1.10:3601` |
| `GOFILM_PROXY_ENABLED` | `true` | 是否启用媒体代理 |
| `GOFILM_PROXY_SECRET` | 空（由 JWT 密钥派生） | 媒体代理签名密钥 |
| `GOFILM_PROXY_ALLOWED_HOSTS` | 空 | 上游域名白名单，逗号分隔，支持 `*.example.com` |

## 安全说明

- 默认管理员为 `admin / admin`，首次登录后请立即修改密码。
- `docker-compose.local.yml` 中的 `root/root` 只适合本地开发；局域网或公网部署请使用 `scripts/lan` 生成随机密码，或自行通过环境变量配置。
- `server/config/SecurityConfig.go` 中的 RSA 密钥对继承自上游，仅适合开发环境。对外部署前请替换为自己的密钥（替换后已签发的 token 全部失效）。
- 媒体代理默认拒绝回环 / 内网 / 链路本地地址，并可通过白名单限定上游域名；请勿削弱 `server/plugin/mediaproxy` 中的校验，否则会引入 SSRF 风险。
- 不要把 `3601` 直接暴露到公网。外网观看建议使用 VPN（WireGuard / Tailscale），或在反向代理后启用 HTTPS 与访问控制。
- `.env`、Android 签名文件和本地日志均已忽略，请勿提交真实密钥。

## 与上游的关系

- 上游项目：[ProudMuBai/GoFilm](https://github.com/ProudMuBai/GoFilm)
- 本仓库在原项目基础上新增：`/api/v1` 多端 API、设备会话与扫码登录、Flutter 手机 / TV 客户端、历史收藏同步、签名媒体代理、Windows / Linux 局域网部署脚本，以及相关文档。
- 原有 Web 前台、管理后台、采集与定时同步逻辑保持兼容。

## 免责声明

本项目仅供学习与技术研究使用。影视数据来自公开网络采集，仓库不附带任何影视资源；请遵守所在地法律法规以及目标站点的服务条款，不要将本项目用于侵权或商业分发。

## License

[MIT](LICENSE)，原始版权归 ProudMuBai 所有，二次开发部分同样遵循 MIT License。
