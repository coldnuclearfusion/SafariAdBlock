# SafariAdBlock

[English](README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · **中文（简体）**

一套 Safari 广告拦截扩展。采用 Safari 原生的**内容拦截器（Content Blocker）**机制，速度快，且不需要读取网页内容的权限。EasyList、EasyPrivacy 以及韩国列表（List-KR、YousList）会被转换为 Safari 规则。

| 扩展 | 来源 | 作用 |
|---|---|---|
| **广告拦截** | EasyList + `filters/custom.txt`（你自己的规则） | 拦截横幅、弹窗和广告脚本，隐藏广告位 |
| **跟踪拦截** | EasyPrivacy | 拦截分析与跟踪脚本和信标 |
| **韩国网站广告拦截** | List-KR（filterslist-KO）+ YousList | 针对 Naver、Daum 等韩国网站的规则 |
| **视频广告跳过** | `WebExtension/`（Safari 网页扩展） | 阻止片头和片中视频广告开始播放，立即跳过仍然出现的广告，并关闭广告拦截器警告 |

四个扩展可在 Safari 设置中分别开启或关闭。前三个是内容拦截器（仅 URL 和 CSS 规则，不在页面中运行代码）；第四个是在视频网站页面内运行脚本的网页扩展。容器应用（SafariAdBlock.app）负责显示各扩展的状态、打开 Safari 设置和重新加载规则。应用和扩展名称支持英语、韩语、日语和简体中文。

## 构建与安装

无需 Xcode，只用 Command Line Tools 即可构建（macOS 13 或更高版本；Apple Silicon 与 Intel 通用二进制）。

```bash
./install.sh     # 构建 → 安装到 /Applications/SafariAdBlock.app → 注册扩展 → 启动
```

只构建请运行 `./build.sh`（输出：`build/SafariAdBlock.app`）。首次构建会下载并转换过滤列表，因此需要网络（`rules/` 不包含在仓库中）。

安装后，在 **Safari › 设置 › 扩展**中开启 `广告拦截`、`跟踪拦截`、`韩国网站广告拦截` 和 `视频广告跳过`。应用中的**在 Safari 中设置**按钮可直接打开该界面。开启 `视频广告跳过` 后首次打开视频网站时，Safari 会询问是否允许访问该网站，请选择**始终允许**。

### 签名

`build.sh` 按以下顺序从钥匙串中选择签名证书：**Apple Development** → Developer ID →（若都没有）ad hoc。也可以通过环境变量 `CODESIGN_IDENTITY="..."` 明确指定。

- 使用 Apple 证书签名时，Safari 会立即识别扩展。免费的 Apple ID 即可：在 Xcode › Settings › Accounts 中添加 Apple ID，然后通过 **Manage Certificates › + › Apple Development** 创建一次证书。
- 使用 ad hoc 签名时，每次都需要在 Safari 中允许：开启 Safari › 设置 › 高级 › **显示网页开发者功能**，然后在**开发 › 开发者设置… › 允许未签名的扩展**。退出 Safari 后会重置。

#### 为什么 codesign 多次要求输入钥匙串密码

Apple Development 证书的私钥保存在登录钥匙串中，`codesign` 每次使用该私钥时 macOS 都会请求许可。一次构建要为 1 个应用和 4 个扩展签名，因此最多弹出五次。点一次**始终允许**之后就不会再问。若想在终端中处理（会询问登录钥匙串密码）：

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db
```

### 在另一台 Mac 上安装

```bash
git clone https://github.com/coldnuclearfusion/SafariAdBlock.git
cd SafariAdBlock && ./install.sh
```

首次构建会下载过滤列表。如果那台 Mac 没有 Apple Development 证书，将使用 ad hoc 签名，请参阅上面的签名部分。

## 语言

应用界面支持英语、韩语、日语和简体中文。默认跟随系统语言；应用右上角的**语言**菜单可立即切换并记住选择。其他语言会回退为英语。

Safari 自身设置中显示的扩展名称（以及 Finder 中的应用名称）来自各 bundle 的 `InfoPlist.strings` 和网页扩展的 `_locales`，因此始终跟随**系统**语言，而不是应用的语言菜单。

要添加或修改字符串，请编辑 `Resources/App/Localizations/<code>.json`（四个文件必须具有相同的键，`build.sh` 会检查）；网页扩展的名称和描述在 `WebExtension/_locales/<code>/messages.json` 中。

## 使用

- **只在某个网站关闭拦截**：打开该网站后选择 Safari 菜单 › **（网站）的设置…** › 取消勾选**启用内容拦截器**。Safari 会按网站记住。
- **切换语言**：应用右上角的语言菜单（跟随系统 / 한국어 / English / 日本語 / 中文）。
- **更新拦截列表**（EasyList 等每隔几天更新一次）：
  ```bash
  ./update-rules.sh && ./install.sh
  ```
- **添加自己的规则**：用 EasyList 语法写入 `filters/custom.txt`，然后运行 `SKIP_DOWNLOAD=1 ./update-rules.sh && ./install.sh`。文件开头有语法示例。
- **规则未生效**：点击应用中的**重新加载规则**。若仍无效，请在 Safari 中关闭再开启扩展。

## 故障排除

- **开启后广告仍然显示**：内容拦截器只对之后加载的页面生效。已打开的标签页请重新加载（⌘R）。对于在同一页面内切换视图的视频网站，关闭标签页再重新打开最可靠。
- **确认是否生效**：应用中的**检查是否生效**按钮会在 Safari 中打开公开测试网站（https://adblock-tester.com）。分数高说明规则已生效。（无法使用本地文件测试页，因为 Safari 不会对其应用按网站的内容拦截器设置。）
- **视频广告（片头和片中）无法被内容拦截器拦截。** 因此才有 `视频广告跳过` 网页扩展，它分两层工作：
  - `WebExtension/main.js`（主世界，Safari 16.4 或更高）：从播放器响应（`/youtubei/v1/player` 和页面内嵌的 `ytInitialPlayerResponse`）中删除广告条目，使广告根本不会开始。没有延迟。
  - `WebExtension/content.js`（隔离世界）：如果广告仍然出现（例如服务器端插入的广告），点击跳过按钮或跳转到广告结尾。这条路径要先加载广告再结束它，因此会残留 1 到 3 秒的延迟。
  - 网站更改响应结构或页面结构后可能暂时失效，届时需要调整键名和选择器。
- **为什么内容拦截器拦不住视频广告。** 广告与视频来自同一服务器、以同样的方式传输，是否为广告只在播放器响应内部决定，按 URL 过滤的内容拦截器无法区分。Safari 上的付费拦截器也是如此。首页、搜索和播放页面的广告卡片和横幅会被隐藏（`filters/custom.txt` 中的视频网站部分）。
- **Safari 个人资料（常见原因）**：标签栏左侧出现个人资料图标说明正在使用个人资料。扩展和内容拦截器按个人资料分别开启，设置 › 扩展中的开关只对默认（个人）个人资料生效。请在 Safari › 设置 › **个人资料** › 对应个人资料 › **扩展**标签页中开启。应用显示的“已开启”状态也指默认个人资料。
- **按网站的默认设置**：如果 Safari › 设置 › 网站 › 内容拦截器 › **访问其他网站时**为“关闭”，即使开启了扩展也不会在任何地方拦截。请保持“打开”。
- **无痕浏览窗口**：Safari 17 及更高版本需要单独允许扩展在无痕浏览中运行：Safari › 设置 › 扩展 › 各项目 › **在无痕浏览中允许**。
- **Safari 对重新加载规则没有响应**：`重新加载规则` 会在 20 秒后超时。在 macOS 26 上 Safari 有时不会调用完成回调，但规则其实已经重新获取（系统日志中可以看到扩展进程被启动）。
- **查看日志**：`/usr/bin/log show --last 10m --info --predicate 'subsystem == "com.jhunos.SafariAdBlock"'` 会显示 Safari 是否识别扩展以及每次重新加载的结果。（在 zsh 中 `log` 是内置命令，因此需要完整路径。）
- **扩展已开启但毫无反应（开发时）**：扩展二进制必须**链接 AppKit**。只链接 Foundation 时，扩展进程能启动，但请求永远到不了处理程序，Safari 会在两分钟后以 `SFErrorDomain Code=3`（loading interrupted）放弃。系统日志中会出现 `misconfigured plugin; external subsystem [NSSharingService_Subsystem] not present` 故障记录。`build.sh` 已经传入了 `-framework AppKit`。

## 工作原理

```
filters/sources/*.txt ─▶ tools/convert.py ─▶ rules/<ext>.json ─▶ <ext>.appex/blockerList.json ─▶ Safari
   (EasyList 语法)         (转换为 Safari 规则)     (由 tools/validate 用 WebKit 验证)
```

- `tools/convert.py` — 把 EasyList（ABP）语法转换为 Safari 规则（JSON）。支持 `||domain^`、锚点、通配符、`$third-party`、`$domain=`、资源类型、`@@` 例外以及 `##` 元素隐藏（按域名、全局和例外）；跳过 Safari 无法表达的内容（正则规则、`$redirect`/`$csp` 等扩展选项、uBO 专有伪类等）。规则顺序为拦截 → 元素隐藏 → 例外。
- `tools/validate` — 用与 Safari 相同的 WebKit 编译器验证结果。编译失败的规则通过二分查找定位并剔除。由于 WebKit 会静默丢弃无效的 CSS 选择器（连同合并在同一规则中的整组选择器），选择器会先用 `querySelector` 逐个预检。
- `tools/smoke-test` — 把转换后的广告规则应用到 WKWebView 中，检查广告脚本和图片确实被拦截、广告元素被隐藏（在 `update-rules.sh` 末尾自动运行）。
- Safari 每个内容拦截器最多允许 150,000 条规则，因此列表被拆分到三个扩展中。
- 三个内容拦截器共用同一份源码（`Sources/ContentBlocker`），只有规则文件不同。

## 目录结构

```
Sources/App/               容器应用（SwiftUI）：状态、打开 Safari 设置、重新加载规则、语言菜单
Sources/ContentBlocker/    内容拦截器入口（三个拦截器共用）
Sources/WebExtension/      视频广告跳过网页扩展的原生部分（最小实现）
WebExtension/              manifest.json、main.js（从响应中去除广告）、content.js（跳过）、content.css、_locales/（各语言的名称和描述）
Resources/                 Info.plist 文件、entitlements、应用图标、Localizations/<code>.json 字符串表
filters/custom.txt         你自己的规则（包含在广告拦截列表中）
filters/sources/           下载的源列表（由 update-rules.sh 填充）
rules/                     转换后的 Safari 规则（JSON）和元信息（构建时生成，不在仓库中）
tools/convert.py           转换器
tools/validate.swift       WebKit 验证器
tools/smoke-test.swift     把结果应用到 WKWebView 中验证真实拦截效果
tools/make-icon.swift      应用图标生成器
build.sh / install.sh / update-rules.sh
```

## 隐私

应用和扩展不发起网络请求，不收集或发送任何数据。过滤列表只在你自己运行 `update-rules.sh` 时才会下载。内容拦截器只是把规则列表交给 Safari，无法看到页面内容；`视频广告跳过` 只在 manifest 列出的视频网站上运行，并且只在那里起作用。全部代码都在本仓库中。

## 许可与免责声明

- 本仓库的代码采用 [MIT](LICENSE) 许可。
- 过滤列表不包含在仓库中，而是在构建时下载。各列表的许可：
  - [EasyList](https://easylist.to)、[EasyPrivacy](https://easylist.to) — GPLv3 / CC BY-SA 3.0（[许可](https://easylist.to/pages/licence.html)）
  - [List-KR](https://github.com/List-KR/List-KR)（AdGuard 分发的 filterslist-KO）— GPLv3
  - [YousList](https://github.com/yous/YousList) — CC BY-SA 4.0
- 跳过广告可能违反视频网站的服务条款。使用风险由你自行承担，本软件不提供任何担保。
