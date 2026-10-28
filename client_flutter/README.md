# GoFilm Flutter 客户端

Android 手机与 Android TV 共用一套 Flutter 代码，接口全部走 `/api/v1`。

## 运行前准备

1. 启动后端（默认 `:3601`），确认手机/TV 与后端在同一局域网。
2. 安装 Flutter 3.27+（当前验证版本 3.47.8）与 Android SDK。
3. 在 `client_flutter` 目录执行：

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3601 --dart-define=APP_TARGET=phone
```

TV 使用：

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3601 --dart-define=APP_TARGET=tv
```

`APP_TARGET` 可省略：宽屏 Android 设备会自动使用 TV 布局，但焦点导航与设备标识建议显式指定。
`API_BASE_URL` 也可省略，首次启动后在登录页的“服务器地址”里填写并保存。

## 打包

```bash
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.10:3601 --dart-define=APP_TARGET=phone
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.10:3601 --dart-define=APP_TARGET=tv
```

TV 版 APK 与手机版是同一工程，差异只在启动入口布局；`AndroidManifest.xml` 已声明 Leanback 启动入口，
可直接被 Android TV 桌面识别。清单同时开启了 `usesCleartextTraffic` 以支持局域网 HTTP，
公网部署切到 HTTPS 后建议关闭。

产物位于 `build/app/outputs/flutter-apk/`。**当前 release 仍复用 debug 签名**，
仅供内测安装；正式分发前需在 `android/app/build.gradle.kts` 中配置自有 keystore 并移除
`signingConfig = signingConfigs.getByName("debug")`。

## 构建环境

已在以下环境验证：

| 组件 | 版本 |
| --- | --- |
| Flutter / Dart | 3.47.8 / 3.13.7 |
| JDK | 21 |
| Android SDK | 37.0.0（compileSdk/targetSdk 由 Flutter 决定） |
| NDK | 28.2.13676358 |
| CMake | 3.31.6 |
| Gradle Wrapper | 9.3.1（AGP 9.1.0，Kotlin 2.4.0） |

国内网络下 Gradle 依赖走本机 `~/.gradle/init.gradle` 里的阿里云与 `storage.flutter-io.cn` 镜像，
仓库内不包含镜像配置，换机后可按需自建。`android/gradle.properties` 已关闭 Kotlin 增量编译
（`kotlin.incremental=false`）：pub 缓存与工程不在同一磁盘时会触发
`different roots` 报错。

`local.properties` 中的 `sdk.dir`、`flutter.sdk` 因机器而异，不入库，请按本地路径生成。

## 已接入能力

- 用户名 + 密码注册/登录，access token 自动刷新
- 游客浏览（首页/分类/搜索/播放无需登录，记录与收藏需登录）
- TV 扫码登录（TV 展示二维码，手机 App 扫码或系统相机打开 H5 确认页）
- 首页、分类、搜索、详情、选集、播放（m3u8 走服务端签名代理）
- 播放进度自动上报、观看记录与收藏同步
- 多设备会话查看与下线、全部下线
- TV 遥控器方向键焦点导航，播放页支持选集与下一集

## 目录

```
lib/
  core/       配置、HTTP、会话、鉴权状态、主题
  models/     v1 接口模型
  services/   内容与同步接口
  screens/    页面（含 tabs/ 四个主 Tab）
  widgets/    海报卡片、分页网格、加载/错误/空态
android/      Android 工程（含 Leanback 声明）
```

## 与服务端联调

- 服务端需开启媒体代理：`GOFILM_PROXY_ENABLED=true`（默认开启）。
- 二维码里的地址默认取请求的 Host。若后端位于反向代理后，请设置 `GOFILM_PUBLIC_BASE_URL=https://your.domain`，
  否则电视上生成的二维码会指向内网地址。
- 媒体代理如需限制上游域名，设置 `GOFILM_PROXY_ALLOWED_HOSTS=example.com,*.cdn.com`。
