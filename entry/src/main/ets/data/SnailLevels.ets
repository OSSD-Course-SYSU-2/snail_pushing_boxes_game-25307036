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
    subtitle: '开阔场压轴，需要在大空间里反复调整角度与落点。',
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
  },
  {
    id: 6,
    name: 'Reed Lattice',
    subtitle: '三箱正式登场，先处理下路拐角，再回头抬上方线路。',
    difficulty: '挑战',
    hint: '先把左下木箱送上去，别急着处理中间那只。',
    parMoves: 47,
    map: [
      '###########',
      '# .   .   #',
      '# $   $   #',
      '# ### ##  #',
      '# .  $ @  #',
      '#         #',
      '###########'
    ]
  },
  {
    id: 7,
    name: 'Lily Vault',
    subtitle: '中央箱位会卡住两侧通道，换位顺序必须更稳。',
    difficulty: '挑战',
    hint: '中间箱子不要太早顶头，先给两侧留出调整空间。',
    parMoves: 51,
    map: [
      '###########',
      '#  . . .  #',
      '#  $ # $  #',
      '# ##  $## #',
      '#   @     #',
      '#         #',
      '###########'
    ]
  },
  {
    id: 8,
    name: 'Cattail Switchyard',
    subtitle: '上下动线开始互相干扰，来回折返会明显增步。',
    difficulty: '挑战',
    hint: '先清左侧目标，再把右半场当成最后收口区域。',
    parMoves: 51,
    map: [
      '###########',
      '#  . . .  #',
      '#  $ $ $  #',
      '# ### ### #',
      '#   @     #',
      '#     #   #',
      '###########'
    ]
  },
  {
    id: 9,
    name: 'Pebble Weir',
    subtitle: '中路被石柱切开，三只箱子会争抢同一条回身线。',
    difficulty: '挑战',
    hint: '别把右侧木箱太早顶死，中路回身口要尽量保留久一点。',
    parMoves: 53,
    map: [
      '###########',
      '#  . . .  #',
      '#  $ $ $  #',
      '# ## # ## #',
      '#   @     #',
      '#         #',
      '###########'
    ]
  },
  {
    id: 10,
    name: 'Drift Gallery',
    subtitle: '中段门洞成了唯一换位点，顺序错一次就会反复返工。',
    difficulty: '挑战',
    hint: '中心门洞是唯一的借位位置，不要太早把自己锁在上半场。',
    parMoves: 56,
    map: [
      '###########',
      '#  . . .  #',
      '#  $ $ $  #',
      '# ### ### #',
      '#   #@#   #',
      '#         #',
      '###########'
    ]
  },
  {
    id: 11,
    name: 'Harbor of Shells',
    subtitle: '最终关，内外两层墙会不断吃掉回旋余地，需要稳定控场。',
    difficulty: '挑战',
    hint: '先稳住中间木箱，再按左、中、右的节奏慢慢收口。',
    parMoves: 57,
    map: [
      '###########',
      '#  . . .  #',
      '#  $ $ $  #',
      '# ## ###  #',
      '# # @   # #',
      '#         #',
      '###########'
    ]
  }
];
