class_name UpgradeData
extends Resource

@export var id: String
@export var display_name: String

@export var base_cost: int
@export var max_level: int  ## 0 = uncapped

@export var cost_type: CostType
@export var cost_delta: int              ## for ADDITIVE: cost += delta each buy
@export var delta_escalation: int        ## for ADDITIVE_ESCALATING: delta += this each buy
@export var cost_multiplier: float       ## for MULTIPLICATIVE: cost *= this each buy

enum CostType {
	ADDITIVE,                ## cost += delta
	ADDITIVE_ESCALATING,     ## cost += delta, then delta += delta_escalation
	MULTIPLICATIVE,          ## cost *= cost_multiplier
}
