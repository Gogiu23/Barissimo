# Barissimo

Explorador lateral con iconos, tabline con tarjetas redondeadas incrustadas sobre un degradado fucsia y selector rápido de pestañas con popups de borde en degradado azul.

## Instalación (lazy.nvim)

```lua
{
	"Gogiu23/Barissimo",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	lazy = false,
	opts = {
		width = 30,
		keys = { toggle = "<leader>E", pick = "<M-Space>", new = { "<C-+>", "<C-=>" } },
		-- degradado azul: carpetas del explorador y su separador
		colors = { "#0a1f4d", "#123a8a", "#1f62c4", "#3d8cf0", "#86c5ff" },
		-- fondo de toda la tabline: lista de tonos o un solo color ("#d6249f") para degradarlo automáticamente
		bg_colors = { "#3a0b2e", "#5e1048", "#86165f", "#b01c84", "#d6249f" },
		brand = "Barissimo", -- "" para ocultarla
		brand_color = "#ffffff",
		tabs = {
			left = "\u{e0b6}", -- extremo izquierdo: redondeado; "\u{e0b2}" flecha; "" recto
			right = "\u{e0b4}", -- extremo derecho: redondeado; "\u{e0b0}" flecha; "" recto
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
		-- popups del selector (<M-Space>): píldoras con la letra de cada pestaña
		picker = {
			left = "\u{e0b6}",
			right = "\u{e0b4}",
			padding = 1,
			bg = "#86c5ff",
			fg = nil, -- nil = automático (oscuro si el fondo es claro)
		},
		-- buscador del "+" (snacks): bordes redondeados en degradado, preview y barra de marca arriba
		finder = {
			width = 0.8, -- fracción del editor
			height = 0.7,
			preview = 0.55, -- ancho de la preview dentro del buscador
			border_color = "#FFDE7D", -- degradado diagonal de su tono oscuro a su tono claro
		},
	},
}
```

## Uso

- `<leader>E`: abrir/cerrar explorador. Dentro: `<CR>`/`l` abrir, `-` subir, `R` refrescar, `q` cerrar.
- `<M-Space>`: popup con letra en cada pestaña; pulsa la letra para saltar.
- `<C-+>` (o `<C-=>`): abre el buscador de archivos, igual que el `+`. El buscador abre en el árbol de archivos (modo normal): `j`/`k` o flechas para moverse, `Enter` abre el archivo o despliega/pliega la carpeta, `Backspace` sube a la carpeta padre y `/` salta a la búsqueda (ahí `Backspace` borra mientras escribes). En el árbol funcionan también los atajos del explorador de snacks (`a` crear, `r` renombrar, `d` borrar…).
- Ratón: clic en una pestaña para cambiar a ella; al pasar por encima aparece una ×, clic para cerrarla (pregunta si hay cambios sin guardar); clic en `+` abre un buscador flotante para elegir el archivo que se abre en una pestaña nueva. Activa `mousemoveevent`.

Requiere una Nerd Font para los iconos y los extremos redondeados.
En macOS la terminal debe enviar Option como Alt (Alacritty: `option_as_alt = "Both"`, kitty: `macos_option_as_alt yes`).
Sustituye la tabline: desactiva barbar/bufferline si los usas.
