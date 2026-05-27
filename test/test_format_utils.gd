extends "res://test/test_base.gd"

## FormatUtils tests — sentence-case currency / board naming and number
## formatting. Run with:
##   godot --headless --scene res://test/test_format_utils.tscn


func _run_tests() -> void:
	print("\n=== FormatUtils Tests ===\n")
	test_currency_name_single_word()
	test_currency_name_multi_word_sentence_case()
	test_currency_name_lowercase()
	test_board_name_capitalization()
	test_format_number_thresholds()


func test_currency_name_single_word() -> void:
	print("test_currency_name_single_word")
	assert_equal(FormatUtils.currency_name(Enums.CurrencyType.GOLD_COIN), "Gold", "GOLD_COIN → Gold")


func test_currency_name_multi_word_sentence_case() -> void:
	# Regression: previously used String.capitalize() which Title-Cases every
	# word, producing "Raw Orange". The sentence-case helper preserves the
	# lowercase second word: "Raw orange".
	print("test_currency_name_multi_word_sentence_case")
	assert_equal(FormatUtils.currency_name(Enums.CurrencyType.RAW_ORANGE), "Raw orange", "RAW_ORANGE → Raw orange (not Raw Orange)")


func test_currency_name_lowercase() -> void:
	print("test_currency_name_lowercase")
	assert_equal(FormatUtils.currency_name(Enums.CurrencyType.RAW_ORANGE, false), "raw orange", "capital=false → all lower")


func test_board_name_capitalization() -> void:
	print("test_board_name_capitalization")
	assert_equal(FormatUtils.board_name(Enums.BoardType.GOLD), "Gold", "GOLD → Gold")
	assert_equal(FormatUtils.board_name(Enums.BoardType.GOLD, false), "gold", "capital=false → gold")


func test_format_number_thresholds() -> void:
	print("test_format_number_thresholds")
	assert_equal(FormatUtils.format_number(500), "500", "<1K stays raw")
	assert_equal(FormatUtils.format_number(1500), "1.5K", "1.5K with one decimal under 10")
	assert_equal(FormatUtils.format_number(15000), "15K", "15K whole at >=10")
	assert_equal(FormatUtils.format_number(2_300_000), "2.3M", "2.3M with decimal under 10")
