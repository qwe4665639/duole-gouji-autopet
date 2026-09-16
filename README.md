# 多乐够级 · 宠物自动打工

给 **多乐够级**（`com.k7k7.goujihd`）用的宠物挂机辅助：自动进宠物家园、自动开工、自动领奖励，掉线能自己恢复。以 Android 无障碍服务运行，靠**截图 + 模板匹配**识别界面，用无障碍手势点击，**不需要 root**。

> **当前只支持「园艺师」这一个工种**（点打工面板上的 **「2开工」**）。
> 建筑工人（「1开工」）的旧模板仍保留在代码里但已不参与流程；画家、文案编辑是锁定状态，模板尚未制作。

---

## 适用环境

| 项目 | 要求 |
|---|---|
| 模拟器 | **MuMu 模拟器**（开发与实测环境：MuMu 12 的 Android 15 实例） |
| 分辨率 | **1600 × 900 横屏** |
| DPI | **240** |
| 系统 | Android 11 及以上（`minSdk 30`，`targetSdk 34`） |
| 游戏 | 多乐够级，需已登录（脚本不处理账号密码/微信密码） |
| 权限 | 无障碍服务 + 截屏能力；**无需 root** |

非 1600×900 的画面会被**缩放**到 1600×900 再识别，但模板是按 1600×900 / 240DPI 从真实截图裁的，**换分辨率或 DPI 需要重做模板**。

---

## 工作原理

```
无障碍服务截屏 ──> 缩放成 1600×900 ──> 9 个模板在各自的搜索区域内匹配
                                              │
                                    命中误差 < 容差(24/27) 就算认出该界面
                                              │
                              状态机决定动作 ──> 无障碍手势点击「模板中心」
```

- **匹配算法**：从模板里挑 alpha>200 的像素，用固定种子 `Random(1729)` 洗牌后取前 240 个采样点；逐像素位置算 RGB 平均绝对误差，超过容差即否，并在第 8/24/64 个采样点处提前否决以加速。
- **点击点 = 模板中心**，再按实际分辨率等比换算回去。
- 主循环**固定 2 秒一轮**。
- 悬浮球（屏上那个「工」字）**可点开、可拖动**：点开是控制面板（含 **暂停/开始运行**），拖动可换位置，位置会记住。灰色=暂停，绿色=运行。

### 状态机（`AutoFlow.java`，按优先级从上到下）

| 优先级 | 识别到 | 动作 |
|---|---|---|
| 1 | 掉线弹窗（`relogin`） | 点「重新登录」 |
| 2 | 签到面板（`signin_close`） | 点右上角 **X** 关掉 |
| 3 | 登录页 + 协议未勾选 | 勾选用户协议（**只勾一次**，有锁存） |
| 4 | 登录页 | 点「微信登录」 |
| 5 | 奖励气泡 + 宠物打工入口同现 | 领取一个奖励 |
| 6 | 打工倒计时（`clock`） | 什么都不点，**等倒计时结束** |
| 7 | 打工面板的「2开工」 | **第一次点选园艺师 → 第二次点确认弹窗**，共两次 |
| 8 | 宠物打工入口 | 点「宠物打工」打开面板 |
| 9 | 宠物家园入口 | 点「宠物家园」进入宠物页 |
| — | 45 秒没认出任何可操作画面 | **暂停**并提示"请检查游戏画面" |

进宠物页后的优先级就是你要的：**正在打工就等它结束 → 有奖励先领 → 都没有就直接开工**。

---

## 目录结构

```
duole-gouji-autopet/
├── app/                              Android 工程
│   ├── AndroidManifest.xml           minSdk 30 / targetSdk 34，声明无障碍服务
│   ├── assets/                       9 张识别模板（PNG）
│   ├── res/values/strings.xml
│   ├── res/values/styles.xml
│   ├── res/xml/accessibility_config.xml   含 canTakeScreenshot / flagRetrieveInteractiveWindows
│   └── src/com/dagong/autopet/
│       ├── PetAccessibilityService.java   主引擎：截屏/匹配/点击/悬浮球
│       ├── VisualMatcher.java             模板匹配算法
│       ├── AutoFlow.java                  状态机
│       └── MainActivity.java              控制面板
└── tools/
    ├── build.ps1                    手工编译签名（aapt2→javac→d8→zipalign→apksigner）
    ├── deploy.ps1                   卸载旧版 + 安装 + 注册无障碍服务
    ├── enable-a11y.ps1              真正让无障碍服务"绑上"的开关重激活
    ├── autopet-a11y-watch.ps1       宿主守护：开机重激活无障碍 + 掉线自愈
    ├── autopet-a11y-watch.vbs       静默启动守护（无黑窗口）
    └── verify-templates.ps1         离线识别诊断："这张截图脚本会看到什么"
```

仓库**不含**签名密钥，也不含原版 2.0 的 APK。

---

## 使用步骤

### 0. 直接装现成的包（可选）

不想自己编译，就去 [Releases](https://github.com/qwe4665639/duole-gouji-autopet/releases) 下载 `autopet-2.1.apk`。

> ⚠️ 发布的 APK 用**调试密钥**签名（`CN=Android Debug`），且签名与旧版不同，所以**必须先卸载已有版本**再装：
> `adb uninstall com.dagong.autopet` → `adb install -r autopet-2.1.apk`。
> 装完仍需要按下面第 3 步开启无障碍服务。

### 1. 自己编译

需要一个 Android SDK（`build-tools 34.0.0` + `platforms/android-34`）和 JDK 17，**不需要 Gradle、不需要联网**。

先生成一把签名密钥（只做一次，**不要提交到仓库**）：

```powershell
keytool -genkeypair -v -keystore keystore\debug.keystore -alias androiddebugkey `
        -storepass android -keypass android -keyalg RSA -keysize 2048 `
        -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
```

然后编译（路径按你的实际安装位置改）：

```powershell
powershell -ExecutionPolicy Bypass -File tools\build.ps1 `
    -AndroidSdk 'D:\Dev\android-sdk' -Jdk 'D:\Dev\jdk-17' -Keystore .\keystore\debug.keystore
```

产物在 `out\autopet.apk`。

> ⚠️ **仓库必须放在纯 ASCII 路径下。** `aapt2` 处理不了含中文的路径，会直接报
> `failed to open directory: 系统找不到指定的文件。 (2)`。这是本项目开发时实测踩到的坑：
> 同一个 `res` 目录，放在 ASCII 路径下编译成功，放在 `E:\...\测试\` 下就失败。
> 如果报这个错，先把仓库挪到例如 `C:\autopet-work\duole-gouji-autopet` 再编译。

### 2. 安装到虚拟机

```powershell
powershell -ExecutionPolicy Bypass -File tools\deploy.ps1
```

> ⚠️ 会**先卸载**已装版本。原版 APK 用的是别把密钥，签名不同无法覆盖升级，所以必须卸载重装——请自己留一份原包做回滚备份。

### 3. 开启无障碍服务

装完在 App 里点 **「1 · 开启无障碍服务」**，在系统列表里打开「宠物自动打工服务」。

**重要**：MuMu 这个 ROM 上经常出现"设置里显示已开启、实际没绑上"的假象（`dumpsys accessibility` 里 `Bound services: {}`，App 里 `instance` 为 null）。只写 `settings put secure` 是没用的，**必须进服务详情页把开关关一次再打开**。用脚本自动做：

```powershell
powershell -ExecutionPolicy Bypass -File tools\enable-a11y.ps1
```

### 4. 开始挂机

在 App 面板点 **「2 · 开始并返回游戏」**（会自动回到游戏前台），或点 **「只缩成悬浮球（暂不运行）」** 先不跑。

之后悬浮球在屏幕上，点开可 **暂停/继续**，拖动可换位置。

### 5. （推荐）挂上宿主守护脚本

`tools\autopet-a11y-watch.ps1` 每 30 秒检查一次，负责两件 App 自己做不到的事：

1. **无障碍自动重激活**——用 `/proc/sys/kernel/random/boot_id` 判断虚拟机是否换了新的一次开机，是就自动"关一次再开一次"。**同一开机周期只动作一次**，之后完全静默。从此不用再手动开权限。
2. **掉线自愈**——安卓不允许 App 杀别的 App，但宿主机可以。脚本盯着 App 的日志，一旦看到 `检测到登录界面` 或 `长时间未识别到可操作画面`，就执行你验证过的手动方案：

```
检测到卡住 → am force-stop 杀掉游戏 → 重新拉起 → 等 20 秒加载进大厅
          → 自动点「2 · 开始并返回游戏」重新武装脚本 → 脚本自己关签到框、进宠物家园
```

> **这个脚本必须保持 UTF-8 BOM**（文件头前三字节 `EF BB BF`）。用 `powershell.exe -File` 执行时，没有 BOM 会按 ANSI 解码，里面的中文匹配串会变成乱码，掉线检测就永远不触发。同理，它内部显式设置了 `[Console]::OutputEncoding`，否则 adb 输出的中文也会乱码。

静默启动（无黑窗口）：

```powershell
wscript.exe tools\autopet-a11y-watch.vbs
```

想开机自启：把 `autopet-a11y-watch.vbs` 的快捷方式丢进 `shell:startup`。日志在 `%LOCALAPPDATA%\autopet-watch.log`。

---

## 诊断：这张截图脚本会看到什么

改模板或排查"为什么不认"时，不用装到模拟器上试。`verify-templates.ps1` 是 App 匹配算法的离线复刻（连 `Random(1729)` 洗牌都一致），直接喂一张截图：

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify-templates.ps1 -Shot .\shots\pet.png
```

输出每张模板的命中/未命中、命中中心坐标、误差和容差，最后给出**状态机会执行的动作**。真实截图上的实测结果：

```
screenshot lobby.png  (1600x900 -> analysed at 1600x900)
  HIT   pet_home_entry.png     centre=(890,703)  err=0.00  (tol 24)  tpl 124x110
  miss  pet_work_entry.png     region=0,380,220,580  tol 24  tpl 126x112
  ...
next action: CLICK_PET_HOME (enter the pet home)
```

---

## 模板与识别参数

| 模板 | 文件 | 搜索区域 (x0,y0,x1,y1) | 容差 | 命中点 | 含义 |
|---|---|---|---|---|---|
| 掉线弹窗 | `relogin.png` | 300,500,1300,790 | 24 | 中心 | 「重新登录」按钮 |
| 签到面板 | `signin_close.png` | 1150,10,1500,180 | 24 | 中心 | 右上角 **X** |
| 微信登录 | `wechat_login.png` | 450,660,1180,800 | 24 | 中心 | 登录页中间那颗按钮 |
| 用户协议 | `agree_unchecked.png` | 250,760,950,870 | 24 | 中心 | 未勾选的复选框 |
| 宠物家园 | `pet_home_entry.png` | 740,600,1030,780 | 24 | (890,703) | 大厅次横排入口 |
| 宠物打工 | `pet_work_entry.png` | 0,380,220,580 | 24 | (77,481) | 宠物页左侧竖排入口 |
| 2开工 | `work2.png` | 380,380,1280,800 | 24 | (750,680) / (943,663) | 面板与确认弹窗两处 |
| 倒计时 | `clock.png` | 570,150,725,270 | 24 | 中心 | 打工中标志 |
| 可领取 | `claim.png` | 160,120,1550,700 | 27 | 中心 | 奖励气泡 |

### 想加一个新工种（例如画家）

1. 在对应界面截一张 1600×900 的图，裁出「N开工」按钮做成同名 PNG 放进 `app/assets/`；
2. 在 `PetAccessibilityService.analyze()` 里加一条 `VisualMatcher.find(...)`（搜索区域取按钮可能出现的位置，容差先用 24）；
3. 用 `tools\verify-templates.ps1` 验证它在该界面命中、在别的界面不命中；
4. 在 `AutoFlow.java` 里加对应动作分支。

---

## 已知限制

- **只支持园艺师**（「2开工」），其他工种未做模板。
- **强依赖 1600×900 / 240DPI 的界面布局**；换分辨率、DPI、游戏皮肤或大版本更新都可能要重做模板。
- 花卉/画家等**锁定工种点不了**；体力不足时脚本不会降级、也不会提示，只会认不出画面。
- 点击依赖**无障碍手势注入**，个别界面（实测：账号登录页）上注入可能不生效。
- 匹配是**纯像素**的，没有 OCR、没有节点树——这游戏是自绘引擎，无障碍节点只有 7 个、零文字，所以只能走图像。
- 微信处于登出状态时，脚本不可能替你输密码；这种情况靠宿主守护"杀进程重开"兜底。

## 常见问题

**Q：设置里显示"已开启"，但脚本不工作？**
A：就是上面那个"假开启"。跑 `tools\enable-a11y.ps1`，或让守护脚本在每次开机后自动做。

**Q：App 里一直显示"请先开启「宠物自动打工服务」"？**
A：MuMu 下 `MainActivity` 常常不会真正 resume，那行字是**开机时定格的陈旧文本**，可以直接无视——服务其实连着。直接点「2 · 开始并返回游戏」即可（按钮在点击那一刻才读服务实例）。

**Q：掉线后卡在登录页不动？**
A：确认宿主守护脚本在跑（日志里应该有 `helper is stuck ... -> full game restart`）。脚本必须带 UTF-8 BOM，否则中文匹配失灵。

**Q：编译时报 `failed to open directory: 系统找不到指定的文件`？**
A：仓库路径里有中文（或其他非 ASCII 字符），`aapt2` 处理不了。把仓库挪到纯 ASCII 路径再编译。

**Q：悬浮球点不开/拖不动？**
A：窗口 flags 里带了 `FLAG_NOT_TOUCHABLE`（`0x10`）就会这样——事件在送达前就被系统丢弃。当前代码用的是 `2024`（清掉不可触摸、补上 `FLAG_NOT_FOCUSABLE`），如果改过这块请确认这一点。

---

## 说明

- 本仓库的 Java 源码是从一个已编译 APK（`classes.dex`）**反编译重建**后改造而来，并做了大量修复与扩展（园艺师、签到面板、宠物家园导航、掉线处理、悬浮球可点可拖等）。
- 仅供个人学习与自动化研究使用。在游戏中使用自动化工具**可能违反游戏用户协议**，存在账号被处罚的风险，请自行判断并承担后果。作者不对任何账号损失负责。
- 未附带任何签名密钥，也没有原作者的任何授权声明。

## 许可

[MIT](LICENSE)。
