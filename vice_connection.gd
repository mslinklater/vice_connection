extends Node
class_name ViceConnection

var vice_info = ""

var _binary_connection: ViceSocketConnection
var _monitor_connection: ViceSocketConnection

var _binary_connected: bool
var _monitor_connected: bool

var _registers_available = {}
var _banks_available = {}

enum ECommand { 
	MON_COMMAND_MEMORY_GET = 0x01,
	MON_COMMAND_MEMORY_SET = 0x02,
	MON_COMMAND_CHECKPOINT_GET = 0x11,
	MON_COMMAND_CHECKPOINT_SET = 0x12,
	MON_COMMAND_CHECKPOINT_DELETE = 0x13,
	MON_COMMAND_CHECKPOINT_LIST = 0x14,
	MON_COMMAND_CHECKPOINT_TOGGLE = 0x15,
	MON_COMMAND_CONDITION_SET = 0x22,
	MON_COMMAND_REGISTERS_GET = 0x31,			# DONE
	MON_COMMAND_REGISTERS_SET = 0x32,
	MON_COMMAND_DUMP = 0x41,
	MON_COMMAND_UNDUMP = 0x42,
	MON_COMMAND_RESOURCE_GET = 0x51,
	MON_COMMAND_RESOURCE_SET = 0x52,
	MON_COMMAND_ADVANCE_INSTRUCTIONS = 0x71,
	MON_COMMAND_KEYBOARD_FEED = 0x72,
	MON_COMMAND_EXECUTE_UNTIL_RETURN = 0x73,
	MON_COMMAND_PING = 0x81,					# DONE
	MON_COMMAND_BANKS_AVAILABLE = 0x82,			# DONE
	MON_COMMAND_REGISTERS_AVAILABLE = 0x83,		# DONE
	MON_COMMAND_DISPLAY_GET = 0x84,
	MON_COMMAND_VICE_INFO = 0x85,				# DONE
	MON_COMMAND_PALETTE_GET = 0x91,
	MON_COMMAND_JOYPORT_SET = 0xa2,
	MON_COMMAND_USERPORT_SET = 0xb2,
	MON_COMMAND_EXIT = 0xaa,
	MON_COMMAND_QUIT = 0xbb,
	MON_COMMAND_RESET = 0xcc,
	MON_COMMAND_AUTOSTART_AUTOLOAD = 0xdd
}

var _commands_in_flight = {}

enum EResponse {
	MON_RESPONSE_INVALID = 0x00,
	MON_RESPONSE_MEM_GET = 0x01,
	MON_RESPONSE_MEM_SET = 0x02,
	MON_RESPONSE_CHECKPOINT_INFO = 0x11,
	MON_RESPONSE_CHECKPOINT_DELETE = 0x13,
	MON_RESPONSE_CHECKPOINT_LIST = 0x14,
	MON_RESPONSE_CHECKPOINT_TOGGLE = 0x15,
	MON_RESPONSE_CONDITION_SET = 0x22,
	MON_RESPONSE_REGISTER_INFO = 0x31,
	MON_RESPONSE_DUMP = 0x41,
	MON_RESPONSE_UNDUMP = 0x42,
	MON_RESPONSE_RESOURCE_GET = 0x51,
	MON_RESPONSE_RESOURCE_SET = 0x52,
	MON_RESPONSE_JAM = 0x61,
	MON_RESPONSE_STOPPED = 0x62,
	MON_RESPONSE_RESUMED = 0x63,
	MON_RESPONSE_ADVANCE_INSTRUCTIONS = 0x71,
	MON_RESPONSE_KEYBOARD_FEED = 0x72,
	MON_RESPONSE_EXECUTE_UNTIL_RETURN = 0x73,
	MON_RESPONSE_PING = 0x81,
	MON_RESPONSE_BANKS_AVAILABLE = 0x82,
	MON_RESPONSE_REGISTERS_AVAILABLE = 0x83,
	MON_RESPONSE_DISPLAY_GET = 0x84,
	MON_RESPONSE_VICE_INFO = 0x85,
	MON_RESPONSE_PALETTE_GET = 0x91,
	MON_RESPONSE_JOYPORT_SET = 0xa2,
	MON_RESPONSE_EXIT = 0xaa,
	MON_RESPONSE_USERPORT_SET = 0xb2,
	MON_RESPONSE_QUIT = 0xbb,
	MON_RESPONSE_RESET = 0xcc,
	MON_RESPONSE_AUTOSTART = 0xdd
}

signal signal_connected()
signal signal_data()
signal signal_disconnected()
signal signal_monitor_input()
signal signal_error()
signal signal_log()

func _ready():
	_binary_connection = ViceSocketConnection.new()
	add_child(_binary_connection)
	_binary_connection.signal_connected.connect(_on_binary_connected)
	_binary_connection.signal_data.connect(_on_binary_received_data)
	_binary_connection.signal_disconnected.connect(_on_binary_disconnected)
	_binary_connection.signal_error.connect(_on_binary_error)
	_binary_connection.signal_log.connect(_on_binary_log)
	_binary_connected = false

	_monitor_connection = ViceSocketConnection.new()
	add_child(_monitor_connection)
	_monitor_connection.signal_connected.connect(_on_monitor_connected)
	_monitor_connection.signal_data.connect(_on_monitor_received_data)
	_monitor_connection.signal_disconnected.connect(_on_monitor_disconnected)
	_monitor_connection.signal_error.connect(_on_monitor_error)
	_monitor_connection.signal_log.connect(_on_monitor_log)
	_monitor_connected = false
	
	_commands_in_flight[ECommand.MON_COMMAND_REGISTERS_AVAILABLE] = false
	_commands_in_flight[ECommand.MON_COMMAND_BANKS_AVAILABLE] = false

func _process(_delta):
	if _binary_connected:
		if vice_info.length() == 0:
			vice_info = "PENDING"
			command_vice_info()
		if _registers_available.size() == 0:
			command_registers_available()
		if _banks_available.size() == 0:
			command_banks_available()
	return

# Monitor connection signals

func _on_monitor_connected():
	_monitor_connected = true

func _on_monitor_disconnected():
	_monitor_connected = false

func _on_monitor_error(message: String):
	signal_error.emit("ERROR:" + message)

func _on_monitor_received_data(data: PackedByteArray):
	var data_string: String = data.get_string_from_ascii()
	signal_monitor_input.emit(data_string)

func _on_monitor_log(message: String):
	print(message)

# Binary connection signals

func _on_binary_connected():
	_binary_connected = true
	signal_connected.emit()

func _on_binary_disconnected():
	_binary_connected = false
	signal_disconnected.emit()
	
func _on_binary_error(message: String):
	signal_error.emit("ERROR:" + message)

func _on_binary_log(message: String):
	print(message)

func _on_binary_received_data(data: PackedByteArray):
	var offset = 0
	while offset < data.size():
		print("----")
		# Check for partial packet
		if data.size() > 2:
			var response_size = get_long_from_data(data, offset + 2) + 12
			if offset + response_size > data.size():
				print("ERROR - partial packet")
				return
		var info = get_response_info(data, offset)
		match info:
			EResponse.MON_RESPONSE_INVALID:
				response_invalid(data)
			EResponse.MON_RESPONSE_MEM_GET:
				response_todo(data)
			EResponse.MON_RESPONSE_MEM_SET:
				response_todo(data)
			EResponse.MON_RESPONSE_CHECKPOINT_INFO:
				response_todo(data)
			EResponse.MON_RESPONSE_CHECKPOINT_DELETE:
				response_todo(data)
			EResponse.MON_RESPONSE_CHECKPOINT_LIST:
				response_todo(data)
			EResponse.MON_RESPONSE_CHECKPOINT_TOGGLE:
				response_todo(data)
			EResponse.MON_RESPONSE_CONDITION_SET:
				response_todo(data)
			EResponse.MON_RESPONSE_REGISTER_INFO:
				response_register_info(data, offset)
			EResponse.MON_RESPONSE_DUMP:
				response_todo(data)
			EResponse.MON_RESPONSE_UNDUMP:
				response_todo(data)
			EResponse.MON_RESPONSE_RESOURCE_GET:
				response_todo(data)
			EResponse.MON_RESPONSE_RESOURCE_SET:
				response_todo(data)
			EResponse.MON_RESPONSE_JAM:
				response_todo(data)
			EResponse.MON_RESPONSE_STOPPED:
				response_stopped(data, offset)
			EResponse.MON_RESPONSE_RESUMED:
				response_todo(data)
			EResponse.MON_RESPONSE_ADVANCE_INSTRUCTIONS:
				response_todo(data)
			EResponse.MON_RESPONSE_KEYBOARD_FEED:
				response_todo(data)
			EResponse.MON_RESPONSE_EXECUTE_UNTIL_RETURN:
				response_todo(data)
			EResponse.MON_RESPONSE_PING:
				response_ping(data, offset)
			EResponse.MON_RESPONSE_BANKS_AVAILABLE:
				response_banks_available(data, offset)
			EResponse.MON_RESPONSE_REGISTERS_AVAILABLE:
				response_registers_available(data, offset)
			EResponse.MON_RESPONSE_DISPLAY_GET:
				response_todo(data)
			EResponse.MON_RESPONSE_VICE_INFO:
				response_vice_info(data, offset)
			EResponse.MON_RESPONSE_PALETTE_GET:
				response_todo(data)
			EResponse.MON_RESPONSE_JOYPORT_SET:
				response_todo(data)
			EResponse.MON_RESPONSE_EXIT:
				response_todo(data)
			EResponse.MON_RESPONSE_USERPORT_SET:
				response_todo(data)
			EResponse.MON_RESPONSE_QUIT:
				response_todo(data)
			EResponse.MON_RESPONSE_RESET:
				response_todo(data)
			EResponse.MON_RESPONSE_AUTOSTART:
				response_todo(data)
		var response_size = get_long_from_data(data, offset + 2) + 12
		offset += response_size

func get_response_info(data: PackedByteArray, offset: int) -> EResponse:
	if data[offset] != 0x02:
		return EResponse.MON_RESPONSE_INVALID
	if data[offset + 1] != 0x02:
		return EResponse.MON_RESPONSE_INVALID
	if data[offset + 7] != 0x00:
		return EResponse.MON_RESPONSE_INVALID
	return data[offset + 6] as EResponse

func is_host_connected() -> bool:
	return _binary_connected

func host_connect():
	if !_binary_connection.is_connected_to_host():
		_binary_connection.connect_to_host("127.0.0.1", 6502)
	if !_monitor_connection.is_connected_to_host():
		_monitor_connection.connect_to_host("127.0.0.1", 6510)

func host_disconnect():
	if _binary_connection.is_connected_to_host():
		_binary_connection.disconnect_from_host()
	if _monitor_connection.is_connected_to_host():
		_monitor_connection.disconnect_from_host()

func monitor_send(command: PackedByteArray):
	command.append(13)
	command.append(10)
	_monitor_connection.send(command)

# Commands

func build_command(command_type: ECommand) -> PackedByteArray:
	var data = PackedByteArray()
	data.append(0x02)
	data.append(0x02)
	
	data.append(0x01)	#size
	data.append(0x00)
	data.append(0x00)
	data.append(0x00)

	data.append(0x00)	#id
	data.append(0x00)
	data.append(0x00)
	data.append(0x00)
	
	data.append(command_type)	# command
	data.append(0x00)	# unit
	return data

func command_banks_available():
	if	_commands_in_flight[ECommand.MON_COMMAND_BANKS_AVAILABLE] == true:
		return
	_commands_in_flight[ECommand.MON_COMMAND_BANKS_AVAILABLE] = true
	var data = build_command(ECommand.MON_COMMAND_BANKS_AVAILABLE)
	_binary_connection.send(data)

func command_memory_get(start: int, end: int):
	var data = build_command(ECommand.MON_COMMAND_MEMORY_GET)
	_binary_connection.send(data)

func command_ping():
	var data = build_command(ECommand.MON_COMMAND_PING)
	_binary_connection.send(data)

func command_registers_available():
	if	_commands_in_flight[ECommand.MON_COMMAND_REGISTERS_AVAILABLE] == true:
		return
	_commands_in_flight[ECommand.MON_COMMAND_REGISTERS_AVAILABLE] = true
	var data = build_command(ECommand.MON_COMMAND_REGISTERS_AVAILABLE)
	_binary_connection.send(data)

func command_registers_get():
	var data = build_command(ECommand.MON_COMMAND_REGISTERS_GET)
	_binary_connection.send(data)

func command_vice_info():
	var data = build_command(ECommand.MON_COMMAND_VICE_INFO)
	_binary_connection.send(data)

# Responses

func response_banks_available(data: PackedByteArray, offset: int):
	print("MON_RESPONSE_BANKS_AVAILABLE")
	_commands_in_flight[ECommand.MON_COMMAND_BANKS_AVAILABLE] = false
	var response_length = get_long_from_data(data, 2 + offset)
	var data_offset = offset + 12
	var num_entries = get_short_from_data(data, data_offset)
	data_offset += 2
	for i in range(num_entries):
		var item_size = data[data_offset]
		var new_bank = ViceConnectionBank.new()
		new_bank.bank_id = get_short_from_data(data, data_offset + 1)
		var name_length = data[data_offset + 3]
		new_bank.bank_name = data.slice(data_offset + 4, data_offset + 4 + name_length).get_string_from_ascii()
		_banks_available[new_bank.bank_id] = new_bank
		print(" bank:" + new_bank.bank_name + ":" + str(new_bank.bank_id))
		data_offset += item_size + 1

func response_invalid(_data: PackedByteArray):
	pass

func response_stopped(_data: PackedByteArray, _offset: int):
	print("MON_RESPONSE_STOPPED")

func response_todo(_data):
	print("RESPONSE_TODO")

func response_registers_available(data: PackedByteArray, offset: int):
	print("MON_RESPONSE_REGISTERS_AVAILABLE")
	var response_length = get_long_from_data(data, 2 + offset)
	var data_offset = offset + 12
	var num_entries = get_short_from_data(data, data_offset)
	data_offset += 2
	for i in range(num_entries):
		var item_size = data[data_offset]
		var new_reg = ViceConnectionRegister.new()
		new_reg.reg_id = data[data_offset + 1]
		new_reg.num_bits = data[data_offset + 2]
		var name_length = data[data_offset + 3]
		new_reg.reg_name = data.slice(data_offset + 4, data_offset + 4 + name_length).get_string_from_ascii()
		print(" " + new_reg.reg_name + ":" + str(new_reg.num_bits))
		data_offset += item_size + 1
		_registers_available[new_reg.reg_id] = new_reg
	_commands_in_flight[ECommand.MON_COMMAND_REGISTERS_AVAILABLE] = false
	command_registers_get()

func response_register_info(data: PackedByteArray, offset: int):
	print("MON_RESPONSE_REGISTER_INFO")
	if _registers_available.size() == 0:
		return
	var _request_id = get_long_from_data(data, 8 + offset)
	var register_count = get_short_from_data(data, 12 + offset)
	var registers_offset = 14 + offset	# beginning of register data
	for i in range(0, register_count):
		var item_size = data[registers_offset]
		var register_id = data[registers_offset + 1]
		var register_value = get_short_from_data(data, registers_offset + 2)
		_registers_available[register_id].value = register_value
		registers_offset += item_size + 1
		print(" reg:" + _registers_available[register_id].reg_name + " = " + str(register_value))
	pass

func response_vice_info(data: PackedByteArray, offset: int):
	print("MON_RESPONSE_VICE_INFO")
	var version_length = data[offset + 12]
	var version_string = ""
	for i in range(version_length):
		version_string += str(data[13 + i + offset])
		if i < version_length - 1:
			version_string += "."
	print("Vice info:" + version_string)
	vice_info = version_string

func response_ping(data: PackedByteArray, offset: int):
	print("MON_RESPONSE_PING")
	
# Utilities

func get_long_from_data(data: PackedByteArray, offset: int) -> int:
	var ret = data[offset]
	ret += data[offset + 1] << 8
	ret += data[offset + 2] << 16
	ret += data[offset + 3] << 24
	return ret

func get_short_from_data(data: PackedByteArray, offset: int) -> int:
	var ret = data[offset]
	ret += data[offset + 1] << 8
	return ret
