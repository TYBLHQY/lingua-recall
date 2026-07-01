# Lingua Recall

> KDE Plasma 6 桌面回忆辅助部件 — 框架占位

参照 [Lingua Spanner](../lingua-spanner) 的架构搭建，待填充业务逻辑。

## 开发

```sh
make configure    # 首次：cmake 配置
make build        # 编译 C++ 模块并打包到 package
make install      # kpackagetool6 -u + clear cache
make test         # plasmawindowed 预览
make restart      # 重启 plasmashell
make full         # build + install + restart（完整部署）
make qml          # install + restart（QML 快速迭代）
make status       # 查看当前状态
```

或使用 `./dev` 快捷脚本：
```sh
./dev build
./dev test
./dev full
```

## 依赖

| 依赖 | 用途 |
|------|------|
| Qt6 (Quick, Gui) | QML 运行时 + 基础 UI |
| KF6 (Plasma, I18n, Config, KCM) | Plasma 部件框架 |

## 许可

GNU General Public License v2.0 or later
