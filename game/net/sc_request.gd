extends DotNetMessage

const ScEvents := preload("sc_events.gd")
const ScRequest := preload("sc_request.gd")

## Anything a client asks the authority for. Reliable, rare, to the server only.
##
## [b]There are three of these and none of them is a per-tick intent.[/b] Firing is a
## BUTTON, because it is held down and has to be ordered against the movement it was aimed
## with; this is for the other kind — "my world exists, start telling me about yours", "I
## want to get into that chopper", "put me on the other side" — each of which happens once
## and must not be lost.

const NAME := &"sc.request"
const KIND_BITS := 4
const MAX_BODY := 256

var kind: int = 0
var body: PackedByteArray = PackedByteArray()


static func of(p_kind: int, p_body: PackedByteArray) -> ScRequest:
	var ask := ScRequest.new()
	ask.kind = p_kind
	ask.body = p_body
	return ask


func _type_name() -> StringName:
	return NAME


func _write(writer: DotNetWriter) -> void:
	writer.write_uint(kind, KIND_BITS)
	writer.write_bytes(body)


func _read(reader: DotNetReader) -> void:
	kind = reader.read_uint(KIND_BITS)
	body = reader.read_bytes(MAX_BODY)


func _validate() -> DotResult:
	if kind < 0 or kind >= ScEvents.Ask.size():
		return DotResult.fail(DotError.CODE_INVALID, "Unknown request kind %d." % kind)

	return DotResult.success(true)


func reader() -> DotNetReader:
	return DotNetReader.new(body)


func _to_string() -> String:
	return "ScRequest(%s, %d bytes)" % [ScEvents.ask_name(kind), body.size()]
