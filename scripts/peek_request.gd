class_name PeekRequest
extends Resource

@export var kind: Enums.PeekKind = Enums.PeekKind.BOARD
@export var board_type: Enums.BoardType = Enums.BoardType.GOLD


static func for_board(type: Enums.BoardType) -> PeekRequest:
	var req := PeekRequest.new()
	req.kind = Enums.PeekKind.BOARD
	req.board_type = type
	return req


static func for_challenges() -> PeekRequest:
	var req := PeekRequest.new()
	req.kind = Enums.PeekKind.CHALLENGES
	return req
