import { describe, it, expect } from '@ohos/hypium';
import { SNAIL_LEVELS, SnailLevel } from '../main/ets/data/SnailLevels';
import {
  KeyboardMove,
  keyboardMoveFromCode,
  keyboardMoveFromText
} from '../main/ets/utils/KeyboardMapping';
import {
  getDeadlockedBoxKeys,
  isLevelSolved,
  keyFor,
  ParsedLevel,
  parseLevel,
  tryMove
} from '../main/ets/utils/SokobanLogic';

export default function localUnitTest() {
  describe('sokobanLogic', () => {
    it('parsesLevelMetadata', 0, () => {
      const parsed = parseLevel(SNAIL_LEVELS[0]);
      expect(parsed.goalKeys.length).assertEqual(1);
      expect(parsed.boxKeys.length).assertEqual(1);
      expect(parsed.playerKey).assertEqual(keyFor(3, 3));
      expect(parsed.floorKeys.length > 0).assertEqual(true);
    });

    it('rotatesVerticalLevelMapsBeforeParsing', 0, () => {
      const level: SnailLevel = {
        id: 98,
        name: 'Vertical Test',
        subtitle: 'test',
        difficulty: '测试',
        hint: 'test',
        parMoves: 1,
        orientation: 'vertical',
        map: [
          '#####',
          '#@$.#',
          '#####'
        ]
      };
      const parsed = parseLevel(level);
      expect(parsed.width).assertEqual(3);
      expect(parsed.height).assertEqual(5);
      expect(parsed.playerKey).assertEqual(keyFor(1, 1));
      expect(parsed.boxKeys[0]).assertEqual(keyFor(2, 1));
      expect(parsed.goalKeys[0]).assertEqual(keyFor(3, 1));
    });

    it('mapsKeyboardControlsToDirections', 0, () => {
      const upByText = keyboardMoveFromText('KEYCODE_W') as KeyboardMove;
      const leftByText = keyboardMoveFromText('a') as KeyboardMove;
      const downByCode = keyboardMoveFromCode(2013) as KeyboardMove;
      const rightByCode = keyboardMoveFromCode(2020) as KeyboardMove;

      expect(upByText.deltaRow).assertEqual(-1);
      expect(upByText.deltaCol).assertEqual(0);
      expect(leftByText.deltaRow).assertEqual(0);
      expect(leftByText.deltaCol).assertEqual(-1);
      expect(downByCode.deltaRow).assertEqual(1);
      expect(downByCode.deltaCol).assertEqual(0);
      expect(rightByCode.deltaRow).assertEqual(0);
      expect(rightByCode.deltaCol).assertEqual(1);
      expect(keyboardMoveFromText('KEYCODE_ENTER') === undefined).assertEqual(true);
    });

    it('preventsMovingIntoVoidSpace', 0, () => {
      const level: SnailLevel = {
        id: 99,
        name: 'Void Test',
        subtitle: 'test',
        difficulty: '测试',
        hint: 'test',
        parMoves: 1,
        map: [
          '#####',
          '#@  #',
          '#',
          '#####'
        ]
      };
      const parsed = parseLevel(level);
      const attempt = tryMove(parsed.playerKey, parsed.boxKeys, parsed.wallKeys, parsed.floorKeys, 1, 0);
      expect(attempt.moved).assertEqual(false);
      expect(attempt.message).assertEqual('前面没有可走的路。');
    });

    it('pushesBoxWhenThePathIsClear', 0, () => {
      const level: SnailLevel = {
        id: 100,
        name: 'Push Test',
        subtitle: 'test',
        difficulty: '测试',
        hint: 'test',
        parMoves: 1,
        map: [
          '#######',
          '#@$.  #',
          '#######'
        ]
      };
      const parsed = parseLevel(level);
      const attempt = tryMove(parsed.playerKey, parsed.boxKeys, parsed.wallKeys, parsed.floorKeys, 0, 1);
      expect(attempt.moved).assertEqual(true);
      expect(attempt.pushed).assertEqual(true);
      expect(attempt.nextPlayerKey).assertEqual(keyFor(1, 2));
      expect(attempt.nextBoxKeys[0]).assertEqual(keyFor(1, 3));
    });

    it('detectsSolvedStateOnlyWhenAllGoalsAreCovered', 0, () => {
      const parsed = parseLevel(SNAIL_LEVELS[0]);
      expect(isLevelSolved([parsed.goalKeys[0]], parsed.goalKeys)).assertEqual(true);
      expect(isLevelSolved([parsed.goalKeys[0], keyFor(0, 0)], parsed.goalKeys)).assertEqual(false);
    });

    it('marksBoxesInStaticCornersAsDeadlocked', 0, () => {
      const level: SnailLevel = {
        id: 101,
        name: 'Deadlock Test',
        subtitle: 'test',
        difficulty: '测试',
        hint: 'test',
        parMoves: 1,
        map: [
          '#####',
          '#@  #',
          '#  $#',
          '# .##',
          '#####'
        ]
      };
      const parsed = parseLevel(level);
      const deadlocked = getDeadlockedBoxKeys(parsed.boxKeys, parsed.wallKeys, parsed.goalKeys, parsed.floorKeys);
      expect(deadlocked.length).assertEqual(1);
      expect(deadlocked[0]).assertEqual(keyFor(2, 3));
    });

    it('keepsAllCampaignLevelsSolvableAndBenchmarked', 0, () => {
      expect(SNAIL_LEVELS.length).assertEqual(11);

      for (let levelIndex = 0; levelIndex < SNAIL_LEVELS.length; levelIndex++) {
        const level = SNAIL_LEVELS[levelIndex];
        const parsed = parseLevel(level);
        expect(parsed.goalKeys.length).assertEqual(parsed.boxKeys.length);

        const bestMoves = solveLevelInMoves(level);
        expect(bestMoves > 0).assertEqual(true);
        expect(bestMoves).assertEqual(level.parMoves);
      }
    });
  });
}

interface SearchState {
  playerKey: string;
  boxKeys: string[];
  moves: number;
}

function solveLevelInMoves(level: SnailLevel): number {
  const parsed = parseLevel(level);
  const queue: SearchState[] = [{
    playerKey: parsed.playerKey,
    boxKeys: parsed.boxKeys,
    moves: 0
  }];
  const visited: Set<string> = new Set<string>();
  let head = 0;

  visited.add(searchStateKey(parsed.playerKey, parsed.boxKeys));

  while (head < queue.length) {
    const current = queue[head];
    head += 1;

    if (isLevelSolved(current.boxKeys, parsed.goalKeys)) {
      return current.moves;
    }

    pushIfReachable(queue, visited, current, parsed, -1, 0);
    pushIfReachable(queue, visited, current, parsed, 1, 0);
    pushIfReachable(queue, visited, current, parsed, 0, -1);
    pushIfReachable(queue, visited, current, parsed, 0, 1);
  }

  return -1;
}

function pushIfReachable(
  queue: SearchState[],
  visited: Set<string>,
  current: SearchState,
  parsed: ParsedLevel,
  deltaRow: number,
  deltaCol: number
): void {
  const attempt = tryMove(current.playerKey, current.boxKeys, parsed.wallKeys, parsed.floorKeys, deltaRow, deltaCol);
  if (!attempt.moved) {
    return;
  }

  const nextKey = searchStateKey(attempt.nextPlayerKey, attempt.nextBoxKeys);
  if (visited.has(nextKey)) {
    return;
  }

  visited.add(nextKey);
  queue.push({
    playerKey: attempt.nextPlayerKey,
    boxKeys: attempt.nextBoxKeys,
    moves: current.moves + 1
  });
}

function searchStateKey(playerKey: string, boxKeys: string[]): string {
  return `${playerKey}|${boxKeys.join(',')}`;
}
