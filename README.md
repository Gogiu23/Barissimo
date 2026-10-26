# Barissimo

Explorador lateral con iconos, tabline de buffers y selector rápido de pestañas con popups de borde en degradado azul.

## Instalación (lazy.nvim)

```lua
{
	"Gogiu23/Barissimo",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	lazy = false,
	opts = {
		width = 30,
		keys = { toggle = "<leader>E", pick = "<M-Space>" },
		colors = { "#0a1f4d", "#123a8a", "#1f62c4", "#3d8cf0", "#86c5ff" },
	},
}
```

## Uso

- `<leader>E`: abrir/cerrar explorador. Dentro: `<CR>`/`l` abrir, `-` subir, `R` refrescar, `q` cerrar.
- `<M-Space>`: popup con letra en cada pestaña; pulsa la letra para saltar.

En macOS la terminal debe enviar Option como Alt (Alacritty: `option_as_alt = "Both"`, kitty: `macos_option_as_alt yes`).
Sustituye la tabline: desactiva barbar/bufferline si los usas.
