extends Control

const DEFAULT_WORDS := [
	{"en": "apple", "ru": "яблоко"},
	{"en": "dog", "ru": "собака"},
	{"en": "cat", "ru": "кошка"},
	{"en": "house", "ru": "дом"},
	{"en": "car", "ru": "машина"},
	{"en": "water", "ru": "вода"},
	{"en": "milk", "ru": "молоко"},
	{"en": "book", "ru": "книга"},
	{"en": "red", "ru": "красный"},
	{"en": "green", "ru": "зелёный"},
	{"en": "happy", "ru": "счастливый"},
	{"en": "quick", "ru": "быстрый"}
]

# Сколько правильных слов нужно найти.
@export var target_score := 10

# Сколько секунд даётся на игру.
@export var game_time := 60.0

# Скорость падения слов.
# Если поставить 0, слова не будут падать.
@export var fall_speed := 14.0

# Если true, слова появляются сверху и падают.
# Если false, слова появляются в случайном месте.
@export var spawn_from_top := true

# Штраф за неправильный ответ.
@export var wrong_penalty := 3.0

# Штраф, если правильное слово улетело вниз.
@export var miss_penalty := 4.0

# Можно подключить свой файл слов.
# Если файла нет, будут использоваться DEFAULT_WORDS.
@export var words_file := "res://words.json"

var words: Array = []
var time_left := 0.0
var score := 0
var is_running := false
var current_pair: Dictionary = {}
var falling_buttons: Array = []

@onready var target_label: Label = %TargetWordLabel
@onready var info_label: Label = %InfoLabel
@onready var play_area: Control = %PlayArea
@onready var message_label: Label = %MessageLabel


func _ready() -> void:
	randomize()

	words = load_words(words_file)

	if words.is_empty():
		words = DEFAULT_WORDS

	time_left = game_time

	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.text = "Нажми, чтобы начать"

	update_hud()


func _input(event: InputEvent) -> void:
	if is_running:
		return

	var pressed := false

	if event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT

	if pressed:
		start_game()


func _process(delta: float) -> void:
	if not is_running:
		return

	time_left -= delta

	if time_left <= 0.0:
		time_left = 0.0
		update_hud()
		end_game(false)
		return

	update_hud()

	if fall_speed <= 0.0:
		return

	var bottom_y := play_area.size.y + 60.0

	for button in falling_buttons.duplicate():
		if not is_instance_valid(button):
			falling_buttons.erase(button)
			continue

		button.position.y += fall_speed * delta

		if button.position.y > bottom_y:
			if button.get_meta("is_correct", false):
				on_correct_missed()
				return
			else:
				falling_buttons.erase(button)
				button.queue_free()


func load_words(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return []

	var text := file.get_as_text()
	var json := JSON.new()

	if json.parse(text) != OK:
		return []

	var data = json.data

	if not (data is Array):
		return []

	var result: Array = []

	for item in data:
		if item is Dictionary and item.has("en") and item.has("ru"):
			result.append(item)

	return result


func start_game() -> void:
	if words.is_empty():
		message_label.text = "Нет слов для игры. Добавь words.json или словарь в скрипт."
		message_label.show()
		return

	score = 0
	time_left = game_time
	is_running = true

	message_label.hide()

	update_hud()
	next_round()


func next_round() -> void:
	if score >= target_score:
		end_game(true)
		return

	clear_buttons()

	current_pair = words[randi() % words.size()]
	target_label.text = str(current_pair.get("en", "???"))

	call_deferred("spawn_round_buttons")


func spawn_round_buttons() -> void:
	#print("spaw_round_buttons вызван, is_running = ", is_running)
	if not is_running:
		return

	var correct_text := str(current_pair.get("ru", "???"))
	#print("correcttext имеет -  ", correct_text)
	var wrong_text := get_random_wrong_translation(correct_text)
	#print("wrong_text имеет -", wrong_text)

	var correct_button := make_word_button(correct_text, true)
	#print("correct_button имеет - ", correct_button)
	var wrong_button := make_word_button(wrong_text, false)

	play_area.add_child(correct_button)
	play_area.add_child(wrong_button)

	falling_buttons = [correct_button, wrong_button]

	place_buttons()


func make_word_button(text: String, is_correct: bool) -> Button:
	var button := Button.new()

	button.text = text
	button.custom_minimum_size = Vector2(220, 76)
	button.size = Vector2(220, 76)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP

	button.set_meta("is_correct", is_correct)

	button.add_theme_font_size_override("font_size", 28)

	button.pressed.connect(_on_word_button_pressed.bind(button))

	return button


func place_buttons() -> void:
	if falling_buttons.size() < 2:
		return

	var area_size := play_area.size

	if area_size.x < 10.0 or area_size.y < 10.0:
		area_size = get_viewport().get_visible_rect().size

	var margin := 100.0
	var button_size := Vector2(220, 76)

	var min_x := margin
	var max_x = max(margin, area_size.x - button_size.x - margin)

	var x1 := randf_range(min_x, max_x)
	var x2 := randf_range(min_x, max_x)

	var attempts := 0

	while absf(x1 - x2) < button_size.x + 16.0 and attempts < 20:
		x2 = randf_range(min_x, max_x)
		attempts += 1

	var y1 = 0.0
	var y2 = 0.0

	if spawn_from_top:
		y1 = 40.0
		y2 = 40.0
	else:
		var min_y := 12.0
		var max_y = max(min_y, area_size.y - button_size.y - 12.0)

		y1 = randf_range(min_y, max_y)
		y2 = randf_range(min_y, max_y)

		attempts = 0

		while absf(y1 - y2) < button_size.y + 16.0 and attempts < 20:
			y2 = randf_range(min_y, max_y)
			attempts += 1

	falling_buttons[0].position = Vector2(x1, y1)
	falling_buttons[1].position = Vector2(x2, y2)


func get_random_wrong_translation(correct_translation: String) -> String:
	var options: Array = []

	for item in words:
		var ru := str(item.get("ru", ""))

		if ru != correct_translation and ru != "":
			options.append(ru)

	if options.is_empty():
		return "ошибка"

	return options[randi() % options.size()]


func _on_word_button_pressed(button: Button) -> void:
	if not is_running or not is_instance_valid(button):
		return

	if button.get_meta("is_correct", false):
		score += 1
		flash(target_label, Color(0.2, 0.9, 0.35))
		next_round()
	else:
		time_left -= wrong_penalty
		button.disabled = true
		flash(button, Color(1.0, 0.3, 0.3))

		update_hud()

		if time_left <= 0.0:
			time_left = 0.0
			update_hud()
			end_game(false)


func on_correct_missed() -> void:
	if not is_running:
		return

	time_left -= miss_penalty

	flash(target_label, Color(1.0, 0.35, 0.3))

	update_hud()

	if time_left <= 0.0:
		time_left = 0.0
		update_hud()
		end_game(false)
		return

	next_round()


func clear_buttons() -> void:
	for button in falling_buttons:
		if is_instance_valid(button):
			button.queue_free()

	falling_buttons.clear()


func update_hud() -> void:
	var seconds_left = max(0, int(ceil(time_left)))
	info_label.text = "Счёт: %d/%d   Время: %d" % [score, target_score, seconds_left]


func flash(control: Control, color: Color) -> void:
	if not is_instance_valid(control):
		return

	control.modulate = color

	get_tree().create_timer(0.18).timeout.connect(_reset_modulate.bind(control))


func _reset_modulate(control: Control) -> void: # при неправильном ответе выдает ошибку что нет аргумента - разобраться!!! 
	if is_instance_valid(control):
		control.modulate = Color.WHITE


func end_game(win: bool) -> void: 
	is_running = false

	clear_buttons()

	if win:
		message_label.text = "Победа! Ты нашёл нужное количество слов."
	else:
		message_label.text = "Время вышло. Счёт: %d/%d\nНажми, чтобы попробовать снова." % [score, target_score]

	message_label.show()
