export interface SnailLevel {
  id: number;
  name: string;
  subtitle: string;
  difficulty: string;
  hint: string;
  parMoves: number;
  map: string[];
}

export const SNAIL_LEVELS: SnailLevel[] = [
  {
    id: 1,
    name: 'Garden Gate',
    subtitle: '教学关，用一口气绕位学会第一次推箱。',
    difficulty: '入门',
    hint: '先绕到木箱右侧，再从侧面把它推上荷叶。',
    parMoves: 3,
    map: [
      '#######',
      '#     #',
      '# .$  #',
      '#  @  #',
      '#     #',
      '#######'
    ]
  },
  {
    id: 2,
    name: 'Mossy Bend',
    subtitle: '墙体开始干扰路线，先看站位再出手。',
    difficulty: '入门',
    hint: '别急着靠近箱子，先保证自己还能走到它后面。',
    parMoves: 3,
    map: [
      '########',
      '#   .  #',
      '#   $  #',
      '# ##   #',
      '#  @   #',
      '#      #',
      '########'
    ]
  },
  {
    id: 3,
    name: 'Twin Ponds',
    subtitle: '第一次同时处理两个木箱，讲究节奏和顺序。',
    difficulty: '标准',
    hint: '先把两只箱子都送到上方，再补足位置修正。',
    parMoves: 6,
    map: [
      '#########',
      '#   .   #',
      '#   $   #',
      '# ## ## #',
      '# . $ @ #',
      '#       #',
      '#########'
    ]
  },
  {
    id: 4,
    name: 'Fern Maze',
    subtitle: '中段墙体会切开动线，错误顺序会明显加步。',
    difficulty: '标准',
    hint: '先腾出狭窄通道，再处理靠近终点的那只木箱。',
    parMoves: 17,
    map: [
      '########',
      '#  .   #',
      '#  $   #',
      '#  ##  #',
      '# .$@  #',
      '#      #',
      '########'
    ]
  },
  {
    id: 5,
    name: 'Moonlit Depot',
    subtitle: '最终关，需要在大空间里反复调整角度与落点。',
    difficulty: '挑战',
    hint: '保留中路回旋余地，不要把两只箱子同时顶进边缘。',
    parMoves: 45,
    map: [
      '#########',
      '#  . .  #',
      '#  $ $  #',
      '# ## ## #',
      '#   @   #',
      '#       #',
      '#########'
    ]
  }
];
