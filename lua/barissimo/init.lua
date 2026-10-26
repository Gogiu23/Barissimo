-- Barissimo: explorador lateral + tabline de buffers + selector rápido de pestañas
local M = {}
local api = vim.api
local has_icons, devicons = pcall(require, "nvim-web-devicons")

local ns = api.nvim_create_namespace("barissimo")
local st = { open = {}, nodes = {}, tabs = {} }

local cfg = {
	width = 30,
	keys = { toggle = "<leader>E", pick = "<M-Space>" },
	-- Degradado azul de oscuro a claro (5 tonos)
	colors = { "#0a1f4d", "#123a8a", "#1f62c4", "#3d8cf0", "#86c5ff" },
}

local function set_hl()
	for i, c in ipairs(cfg.colors) do
		api.nvim_set_hl(0, "ExplorerGrad" .. i, { fg = c })
	end
	api.nvim_set_hl(0, "ExplorerLabel", { fg = cfg.colors[5], bold = true })
	api.nvim_set_hl(0, "ExplorerSep", { fg = cfg.colors[3] })
end

-- Orden de nvim: ╭ ─ ╮ │ ╯ ─ ╰ │ → diagonal de arriba-izq (oscuro) a abajo-der (claro)
local BORDER = {}
for i, ch in ipairs({ "╭", "─", "╮", "│", "╯", "─", "╰", "│" }) do
	BORDER[i] = { ch, "ExplorerGrad" .. ({ 1, 2, 3, 4, 5, 4, 3, 2 })[i] }
end

local function rgb(c)
	return tonumber(c:sub(2, 3), 16), tonumber(c:sub(4, 5), 16), tonumber(c:sub(6, 7), 16)
end

-- Color del degradado en t ∈ [0,1], multiplicado por k para oscurecer
local function grad(t, k)
	k = k or 1
	local n = #cfg.colors
	local x = t * (n - 1)
	local i = math.min(math.floor(x), n - 2)
	local f = x - i
	local r1, g1, b1 = rgb(cfg.colors[i + 1])
	local r2, g2, b2 = rgb(cfg.colors[i + 2])
	local function mix(a, b)
		return math.floor((a + (b - a) * f) * k)
	end
	return string.format("#%02x%02x%02x", mix(r1, r2), mix(g1, g2), mix(b1, b2))
end

local function file_icon(name)
	if not has_icons then
		return "", nil
	end
	return devicons.get_icon_color(name, vim.fn.fnamemodify(name, ":e"), { default = true })
end

-- Grupo de highlight con ese color de texto
local function fg_hl(color)
	if not color then
		return "Normal"
	end
	local name = "BarissimoFg" .. color:sub(2)
	api.nvim_set_hl(0, name, { fg = color })
	return name
end

local function scan(dir)
	local items = {}
	for name, t in vim.fs.dir(dir) do
		if name:sub(1, 1) ~= "." then
			items[#items + 1] = { name = name, path = dir .. "/" .. name, dir = t == "directory" }
		end
	end
	table.sort(items, function(a, b)
		if a.dir ~= b.dir then
			return a.dir
		end
		return a.name:lower() < b.name:lower()
	end)
	return items
end

local function render()
	local lines, marks = {}, {}
	st.nodes = {}
	local function walk(dir, depth)
		for _, n in ipairs(scan(dir)) do
			local ic, hl
			if n.dir then
				-- cada nivel de profundidad un tono más claro del degradado
				ic, hl = st.open[n.path] and "" or "", fg_hl(grad(0.5 + 0.5 * math.min(depth / 4, 1)))
			else
				local color
				ic, color = file_icon(n.name)
				hl = fg_hl(color)
			end
			local pad = string.rep("  ", depth)
			lines[#lines + 1] = pad .. ic .. " " .. n.name
			st.nodes[#lines] = n
			marks[#lines] = { #pad, n.dir and #lines[#lines] or #pad + #ic, hl }
			if n.dir and st.open[n.path] then
				walk(n.path, depth + 1)
			end
		end
	end
	walk(st.root, 0)
	vim.bo[st.buf].modifiable = true
	api.nvim_buf_set_lines(st.buf, 0, -1, false, lines)
	vim.bo[st.buf].modifiable = false
	api.nvim_buf_clear_namespace(st.buf, ns, 0, -1)
	for l, m in pairs(marks) do
		-- carpetas: icono + nombre coloreados; archivos: solo el icono
		api.nvim_buf_set_extmark(st.buf, ns, l - 1, m[1], { end_col = m[2], hl_group = m[3] })
	end
end

local function activate()
	local n = st.nodes[api.nvim_win_get_cursor(0)[1]]
	if not n then
		return
	end
	if n.dir then
		st.open[n.path] = not st.open[n.path] or nil
		return render()
	end
	local target
	for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
		if w ~= st.win and api.nvim_win_get_config(w).relative == "" then
			target = w
			break
		end
	end
	if not target then
		vim.cmd("rightbelow vsplit")
		target = api.nvim_get_current_win()
		api.nvim_win_set_width(st.win, cfg.width)
	end
	api.nvim_set_current_win(target)
	vim.cmd.edit(vim.fn.fnameescape(n.path))
end

function M.toggle()
	if st.win and api.nvim_win_is_valid(st.win) then
		return api.nvim_win_close(st.win, true)
	end
	st.root = st.root or vim.fn.getcwd()
	if not (st.buf and api.nvim_buf_is_valid(st.buf)) then
		st.buf = api.nvim_create_buf(false, true)
		vim.bo[st.buf].filetype = "explorer"
		local o = { buffer = st.buf, nowait = true, silent = true }
		vim.keymap.set("n", "<CR>", activate, o)
		vim.keymap.set("n", "l", activate, o)
		vim.keymap.set("n", "-", function()
			st.root = vim.fs.dirname(st.root)
			render()
		end, o)
		vim.keymap.set("n", "R", render, o)
		vim.keymap.set("n", "q", M.toggle, o)
	end
	vim.cmd("topleft " .. cfg.width .. "vsplit")
	st.win = api.nvim_get_current_win()
	api.nvim_win_set_buf(st.win, st.buf)
	local wo = vim.wo[st.win]
	wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn = false, false, "no", ""
	wo.foldcolumn, wo.wrap, wo.cursorline, wo.winfixwidth = "0", false, true, true
	wo.winhl = "WinSeparator:ExplorerSep"
	render()
end

function M.tabline()
	local s, col = {}, 0
	st.tabs = {}
	local bufs = vim.tbl_filter(function(b)
		return vim.bo[b].buflisted
	end, api.nvim_list_bufs())
	local fill = api.nvim_get_hl(0, { name = "TabLineFill", link = false }).bg
	local cur = api.nvim_get_current_buf()
	local function hl(name, spec)
		api.nvim_set_hl(0, name, spec)
		return "%#" .. name .. "#"
	end
	for i, b in ipairs(bufs) do
		local name = vim.fn.fnamemodify(api.nvim_buf_get_name(b), ":t")
		if name == "" then
			name = "[sin nombre]"
		end
		local ic, icolor = file_icon(name)
		-- degradado de oscuro a claro a lo largo de las pestañas; las no activas, atenuadas
		local bg = grad((i - 1) / math.max(#bufs - 1, 1), b == cur and 1 or 0.55)
		local r, g, bl = rgb(bg)
		local fg = (0.299 * r + 0.587 * g + 0.114 * bl) > 140 and "#0a1f4d" or "#eaf2ff"
		local label = " " .. name .. (vim.bo[b].modified and " ●" or "") .. " "
		st.tabs[i] = { buf = b, col = col }
		s[#s + 1] = hl("BarissimoCap" .. i, { fg = bg, bg = fill })
			.. ""
			.. hl("BarissimoIcon" .. i, { fg = icolor or fg, bg = bg })
			.. ic
			.. hl("BarissimoTab" .. i, { fg = fg, bg = bg, bold = b == cur })
			.. (label:gsub("%%", "%%%%"))
			.. "%#BarissimoCap"
			.. i
			.. "#%#TabLineFill# "
		col = col + vim.fn.strdisplaywidth("" .. ic .. label .. " ")
	end
	return table.concat(s) .. "%#TabLineFill#"
end

local KEYS = "asdfghjklqwertyuiopzxcvbnm"
function M.pick()
	vim.cmd.redrawtabline()
	local wins, map = {}, {}
	for i, t in ipairs(st.tabs) do
		local k = KEYS:sub(i, i)
		if k == "" or t.col + 5 > vim.o.columns then
			break
		end
		map[k] = t.buf
		local b = api.nvim_create_buf(false, true)
		vim.bo[b].bufhidden = "wipe"
		api.nvim_buf_set_lines(b, 0, -1, false, { " " .. k .. " " })
		api.nvim_buf_set_extmark(b, ns, 0, 0, { end_col = 3, hl_group = "ExplorerLabel" })
		wins[#wins + 1] = api.nvim_open_win(b, false, {
			relative = "editor",
			row = 1,
			col = t.col,
			width = 3,
			height = 1,
			style = "minimal",
			border = BORDER,
			focusable = false,
			zindex = 250,
		})
	end
	vim.cmd.redraw()
	local ok, c = pcall(vim.fn.getcharstr)
	for _, w in ipairs(wins) do
		api.nvim_win_close(w, true)
	end
	if ok and map[c] then
		if api.nvim_get_current_win() == st.win then
			vim.cmd("wincmd p")
		end
		api.nvim_set_current_buf(map[c])
	end
end

function M.setup(opts)
	cfg = vim.tbl_deep_extend("force", cfg, opts or {})
	set_hl()
	api.nvim_create_autocmd("ColorScheme", { callback = set_hl })
	vim.o.showtabline = 2
	vim.o.tabline = "%!v:lua.require'barissimo'.tabline()"
	vim.keymap.set("n", cfg.keys.toggle, M.toggle, { desc = "Explorador lateral" })
	vim.keymap.set("n", cfg.keys.pick, M.pick, { desc = "Saltar a pestaña" })
end

return M
