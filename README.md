# ArtI flow

<div align="center">
  <img src="docs/assets/logo.png" alt="ArtI flow logo" width="108" />

  <h3>一个面向中学学习场景的 AI 辅导 App（iOS / SwiftUI）</h3>
  <p>支持拍照搜题、LaTeX 公式渲染、语音追问、学习教练、题目归档与复习辅助。</p>

  <p>
    <img src="https://img.shields.io/badge/Platform-iOS-000000?logo=apple&logoColor=white" alt="iOS" />
    <img src="https://img.shields.io/badge/UI-SwiftUI-FA7343?logo=swift&logoColor=white" alt="SwiftUI" />
    <img src="https://img.shields.io/badge/iOS-16%2B-000000?logo=apple&logoColor=white" alt="iOS 16+" />
    <img src="https://img.shields.io/badge/Build-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white" alt="GitHub Actions" />
  </p>
</div>

> 本仓库为 **ArtI flow 的原生 iOS 移植**（Swift / SwiftUI），GitHub Action 自动构建并测试。

<details>
  <summary>📷 效果预览（来自原 Android 版本，iOS 界面与其一致）</summary>

  <div align="center">
    <img src="screenshots/qa-answer.jpg" width="200" /> &nbsp;
    <img src="screenshots/qa-followup.jpg" width="200" /> &nbsp;
    <img src="screenshots/coach-review.jpg" width="200" /> &nbsp;
    <img src="screenshots/anki-review.jpg" width="200" /> &nbsp;
    <img src="screenshots/user-center.jpg" width="200" />
  </div>
</details>

---

## ✨ 功能

- **拍照搜题**：从相册导入图片，调用 ARK 兼容接口识别并讲解题目。
- **Markdown + LaTeX**：`WKWebView` + 内置 HTML 模板 + KaTeX 渲染，自动检测与归一化行内/块级公式。
- **语音追问**：使用 iOS 原生 `Speech` 框架，把语音转写成学习追问。
- **滑动交互**：段落卡左滑自动讲解、右滑精细追问；时间层左滑进入追问。
- **学习教练**：每日摘要、训练轮次、知识点薄弱洞察、推荐题与快捷动作。
- **题目归档**：收藏题目，知识点标签归一化，错题导出。
- **Anki 测验**：卡片 SRS（间隔重复）、卡组聚合、按卡组复习。
- **会话持久化**：`study_suit_sessions_v1.json`，多会话切换，崩溃/重启可恢复。
- **多端点兼容**：ARK / 豆包官方端点与任意自定义兼容接口（自动选择 `chat/completions` 或 `responses`）。

## 🏗 技术栈

- **语言**：Swift 5
- **UI**：SwiftUI（iOS 16+），`@MainActor` 观察对象驱动状态
- **渲染**：`WKWebView` + KaTeX（CDN）
- **语音**：`SFSpeechRecognizer`（Speech 框架）
- **图片**：`PhotosPicker`
- **网络**：`URLSession`，SSE 流式解析
- **工程生成**：XcodeGen（`project.yml` → `ArtIflow.xcodeproj`）
- **CI**：GitHub Actions（macos-14，`xcodebuild` 构建 + 测试）

## 📁 目录结构

```text
ios/
├── project.yml                      # XcodeGen 工程描述
├── ArtIflow/
│   ├── App/                         # @main 入口
│   ├── Core/
│   │   ├── Models.swift             # 数据模型
│   │   ├── JSONSupport.swift        # org.json 风格的 opt 访问
│   │   ├── Helpers.swift            # 时间 / 文本工具
│   │   ├── Markdown/                # LaTeX 检测与归一化
│   │   ├── Knowledge/               # QuestionTagger / 知识点归一化
│   │   ├── State/                   # 状态机 / 会话编解码 / 教练 / 知识洞察
│   │   ├── Networking/              # ArkApiClient / FlowStudy / OpenSpeech / Mistake
│   │   ├── Persistence/             # SessionStore 文件持久化
│   │   └── Speech/                  # SpeechRecognizer
│   ├── UI/                          # SwiftUI 视图
│   └── Resources/                   # Info.plist / Assets / Markdown 模板
└── ArtIflowTests/                   # XCTest 单元测试
```

## 🔨 本地构建

需要 macOS + Xcode 15（建议 15.3+）。

```bash
cd ios
brew install xcodegen          # 一次性安装 XcodeGen
xcodegen generate              # 生成 ArtIflow.xcodeproj
open ArtIflow.xcodeproj        # 在 Xcode 中运行 / 测试
```

命令行构建与测试：

```bash
xcodebuild -project ios/ArtIflow.xcodeproj -scheme ArtIflow \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project ios/ArtIflow.xcodeproj -scheme ArtIflow \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  CODE_SIGNING_ALLOWED=NO test
```

## ⚙️ 配置

在应用内 **设置页** 直接配置（无需改代码 / 环境变量）：

- **ARK / 豆包**：`ARK_API_KEY`、`ARK_MODEL`、`ARK_BASE_URL`、`ARK_ENDPOINT`、系统提示词、图片提问提示词
- **自定义兼容接口**：Base URL / API Key / 模型名（三件套齐备时优先使用，并自动归到 `chat/completions`）
- **OpenSpeech**（可选）：API Key / Resource ID 等
- **FlowStudy**（可选）：服务器地址 / 设备 ID / Token

> 未配置 API Key 时仍可启动应用，发问时会提示「请先在设置中配置」。

## 🤖 GitHub Action 构建

仓库根目录的 `.github/workflows/build.yml` 会在 `push` / `pull_request` 时：

1. 在 `macos-14` runner 上选择 Xcode；
2. 安装并运行 `xcodegen` 生成工程；
3. `xcodebuild` 构建 iOS 模拟器版本（关闭签名）；
4. 运行 `ArtIflowTests` 单元测试。

构建产物与日志在失败时会作为 Artifact 上传。

---

## 📄 License

本项目仅供学习交流使用。
