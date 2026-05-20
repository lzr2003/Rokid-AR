extends Resource
## 交互器和可交互对象的状态枚举
class_name InteractionEnums

enum InteractorState {
	NORMAL = 0,
	HOVER = 1,
	SELECT = 2,
	DISABLED = 3,
}

enum InteractableState {
	NORMAL = 0,
	HOVER = 1,
	SELECT = 2,
	DISABLED = 3,
}

enum PointerEventType {
	HOVER = 0,
	UNHOVER = 1,
	SELECT = 2,
	UNSELECT = 3,
	MOVE = 4,
	CANCEL = 5,
}
