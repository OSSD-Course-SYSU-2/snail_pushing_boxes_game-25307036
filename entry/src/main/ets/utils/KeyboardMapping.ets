export interface KeyboardMove {
  deltaRow: number;
  deltaCol: number;
}

// OpenHarmony keyCode values from the system keyboard mapping table.
const KEYCODE_DPAD_UP: number = 2012;
const KEYCODE_DPAD_DOWN: number = 2013;
const KEYCODE_DPAD_LEFT: number = 2014;
const KEYCODE_DPAD_RIGHT: number = 2015;
const KEYCODE_A: number = 2017;
const KEYCODE_D: number = 2020;
const KEYCODE_S: number = 2035;
const KEYCODE_W: number = 2039;

const MOVE_UP: KeyboardMove = { deltaRow: -1, deltaCol: 0 };
const MOVE_DOWN: KeyboardMove = { deltaRow: 1, deltaCol: 0 };
const MOVE_LEFT: KeyboardMove = { deltaRow: 0, deltaCol: -1 };
const MOVE_RIGHT: KeyboardMove = { deltaRow: 0, deltaCol: 1 };

export function keyboardMoveFromKey(keyCode: number, keyText: string): KeyboardMove | undefined {
  const textMove = keyboardMoveFromText(keyText);
  if (textMove !== undefined) {
    return textMove;
  }
  return keyboardMoveFromCode(keyCode);
}

export function keyboardMoveFromText(keyText: string): KeyboardMove | undefined {
  const normalized = keyText.trim().toUpperCase();
  switch (normalized) {
    case 'KEYCODE_DPAD_UP':
    case 'ARROWUP':
    case 'UP':
    case 'W':
      return MOVE_UP;
    case 'KEYCODE_DPAD_DOWN':
    case 'ARROWDOWN':
    case 'DOWN':
    case 'S':
      return MOVE_DOWN;
    case 'KEYCODE_DPAD_LEFT':
    case 'ARROWLEFT':
    case 'LEFT':
    case 'A':
      return MOVE_LEFT;
    case 'KEYCODE_DPAD_RIGHT':
    case 'ARROWRIGHT':
    case 'RIGHT':
    case 'D':
      return MOVE_RIGHT;
    default:
      return undefined;
  }
}

export function keyboardMoveFromCode(keyCode: number): KeyboardMove | undefined {
  switch (keyCode) {
    case KEYCODE_DPAD_UP:
    case KEYCODE_W:
      return MOVE_UP;
    case KEYCODE_DPAD_DOWN:
    case KEYCODE_S:
      return MOVE_DOWN;
    case KEYCODE_DPAD_LEFT:
    case KEYCODE_A:
      return MOVE_LEFT;
    case KEYCODE_DPAD_RIGHT:
    case KEYCODE_D:
      return MOVE_RIGHT;
    default:
      return undefined;
  }
}
