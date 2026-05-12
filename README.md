# 蜗牛推箱子

这是一个运行在 HarmonyOS / DevEco Studio 工程里的推箱子小游戏正式版整理稿。

当前版本不再追求“3D 演示感”，而是把重点放在一个可以直接交付展示的小型完整游戏上：流程完整、规则稳定、开始页和音频反馈完整，11 关战役的体验闭环也更清楚。

## 当前版本亮点

- 使用 `开始页面.png` 作为游戏开始页，点击“开始游戏”后进入原来的关卡总览
- 首页总览与局内界面分离，游戏流程更完整
- 11 个手工设计关卡，难度从教学到最终挑战递进
- 初次进入即可自由选择全部关卡，本地保存最近游玩进度、挑战次数、最佳步数、最佳推箱次数和通关评级
- `撤销`、`重开`、`上一关 / 下一关` 全部保留
- 加入明显死角提示，减少无反馈的失败体验
- 长地图支持竖版摆放，避免在窄屏或分栏布局中向右溢出
- 支持方向键和 WASD 物理键盘控制
- 开始页音乐、游戏背景音乐和通关音效分离，点击开始后自动切换 BGM
- 播放通关音效时会暂停背景音乐，音效结束后恢复背景音乐
- 棋盘素材、按钮风格、通关弹层和状态提示整体重做，更适合手机和平板展示

## 核心规则

- 蜗牛每次只能移动一格
- 木箱只能推，不能拉
- 木箱前方必须是可行走地块才能被推动
- 墙体和地图外空洞都会阻止移动
- 所有木箱都推到绿色荷叶目标点上即算通关

## 界面与音频

- 开始页：`entry/src/main/resources/base/media/start_page.png`
- 开始页音乐：`entry/src/main/resources/rawfile/开始页面音乐.mp3`
- 游戏背景音乐：`entry/src/main/resources/rawfile/背景音乐.mp3`
- 通关音效：`entry/src/main/resources/rawfile/通关音效.mp3`
- 蜗牛、木箱、目标点使用 ArkUI 组件绘制，包含蜗牛壳、触角、木箱纹理和荷叶目标
- 通关弹层包含星级展示、淡入、缩放和上移动画
- 主按钮、局内按钮、方向键和弹层按钮使用统一圆角、边框、阴影和字体风格

## 关卡列表

1. `Garden Gate`
   教学关，学习第一次绕位推箱
2. `Mossy Bend`
   墙体开始影响站位，提醒玩家先判断后行动
3. `Twin Ponds`
   第一次同时处理两个木箱
4. `Fern Maze`
   中段墙体切开路线，顺序错误会明显加步
5. `Moonlit Depot`
   开阔场压轴，练习大空间里的连续调整
6. `Reed Lattice`
   三箱正式登场，先处理下路拐角再抬上方线路
7. `Lily Vault`
   中央箱位会卡住两侧通道，换位顺序要求更稳
8. `Cattail Switchyard`
   上下动线互相干扰，折返多了会明显加步
9. `Pebble Weir`
   石柱切开中路，三只箱子会争抢回身空间
10. `Drift Gallery`
   中段门洞成了唯一换位点，顺序错一次就会返工
11. `Harbor of Shells`
   最终关，内外两层墙会不断吃掉回旋余地

## 项目结构

```text
entry/src/main/ets/
  data/
    SnailLevels.ets
  pages/
    Index.ets
  utils/
    SokobanLogic.ets
```

```text
entry/src/main/resources/
  base/media/
    start_page.png
  rawfile/
    开始页面音乐.mp3
    背景音乐.mp3
    通关音效.mp3
```

## 主要实现

- `Index.ets`
  负责开始页、首页、关卡流程、棋盘绘制、局内操作、音频播放、通关覆盖层和进度保存
- `SnailLevels.ets`
  定义关卡地图、难度、说明文案和评级标杆步数
- `SokobanLogic.ets`
  负责地图解析、空洞/墙体判定、推箱规则、通关判定、撤销快照和死角检测
- `KeyboardMapping.ets`
  按 OpenHarmony 键码映射方向键与 WASD，用于局内物理键盘移动

## 运行方式

1. 用 DevEco Studio 打开项目
2. 确保本机 HarmonyOS SDK 组件完整
3. 在模拟器或真机中运行 `entry` 模块

## 已完成的质量检查

- 逐关做了可解性校验，确保 11 个关卡都存在解法
- 规则层补了单元测试样例，覆盖解析、推箱、通关和死角判定
- 对当前改动执行过 `git diff --check`
- 完整打包建议在 DevEco Studio 中执行；当前命令行环境未提供 `hvigor` / `ohpm`
