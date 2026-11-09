class_name UiTheme
## Builds the game's UI theme in code (font, panels, button styles, label variations).

const GOLD := Color("ffd166")
const CYAN := Color("7ff3ff")
const ORANGE := Color("ff9f43")
const PURPLE := Color("b48cff")
const INK := Color("120d2e")
const PANEL := Color(0.05, 0.035, 0.14, 0.92)
const MUTED := Color("b9a9ff")


static func build() -> Theme:
	var t := Theme.new()
	var font: Font = load("res://assets/fonts/Fredoka-SemiBold.woff2")
	if font:
		t.default_font = font
	t.default_font_size = 26

	# panels
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 28, 28, Color(1, 1, 1, 0.08), 2))

	# labels
	t.set_color("font_color", "Label", Color.WHITE)
	t.set_color("font_outline_color", "Label", INK)
	_label_var(t, "Title", 44, 8, Color.WHITE)
	_label_var(t, "Big", 40, 6, GOLD)
	_label_var(t, "Small", 20, 0, MUTED)
	_label_var(t, "Hud", 28, 8, Color.WHITE)
	_label_var(t, "CardName", 26, 0, Color.WHITE)

	# buttons
	_button_styles(t, "Button", Color("2a2060"), Color.WHITE)
	_button_var(t, "Primary", ORANGE, INK, 44)
	_button_var(t, "Ad", Color("123a52"), CYAN, 24)
	_button_var(t, "Special", Color("3d2470"), PURPLE, 24)
	_button_var(t, "Card", Color("1c1645"), Color.WHITE, 26)

	# fuel bar
	t.set_stylebox("background", "ProgressBar", _box(Color(0.04, 0.03, 0.12, 0.8), 14, 0))
	t.set_stylebox("fill", "ProgressBar", _box(ORANGE, 14, 0))
	return t


static func _box(c: Color, radius: int, pad: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.anti_aliasing = true
	return s


static func _label_var(t: Theme, name: String, size: int, outline: int, color: Color) -> void:
	t.set_type_variation(name, "Label")
	t.set_font_size("font_size", name, size)
	t.set_constant("outline_size", name, outline)
	t.set_color("font_color", name, color)


static func _button_styles(t: Theme, type: String, base: Color, text: Color) -> void:
	var normal := _box(base, 18, 14)
	normal.border_width_bottom = 6
	normal.border_color = base.darkened(0.45)
	var hover := normal.duplicate()
	hover.bg_color = base.lightened(0.12)
	var pressed := normal.duplicate()
	pressed.bg_color = base.darkened(0.12)
	pressed.border_width_bottom = 2
	pressed.content_margin_top = 18
	var disabled := normal.duplicate()
	disabled.bg_color = base.darkened(0.35)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, type, text)
	t.set_color("font_disabled_color", type, text.darkened(0.4))


static func _button_var(t: Theme, name: String, base: Color, text: Color, size: int) -> void:
	t.set_type_variation(name, "Button")
	_button_styles(t, name, base, text)
	t.set_font_size("font_size", name, size)
