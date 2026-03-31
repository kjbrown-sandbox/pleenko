class_name HitBucketsInOrder
extends ChallengeObjective

@export var board_type: Enums.BoardType
## Each inner array is a group of bucket indices that must ALL be hit before the next group activates.
## Example: [[3], [2, 4], [1, 5], [0, 6]] means hit middle first, then its neighbors, etc.
@export var bucket_groups: Array[PackedInt32Array] = []
