-- Tern 简体中文设置中心与菜单插件 (window 入口)

local function load_module(name)
	local ok, mod = pcall(require, "./" .. name)
	if ok and type(mod) == "table" then
		return mod
	end
	local src = tern.fs.read(name .. ".luau")
	local fn, err = loadstring(src, name .. ".luau")
	if not fn then
		error("加载模块 " .. name .. " 失败: " .. tostring(err))
	end
	return fn()
end

local i18n_settings = load_module("i18n_settings")
local i18n_actions = load_module("i18n_actions")

local PAGE_SIZE = 12
local KV_OVERRIDE_KEY = "override_preferences"

local desc_cache = {}

local state = {
	pane = nil,
	tab = "settings", -- "settings" | "keybinds"
	category = "general",
	search = "",
	modified_only = false,
	keybind_search = "",
	page = 1,
}

local function is_null(v)
	return v == nil or v == tern.json.null
end

local function is_override_enabled()
	local v = tern.kv.get(KV_OVERRIDE_KEY)
	if v == nil then
		return false
	end
	return v == true
end

local function get_desc(cx, key)
	local cached = desc_cache[key]
	if cached then
		return cached
	end
	local ok, desc = pcall(function()
		return cx.settings:describe(key)
	end)
	if ok and type(desc) == "table" then
		desc_cache[key] = desc
		return desc
	end
	return { type = "any", nullable = true, default = nil, doc = "" }
end

local function values_equal(a, b)
	if is_null(a) and is_null(b) then
		return true
	end
	if is_null(a) or is_null(b) then
		return false
	end
	if type(a) ~= type(b) then
		return false
	end
	if type(a) == "table" then
		for k, v in pairs(a) do
			if not values_equal(v, b[k]) then
				return false
			end
		end
		for k, v in pairs(b) do
			if not values_equal(v, a[k]) then
				return false
			end
		end
		return true
	end
	return a == b
end

local function format_value_zh(key, val, desc)
	if is_null(val) then
		return "未设置（跟随默认）"
	end
	if desc and desc.type == "boolean" then
		return val and "已开启" or "已关闭"
	end
	if desc and (desc.type == "enum" or key == "theme_dark" or key == "theme_light") then
		return i18n_settings.format_enum(key, val)
	end
	if type(val) == "table" then
		local ok, encoded = pcall(tern.json.encode, val)
		if ok then
			if #encoded > 80 then
				return string.sub(encoded, 1, 77) .. "..."
			end
			return encoded
		end
		return "[对象]"
	end
	if type(val) == "string" then
		if val == "" then
			return "（空）"
		end
		return val
	end
	return tostring(val)
end

local function format_editable_value(val, desc)
	if is_null(val) then
		return ""
	end
	if type(val) == "table" then
		local ok, encoded = pcall(tern.json.encode, val)
		return ok and encoded or ""
	end
	return tostring(val)
end

local function collect_settings(cx)
	local raw_list = cx.settings:list()
	local all_keys = {}
	for k in pairs(raw_list) do
		table.insert(all_keys, k)
	end
	table.sort(all_keys)

	local cat_counts = {}
	for _, c in ipairs(i18n_settings.categories) do
		cat_counts[c.id] = 0
	end

	local total_count = #all_keys
	local modified_count = 0
	local query = string.lower(state.search or "")
	local items = {}

	for _, key in ipairs(all_keys) do
		local val = raw_list[key]
		local meta = i18n_settings.get_meta(key)
		local cat = meta.cat or "other"
		if cat_counts[cat] == nil then
			cat = "other"
		end

		-- 若缓存已有描述或处于“仅看已修改”模式，则精确计算是否偏离默认值
		local desc = desc_cache[key]
		if not desc and state.modified_only then
			desc = get_desc(cx, key)
		end

		local is_mod = false
		if desc then
			is_mod = not values_equal(val, desc.default)
			if is_mod then
				modified_count += 1
			end
		end

		if (not state.modified_only) or is_mod then
			local matched_search = true
			if query ~= "" then
				local doc_str = desc and desc.doc or ""
				local hay = string.lower(key .. "\n" .. (meta.title or "") .. "\n" .. (meta.desc or "") .. "\n" .. doc_str)
				matched_search = string.find(hay, query, 1, true) ~= nil
			end

			if matched_search then
				cat_counts[cat] = (cat_counts[cat] or 0) + 1
				if query ~= "" or cat == state.category then
					table.insert(items, {
						key = key,
						val = val,
						desc = desc,
						meta = meta,
						cat = cat,
						modified = is_mod,
					})
				end
			end
		end
	end

	return {
		items = items,
		cat_counts = cat_counts,
		total_count = total_count,
		modified_count = modified_count,
	}
end

local function build_setting_card(entry)
	local ui = tern.ui
	local key = entry.key
	local val = entry.val
	local desc = entry.desc
	local meta = entry.meta
	local title = meta.title or key
	local summary = meta.desc or (desc.doc ~= "" and desc.doc or "暂无详细说明")

	local head_spans = {
		ui.span(title, "bold"),
		ui.span("  ·  " .. key, "muted"),
	}

	local val_text = format_value_zh(key, val, desc)
	local def_text = format_value_zh(key, desc.default, desc)
	local hint_parts = { "默认: " .. def_text }
	if desc.range then
		table.insert(hint_parts, string.format("范围: %s ~ %s", tostring(desc.range.min), tostring(desc.range.max)))
	end

	local body_nodes = {
		ui.text({ ui.span(summary, "muted") }),
		ui.row({
			ui.badge(entry.modified and "已修改" or "默认", entry.modified and "accent" or "neutral"),
			ui.text({ ui.span("当前值: ", "muted"), ui.span(val_text, entry.modified and "accent" or nil) }),
		}),
		ui.text({ ui.span(table.concat(hint_parts, "   |   "), "muted") }),
	}

	local action_btns = {}
	if desc.type == "boolean" then
		table.insert(
			action_btns,
			ui.button(val and "点击关闭" or "点击开启", {
				size = "sm",
				variant = val and "primary" or "default",
				on = val == true,
				actions = { click = "toggle:" .. key },
			})
		)
	elseif desc.type == "enum" or key == "theme_dark" or key == "theme_light" then
		table.insert(
			action_btns,
			ui.button("选择选项…", {
				size = "sm",
				variant = "primary",
				actions = { click = "pick:" .. key },
			})
		)
	else
		table.insert(
			action_btns,
			ui.button("修改值…", {
				size = "sm",
				variant = "primary",
				actions = { click = "edit:" .. key },
			})
		)
	end

	if entry.modified then
		table.insert(
			action_btns,
			ui.button("恢复默认", {
				size = "sm",
				variant = "quiet",
				actions = { click = "reset:" .. key },
			})
		)
	end

	table.insert(body_nodes, ui.row(action_btns))
	return ui.card(head_spans, body_nodes)
end

local function build_settings_view(cx)
	local ui = tern.ui
	local data = collect_settings(cx)
	local nodes = {}

	-- 统计概览
	table.insert(
		nodes,
		ui.stats({
			{ label = "全部设置项", value = tostring(data.total_count), sub = "实时同步 settings.json" },
			{ label = "已自定义", value = tostring(data.modified_count), tone = data.modified_count > 0 and "accent" or nil, sub = "偏离默认值的项目" },
			{ label = "当前显示", value = tostring(#data.items), sub = state.search ~= "" and ("搜索: " .. state.search) or "当前分类条目" },
		})
	)

	-- 分类导航（分两行以适配不同宽度窗口）
	local cat_rows = {}
	local cur_row = {}
	for idx, c in ipairs(i18n_settings.categories) do
		local cnt = data.cat_counts[c.id] or 0
		if c.id ~= "other" or cnt > 0 then
			local active = (state.search == "" and state.category == c.id)
			table.insert(
				cur_row,
				ui.button(string.format("%s (%d)", c.label, cnt), {
					size = "sm",
					variant = active and "primary" or "default",
					on = active,
					actions = { click = "cat:" .. c.id },
				})
			)
			if #cur_row >= 4 then
				table.insert(cat_rows, ui.row(cur_row))
				cur_row = {}
			end
		end
	end
	if #cur_row > 0 then
		table.insert(cat_rows, ui.row(cur_row))
	end

	local cat_desc = "当前显示全部匹配搜索条件的设置项"
	if state.search == "" then
		for _, c in ipairs(i18n_settings.categories) do
			if c.id == state.category then
				cat_desc = c.desc
				break
			end
		end
	end
	table.insert(cat_rows, ui.text({ ui.span(cat_desc, "muted") }))
	table.insert(nodes, ui.card("设置分类", cat_rows))

	-- 分页计算与渲染当前页（仅在未缓存时对当前页可见项查询 describe，保证单帧 < 15ms）
	local total_items = #data.items
	local total_pages = math.max(1, math.ceil(total_items / PAGE_SIZE))
	if state.page > total_pages then
		state.page = total_pages
	end
	if state.page < 1 then
		state.page = 1
	end

	if total_items == 0 then
		table.insert(
			nodes,
			ui.card("没有匹配的设置项", {
				ui.text({ ui.span("当前过滤条件下没有可显示的设置项，可点击「清除搜索」或关闭「仅看已修改」。", "muted") }),
			})
		)
	else
		local start_idx = (state.page - 1) * PAGE_SIZE + 1
		local end_idx = math.min(total_items, start_idx + PAGE_SIZE - 1)

		for i = start_idx, end_idx do
			local entry = data.items[i]
			if not entry.desc then
				entry.desc = get_desc(cx, entry.key)
				entry.modified = not values_equal(entry.val, entry.desc.default)
			end
			table.insert(nodes, build_setting_card(entry))
		end

		if total_pages > 1 then
			table.insert(
				nodes,
				ui.row({
					ui.button("上一页", {
						size = "sm",
						disabled = state.page <= 1,
						actions = { click = "page:" .. tostring(state.page - 1) },
					}),
					ui.text({ ui.span(string.format("第 %d / %d 页（共 %d 项）", state.page, total_pages, total_items), "muted") }),
					ui.button("下一页", {
						size = "sm",
						disabled = state.page >= total_pages,
						actions = { click = "page:" .. tostring(state.page + 1) },
					}),
				})
			)
		end
	end

	return nodes, data
end

local function build_keybinds_view(cx)
	local ui = tern.ui
	local actions = cx.actions:list()
	local query = string.lower(state.keybind_search or "")
	local filtered = {}

	local group_labels = {}
	for _, g in ipairs(i18n_actions.groups) do
		group_labels[g.id] = g.label
	end

	for _, a in ipairs(actions) do
		local grp_id, zh_label = i18n_actions.get_action_info(a.id, a.label)
		local grp_label = group_labels[grp_id] or a.group or "其他"
		local keys_str = (a.keys and #a.keys > 0) and table.concat(a.keys, ", ") or "未绑定"
		if query == "" then
			table.insert(filtered, { a = a, zh = zh_label, grp = grp_label, keys = keys_str })
		else
			local hay = string.lower(a.id .. "\n" .. (a.label or "") .. "\n" .. zh_label .. "\n" .. grp_label .. "\n" .. keys_str)
			if string.find(hay, query, 1, true) ~= nil then
				table.insert(filtered, { a = a, zh = zh_label, grp = grp_label, keys = keys_str })
			end
		end
	end

	local nodes = {
		ui.card("快捷键与命令映射", {
			ui.text({
				ui.span("点击「绑定快捷键」可为任意命令新增或覆盖按键（例如 ctrl+shift+p、alt+k）；也可直接打开 Tern 原生图形化快捷键页。", "muted"),
			}),
			ui.row({
				ui.button(state.keybind_search ~= "" and ("搜索: " .. state.keybind_search) or "搜索命令/快捷键…", {
					size = "sm",
					variant = "primary",
					actions = { click = "kb_search" },
				}),
				state.keybind_search ~= "" and ui.button("清除搜索", {
					size = "sm",
					actions = { click = "kb_clear" },
				}) or ui.text({ ui.span(string.format("共 %d 条命令", #filtered), "muted") }),
				ui.button("打开原生设置页面", {
					size = "sm",
					actions = { click = "open_native_prefs" },
				}),
			}),
		}),
	}

	local total_items = #filtered
	local total_pages = math.max(1, math.ceil(total_items / PAGE_SIZE))
	if state.page > total_pages then
		state.page = total_pages
	end
	if state.page < 1 then
		state.page = 1
	end

	local start_idx = (state.page - 1) * PAGE_SIZE + 1
	local end_idx = math.min(total_items, start_idx + PAGE_SIZE - 1)
	for i = start_idx, end_idx do
		local item = filtered[i]
		local a = item.a
		local has_keys = a.keys and #a.keys > 0
		table.insert(
			nodes,
			ui.card({ ui.span(item.zh, "bold"), ui.span("  ·  " .. a.id, "muted") }, {
				ui.row({
					ui.badge(item.grp, "neutral"),
					ui.text({ ui.span("当前快捷键: ", "muted"), ui.span(item.keys, has_keys and "accent" or "muted") }),
				}),
				ui.row({
					ui.button("绑定快捷键…", {
						size = "sm",
						variant = "primary",
						actions = { click = "kb_bind:" .. a.id },
					}),
					ui.button("立即执行", {
						size = "sm",
						actions = { click = "kb_run:" .. a.id },
					}),
				}),
			})
		)
	end

	if total_pages > 1 then
		table.insert(
			nodes,
			ui.row({
				ui.button("上一页", {
					size = "sm",
					disabled = state.page <= 1,
					actions = { click = "page:" .. tostring(state.page - 1) },
				}),
				ui.text({ ui.span(string.format("第 %d / %d 页（共 %d 条）", state.page, total_pages, total_items), "muted") }),
				ui.button("下一页", {
					size = "sm",
					disabled = state.page >= total_pages,
					actions = { click = "page:" .. tostring(state.page + 1) },
				}),
			})
		)
	end

	return nodes
end

local function build_view(cx)
	local ui = tern.ui
	local override_on = is_override_enabled()

	local top_bar = ui.card("Tern 简体中文设置中心", {
		ui.row({
			ui.button("设置项", {
				size = "sm",
				variant = state.tab == "settings" and "primary" or "default",
				on = state.tab == "settings",
				actions = { click = "tab:settings" },
			}),
			ui.button("快捷键管理", {
				size = "sm",
				variant = state.tab == "keybinds" and "primary" or "default",
				on = state.tab == "keybinds",
				actions = { click = "tab:keybinds" },
			}),
			ui.button("中文全功能菜单…", {
				size = "sm",
				actions = { click = "open_menu" },
			}),
			ui.button("原生英文设置", {
				size = "sm",
				variant = "quiet",
				actions = { click = "open_native_prefs" },
			}),
		}),
		ui.row({
			ui.button(state.search ~= "" and ("搜索: " .. state.search) or "搜索设置…", {
				size = "sm",
				actions = { click = "search" },
			}),
			state.search ~= "" and ui.button("清除搜索", {
				size = "sm",
				actions = { click = "clear_search" },
			}) or ui.button("仅看已修改", {
				size = "sm",
				on = state.modified_only,
				variant = state.modified_only and "primary" or "default",
				actions = { click = "toggle_modified" },
			}),
			ui.button(override_on and "接管 Ctrl+, : 已开启" or "接管 Ctrl+, : 已关闭", {
				size = "sm",
				on = override_on,
				actions = { click = "toggle_override" },
			}),
			ui.button("刷新", {
				size = "sm",
				variant = "quiet",
				actions = { click = "refresh" },
			}),
		}),
	})

	local body_nodes = { top_bar }
	local dock_msg = "修改配置将直接写入 settings.json 并立即生效"
	if state.tab == "keybinds" then
		local kb_nodes = build_keybinds_view(cx)
		for _, n in ipairs(kb_nodes) do
			table.insert(body_nodes, n)
		end
		dock_msg = "快捷键页 · 修改会写入 settings.json 的 keybinds 覆盖表"
	else
		local set_nodes, data = build_settings_view(cx)
		for _, n in ipairs(set_nodes) do
			table.insert(body_nodes, n)
		end
		dock_msg = string.format("共 %d 项设置 · 已修改 %d 项 · 支持点击即时保存", data.total_count, data.modified_count)
	end

	local dock = ui.row({
		ui.text({ ui.span(dock_msg, "muted") }),
	})

	return ui.col(body_nodes), dock
end

local function refresh_canvas(cx)
	local view, dock = build_view(cx)
	if state.pane ~= nil then
		local existing = cx.canvas:get(state.pane)
		if existing then
			cx.canvas:set(state.pane, {
				title = "Tern 中文设置中心",
				view = view,
				dock = dock,
			})
			return true
		end
	end
	local pane_id, err = cx.canvas:open({
		title = "Tern 中文设置中心",
		about = "Tern 简体中文设置中心：浏览、搜索并修改 Tern 全量配置与快捷键",
		view = view,
		dock = dock,
		how = "beside",
		focus = true,
	})
	if pane_id then
		state.pane = pane_id
		return true
	end
	cx:toast("error", "无法打开中文设置中心", tostring(err))
	return false
end

local function open_chinese_menu(cx)
	local actions = cx.actions:list()
	local by_group = {}
	for _, g in ipairs(i18n_actions.groups) do
		by_group[g.id] = {}
	end
	by_group["other"] = {}

	for _, a in ipairs(actions) do
		local grp_id, zh_label = i18n_actions.get_action_info(a.id, a.label)
		if not by_group[grp_id] then
			grp_id = "other"
		end
		local keys_str = (a.keys and #a.keys > 0) and ("  [" .. table.concat(a.keys, ", ") .. "]") or ""
		local detail = a.id .. keys_str
		table.insert(by_group[grp_id], {
			label = zh_label,
			detail = detail,
			group = nil, -- 下面按分组赋中文名
			action_id = a.id,
		})
	end

	local items = {}
	for _, g in ipairs(i18n_actions.groups) do
		local list = by_group[g.id]
		if list and #list > 0 then
			for _, it in ipairs(list) do
				it.group = g.label
				table.insert(items, it)
			end
		end
	end
	for _, it in ipairs(by_group["other"]) do
		it.group = "其他功能"
		table.insert(items, it)
	end

	cx:pick({
		items = items,
		placeholder = "输入中文或英文命令名称筛选菜单操作…",
		action = "执行",
	}):next(function(choice, err, ncx)
		if err then
			if ncx then
				ncx:toast("error", "打开中文菜单失败", tostring(err))
			end
			return
		end
		if not choice or not ncx then
			return
		end
		if choice.action_id == "preferences" then
			ncx:command("preferences")
			return
		end
		local ok, run_err = pcall(function()
			ncx.actions:run(choice.action_id)
		end)
		if not ok then
			ncx:toast("error", "执行命令失败: " .. choice.label, tostring(run_err))
		end
	end)
end

local function handle_pick_setting(cx, key)
	local ok, desc = pcall(function()
		return cx.settings:describe(key)
	end)
	if not ok then
		cx:toast("error", "读取设置描述失败", tostring(desc))
		return
	end

	local cur = cx.settings:get(key)
	local meta = i18n_settings.get_meta(key)
	local options = {}
	if key == "theme_dark" or key == "theme_light" then
		options = cx.settings:themes()
	elseif desc.enum then
		options = desc.enum
	end

	local items = {}
	if desc.nullable then
		table.insert(items, {
			label = "跟随默认 / 清空 (未设置)",
			detail = "恢复为 nil",
			current = is_null(cur),
			is_nil = true,
		})
	end

	for _, opt in ipairs(options) do
		table.insert(items, {
			label = i18n_settings.format_enum(key, opt),
			detail = tostring(opt),
			current = (not is_null(cur)) and tostring(cur) == tostring(opt),
			raw_val = opt,
		})
	end

	if #items == 0 then
		cx:toast("warning", "该项没有可选项", key)
		return
	end

	cx:pick({
		items = items,
		placeholder = "选择「" .. (meta.title or key) .. "」的值…",
		action = "应用",
	}):next(function(choice, err, ncx)
		if err or not choice or not ncx then
			return
		end
		local target = choice.is_nil and nil or choice.raw_val
		local set_ok, set_err = pcall(function()
			ncx.settings:set(key, target)
		end)
		if set_ok then
			ncx:toast("info", "已更新设置", (meta.title or key) .. " = " .. (choice.is_nil and "默认" or choice.label))
			refresh_canvas(ncx)
		else
			ncx:toast("error", "设置失败: " .. key, tostring(set_err))
		end
	end)
end

local function parse_input_value(raw, desc)
	local trimmed = string.match(raw, "^%s*(.-)%s*$")
	if trimmed == "" and desc.nullable then
		return true, nil
	end
	if desc.type == "integer" or desc.type == "number" then
		local num = tonumber(trimmed)
		if not num then
			return false, "请输入有效的数字"
		end
		if desc.type == "integer" then
			num = math.floor(num)
		end
		return true, num
	end
	if desc.type == "array" or desc.type == "table" then
		local ok, decoded = pcall(tern.json.decode, trimmed)
		if not ok then
			return false, "请输入合法的 JSON 格式: " .. tostring(decoded)
		end
		return true, decoded
	end
	if desc.type == "any" then
		local num = tonumber(trimmed)
		if num ~= nil and tostring(num) == trimmed then
			return true, num
		end
		if trimmed == "true" then
			return true, true
		elseif trimmed == "false" then
			return true, false
		elseif string.sub(trimmed, 1, 1) == "[" or string.sub(trimmed, 1, 1) == "{" then
			local ok, decoded = pcall(tern.json.decode, trimmed)
			if ok then
				return true, decoded
			end
		end
		return true, raw
	end
	return true, raw
end

local function handle_edit_setting(cx, key)
	local ok, desc = pcall(function()
		return cx.settings:describe(key)
	end)
	if not ok then
		cx:toast("error", "读取设置描述失败", tostring(desc))
		return
	end
	local cur = cx.settings:get(key)
	local meta = i18n_settings.get_meta(key)
	local hint = "输入新值"
	if desc.type == "array" or desc.type == "table" then
		hint = "请输入 JSON（如 [] 或 {}）"
	elseif desc.range then
		hint = string.format("请输入数值（%s ~ %s）", tostring(desc.range.min), tostring(desc.range.max))
	elseif desc.nullable then
		hint = "留空提交可清除为默认 (nil)"
	end

	cx:prompt({
		value = format_editable_value(cur, desc),
		placeholder = (meta.title or key) .. " · " .. hint,
		action = "保存",
	}):next(function(text, err, ncx)
		if err or text == nil or not ncx then
			return
		end
		local parse_ok, parsed = parse_input_value(text, desc)
		if not parse_ok then
			ncx:toast("error", "格式错误", tostring(parsed))
			return
		end
		local set_ok, set_err = pcall(function()
			ncx.settings:set(key, parsed)
		end)
		if set_ok then
			ncx:toast("info", "已保存设置", (meta.title or key) .. " 已更新")
			refresh_canvas(ncx)
		else
			ncx:toast("error", "保存失败: " .. key, tostring(set_err))
		end
	end)
end

-- 处理 Canvas 内所有按钮点击事件
tern.on("canvas_action", function(ev, cx)
	if not state.pane or ev.pane ~= state.pane then
		return false
	end
	local act = ev.act or ""

	if act == "tab:settings" then
		state.tab = "settings"
		state.page = 1
		refresh_canvas(cx)
		return true
	elseif act == "tab:keybinds" then
		state.tab = "keybinds"
		state.page = 1
		refresh_canvas(cx)
		return true
	elseif act == "open_menu" then
		open_chinese_menu(cx)
		return true
	elseif act == "open_native_prefs" then
		cx:command("preferences")
		return true
	elseif act == "refresh" then
		refresh_canvas(cx)
		return true
	elseif act == "toggle_modified" then
		state.modified_only = not state.modified_only
		state.page = 1
		refresh_canvas(cx)
		return true
	elseif act == "clear_search" then
		state.search = ""
		state.page = 1
		refresh_canvas(cx)
		return true
	elseif act == "search" then
		cx:prompt({
			value = state.search,
			placeholder = "输入中文或英文关键词搜索设置项…",
			action = "搜索",
		}):next(function(text, err, ncx)
			if err or text == nil or not ncx then
				return
			end
			state.search = text
			state.page = 1
			refresh_canvas(ncx)
		end)
		return true
	elseif act == "toggle_override" then
		local next_val = not is_override_enabled()
		tern.kv.set(KV_OVERRIDE_KEY, next_val)
		cx:toast("info", next_val and "已开启接管 Ctrl+," or "已关闭接管 Ctrl+,", next_val and "按下设置快捷键将打开中文设置中心" or "按下设置快捷键将打开原生英文设置")
		refresh_canvas(cx)
		return true
	elseif act == "kb_search" then
		cx:prompt({
			value = state.keybind_search,
			placeholder = "搜索命令中文名、英文 ID 或快捷键…",
			action = "筛选",
		}):next(function(text, err, ncx)
			if err or text == nil or not ncx then
				return
			end
			state.keybind_search = text
			state.page = 1
			refresh_canvas(ncx)
		end)
		return true
	elseif act == "kb_clear" then
		state.keybind_search = ""
		state.page = 1
		refresh_canvas(cx)
		return true
	elseif string.sub(act, 1, 4) == "cat:" then
		state.category = string.sub(act, 5)
		state.search = ""
		state.page = 1
		refresh_canvas(cx)
		return true
	elseif string.sub(act, 1, 5) == "page:" then
		local p = tonumber(string.sub(act, 6))
		if p then
			state.page = p
			refresh_canvas(cx)
		end
		return true
	elseif string.sub(act, 1, 7) == "toggle:" then
		local key = string.sub(act, 8)
		local cur = cx.settings:get(key)
		local set_ok, set_err = pcall(function()
			cx.settings:set(key, not cur)
		end)
		if set_ok then
			refresh_canvas(cx)
		else
			cx:toast("error", "切换失败: " .. key, tostring(set_err))
		end
		return true
	elseif string.sub(act, 1, 5) == "pick:" then
		handle_pick_setting(cx, string.sub(act, 6))
		return true
	elseif string.sub(act, 1, 5) == "edit:" then
		handle_edit_setting(cx, string.sub(act, 6))
		return true
	elseif string.sub(act, 1, 6) == "reset:" then
		local key = string.sub(act, 7)
		local ok, desc = pcall(function()
			return cx.settings:describe(key)
		end)
		if ok then
			local target = is_null(desc.default) and nil or desc.default
			local set_ok, set_err = pcall(function()
				cx.settings:set(key, target)
			end)
			if set_ok then
				cx:toast("info", "已恢复默认", key)
				refresh_canvas(cx)
			else
				cx:toast("error", "恢复失败: " .. key, tostring(set_err))
			end
		end
		return true
	elseif string.sub(act, 1, 8) == "kb_bind:" then
		local aid = string.sub(act, 9)
		cx:prompt({
			value = "",
			placeholder = "输入要绑定的快捷键组合（例如 ctrl+shift+p 或 alt+k）",
			action = "绑定",
		}):next(function(chord, err, ncx)
			if err or chord == nil or not ncx then
				return
			end
			local trimmed = string.match(chord, "^%s*(.-)%s*$")
			if trimmed == "" then
				return
			end
			local bind_ok, bind_err = pcall(function()
				ncx.settings:bind(trimmed, aid)
			end)
			if bind_ok then
				ncx:toast("info", "快捷键已绑定", trimmed .. " -> " .. aid)
				refresh_canvas(ncx)
			else
				ncx:toast("error", "绑定失败", tostring(bind_err))
			end
		end)
		return true
	elseif string.sub(act, 1, 7) == "kb_run:" then
		local aid = string.sub(act, 8)
		if aid == "preferences" then
			cx:command("preferences")
			return true
		end
		local run_ok, run_err = pcall(function()
			cx.actions:run(aid)
		end)
		if not run_ok then
			cx:toast("error", "执行失败", tostring(run_err))
		end
		return true
	end

	return false
end)

-- 注册核心中文入口命令
tern.command({
	id = "open_settings",
	title = "中文设置中心",
	group = "中文界面",
	run = function(cx)
		state.tab = "settings"
		refresh_canvas(cx)
	end,
})

tern.command({
	id = "menu",
	title = "中文菜单：全部功能…",
	group = "中文界面",
	run = function(cx)
		open_chinese_menu(cx)
	end,
})

tern.command({
	id = "keybinds",
	title = "中文快捷键管理",
	group = "中文界面",
	run = function(cx)
		state.tab = "keybinds"
		state.page = 1
		refresh_canvas(cx)
	end,
})

tern.command({
	id = "toggle_override",
	title = "切换中文设置接管 (Ctrl+,)",
	group = "中文界面",
	run = function(cx)
		local next_val = not is_override_enabled()
		tern.kv.set(KV_OVERRIDE_KEY, next_val)
		cx:toast("info", next_val and "已开启接管 Ctrl+," or "已关闭接管 Ctrl+,")
		if state.pane and cx.canvas:get(state.pane) then
			refresh_canvas(cx)
		end
	end,
})

tern.command({
	id = "open_native_settings",
	title = "打开原生英文设置",
	group = "中文界面",
	run = function(cx)
		cx:command("preferences")
	end,
})

-- 在原生命令面板全量注册全部 223 项内置命令的中文直达入口
local group_labels = {}
for _, g in ipairs(i18n_actions.groups) do
	group_labels[g.id] = g.label
end

local action_ids = {}
for aid in pairs(i18n_actions.actions) do
	if aid ~= "preferences" then
		table.insert(action_ids, aid)
	end
end
table.sort(action_ids)

for _, aid in ipairs(action_ids) do
	local info = i18n_actions.actions[aid]
	local cmd_id = "zh_" .. string.gsub(aid, "[^a-zA-Z0-9_%-]", "_")
	local grp_title = "中文 · " .. (group_labels[info.group] or "其他")
	tern.command({
		id = cmd_id,
		title = info.label,
		group = grp_title,
		run = function(cx)
			local ok, err = pcall(function()
				cx.actions:run(aid)
			end)
			if not ok then
				cx:toast("error", "执行失败: " .. info.label, tostring(err))
			end
		end,
	})
end

-- 接管 Ctrl+, / Cmd+, 打开设置命令
tern.override("preferences", function(cx)
	if not is_override_enabled() then
		return false
	end
	state.tab = "settings"
	refresh_canvas(cx)
	return true
end)

-- 分批预热设置描述缓存，避免首次打开设置时超出 50ms 单次切片预算
tern.on("window_start", function(cx)
	local raw_list = cx.settings:list()
	local keys = {}
	for k in pairs(raw_list) do
		if not desc_cache[k] then
			table.insert(keys, k)
		end
	end
	local idx = 1
	local function warm_batch(ncx)
		local c = ncx or cx
		local stop = math.min(#keys, idx + 49)
		while idx <= stop do
			get_desc(c, keys[idx])
			idx += 1
		end
		if idx <= #keys then
			tern.timer(10, warm_batch)
		end
	end
	if #keys > 0 then
		tern.timer(10, warm_batch)
	end
end)
