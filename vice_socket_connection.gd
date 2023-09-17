extends Node
class_name ViceSocketConnection

signal signal_connected()
signal signal_data()
signal signal_disconnected()
signal signal_error()
signal signal_log()

var _status: int = 0
var _stream: StreamPeerTCP = StreamPeerTCP.new()

func _ready() -> void:
	_status = _stream.get_status()

func connect_to_host(host: String, port: int) -> void:
	signal_log.emit("Connecting to %s:%d" % [host, port])
	_status = _stream.STATUS_NONE
	if _stream.connect_to_host(host, port) != OK:
		signal_log.emit("Error connecting to host.")
		emit_signal("error")

func disconnect_from_host():
	_stream.disconnect_from_host()

func is_connected_to_host() -> bool:
	return _status == _stream.STATUS_CONNECTED

func _process(_delta: float) -> void:
	_stream.poll()
	var new_status: int = _stream.get_status()
	if new_status != _status:
		_status = new_status
		match _status:
			_stream.STATUS_NONE:
				signal_log.emit("Disconnected")
				signal_disconnected.emit()
			_stream.STATUS_CONNECTING:
				signal_log.emit("Connecting")
			_stream.STATUS_CONNECTED:
				signal_log.emit("Connected")
				signal_connected.emit()
			_stream.STATUS_ERROR:
				signal_log.emit("Error with socket connection")
				signal_error.emit()
	
	if _status == _stream.STATUS_CONNECTED:
		var available_bytes: int = _stream.get_available_bytes()
		if available_bytes > 0:
			signal_log.emit("-> Incoming bytes: ", available_bytes)
			var received_data: Array = _stream.get_partial_data(available_bytes)
			if received_data[0] != OK:
				signal_log.emit("Error getting data from stream: ", received_data[0])
				signal_error.emit()
			else:
				signal_data.emit(received_data[1])

func send(send_data: PackedByteArray) -> bool:
	if _status != _stream.STATUS_CONNECTED:
		signal_log.emit("Error: Stream is not currently connected")
		return false
	var error: int = _stream.put_data(send_data)
	if error != OK:
		signal_log.emit("Error writing to stream: ", error)
		return false
	return true
