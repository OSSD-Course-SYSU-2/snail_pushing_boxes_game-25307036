import { SnailLevel } from '../data/SnailLevels';

const VERTICAL_ORIENTATION: string = 'vertical';
const VOID_TILE: string = '\0';

export interface ParsedLevel {
  width: number;
  height: number;
  floorKeys: string[];
  wallKeys: string[];
  goalKeys: string[];
  boxKeys: string[];
  playerKey: string;
}

export interface MoveAttempt {
  moved: boolean;
  pushed: boolean;
  blocked: boolean;
  message: string;
  nextPlayerKey: string;
  nextBoxKeys: string[];
}

export interface Snapshot {
  playerKey: string;
  boxKeys: string[];
  moveCount: number;
  pushCount: number;
}

export function keyFor(row: number, col: number): string {
  return `${row}:${col}`;
}

export function rowFromKey(key: string): number {
  const parts = key.split(':');
  return Number.parseInt(parts[0]);
}

export function colFromKey(key: string): number {
  const parts = key.split(':');
  return Number.parseInt(parts[1]);
}

export function parseLevel(level: SnailLevel): ParsedLevel {
  const mapRows = orientedLevelMap(level);
  let width = 0;
  for (const row of mapRows) {
    width = Math.max(width, row.length);
  }

  const floorKeys: string[] = [];
  const wallKeys: string[] = [];
  const goalKeys: string[] = [];
  const boxKeys: string[] = [];
  let playerKey = keyFor(0, 0);

  for (let rowIndex = 0; rowIndex < mapRows.length; rowIndex++) {
    const rowText = mapRows[rowIndex];
    for (let colIndex = 0; colIndex < rowText.length; colIndex++) {
      const token = rowText[colIndex];
      const key = keyFor(rowIndex, colIndex);
      switch (token) {
        case '#':
          wallKeys.push(key);
          break;
        case '.':
          floorKeys.push(key);
          goalKeys.push(key);
          break;
        case '$':
          floorKeys.push(key);
          boxKeys.push(key);
          break;
        case '@':
          floorKeys.push(key);
          playerKey = key;
          break;
        case '*':
          floorKeys.push(key);
          goalKeys.push(key);
          boxKeys.push(key);
          break;
        case '+':
          floorKeys.push(key);
          goalKeys.push(key);
          playerKey = key;
          break;
        case VOID_TILE:
          break;
        default:
          floorKeys.push(key);
          break;
      }
    }
  }

  return {
    width,
    height: mapRows.length,
    floorKeys: sortedKeys(floorKeys),
    wallKeys: sortedKeys(wallKeys),
    goalKeys: sortedKeys(goalKeys),
    boxKeys: sortedKeys(boxKeys),
    playerKey
  };
}

export function orientedLevelMap(level: SnailLevel): string[] {
  if (level.orientation === VERTICAL_ORIENTATION) {
    return rotateLevelMapClockwise(level.map);
  }
  return cloneRows(level.map);
}

export function rotateLevelMapClockwise(mapRows: string[]): string[] {
  let width = 0;
  for (const row of mapRows) {
    width = Math.max(width, row.length);
  }

  const rotated: string[] = [];
  for (let col = 0; col < width; col++) {
    let nextRow = '';
    for (let row = mapRows.length - 1; row >= 0; row--) {
      const sourceRow = mapRows[row];
      nextRow += col < sourceRow.length ? sourceRow[col] : VOID_TILE;
    }
    rotated.push(trimTrailingVoidTiles(nextRow));
  }
  return rotated;
}

export function tryMove(
  playerKey: string,
  boxKeys: string[],
  wallKeys: string[],
  floorKeys: string[],
  deltaRow: number,
  deltaCol: number
): MoveAttempt {
  const nextPlayerKey = movedKey(playerKey, deltaRow, deltaCol);
  if (!hasKey(floorKeys, nextPlayerKey)) {
    return {
      moved: false,
      pushed: false,
      blocked: true,
      message: '前面没有可走的路。',
      nextPlayerKey: playerKey,
      nextBoxKeys: cloneKeys(boxKeys)
    };
  }

  if (hasKey(wallKeys, nextPlayerKey)) {
    return {
      moved: false,
      pushed: false,
      blocked: true,
      message: '前面是石墙，蜗牛撞不过去。',
      nextPlayerKey: playerKey,
      nextBoxKeys: cloneKeys(boxKeys)
    };
  }

  if (!hasKey(boxKeys, nextPlayerKey)) {
    return {
      moved: true,
      pushed: false,
      blocked: false,
      message: '蜗牛稳稳地向前爬了一格。',
      nextPlayerKey,
      nextBoxKeys: cloneKeys(boxKeys)
    };
  }

  const nextBoxKey = movedKey(nextPlayerKey, deltaRow, deltaCol);
  if (!hasKey(floorKeys, nextBoxKey) || hasKey(wallKeys, nextBoxKey) || hasKey(boxKeys, nextBoxKey)) {
    return {
      moved: false,
      pushed: false,
      blocked: true,
      message: '箱子后面被堵住了，推不动。',
      nextPlayerKey: playerKey,
      nextBoxKeys: cloneKeys(boxKeys)
    };
  }

  const nextBoxes = cloneKeys(boxKeys);
  const replaceIndex = indexOfKey(nextBoxes, nextPlayerKey);
  if (replaceIndex >= 0) {
    nextBoxes[replaceIndex] = nextBoxKey;
  }

  return {
    moved: true,
    pushed: true,
    blocked: false,
    message: '木箱被稳稳推进了一格。',
    nextPlayerKey,
    nextBoxKeys: sortedKeys(nextBoxes)
  };
}

export function isLevelSolved(boxKeys: string[], goalKeys: string[]): boolean {
  if (goalKeys.length === 0 || boxKeys.length === 0 || boxKeys.length !== goalKeys.length) {
    return false;
  }
  for (const goalKey of goalKeys) {
    if (!hasKey(boxKeys, goalKey)) {
      return false;
    }
  }
  return true;
}

export function encodeSnapshot(playerKey: string, boxKeys: string[], moveCount: number, pushCount: number): string {
  const snapshot: Snapshot = {
    playerKey,
    boxKeys: sortedKeys(boxKeys),
    moveCount,
    pushCount
  };
  return JSON.stringify(snapshot);
}

export function decodeSnapshot(snapshotText: string): Snapshot {
  const snapshot = JSON.parse(snapshotText) as Snapshot;
  return {
    playerKey: snapshot.playerKey,
    boxKeys: sortedKeys(snapshot.boxKeys),
    moveCount: snapshot.moveCount,
    pushCount: snapshot.pushCount
  };
}

export function cloneKeys(keys: string[]): string[] {
  const next: string[] = [];
  for (const key of keys) {
    next.push(key);
  }
  return next;
}

function cloneRows(rows: string[]): string[] {
  const next: string[] = [];
  for (const row of rows) {
    next.push(row);
  }
  return next;
}

export function hasKey(keys: string[], target: string): boolean {
  return indexOfKey(keys, target) >= 0;
}

export function countGoalsCovered(boxKeys: string[], goalKeys: string[]): number {
  let count = 0;
  for (const goalKey of goalKeys) {
    if (hasKey(boxKeys, goalKey)) {
      count += 1;
    }
  }
  return count;
}

export function getDeadlockedBoxKeys(
  boxKeys: string[],
  wallKeys: string[],
  goalKeys: string[],
  floorKeys: string[]
): string[] {
  const deadlocked: string[] = [];
  for (const boxKey of boxKeys) {
    if (hasKey(goalKeys, boxKey)) {
      continue;
    }

    const upBlocked = isStaticBlock(movedKey(boxKey, -1, 0), wallKeys, floorKeys);
    const downBlocked = isStaticBlock(movedKey(boxKey, 1, 0), wallKeys, floorKeys);
    const leftBlocked = isStaticBlock(movedKey(boxKey, 0, -1), wallKeys, floorKeys);
    const rightBlocked = isStaticBlock(movedKey(boxKey, 0, 1), wallKeys, floorKeys);

    if ((upBlocked && leftBlocked) || (upBlocked && rightBlocked) || (downBlocked && leftBlocked) ||
      (downBlocked && rightBlocked)) {
      deadlocked.push(boxKey);
    }
  }
  return sortedKeys(deadlocked);
}

function movedKey(key: string, deltaRow: number, deltaCol: number): string {
  return keyFor(rowFromKey(key) + deltaRow, colFromKey(key) + deltaCol);
}

function indexOfKey(keys: string[], target: string): number {
  for (let index = 0; index < keys.length; index++) {
    if (keys[index] === target) {
      return index;
    }
  }
  return -1;
}

function sortedKeys(keys: string[]): string[] {
  const next = cloneKeys(keys);
  next.sort();
  return next;
}

function isStaticBlock(key: string, wallKeys: string[], floorKeys: string[]): boolean {
  return hasKey(wallKeys, key) || !hasKey(floorKeys, key);
}

function trimTrailingVoidTiles(row: string): string {
  let end = row.length;
  while (end > 0 && row[end - 1] === VOID_TILE) {
    end -= 1;
  }
  return row.slice(0, end);
}
