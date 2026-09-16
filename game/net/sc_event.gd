extends DotNetMessage

const ScEvent := preload("sc_event.gd")
const ScEvents := preload("sc_events.gd")

## Anything the authority tells a client that is not a snapshot. Reliable, to clients.

const NAME := &"sc.event"
const KIND_BITS := 5
const MAX_BODY := 4096

var kind: int = 0
var body: PackedByteArray = PackedByteArray()


static func of(p_kind: int, p_body: PackedByteArray) -> ScEvent:
	var event := ScEvent.new()
	event.kind = p_kind
	event.body = p_body
	return event


func _type_name() -> StringName:
	return NAME


func _write(writer: DotNetWriter) -> void:
	writer.write_uint(kind, KIND_BITS)
	writer.write_bytes(body)


func _read(reader: DotNetReader) -> void:
	kind = reader.read_uint(KIND_BITS)
	body = reader.read_bytes(MAX_BODY)


func _validate() -> DotResult:
	if kind < 0 or kind >= ScEvents.Kind.size():
		return DotResult.fail(DotError.CODE_INVALID, "Unknown event kind %d." % kind)

	return DotResult.success(true)


func reader() -> DotNetReader:
	return DotNetReader.new(body)


func _to_string() -> String:
	return "ScEvent(%s, %d bytes)" % [ScEvents.kind_name(kind), body.size()]
