-- Barissimo: explorador lateral + tabline con tarjetas sobre degradado + selector rápido de pestañas
local M = {}
local api = vim.api
local has_icons, devicons = pcall(require, "nvim-web-devicons")

local ns = api.nvim_create_namespace("barissimo")
local st = { open = {}, nodes = {}, tabs = {} }

local cfg = {
	width = 30,
	-- new: abre el buscador como el "+". <C-+> necesita el protocolo de teclado de kitty;
	-- <C-=> es el respaldo para las terminales que no lo distinguen
	keys = { toggle = "<leader>E", pick = "<M-Space>", new = { "<C-+>", "<C-=>" } },
	-- Degradado azul de oscuro a claro (carpetas del explorador y su separador)
	colors = { "#0a1f4d", "#123a8a", "#1f62c4", "#3d8cf0", "#86c5ff" },
	-- Fondo de toda la tabline: lista de tonos, o un solo color ("#d6249f") y se genera
	-- el degradado desde un tono oscuro de ese color hasta el color tal cual
	bg_colors = { "#3a0b2e", "#5e1048", "#86165f", "#b01c84", "#d6249f" },
	brand = "Barissimo", -- "" para ocultarla
	brand_color = "#ffffff",
	-- Tarjetas de la tabline
	tabs = {
		left = "\u{e0b6}", -- extremo izquierdo (redondeado). Otros: "\u{e0b2}" flecha, "" recto
		right = "\u{e0b4}", -- extremo derecho (redondeado). Otros: "\u{e0b0}" flecha, "" recto
		padding = 1, -- espacios dentro de la tarjeta a cada lado
		gap = 0, -- espacios entre tarjetas
		bg = nil, -- fondo de las inactivas: nil = el del colorscheme; un color o lista = degradado a lo ancho
		fg = nil, -- texto de las inactivas (nil = automático: Comment, u oscuro si el fondo es claro)
		active_bg = nil, -- fondo de la activa: igual que bg (p. ej. "#FFDE7D")
		active_fg = nil, -- texto de la activa (nil = automático: Normal, u oscuro si el fondo es claro)
		active_bold = true,
		close = "\u{f00d}", -- botón de cerrar (aparece al pasar el ratón)
		modified = "●", -- marca de cambios sin guardar
		new = "+", -- tarjeta para abrir otro archivo
		on_new = nil, -- función al pulsar +; nil = buscador de snacks, telescope o lista simple
	},
	-- Popups del selector (<M-Space>): píldoras con la letra de cada pestaña
	picker = {
		left = "\u{e0b6}",
		right = "\u{e0b4}",
		padding = 1,
		bg = "#86c5ff",
		fg = nil, -- nil = automático (oscuro si el fondo es claro, blanco si no)
	},
	-- Buscador del "+" (snacks): bordes redondeados en degradado, preview y barra de marca arriba
	finder = {
		width = 0.8, -- fracción del editor
		height = 0.7,
		preview = 0.55, -- ancho de la preview dentro del buscador
		border_color = "#FFDE7D", -- degradado diagonal de su tono oscuro a su tono claro
	},
}

local function set_hl()
	api.nvim_set_hl(0, "ExplorerSep", { fg = cfg.colors[3] })
end

local function rgb(c)
	return tonumber(c:sub(2, 3), 16), tonumber(c:sub(4, 5), 16), tonumber(c:sub(6, 7), 16)
end

-- Texto legible sobre `bg`: oscuro si el fondo es claro; si no, `fallback`
local function text_on(bg, fallback)
	local r, g, b = rgb(bg)
	return (0.299 * r + 0.587 * g + 0.114 * b) > 140 and "#1a1a1a" or fallback
end

-- Color del degradado `stops` (por defecto cfg.colors) en t ∈ [0,1], multiplicado por k para oscurecer
local function grad(t, k, stops)
	k = k or 1
	stops = stops or cfg.colors
	local n = #stops
	local x = math.min(math.max(t, 0), 1) * (n - 1)
	local i = math.min(math.floor(x), n - 2)
	local f = x - i
	local r1, g1, b1 = rgb(stops[i + 1])
	local r2, g2, b2 = rgb(stops[i + 2])
	local function mix(a, b)
		return math.floor((a + (b - a) * f) * k)
	end
	return string.format("#%02x%02x%02x", mix(r1, r2), mix(g1, g2), mix(b1, b2))
end

local function file_icon(name)
	if not has_icons then
		return "\u{f15b}", nil
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

-- Un solo color "#rrggbb" → degradado de su tono oscuro (25%) al color; una lista se deja igual
local function gradient_of(v)
	if type(v) ~= "string" then
		return v
	end
	return { grad(1, 0.25, { v, v }), grad(1, 0.5, { v, v }), grad(1, 0.75, { v, v }), v }
end

-- Color fg de un grupo como "#rrggbb"
local function hl_fg(group)
	local v = api.nvim_get_hl(0, { name = group, link = false }).fg
	return v and string.format("#%06x", v)
end

-- Grupo de highlight para una combinación fg/bg/estilo ("b" negrita, "i" cursiva)
local function hl_for(fg, bg, style)
	local name = ("BarissimoTl%s_%s_%s"):format(fg and fg:sub(2) or "", bg and bg:sub(2) or "", style or "")
	api.nvim_set_hl(0, name, { fg = fg, bg = bg, bold = style == "b", italic = style == "i" })
	return name
end

-- Columnas [first, last) del degradado de fondo (bg_colors, repartido sobre 0..last-1)
-- con la marca en cursiva al final si cabe y, opcionalmente, `label` en negrita al principio
-- (recortada por la izquierda si no cabe). Llama put(ch, fg, bg, style) por cada columna
local function strip(first, last, put, label)
	local stops = gradient_of(cfg.bg_colors)
	local brand = cfg.brand ~= "" and (cfg.brand .. " ") or ""
	if last - first < #brand then
		brand = ""
	end
	local chars = label and vim.fn.split(" " .. label .. " ", "\\zs") or {}
	local room = last - first - #brand
	if #chars > room then
		chars = vim.list_slice(chars, #chars - room + 1)
	end
	for c = first, last - 1 do
		local bg = grad(c / math.max(last - 1, 1), 1, stops)
		local bi = c - (last - #brand) + 1 -- índice dentro de la marca (≥ 1 en sus últimas columnas)
		local li = c - first + 1
		if bi >= 1 then
			put(brand:sub(bi, bi), cfg.brand_color, bg, "i")
		elseif chars[li] then
			put(chars[li], cfg.brand_color, bg, "b")
		else
			put(" ", nil, bg)
		end
	end
end

-- Primera ventana normal (ni explorador, ni flotante)
local function main_win()
	for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
		if w ~= st.win and api.nvim_win_get_config(w).relative == "" then
			return w
		end
	end
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
				ic, hl = st.open[n.path] and "\u{f07c}" or "\u{f07b}", fg_hl(grad(0.5 + 0.5 * math.min(depth / 4, 1)))
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
	local target = main_win()
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

-- Sale del explorador a una ventana normal, si estamos en él
local function leave_explorer()
	if api.nvim_get_current_win() == st.win then
		api.nvim_set_current_win(main_win() or st.win)
	end
end

-- Cambia al buffer desde una ventana normal (nunca dentro del explorador)
function M.select(buf)
	leave_explorer()
	api.nvim_set_current_buf(buf)
end

-- Barra de marca (mismo degradado que la tabline) en la primera fila dentro de `win`,
-- con `label` a la izquierda
local function brand_bar(win, label)
	-- win_screenpos da la esquina exterior (borde incluido), 1-based; el contenido empieza 1 más adentro
	local pos = vim.fn.win_screenpos(win)
	local w = api.nvim_win_get_width(win)
	local text, marks, s = {}, {}, 0
	strip(0, w, function(ch, fg, bg, style)
		text[#text + 1] = ch
		marks[#marks + 1] = { s, s + #ch, hl_for(fg, bg, style) }
		s = s + #ch
	end, label)
	local b = api.nvim_create_buf(false, true)
	vim.bo[b].bufhidden = "wipe"
	api.nvim_buf_set_lines(b, 0, -1, false, { table.concat(text) })
	for _, m in ipairs(marks) do
		api.nvim_buf_set_extmark(b, ns, 0, m[1], { end_col = m[2], hl_group = m[3] })
	end
	return api.nvim_open_win(b, false, {
		relative = "editor",
		row = pos[1], -- primera fila del contenido (0-based)
		col = pos[2],
		width = w,
		height = 1,
		style = "minimal",
		focusable = false,
		zindex = 300,
	})
end

-- Fondo que queda detrás del buscador (que tiene el foco): el de las ventanas sin foco
-- (NormalNC, p. ej. con dimInactive) o, si el tema no lo cambia, el de Normal
local function behind_bg()
	return api.nvim_get_hl(0, { name = "NormalNC", link = false }).bg
		or api.nvim_get_hl(0, { name = "Normal", link = false }).bg
end

-- Rehace el winhighlight de `win` para que los grupos que usa tengan el fondo de detrás
local function clear_bg(win)
	local nbg = behind_bg()
	local map = { NormalFloat = "NormalFloat", FloatBorder = "FloatBorder", FloatTitle = "FloatTitle" }
	for from, to in vim.wo[win].winhighlight:gmatch("([^:,]+):([^,]+)") do
		map[from] = to:gsub("^BarissimoClear", "") -- por si ya se aplicó
	end
	local parts = {}
	for from, to in pairs(map) do
		local h = api.nvim_get_hl(0, { name = to, link = false })
		h.bg = nbg
		api.nvim_set_hl(0, "BarissimoClear" .. to, h)
		parts[#parts + 1] = from .. ":BarissimoClear" .. to
	end
	vim.wo[win].winhighlight = table.concat(parts, ",")
end

-- Buscador de archivos de snacks: recuadro con lista y preview, y debajo la búsqueda a todo
-- el ancho, ambos con bordes redondeados en degradado diagonal (de oscuro arriba-izq a claro
-- abajo-der). Arriba, la barra de marca con la carpeta actual. Usa el explorador de snacks:
-- árbol de archivos, Enter despliega carpetas y Backspace con la búsqueda vacía sube de carpeta.
-- ponytail: la barra no se recoloca si se redimensiona el editor con el buscador abierto
local function finder(snacks)
	local f = cfg.finder
	local from, to = grad(0.45, 1, { f.border_color, "#000000" }), grad(0.35, 1, { f.border_color, "#ffffff" })
	-- el fondo de lo que queda detrás, para que se funda con el editor
	local fbg = behind_bg()
	local edge = {}
	for i = 1, 5 do
		api.nvim_set_hl(0, "BarissimoEdge" .. i, { fg = grad((i - 1) / 4, 1, { from, to }), bg = fbg })
	end
	for i, ch in ipairs({ "╭", "─", "╮", "│", "╯", "─", "╰", "│" }) do
		edge[i] = { ch, "BarissimoEdge" .. ({ 1, 2, 3, 4, 5, 4, 3, 2 })[i] }
	end
	local bar
	local function close_bar()
		if bar and api.nvim_win_is_valid(bar) then
			api.nvim_win_close(bar, true)
		end
	end
	-- la barra va dentro del recuadro de arriba (la caja con el borde redondeado)
	local function show_bar(picker)
		close_bar()
		for _, w in pairs(picker.layout.box_wins) do
			local b = w.win and api.nvim_win_is_valid(w.win) and api.nvim_win_get_config(w.win).border
			if type(b) == "table" and type(b[1]) == "table" and b[1][1] == "╭" then
				bar = brand_bar(w.win, vim.fn.fnamemodify(picker:cwd(), ":~"))
			end
		end
	end
	-- explorador de snacks: árbol dibujado con iconos de carpeta; Enter despliega/pliega
	-- carpetas o abre el archivo (y cierra el buscador)
	snacks.picker.explorer({
		cwd = vim.fn.getcwd(),
		focus = "list", -- empieza en el árbol (modo normal); "/" salta a la búsqueda
		auto_close = true,
		jump = { close = true },
		actions = {
			-- Enter: un archivo se abre siempre (también buscando); una carpeta se despliega/pliega.
			-- Nombre propio: el explorador de snacks sobrescribe siempre la acción "confirm"
			barissimo_confirm = function(picker, item, action)
				if item and not item.dir then
					return snacks.picker.actions.jump(picker, item, action)
				end
				require("snacks.explorer.actions").actions.confirm(picker, item, action)
			end,
			-- Backspace sube a la carpeta padre; solo borra si se está escribiendo y hay texto
			barissimo_up = function(picker)
				if vim.fn.mode() == "i" and picker.input:get() ~= "" then
					return api.nvim_feedkeys(vim.keycode("<BS>"), "n", false)
				end
				require("snacks.explorer.actions").actions.explorer_up(picker)
				show_bar(picker)
			end,
		},
		win = {
			input = {
				keys = {
					["<BS>"] = { "barissimo_up", mode = { "i", "n" } },
					["<CR>"] = { "barissimo_confirm", mode = { "i", "n" } },
				},
			},
			list = { keys = { ["<BS>"] = "barissimo_up", ["<CR>"] = "barissimo_confirm" } },
		},
		layout = {
			preview = true, -- el explorador de snacks la oculta por defecto
			layout = {
				backdrop = false,
				box = "vertical",
				width = f.width,
				height = f.height,
				border = "none",
				{
					box = "horizontal",
					border = edge,
					{
						box = "horizontal",
						-- borde superior en blanco: reserva la fila donde se dibuja la barra de marca
						border = { "", " ", "", "", "", "", "", "" },
						{ win = "list", border = "none" },
						{ win = "preview", width = f.preview, border = "left" },
					},
				},
				{ win = "input", height = 1, border = edge }, -- búsqueda abajo, a todo el ancho
			},
		},
		on_show = function(picker)
			-- todas las ventanas del buscador con el fondo del editor
			local wins = vim.list_extend({ picker.layout.root }, vim.tbl_values(picker.layout.wins))
			for _, w in ipairs(vim.list_extend(wins, vim.tbl_values(picker.layout.box_wins))) do
				if w.win and api.nvim_win_is_valid(w.win) then
					clear_bg(w.win)
				end
			end
			show_bar(picker)
		end,
		on_close = close_bar,
	})
end

-- Botón "+": buscador flotante para elegir el archivo que se abre como pestaña nueva.
-- Usa tabs.on_new si está; si no, snacks, telescope o una lista simple
function M.new()
	leave_explorer()
	if cfg.tabs.on_new then
		return cfg.tabs.on_new()
	end
	local has_snacks, snacks = pcall(require, "snacks")
	if has_snacks and snacks.picker then
		return finder(snacks)
	end
	local has_tb, builtin = pcall(require, "telescope.builtin")
	if has_tb then
		return builtin.find_files()
	end
	-- ponytail: lista sin búsqueda difusa y con límite de 2000; para más, snacks o telescope
	local files = vim.fs.find(function(_, path)
		return not path:find("/%.")
	end, { type = "file", limit = 2000, path = vim.fn.getcwd() })
	vim.ui.select(files, {
		prompt = "Abrir archivo",
		format_item = function(f)
			return vim.fn.fnamemodify(f, ":.")
		end,
	}, function(f)
		if f then
			vim.cmd.edit(vim.fn.fnameescape(f))
		end
	end)
end

-- Botón de cerrar: pregunta si hay cambios y no cierra ninguna ventana
function M.close(buf)
	if not api.nvim_buf_is_valid(buf) then
		return
	end
	if vim.bo[buf].modified then
		local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
		local choice = vim.fn.confirm(
			("¿Guardar los cambios de %s?"):format(name ~= "" and name or "[sin nombre]"),
			"&Guardar\n&Descartar\n&Cancelar",
			3
		)
		if choice == 1 then
			local ok, err = pcall(api.nvim_buf_call, buf, function()
				vim.cmd.write()
			end)
			if not ok then
				return vim.notify("Barissimo: no se pudo guardar: " .. err, vim.log.levels.ERROR)
			end
		elseif choice ~= 2 then
			return
		end
	end
	-- en las ventanas que lo muestran, poner la pestaña vecina (o un buffer nuevo)
	local listed = vim.tbl_filter(function(b)
		return vim.bo[b].buflisted
	end, api.nvim_list_bufs())
	local repl
	for i, b in ipairs(listed) do
		if b == buf then
			repl = listed[i + 1] or listed[i - 1]
		end
	end
	repl = repl or api.nvim_create_buf(true, false)
	for _, w in ipairs(api.nvim_list_wins()) do
		if api.nvim_win_get_buf(w) == buf then
			api.nvim_win_set_buf(w, repl)
		end
	end
	api.nvim_buf_delete(buf, { force = true })
end

-- Tabline: tarjetas incrustadas sobre un degradado fucsia que cubre toda la fila
function M.tabline()
	local t = cfg.tabs
	local cur = api.nvim_get_current_buf()
	if vim.bo[cur].buflisted then
		st.cur = cur
	end
	local width = vim.o.columns
	local stops = gradient_of(cfg.bg_colors)
	-- fondo de las tarjetas por defecto: el del colorscheme (negro si el tema es transparente)
	local nbg = api.nvim_get_hl(0, { name = "Normal", link = false }).bg
	local card_bg = nbg and string.format("#%06x", nbg) or "#000000"
	local out, col = {}, 0
	local function fuchsia(c)
		return grad(c / math.max(width - 1, 1), 1, stops)
	end
	-- añade texto con sus colores; un grupo de highlight por combinación
	local function put(text, fg, bg, style)
		if text == "" then
			return
		end
		out[#out + 1] = "%#" .. hl_for(fg, bg, style) .. "#" .. (text:gsub("%%", "%%%%"))
		col = col + vim.fn.strdisplaywidth(text)
	end
	local pad = string.rep(" ", t.padding)
	local gap = string.rep(" ", t.gap)
	st.tabs = {}
	for _, b in ipairs(api.nvim_list_bufs()) do
		if vim.bo[b].buflisted then
			local name = vim.fn.fnamemodify(api.nvim_buf_get_name(b), ":t")
			if name == "" then
				name = "[sin nombre]"
			end
			local ic, icolor = file_icon(name)
			local active = b == st.cur
			-- fondo de la tarjeta: el del tema, o el color/lista dado degradado a lo ancho
			-- (un solo color va de su 70 % al 100 %, para que el texto se lea en toda la tarjeta)
			local bg_opt = active and t.active_bg or t.bg
			local card = type(bg_opt) == "string" and { grad(1, 0.7, { bg_opt, bg_opt }), bg_opt }
				or bg_opt
				or { card_bg, card_bg }
			local fg = active and t.active_fg or not active and t.fg or nil
			if not fg then
				fg = text_on(card[#card], hl_fg(active and "Normal" or "Comment"))
			end
			local label = " " .. name .. " "
			-- celda fija para el botón: × al pasar el ratón, ● si hay cambios (no mueve las pestañas)
			local slot = st.hover == b and t.close or vim.bo[b].modified and t.modified or " "
			local w = vim.fn.strdisplaywidth(pad .. ic .. label .. slot .. pad)
			local function cbg(k)
				return grad(k / math.max(w - 1, 1), 1, card)
			end
			local start, x = col, nil
			put(t.left, cbg(0), fuchsia(col))
			local k = 0
			local bold = active and t.active_bold and "b" or nil
			for _, part in ipairs({ { pad }, { ic, icolor }, { label, nil, bold }, { slot, nil, bold, true }, { pad } }) do
				if part[4] then
					x = col
				end
				for _, ch in ipairs(vim.fn.split(part[1], "\\zs")) do
					put(ch, part[2] or fg, cbg(k), part[3])
					k = k + vim.fn.strdisplaywidth(ch)
				end
			end
			put(t.right, cbg(w - 1), fuchsia(col))
			st.tabs[#st.tabs + 1] = { buf = b, col = start, w = col - start, x = x }
			for _ = 1, #gap do
				put(" ", nil, fuchsia(col))
			end
		end
	end
	-- tarjeta "+" con el estilo de las inactivas
	local nb = type(t.bg) == "table" and t.bg[1] or t.bg or card_bg
	local pstart = col
	put(t.left, nb, fuchsia(col))
	put(pad .. t.new .. pad, t.fg or text_on(nb, hl_fg("Comment")), nb)
	put(t.right, nb, fuchsia(col))
	st.plus = { col = pstart, w = col - pstart }
	-- resto de la fila: degradado y la marca al final si cabe
	strip(col, width, put)
	return table.concat(out)
end

local KEYS = "asdfghjklqwertyuiopzxcvbnm"
function M.pick()
	vim.cmd.redrawtabline()
	local p = cfg.picker
	local pad = string.rep(" ", p.padding)
	-- los extremos redondeados se funden con el fondo del editor que queda debajo
	local nbg = api.nvim_get_hl(0, { name = "Normal", link = false }).bg
	api.nvim_set_hl(0, "BarissimoPickCap", { fg = p.bg, bg = nbg })
	api.nvim_set_hl(0, "BarissimoPickKey", { fg = p.fg or text_on(p.bg, "#ffffff"), bg = p.bg, bold = true })
	local wins, map = {}, {}
	for i, t in ipairs(st.tabs) do
		local k = KEYS:sub(i, i)
		if k == "" or t.col + 5 > vim.o.columns then
			break
		end
		map[k] = t.buf
		local b = api.nvim_create_buf(false, true)
		vim.bo[b].bufhidden = "wipe"
		local key = pad .. k .. pad
		api.nvim_buf_set_lines(b, 0, -1, false, { p.left .. key .. p.right })
		api.nvim_buf_set_extmark(b, ns, 0, 0, { end_col = #p.left, hl_group = "BarissimoPickCap" })
		api.nvim_buf_set_extmark(b, ns, 0, #p.left, { end_col = #p.left + #key, hl_group = "BarissimoPickKey" })
		api.nvim_buf_set_extmark(b, ns, 0, #p.left + #key, { end_col = #p.left + #key + #p.right, hl_group = "BarissimoPickCap" })
		wins[#wins + 1] = api.nvim_open_win(b, false, {
			relative = "editor",
			row = 1, -- justo debajo de la tabline
			col = t.col,
			width = vim.fn.strdisplaywidth(p.left .. key .. p.right),
			height = 1,
			style = "minimal",
			focusable = false,
			zindex = 250,
		})
		vim.wo[wins[#wins]].winhl = "NormalFloat:Normal"
	end
	vim.cmd.redraw()
	local ok, c = pcall(vim.fn.getcharstr)
	for _, w in ipairs(wins) do
		api.nvim_win_close(w, true)
	end
	if ok and map[c] then
		M.select(map[c])
	end
end

-- Columna (0-based) del ratón si está sobre la tabline; nil si no.
-- Ojo: sobre la tabline getmousepos() da el winid de la ventana de debajo, no 0; solo vale la fila
local function tabline_col(p)
	local visible = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #api.nvim_list_tabpages() > 1)
	if visible and p.screenrow == 1 then
		return p.screencol - 1
	end
end

local function tab_at(c)
	for _, t in ipairs(st.tabs) do
		if c >= t.col and c < t.col + t.w then
			return t
		end
	end
end

-- Clic sobre la tabline: × cierra, + abre uno nuevo, la tarjeta cambia a ese buffer.
-- En cualquier otro sitio, clic normal
local function click()
	local c = tabline_col(vim.fn.getmousepos())
	if not c then
		return "<LeftMouse>"
	end
	if st.plus and c >= st.plus.col and c < st.plus.col + st.plus.w then
		return "<Cmd>lua require('barissimo').new()<CR>"
	end
	local t = tab_at(c)
	if not t then
		return "<Ignore>"
	end
	return ("<Cmd>lua require('barissimo').%s(%d)<CR>"):format(c == t.x and "close" or "select", t.buf)
end

-- Al pasar el ratón por una pestaña se muestra su botón de cerrar
local function hover()
	local c = tabline_col(vim.fn.getmousepos())
	local t = c and tab_at(c)
	local h = t and t.buf
	if h ~= st.hover then
		st.hover = h
		vim.cmd.redrawtabline()
	end
end

function M.setup(opts)
	cfg = vim.tbl_deep_extend("force", cfg, opts or {})
	set_hl()
	local group = api.nvim_create_augroup("Barissimo", {})
	api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })
	api.nvim_create_autocmd("BufModifiedSet", { group = group, command = "redrawtabline" })
	-- si solo queda el explorador, salir
	api.nvim_create_autocmd("WinEnter", {
		group = group,
		callback = function()
			if api.nvim_get_current_win() == st.win and not main_win() then
				vim.schedule(function()
					if not pcall(vim.cmd.qall) then
						vim.cmd("botright new")
					end
				end)
			end
		end,
	})
	vim.o.showtabline = 2
	vim.o.tabline = "%!v:lua.require'barissimo'.tabline()"
	vim.keymap.set("n", cfg.keys.toggle, M.toggle, { desc = "Explorador lateral" })
	vim.keymap.set("n", cfg.keys.pick, M.pick, { desc = "Saltar a pestaña" })
	for _, k in ipairs(type(cfg.keys.new) == "table" and cfg.keys.new or { cfg.keys.new }) do
		vim.keymap.set("n", k, M.new, { desc = "Abrir archivo en pestaña nueva" })
	end
	vim.keymap.set({ "n", "i" }, "<LeftMouse>", click, { expr = true, desc = "Clic en pestaña" })
	vim.o.mousemoveevent = true
	vim.keymap.set({ "n", "i" }, "<MouseMove>", hover, { desc = "Hover en pestañas" })
end

return M
