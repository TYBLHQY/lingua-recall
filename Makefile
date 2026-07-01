# ── Lingua Recall Makefile ─────────────────────────────────
# Usage:
#   make             → build → install → restart (full deploy)
#   make qml         → install → restart (QML-only, no C++ rebuild)
#   make test        → plasmawindowed quick preview
#   make build       → compile C++ → stage .so to package/
#   make install     → kpackagetool6 update + clear cache
#   make restart     → restart plasmashell (for panel widget)
#   make configure   → cmake configure (needed once after clone)
#   make clean       → remove build directory
#   make status      → show git log + plasmoid status + module files

SHELL := /usr/bin/env bash
PROJ  := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
JOBS  := $(shell nproc 2>/dev/null || echo 2)

PLUGIN_DST := $(PROJ)/package/contents/lib/LinguaRecallHelper
PLUGIN_OUT := $(HOME)/.local/lib/qml/LinguaRecallHelper
CACHE_DIR  := $(HOME)/.cache/libqmlcache
PLASMOID_ID := org.kde.lingua-recall

# ── Default: full deploy (for panel testing) ─────────────────
.PHONY: default
default: full

# ── Full deploy: build C++ → install → restart ────────────
.PHONY: full
full: build install restart
	@echo ""
	@echo "✅ 部署完成。在面板上测试 Lingua Recall。"

# ── Quick QML-only: install QML changes → restart ─────────
.PHONY: qml
qml: install restart
	@echo ""
	@echo "✅ QML 更新完成。"

# ── Build C++ helper + stage .so to package ───────────────
.PHONY: build
build:
	@echo "==> [1/3] 编译 C++ 模块…"
	cmake --build $(PROJ)/build -j$(JOBS) 2>&1 | tail -2
	@echo "==> [2/3] 拷贝 .so 到包装…"
	mkdir -p $(PLUGIN_DST)
	cp -a $(PROJ)/build/liblingua_recall_helper.so $(PLUGIN_DST)/
	cp -a $(PLUGIN_OUT)/lingua_recall_helperplugin.so $(PLUGIN_DST)/
	ln -sf lingua_recall_helperplugin.so $(PLUGIN_DST)/liblingua_recall_helperplugin.so
	@echo "==> [3/3] 完成。"

# ── Update plasmoid package + clear cache ─────────────────
.PHONY: install
install:
	@echo "==> [1/2] 更新 Plasma 包…"
	kpackagetool6 -t Plasma/Applet -u $(PROJ)/package/ 2>&1 | grep -E "Upgrading|Success|Error|Failed" || echo "     (已是最新)"
	@echo "==> [2/2] 清除 QML 缓存…"
	rm -rf $(CACHE_DIR)
	@echo "     完成。"

# ── Restart Plasma shell ─────────────────────────────────
.PHONY: restart
restart:
	@echo "==> 重启 plasmashell…"
	@if pidof plasmashell >/dev/null 2>&1; then \
		kquitapp6 plasmashell 2>/dev/null; \
		sleep 2; \
	fi
	@nohup plasmashell --replace > /dev/null 2>&1 &
	@sleep 2
	@echo "     完成。"

# ── Quick test with plasmawindowed (不会重启面板) ──────────
.PHONY: test
test: install
	@echo "==> 启动 plasmawindowed…"
	@echo "     关闭后继续。"
	plasmawindowed $(PLASMOID_ID)

# ── CMake configure (只需第一次) ──────────────────────────
.PHONY: configure
configure:
	@echo "==> 配置 CMake 构建…"
	mkdir -p $(PROJ)/build
	cd $(PROJ)/build && cmake .. -DCMAKE_INSTALL_PREFIX=$$HOME/.local 2>&1 | tail -2
	@echo "     完成。运行 'make build' 编译。"

# ── 清理 ─────────────────────────────────────────────────
.PHONY: clean
clean:
	@echo "==> 删除构建目录…"
	rm -rf $(PROJ)/build
	@echo "     完成。"

# ── 状态检查 ─────────────────────────────────────────────
.PHONY: status
status:
	@echo "=== Git ==="
	@git -C $(PROJ) log --oneline -3 2>/dev/null || echo "  (no commits)"
	@echo ""
	@echo "=== Plasmoid 安装状态 ==="
	@ls -d $(HOME)/.local/share/plasma/plasmoids/$(PLASMOID_ID) 2>/dev/null \
		&& echo "  ✅ $(PLASMOID_ID) 已安装" \
		|| echo "  ❌ 未安装 (运行 make install)"
	@echo ""
	@echo "=== C++ 模块文件 ==="
	@ls -la $(PLUGIN_DST)/*.so 2>/dev/null || echo "  (无)"
	@echo ""
	@echo "=== Build 目录 ==="
	@ls -d $(PROJ)/build 2>/dev/null && echo "  ✅ 已配置" || echo "  ❌ 未配置 (运行 make configure)"
