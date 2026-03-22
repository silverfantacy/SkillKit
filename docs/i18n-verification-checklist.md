# i18n Verification Checklist — zh-Hant ↔ en

驗證方式：在 macOS 系統設定中切換慣用語言（繁體中文 / English），重新啟動 app 或使用 `defaults write -g AppleLanguages '("zh-Hant")'` 後 re-launch。

## 切換語系指令

```bash
# 切換為繁體中文（模擬）
defaults write -g AppleLanguages '("zh-Hant")'
# 切換回英文
defaults write -g AppleLanguages '("en")'
# 重新啟動 app 以套用
```

---

## 1. 導覽 / Navigation

| 位置 | key | zh-Hant 預期 | en 預期 |
|------|-----|-------------|---------|
| 側邊欄標題 section | `nav.section.view` | 檢視 | View |
| 側邊欄來源 section | `nav.section.sources` | 來源篩選 | Source Filter |
| 側邊欄 Skills 項目 | `nav.skills` | 技能 | Skills |
| 側邊欄 Sources 項目 | `nav.sources` | 來源 | Sources |
| 全部來源篩選 | `nav.allSources` | 全部來源 | All Sources |
| Toolbar 重整按鈕 | `toolbar.refresh` | 重新整理 | Refresh |
| Toolbar 重整 tooltip | `toolbar.refresh.help` | 重新整理所有來源 | Refresh all sources |
| Toolbar 重整中 tooltip | `toolbar.refreshing.help` | 正在重新整理來源… | Refreshing sources… |

## 2. 技能列表 / Skill List

| 位置 | key | zh-Hant 預期 | en 預期 |
|------|-----|-------------|---------|
| 技能計數 | `skills.shown` | N 項 | N shown |
| 搜尋欄 placeholder | `skills.search.placeholder` | 搜尋技能… | Search skills… |
| 篩選：全部 | `skills.filter.all` | 全部 | All |
| 篩選：已啟用 | `skills.filter.enabled` | 已啟用 | Enabled |
| 篩選：已停用 | `skills.filter.disabled` | 已停用 | Disabled |
| 空狀態（無符合） | `skills.empty.noMatch` | 找不到符合「…」的技能 | No skills match "…" |
| 空狀態（無技能） | `skills.empty.noSkill` | 目前沒有技能。\n先新增來源開始。 | No skills found.\nAdd a source to get started. |
| 選取提示 | `skills.select` | 請先選擇技能 | Select a skill |
| 全部技能標題 | `skills.all.title` | 全部技能（N） | All Skills (N) |
| 清除來源篩選 | `skills.clearSource` | 清除來源 | Clear source |
| 窄版模式標籤 | `pipeline.compact` | 窄版 | Compact |
| 窄版模式 List tab | `pipeline.list` | 列表 | List |
| 窄版模式 Detail tab | `pipeline.detail` | 詳細 | Detail |

## 3. 技能詳細 / Skill Detail

| 位置 | key | zh-Hant 預期 | en 預期 |
|------|-----|-------------|---------|
| 詳細資訊標題 | `details.title` | 詳細資訊 | Details |
| 欄位：來源 | `details.source` | 來源 | Source |
| 欄位：類型 | `details.type` | 類型 | Type |
| 欄位：路徑 | `details.path` | 路徑 | Path |
| 欄位：索引時間 | `details.indexed` | 索引時間 | Indexed |
| 欄位：版本 | `details.version` | 版本 | Version |
| 狀態：已啟用 | `state.enabled` | 已啟用 | Enabled |
| 狀態：已停用 | `state.disabled` | 已停用 | Disabled |
| 操作標題 | `actions.title` | 操作 | Actions |
| 啟用按鈕 | `action.enable` | 啟用 | Enable |
| 停用按鈕 | `action.disable` | 停用 | Disable |
| 移除按鈕 | `action.remove` | 移除 | Remove |
| 移除確認訊息 | `action.remove.confirm` | 會從來源刪除… | The skill directory will be deleted… |
| 不支援提示 | `actions.unsupported` | 此來源類型不支援… | This source type does not support… |

## 4. 來源管理 / Sources View

| 位置 | key | zh-Hant 預期 | en 預期 |
|------|-----|-------------|---------|
| 頁面標題 | `sources.title` | 來源 | Sources |
| 來源計數 | `sources.count` / `.plural` | N 個來源 | N source / N sources |
| 失敗計數 badge | `sources.failed` | N 失敗 | N failed |
| 重試失敗按鈕 | `sources.toolbar.retry` | 重試失敗 | Retry Failed |
| 新增來源按鈕 | `sources.toolbar.add` | 新增來源 | Add Source |
| 重整 banner | `sources.banner.refreshing` | 正在重新整理來源… | Refreshing sources… |
| 關閉 banner | `sources.banner.dismiss` | 關閉 | Dismiss |
| 載入中狀態 | `sources.loading` | 正在載入來源… | Loading sources… |
| 空狀態標題 | `sources.empty.title` | 尚未新增來源 | No sources added |
| 空狀態說明 | `sources.empty.subtitle` | 新增來源以開始管理技能。 | Add a source to start managing your skills. |
| 空狀態按鈕 | `sources.empty.add` | 新增來源 | Add Source |
| 移除確認 dialog | `sources.remove.title` | 移除來源？ | Remove source? |
| 移除確認按鈕 | `sources.remove.confirm` | 移除來源 | Remove Source |
| 移除說明訊息 | `sources.remove.message` | 來自「…」的所有技能將從索引中移除… | All skills from … will be removed… |
| 尚未掃描 | `sources.scan.notScanned` | 尚未掃描 | Not scanned |
| 部分失敗 | `sources.scan.partial` | 部分失敗 | Partial failure |
| 重試掃描 tooltip | `sources.scan.retry.help` | 重試掃描 | Retry scan |
| 移除來源 tooltip | `sources.scan.remove.help` | 移除來源 | Remove source |
| 技能數量（列表列） | `sources.skills.count` / `.plural` | N 個技能 | N skill / N skills |

### 新增來源 Sheet

| 位置 | key | zh-Hant 預期 | en 預期 |
|------|-----|-------------|---------|
| Sheet 標題 | `addsource.title` | 新增來源 | Add Source |
| 類型欄位 | `addsource.type` | 類型 | Type |
| 名稱欄位 | `addsource.name` | 顯示名稱 | Display Name |
| 路徑欄位 | `addsource.path` | 路徑 | Path |
| 瀏覽按鈕 | `addsource.browse` | 選擇… | Browse… |
| 新增按鈕 | `addsource.add` | 新增 | Add |
| 取消按鈕 | `common.cancel` | 取消 | Cancel |

## 5. Pipeline 狀態 / Pipeline Status

| 位置 | key | zh-Hant 預期 | en 預期 |
|------|-----|-------------|---------|
| 重整開始 | `pipeline.refresh.start` | 正在重新整理來源目錄… | Refreshing source inventory… |
| 安全掃描 | `pipeline.refresh.security` | 正在更新安全掃描結果… | Refreshing security findings… |
| 同步計畫 | `pipeline.sync.plan` | 正在計算同步計畫… | Computing sync plan… |
| 套用同步 | `pipeline.sync.apply` | 正在套用同步計畫… | Applying sync plan… |
| 重試掃描 | `pipeline.scan.retry` | 正在重試「…」的來源掃描… | Retrying source scan for …… |

## 6. 設定 / Settings

| 位置 | key | zh-Hant 預期 | en 預期 |
|------|-----|-------------|---------|
| 一般 tab | `settings.general` | 一般 | General |
| 無設定提示 | `settings.noSettings` | 目前沒有可設定的選項。 | No configurable settings yet. |

## 7. 警示狀態 / Alert States

| 位置 | key | zh-Hant 預期 | en 預期 |
|------|-----|-------------|---------|
| 重試成功 | `action.retry.success` | 已成功重試「…」 | Retry succeeded for … |
| 重試失敗 | `action.retry.failed` | 重試失敗：… | Retry failed: … |
| 無失敗來源 | `action.retry.noFailed` | 沒有需要重試的失敗來源 | No failed sources to retry |
| 已重試 N 個 | `action.retry.count` / `.plural` | 已重試 N 個來源 | Retried N source / Retried N sources |

---

## 驗收標準

- [ ] 切換語系後 app 重啟，所有表格中的文字正確顯示對應語系
- [ ] 所有 `%@`/`%d` 格式字串正確代入動態值
- [ ] 沒有任何硬碼英文字串在 zh-Hant 模式下顯示
- [ ] Pipeline overlay 訊息在操作中即時顯示正確語系文字
- [ ] SourcesView banner 訊息正確顯示並可關閉
