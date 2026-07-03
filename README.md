# Lingua Recall

> KDE Plasma 6 桌面单词复习部件 — FSRS-6 间隔重复

与 [Lingua Spanner](../lingua-spanner) 配合使用：Spanner 查词保存到 `linguaspanner.db`，Recall 读取做 FSRS-6 间隔重复复习。

## 架构

```
FsrsEngine  →  纯 C++ FSRS-6 算法（21参数，零 Qt 依赖）
ReviewDb    →  SQLite CRUD（三张表 + FsrsEngine 集成）
RecallHelper → QML_ELEMENT 胶水层
main.qml    →  复习面板（卡片 + 评级 + 新词 + 统计）
```

## 开发

```sh
make configure    # 首次：cmake 配置
make build        # 编译 C++ 模块并打包到 package
make check        # 运行 46 个 C++ 单元测试
make qml-check    # 运行 5 个 QML 集成测试
make test         # plasmawindowed 预览
make full         # build + install + restart（完整部署）
make launch       # 快速预览（不重启面板）
```

或使用 `./dev` 快捷脚本：

```sh
./dev build
./dev test
./dev full
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
```

## 依赖

| 依赖 | 用途 |
|------|------|
| Qt6 (Core, Gui, Qml, Sql, Test) | QML 运行时 + SQLite |
| KF6 (Plasma, I18n, Config, KCM, Kirigami) | Plasma 部件框架 |

## 许可

GNU General Public License v2.0 or later
