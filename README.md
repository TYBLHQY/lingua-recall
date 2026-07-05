# Lingua Recall

> KDE Plasma 6 桌面单词复习部件 — FSRS-6 间隔重复

与 [Lingua Spanner](../lingua-spanner) 配合使用：Spanner 查词保存到 `linguaspanner.db`，Recall 读取做 FSRS-6 间隔重复复习。

## 功能

- **FSRS-6 间隔重复**: 21 参数 FSRS-6 算法，纯 C++ 实现
- **合并卡片队列**: 新词与到期复习卡片在同一视图中无缝切换
- **揭卡评分**: 点击/空格揭晓答案，1-4 快速评分 (Again/Hard/Good/Easy)
- **AI 辅助内容**: 自动解析翻译结果中的单词分析、搭配、例句
- **键盘快捷键**: 全键盘操作 (Space 揭卡, 1-4 评分, A 朗读, Ctrl+P 固定面板)
- **文本朗读**: 内置 Edge-TTS 语音合成，按语言自动匹配音色
- **配置灵活**: 自定义字体、字号、目标记忆保留率、最大间隔天数

## 安装

```sh
make install
```

> 需要先安装依赖：Qt6 (Core, Gui, Qml, Sql) + KF6 (Plasma, I18n, Config, KCM, Kirigami)

## 键盘快捷键

| 按键 | 操作 |
|------|------|
| `Space` | 揭晓答案 |
| `1` | 评分 — Again |
| `2` | 评分 — Hard |
| `3` | 评分 — Good |
| `4` | 评分 — Easy |
| `A` | 朗读卡片文本 |
| `Ctrl+P` | 固定/取消固定面板 |

## 配置

- **系统设置** → 桌面部件 → Lingua Recall
- **FSRS 调度**（配置页内）：
  - Desired retention — 目标记忆保留率（80%–97%）
  - Max interval — 最大间隔天数（30–36500）
- **TTS 音色**（配置页内）：按语言选择语音

## 许可

GNU General Public License v2.0 or later
