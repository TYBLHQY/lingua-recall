# Lingua Recall

> KDE Plasma 6 桌面单词复习部件 — FSRS-6 间隔重复

与 [Lingua Spanner](../lingua-spanner) 配合使用：Spanner 查词保存到 `linguaspanner.db`，Recall 读取做 FSRS-6 间隔重复复习。

## 功能

- **FSRS-6 间隔重复**: 21 参数 FSRS-6 算法，纯 C++ 实现，零 Qt 依赖
- **合并卡片队列**: 新词与到期复习卡片在同一视图中无缝切换
- **揭卡评分**: 点击/空格揭晓答案，1-4 快速评分 (Again/Hard/Good/Easy)
- **AI 辅助内容**: 自动解析翻译结果中的单词分析、搭配、例句
- **键盘快捷键**: 全键盘操作 (Space 揭卡, 1-4 评分, Ctrl+P 固定面板)
- **配置灵活**: 自定义字体、字号、目标记忆保留率、最大间隔天数
- **数据持久化**: 与 Lingua Spanner 共享 `linguaspanner.db`，SQLite 存储

## 架构

```
FsrsEngine  →  纯 C++ FSRS-6 算法（21参数，零 Qt 依赖）
ReviewDb    →  SQLite CRUD（三张表：review_cards, review_log, fsrs_params）
RecallHelper → QML_ELEMENT 胶水层
main.qml    →  单面板复习界面（合并队列：新词先出，到期卡后出）
```

关键集成点：`ReviewDb::reviewCard()` 加载卡片状态 → 调用 `FsrsEngine::review()` → 更新卡片 + 写入日志 → 返回 JSON。

## 安装

```sh
# 构建并安装
make build        # 编译 C++ 模块并打包到 package
make install      # kpackagetool6 安装/更新

# 或一键部署
make full         # build + install + restart
```

## 开发

```sh
# 便捷脚本
./dev status          # 查看状态
./dev build | full | qml | install | test | restart

# 首次：cmake 配置
make configure

# 编译 C++ 模块
make build

# 快速迭代（QML 改动）
make qml          # install + restart

# 完整部署
make full         # build + install + restart

# 测试预览
make test         # install + plasmawindowed
make launch       # plasmawindowed（不安装）

# 查看状态
make status

# 清理
make clean
```

## 测试

```sh
# 全部 46 个 C++ 测试
make check

# 单独运行
./build/tst_FsrsEngine        # 23 算法测试
./build/tst_ReviewDb          # 23 数据库测试
./build/tst_ReviewDb "test_createCard_success"  # 单个用例

# QML 测试
make qml-check

# 调试日志
journalctl -f -o cat | grep -E "RecallHelper|ReviewDb|qml:"
```

## 快捷键

| 按键 | 操作 |
|------|------|
| `Space` | 揭晓答案 |
| `1` | 评分 — Again |
| `2` | 评分 — Hard |
| `3` | 评分 — Good |
| `4` | 评分 — Easy |
| `Ctrl+P` | 固定/取消固定面板 |

## 配置

**KConfig XT**（通过等离子体部件设置）：
- `fontSizeBase` — 基础字号，单位 px（默认 14）
- `fontFamily` — 字体设置（留空使用系统默认字体）

**FSRS 调度设置**（在配置页面中）：
- Desired retention — 目标记忆保留率（80%–97%）
- Max interval — 最大间隔天数（30–36500）

## 依赖

| 依赖 | 用途 |
|------|------|
| Qt6 (Core, Gui, Qml, Sql, Test) | QML 运行时 + SQLite |
| KF6 (Plasma, I18n, Config, KCM, Kirigami) | Plasma 部件框架 |

## 许可

GNU General Public License v2.0 or later
