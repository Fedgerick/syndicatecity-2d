extends Node

## Settings menu — volume sliders, keybind toggles, screen size, audio on/off.
## Built as a standalone Node so it doesn't bloat main.gd further.
## Pressed O in-game to open; 0 or Esc to close.

var settings_cl: CanvasLayer
var settings_open: bool = false

# References back to the parent's mutable state so sliders reflect reality
var parent_node: Node = null

func _ready() -> void:
    pass

func toggle() -> void:
    if settings_open:
        close()
    else:
        open()

func open() -> void:
    if settings_cl:
        settings_cl.visible = true
        settings_open = true
        return
    settings_cl = CanvasLayer.new()
    settings_cl.layer = 15
    get_parent().add_child(settings_cl)

    var bg := ColorRect.new()
    bg.color = Color(0.02, 0.05, 0.10, 0.95)
    bg.size = Vector2(560, 480)
    bg.position = Vector2(360, 120)
    settings_cl.add_child(bg)

    var title := Label.new()
    title.text = "SETTINGS"
    title.position = Vector2(570, 135)
    title.add_theme_font_size_override("font_size", 32)
    title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
    settings_cl.add_child(title)

    # BGM volume
    var lbl1 := Label.new()
    lbl1.text = "Music Volume"
    lbl1.position = Vector2(380, 190)
    lbl1.add_theme_font_size_override("font_size", 18)
    lbl1.add_theme_color_override("font_color", Color(0.9, 0.95, 1))
    settings_cl.add_child(lbl1)
    var sld1 := HSlider.new()
    sld1.min_value = 0.0
    sld1.max_value = 1.0
    sld1.step = 0.01
    sld1.value = _get_parent().bgm_volume
    sld1.size = Vector2(200, 30)
    sld1.position = Vector2(540, 185)
    sld1.value_changed.connect(func(v):
        _get_parent().bgm_volume = v
        if _get_parent().bgm_player:
            _get_parent().bgm_player.volume_db = linear_to_db(v * _get_parent().bgm_weather_mod)
    )
    settings_cl.add_child(sld1)

    # Audio on/off
    var lbl2 := Label.new()
    lbl2.text = "Audio On/Off"
    lbl2.position = Vector2(380, 240)
    lbl2.add_theme_font_size_override("font_size", 18)
    lbl2.add_theme_color_override("font_color", Color(0.9, 0.95, 1))
    settings_cl.add_child(lbl2)
    var chk := CheckButton.new()
    chk.position = Vector2(560, 235)
    chk.size = Vector2(40, 30)
    chk.button_pressed = _get_parent().audio_on
    chk.toggled.connect(func(on):
        _get_parent().audio_on = on
    )
    settings_cl.add_child(chk)

    # Screen size
    var lbl3 := Label.new()
    lbl3.text = "Resolution"
    lbl3.position = Vector2(380, 290)
    lbl3.add_theme_font_size_override("font_size", 18)
    lbl3.add_theme_color_override("font_color", Color(0.9, 0.95, 1))
    settings_cl.add_child(lbl3)
    var opt := OptionButton.new()
    opt.position = Vector2(520, 285)
    opt.size = Vector2(180, 30)
    opt.add_item("640x360")
    opt.add_item("854x480")
    opt.add_item("1280x720")
    opt.add_item("1600x900")
    opt.add_item("1920x1080")
    opt.select(2)  # default 1280x720
    opt.item_selected.connect(func(idx):
        var sizes := [Vector2i(640,360), Vector2i(854,480), Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]
        get_tree().root.content_scale_size = sizes[idx]
        get_tree().root.content_scale_mode = Window(ContentScaleMode.SCALE_MODE_FRACTIONAL)
    )
    settings_cl.add_child(opt)

    # Keybinds info
    var lbl4 := Label.new()
    lbl4.text = "Keybinds (in-game)\nWASD = move  F = vehicle  E = enter\nSpace = shoot  1-5 = tools  B = store\nTAB = stats  P = pause  O = this menu\n[/] = tax rate  +/- = speed  N = weather\nF5/F9 = save/load  M = mission"
    lbl4.position = Vector2(380, 340)
    lbl4.add_theme_font_size_override("font_size", 14)
    lbl4.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
    settings_cl.add_child(lbl4)

    # Close button
    var close_btn := Button.new()
    close_btn.text = "[0] Close"
    close_btn.position = Vector2(560, 430)
    close_btn.size = Vector2(120, 36)
    close_btn.add_theme_font_size_override("font_size", 16)
    close_btn.pressed.connect(func(): close())
    settings_cl.add_child(close_btn)

    settings_open = true

func close() -> void:
    if settings_cl:
        settings_cl.visible = false
    settings_open = false

func _get_parent() -> Node:
    return get_parent()