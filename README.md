# SkillKit

專為 macOS 打造的原生 AI 技能管理工具，支援 Claude Code、OpenClaw 與自訂專案資料夾。

![SkillKit 截圖](docs/screenshot.png)

## 功能

- **統一管理** — 瀏覽並管理來自多個來源的技能
- **標籤系統** — 為技能加上標籤，快速篩選
- **情境切換** — 將技能分組成不同情境，一鍵切換
- **Git 備份** — 一鍵將技能來源備份到 git 遠端
- **更新追蹤** — 自動偵測有 git 來源的技能是否有新版本
- **安全掃描** — 掃描技能檔案是否有潛在安全疑慮
- **多語系** — 支援繁體中文與英文介面

## 支援來源

- Claude Code（`~/.claude/skills`）
- OpenClaw（`~/.openclaw/skills`）
- 任意本地專案資料夾

## 系統需求

- macOS 14+
- Xcode 15+（從原始碼建置）

## 安裝注意事項

由於 SkillKit 尚未通過 Apple 公證，首次開啟時 macOS 會顯示安全警告。

**方法一：右鍵開啟**

1. 在 Finder 找到 `SkillKit.app`
2. 按住 Control 再點一下（或右鍵）→ 選「開啟」
3. 在跳出的對話框點「開啟」

**方法二：終端機指令**

```bash
xattr -cr /path/to/SkillKit.app
```

之後就能正常雙擊開啟。

## 建置方式

```bash
git clone https://github.com/silverfantacy/SkillKit.git
cd SkillKit
swift build -c release
```

或使用建置腳本產生 `.app`：

```bash
./scripts/build_app.sh
```

## 授權

MIT
