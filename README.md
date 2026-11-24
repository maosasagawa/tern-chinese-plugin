# Tern Chinese Plugin (`zh-cn`)

[Tern](https://stencil.so/tern) 简体中文插件 — 提供交互式**简体中文设置中心**（完整覆盖全部 322 项设置）、**中文快捷键管理**与**中文全功能命令菜单**（223 项内置动作）。

A Simplified Chinese (`zh-CN`) localization plugin for [Tern](https://stencil.so/tern) featuring an interactive Chinese Settings Center (all 322 settings), Chinese Keybind Manager, and Chinese Command Menu (all 223 built-in actions).

> **Note / 说明**：Tern 的原生菜单栏与弹窗文案硬编码在客户端二进制中，官方 Luau 插件 API 暂不支持直接覆写原生界面文本。本插件通过原生 `Canvas`、`Command Palette` 与 `preferences` 拦截机制提供完整的中文交互界面，所有配置修改均实时写入真实的 `settings.json` 并立即生效。

---

## 核心特性 / Features

1. **中文设置中心（Interactive Chinese Settings Center）**
   - 按 `Ctrl+,`（macOS 为 `Cmd+,`）或在命令面板搜索 `中文设置中心` 即可打开。
   - **完整覆盖 322 项设置**，归类为 11 个中文大类：常规与窗口、外观与字体、光标与指针、终端与输入、原生提示符、AI 与 Carly、文件与编辑器、Git 面板、Notebook、SQLite 数据库、远程/云与插件。
   - 支持 **中英文关键词实时搜索**、**仅看已修改项**、**一键恢复默认值**。
   - 全类型实时编辑：布尔开关一键切换、枚举与配色主题下拉选择、数值/字符串/JSON 弹出编辑。
   - 顶栏提供 **「接管 Ctrl+,」开关**（状态持久化）和 **「原生英文设置」** 快捷按钮，随时切回原生设置页。
2. **中文全功能菜单（223 Actions）**
   - 运行命令面板中的 `中文菜单：全部功能…`，按中文分组浏览、搜索并执行 Tern 全部 223 项内置操作。
3. **原生命令面板中文直达项**
   - 直接在原生命令面板（`Ctrl+Shift+F1` / `Cmd+Shift+P`）注册 **44 个高频中文命令** + 5 个中文插件管理命令（如 `新建标签页`、`向右分屏`、`切换配色主题`、`显示/隐藏左侧文件树`、`切换远程主机` 等）。
4. **中文快捷键管理**
   - 在设置中心切换到「快捷键管理」页签，可按中文名检索所有命令、查看当前快捷键、自定义绑定或立即运行。

---

## 安装 / Installation

在本地安装了 Tern 的终端中运行：

```bash
tern plugin install github.com/maosasagawa/tern-chinese-plugin
tern plugin reload
```

卸载或更新：

```bash
# 更新到最新版本
tern plugin install github.com/maosasagawa/tern-chinese-plugin --force

# 卸载
tern plugin remove zh-cn
```

---

## 使用说明 / Usage

- `Ctrl+,` / `Cmd+,`：打开 **Tern 中文设置中心**（可在设置中心顶栏关闭接管以还原原生英文设置）。
- 命令面板搜索 `中文设置中心`、`中文菜单`、`中文快捷键管理`、`打开原生英文设置`。
- 本插件兼容 Tern `0.9.18` 及支持 `schema = 1` Window 插件的桌面/远程环境。

## License

[MIT](./LICENSE)
