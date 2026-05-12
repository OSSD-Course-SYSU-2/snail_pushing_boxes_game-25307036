import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { media } from '@kit.MediaKit';
import { SNAIL_LEVELS, SnailLevel } from '../data/SnailLevels';
import { keyboardMoveFromKey } from '../utils/KeyboardMapping';
import {
  countGoalsCovered,
  decodeSnapshot,
  encodeSnapshot,
  getDeadlockedBoxKeys,
  hasKey,
  isLevelSolved,
  keyFor,
  parseLevel,
  tryMove
} from '../utils/SokobanLogic';

const VIEW_START: number = -1;
const VIEW_HOME: number = 0;
const VIEW_PLAY: number = 1;
const SAVE_KEY: string = 'snail_publish_save_data';
const DEFAULT_SAVE_DATA_TEXT: string = '{"lastPlayedLevelIndex":0,"records":[]}';
const GAME_FOCUS_ID: string = 'snail-game-root';
const START_PAGE_BGM_RAW_FILE: string = '开始页面音乐.mp3';
const GAME_BGM_RAW_FILE: string = '背景音乐.mp3';
const CLEAR_SOUND_RAW_FILE: string = '通关音效.mp3';

PersistentStorage.persistProp(SAVE_KEY, DEFAULT_SAVE_DATA_TEXT);

interface LevelRecord {
  levelId: number;
  bestMoves: number;
  bestPushes: number;
  bestStars: number;
  attemptCount: number;
}

interface SaveData {
  lastPlayedLevelIndex: number;
  records: LevelRecord[];
}

@Entry
@Component
struct Index {
  @StorageLink(SAVE_KEY) saveDataText: string = DEFAULT_SAVE_DATA_TEXT;
  @State currentView: number = VIEW_START;
  @State layoutWidth: number = 0;
  @State levelIndex: number = 0;
  @State boardWidth: number = 0;
  @State boardHeight: number = 0;
  @State floorKeys: string[] = [];
  @State wallKeys: string[] = [];
  @State goalKeys: string[] = [];
  @State boxKeys: string[] = [];
  @State deadlockedBoxKeys: string[] = [];
  @State playerKey: string = keyFor(0, 0);
  @State moveCount: number = 0;
  @State pushCount: number = 0;
  @State history: string[] = [];
  @State isCleared: boolean = false;
  @State lastClearStars: number = 0;
  @State clearOverlayProgress: number = 0;
  @State statusText: string = '欢迎来到蜗牛推箱子。';
  @State statusTone: number = 0;
  private bgmPlayer: media.AVPlayer | undefined = undefined;
  private bgmPreparing: boolean = false;
  private bgmRawFileOpened: boolean = false;
  private bgmRawFileName: string = '';
  private bgmPausedForClearSound: boolean = false;
  private bgmRequestToken: number = 0;
  private clearSoundPlayer: media.AVPlayer | undefined = undefined;
  private clearSoundPreparing: boolean = false;
  private clearSoundRawFileOpened: boolean = false;

  aboutToAppear(): void {
    this.ensureSaveData();
    this.loadLevel(this.readSaveData().lastPlayedLevelIndex);
    this.currentView = VIEW_START;
    this.setStatus('选择任意关卡，帮蜗牛把补给箱慢慢送回荷叶码头。', 0);
    this.startBackgroundMusic(START_PAGE_BGM_RAW_FILE);
  }

  aboutToDisappear(): void {
    this.releaseClearSoundEffect(false);
    this.stopBackgroundMusic();
  }

  build() {
    if (this.currentView === VIEW_START) {
      this.startPage()
    } else {
      Scroll() {
        Column({ space: this.currentView === VIEW_HOME ? 20 : 18 }) {
          if (this.currentView === VIEW_HOME) {
            this.homeHeroCard()
            this.levelOverviewCard()
            this.featureCard()
          } else {
            this.playHeader()
            if (this.isCompactLayout()) {
              Column({ space: 16 }) {
                this.boardCard()
                this.controlCard()
                this.levelRailCard()
                this.ruleCard()
              }
              .width('100%')
            } else {
              Row({ space: 18 }) {
                Column({ space: 16 }) {
                  this.controlCard()
                  this.ruleCard()
                }
                .width('31%')

                Column({ space: 16 }) {
                  this.boardCard()
                }
                .layoutWeight(1)

                Column({ space: 16 }) {
                  this.levelRailCard()
                }
                .width('28%')
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }
          }
        }
        .width('100%')
        .padding(this.currentView === VIEW_HOME ? 18 : this.isCompactLayout() ? 14 : 20)
      }
      .width('100%')
      .height('100%')
      .id(GAME_FOCUS_ID)
      .focusable(true)
      .defaultFocus(true)
      .backgroundColor('#10261C')
      .scrollBar(BarState.Auto)
      .onAppear(() => this.focusGameRoot())
      .onClick(() => this.focusGameRoot())
      .onKeyEvent((event?: KeyEvent) => this.handleKeyboardEvent(event))
      .onAreaChange((oldValue, newValue) => {
        this.updateLayoutWidth(newValue.width as number | string);
      })
    }
  }

  private loadLevel(index: number): void {
    const nextIndex = this.safeLevelIndex(index);
    const level = SNAIL_LEVELS[nextIndex];
    const parsed = parseLevel(level);

    this.levelIndex = nextIndex;
    this.boardWidth = parsed.width;
    this.boardHeight = parsed.height;
    this.floorKeys = parsed.floorKeys;
    this.wallKeys = parsed.wallKeys;
    this.goalKeys = parsed.goalKeys;
    this.boxKeys = parsed.boxKeys;
    this.deadlockedBoxKeys = [];
    this.playerKey = parsed.playerKey;
    this.moveCount = 0;
    this.pushCount = 0;
    this.history = [];
    this.isCleared = false;
    this.lastClearStars = this.bestStarsForLevel(nextIndex);
    this.clearOverlayProgress = 0;
    this.updateLastPlayedLevel(nextIndex);
    this.setStatus(level.hint, 0);
  }

  private openLevel(requestedLevelIndex: number): void {
    const targetLevelIndex = this.safeLevelIndex(requestedLevelIndex);
    this.persistChallengeRecord(targetLevelIndex);
    this.loadLevel(targetLevelIndex);
    this.currentView = VIEW_PLAY;
    this.focusGameRoot();
  }

  private continueAdventure(): void {
    const saveData = this.readSaveData();
    this.openLevel(saveData.lastPlayedLevelIndex);
  }

  private playRecommendedLevel(): void {
    this.openLevel(this.recommendedLevelIndex());
  }

  private returnHome(): void {
    this.currentView = VIEW_HOME;
    this.setStatus('进度已自动保存，可以继续挑关或重玩已通关内容。', 0);
  }

  private moveSnail(deltaRow: number, deltaCol: number): void {
    if (this.isCleared) {
      this.setStatus('本关已经完成，可以直接去下一关。', 1);
      return;
    }

    const snapshotText = encodeSnapshot(this.playerKey, this.boxKeys, this.moveCount, this.pushCount);
    const attempt = tryMove(this.playerKey, this.boxKeys, this.wallKeys, this.floorKeys, deltaRow, deltaCol);
    if (!attempt.moved) {
      this.setStatus(attempt.message, 2);
      return;
    }

    const nextMoveCount = this.moveCount + 1;
    const nextPushCount = this.pushCount + (attempt.pushed ? 1 : 0);
    const nextBoxKeys = attempt.nextBoxKeys;
    const solved = isLevelSolved(nextBoxKeys, this.goalKeys);
    const deadlockedBoxKeys = solved ? [] : getDeadlockedBoxKeys(nextBoxKeys, this.wallKeys, this.goalKeys, this.floorKeys);

    this.history = [...this.history, snapshotText];
    this.playerKey = attempt.nextPlayerKey;
    this.boxKeys = nextBoxKeys;
    this.deadlockedBoxKeys = deadlockedBoxKeys;
    this.moveCount = nextMoveCount;
    this.pushCount = nextPushCount;
    this.isCleared = solved;

    if (solved) {
      this.handleLevelCleared(nextMoveCount, nextPushCount);
      return;
    }

    if (deadlockedBoxKeys.length > 0) {
      this.setStatus('有木箱被顶进了死角，建议立刻撤销刚才的步骤。', 3);
      return;
    }

    this.setStatus(attempt.message, attempt.pushed ? 0 : 0);
  }

  private handleLevelCleared(moves: number, pushes: number): void {
    const stars = this.starRating(this.levelIndex, moves);
    this.lastClearStars = stars;
    this.clearOverlayProgress = 0;
    this.deadlockedBoxKeys = [];
    this.persistClearRecord(this.levelIndex, moves, pushes, stars);
    this.playClearSoundEffect();
    animateTo({ duration: 360, curve: Curve.EaseOut }, () => {
      this.clearOverlayProgress = 1;
    });

    if (this.completedLevelCount() === SNAIL_LEVELS.length) {
      this.setStatus(`全关卡完成：共 ${moves} 步通关当前关，战役已经全部打通。`, 1);
      return;
    }

    this.setStatus(`通关成功：${moves} 步，推箱 ${pushes} 次，评级 ${stars} 星。`, 1);
  }

  private undoMove(): void {
    if (this.history.length === 0) {
      this.setStatus('还没有可以撤销的步骤。', 2);
      return;
    }

    const previous = decodeSnapshot(this.history[this.history.length - 1]);
    this.history = this.history.slice(0, this.history.length - 1);
    this.playerKey = previous.playerKey;
    this.boxKeys = previous.boxKeys;
    this.moveCount = previous.moveCount;
    this.pushCount = previous.pushCount;
    this.isCleared = isLevelSolved(previous.boxKeys, this.goalKeys);
    this.clearOverlayProgress = this.isCleared ? 1 : 0;
    this.deadlockedBoxKeys = getDeadlockedBoxKeys(this.boxKeys, this.wallKeys, this.goalKeys, this.floorKeys);

    if (this.deadlockedBoxKeys.length > 0) {
      this.setStatus('已撤销一步，但场上仍有死角木箱。', 2);
      return;
    }

    this.setStatus('已撤销上一步。', 0);
  }

  private resetLevel(): void {
    this.loadLevel(this.levelIndex);
    this.currentView = VIEW_PLAY;
    this.setStatus('本关已重开。', 0);
  }

  private nextLevel(): void {
    if (this.levelIndex >= SNAIL_LEVELS.length - 1) {
      this.setStatus('已经是最后一关。', 2);
      return;
    }

    this.openLevel(this.levelIndex + 1);
  }

  private previousLevel(): void {
    if (this.levelIndex <= 0) {
      this.setStatus('已经是第一关。', 2);
      return;
    }
    this.openLevel(this.levelIndex - 1);
  }

  private startGame(): void {
    this.currentView = VIEW_HOME;
    this.setStatus('选择任意关卡，帮蜗牛把补给箱慢慢送回荷叶码头。', 0);
    this.switchBackgroundMusic(GAME_BGM_RAW_FILE);
  }

  private handleKeyboardEvent(event?: KeyEvent): void {
    if (!event || this.currentView !== VIEW_PLAY || event.type !== KeyType.Down) {
      return;
    }

    const move = keyboardMoveFromKey(event.keyCode, event.keyText);
    if (move === undefined) {
      return;
    }

    if (event.stopPropagation) {
      event.stopPropagation();
    }
    this.moveSnail(move.deltaRow, move.deltaCol);
  }

  private focusGameRoot(): void {
    try {
      this.getUIContext().getFocusController().requestFocus(GAME_FOCUS_ID);
    } catch (error) {
    }
  }

  private startBackgroundMusic(rawFileName: string): void {
    if ((this.bgmPlayer || this.bgmPreparing) && this.bgmRawFileName === rawFileName) {
      return;
    }

    const requestToken = this.bgmRequestToken + 1;
    this.bgmRequestToken = requestToken;
    this.prepareBackgroundMusic(rawFileName, requestToken);
  }

  private switchBackgroundMusic(rawFileName: string): void {
    if ((this.bgmPlayer || this.bgmPreparing) && this.bgmRawFileName === rawFileName) {
      return;
    }

    const requestToken = this.bgmRequestToken + 1;
    this.bgmRequestToken = requestToken;
    this.releaseBackgroundMusic();
    this.prepareBackgroundMusic(rawFileName, requestToken);
  }

  private stopBackgroundMusic(): void {
    this.bgmRequestToken += 1;
    this.releaseBackgroundMusic();
  }

  private prepareBackgroundMusic(rawFileName: string, requestToken: number): void {
    if (requestToken !== this.bgmRequestToken) {
      return;
    }

    this.bgmRawFileName = rawFileName;
    this.bgmPreparing = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      context.resourceManager.getRawFd(rawFileName)
        .then((rawFd: resourceManager.RawFileDescriptor) => {
          if (requestToken !== this.bgmRequestToken) {
            this.closeRawFileFd(rawFileName);
            return;
          }
          this.bgmRawFileOpened = true;
          const source: media.AVFileDescriptor = {
            fd: rawFd.fd,
            offset: rawFd.offset,
            length: rawFd.length
          };
          return media.createAVPlayer()
            .then((player: media.AVPlayer) => {
              if (requestToken !== this.bgmRequestToken) {
                player.release()
                  .then(() => this.closeRawFileFd(rawFileName))
                  .catch(() => this.closeRawFileFd(rawFileName));
                return;
              }
              this.bgmPlayer = player;
              try {
                player.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason) => {
                  this.handleBackgroundMusicState(player, state, reason);
                });
                player.on('error', () => {
                  if (player === this.bgmPlayer) {
                    this.releaseBackgroundMusic();
                  }
                });
                player.fdSrc = source;
              } catch (error) {
                if (player === this.bgmPlayer) {
                  this.releaseBackgroundMusic();
                }
              }
            })
            .catch(() => {
              if (requestToken === this.bgmRequestToken) {
                this.releaseBackgroundMusic();
              }
            });
        })
        .catch(() => {
          if (requestToken === this.bgmRequestToken) {
            this.releaseBackgroundMusic();
          }
        });
    } catch (error) {
      if (requestToken === this.bgmRequestToken) {
        this.releaseBackgroundMusic();
      }
    }
  }

  private handleBackgroundMusicState(
    player: media.AVPlayer,
    state: media.AVPlayerState,
    reason: media.StateChangeReason
  ): void {
    if (player !== this.bgmPlayer) {
      return;
    }
    if (reason === media.StateChangeReason.BACKGROUND && state === 'paused') {
      this.bgmPreparing = false;
      return;
    }
    if (state === 'initialized') {
      player.prepare().catch(() => {
        if (player === this.bgmPlayer) {
          this.releaseBackgroundMusic();
        }
      });
      return;
    }
    if (state !== 'prepared') {
      return;
    }

    this.bgmPreparing = false;
    try {
      player.loop = true;
      player.setVolume(0.35);
      player.play().catch(() => {
        if (player === this.bgmPlayer) {
          this.releaseBackgroundMusic();
        }
      });
    } catch (error) {
      this.releaseBackgroundMusic();
    }
  }

  private releaseBackgroundMusic(): Promise<void> {
    const player = this.bgmPlayer;
    const rawFileName = this.bgmRawFileOpened ? this.bgmRawFileName : '';
    this.bgmPlayer = undefined;
    this.bgmPreparing = false;
    this.bgmRawFileOpened = false;
    this.bgmRawFileName = '';
    this.bgmPausedForClearSound = false;
    if (!player) {
      return this.closeRawFileFd(rawFileName);
    }

    try {
      return player.release()
        .then(() => this.closeRawFileFd(rawFileName))
        .catch(() => this.closeRawFileFd(rawFileName));
    } catch (error) {
      return this.closeRawFileFd(rawFileName);
    }
  }

  private closeRawFileFd(rawFileName: string): Promise<void> {
    if (rawFileName.length === 0) {
      return Promise.resolve();
    }

    try {
      const context = getContext(this) as common.UIAbilityContext;
      return context.resourceManager.closeRawFd(rawFileName).catch(() => {
      });
    } catch (error) {
      return Promise.resolve();
    }
  }

  private pauseBackgroundMusicForClearSound(): Promise<void> {
    if (this.bgmPausedForClearSound) {
      return Promise.resolve();
    }

    const player = this.bgmPlayer;
    if (!player) {
      return Promise.resolve();
    }

    try {
      if (player.state !== 'playing') {
        return Promise.resolve();
      }
      this.bgmPausedForClearSound = true;
      return player.pause().catch(() => {
        this.bgmPausedForClearSound = false;
      });
    } catch (error) {
      this.bgmPausedForClearSound = false;
      return Promise.resolve();
    }
  }

  private resumeBackgroundMusicAfterClearSound(): void {
    if (!this.bgmPausedForClearSound) {
      return;
    }

    this.bgmPausedForClearSound = false;
    const player = this.bgmPlayer;
    if (!player) {
      return;
    }

    try {
      if (player.state !== 'paused' && player.state !== 'prepared' && player.state !== 'completed') {
        return;
      }
      player.play().catch(() => {
      });
    } catch (error) {
    }
  }

  private playClearSoundEffect(): void {
    if (this.clearSoundPlayer || this.clearSoundPreparing) {
      return;
    }

    this.clearSoundPreparing = true;
    this.pauseBackgroundMusicForClearSound()
      .then(() => this.prepareClearSoundEffect())
      .catch(() => this.prepareClearSoundEffect());
  }

  private prepareClearSoundEffect(): void {
    if (!this.clearSoundPreparing) {
      return;
    }

    try {
      const context = getContext(this) as common.UIAbilityContext;
      context.resourceManager.getRawFd(CLEAR_SOUND_RAW_FILE)
        .then((rawFd: resourceManager.RawFileDescriptor) => {
          this.clearSoundRawFileOpened = true;
          const source: media.AVFileDescriptor = {
            fd: rawFd.fd,
            offset: rawFd.offset,
            length: rawFd.length
          };
          return media.createAVPlayer()
            .then((player: media.AVPlayer) => {
              this.clearSoundPlayer = player;
              try {
                player.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason) => {
                  this.handleClearSoundState(player, state, reason);
                });
                player.on('error', () => this.releaseClearSoundEffect());
                player.fdSrc = source;
              } catch (error) {
                this.releaseClearSoundEffect();
              }
            })
            .catch(() => {
              this.releaseClearSoundEffect();
            });
        })
        .catch(() => {
          this.releaseClearSoundEffect();
        });
    } catch (error) {
      this.releaseClearSoundEffect();
    }
  }

  private handleClearSoundState(
    player: media.AVPlayer,
    state: media.AVPlayerState,
    reason: media.StateChangeReason
  ): void {
    if (reason === media.StateChangeReason.BACKGROUND && state === 'paused') {
      this.clearSoundPreparing = false;
      return;
    }
    if (state === 'initialized') {
      player.prepare().catch(() => this.releaseClearSoundEffect());
      return;
    }
    if (state === 'completed') {
      this.releaseClearSoundEffect();
      return;
    }
    if (state !== 'prepared') {
      return;
    }

    this.clearSoundPreparing = false;
    try {
      player.loop = false;
      player.setVolume(0.85);
      player.play().catch(() => this.releaseClearSoundEffect());
    } catch (error) {
      this.releaseClearSoundEffect();
    }
  }

  private releaseClearSoundEffect(resumeBackgroundMusic: boolean = true): void {
    const player = this.clearSoundPlayer;
    this.clearSoundPlayer = undefined;
    this.clearSoundPreparing = false;
    if (!player) {
      this.finishClearSoundRelease(resumeBackgroundMusic);
      return;
    }

    try {
      player.release()
        .then(() => this.finishClearSoundRelease(resumeBackgroundMusic))
        .catch(() => this.finishClearSoundRelease(resumeBackgroundMusic));
    } catch (error) {
      this.finishClearSoundRelease(resumeBackgroundMusic);
    }
  }

  private finishClearSoundRelease(resumeBackgroundMusic: boolean): void {
    this.closeClearSoundFd();
    if (resumeBackgroundMusic) {
      this.resumeBackgroundMusicAfterClearSound();
    }
  }

  private closeClearSoundFd(): void {
    if (!this.clearSoundRawFileOpened) {
      return;
    }

    this.clearSoundRawFileOpened = false;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      context.resourceManager.closeRawFd(CLEAR_SOUND_RAW_FILE).catch(() => {
      });
    } catch (error) {
    }
  }

  @Builder
  private startPage() {
    Stack({ alignContent: Alignment.Bottom }) {
      Image($r('app.media.start_page'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)

      Column() {
        Button('开始游戏')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#3A2407')
          .backgroundColor('#FFD76A')
          .border({ width: 2, color: '#8A4E14' })
          .borderRadius(18)
          .width('68%')
          .height(58)
          .shadow({ radius: 14, color: '#00000044', offsetX: 0, offsetY: 6 })
          .onClick(() => this.startGame())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ bottom: this.isCompactLayout() ? 56 : 80 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#10261C')
    .onAreaChange((oldValue, newValue) => {
      this.updateLayoutWidth(newValue.width as number | string);
    })
  }

  @Builder
  private homeHeroCard() {
    Column({ space: 18 }) {
      if (this.isCompactLayout()) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            this.pill('发布版打磨', '#7A4D2C')
            this.pill(`${SNAIL_LEVELS.length} 个精选关卡`, '#355F46')
          }
          Row({ space: 8 }) {
            this.pill('本地进度保存', '#566F23')
          }
        }
        .width('100%')
      } else {
        Row({ space: 8 }) {
          this.pill('发布版打磨', '#7A4D2C')
          this.pill(`${SNAIL_LEVELS.length} 个精选关卡`, '#355F46')
          this.pill('本地进度保存', '#566F23')
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }

      Text('蜗牛推箱子')
        .fontSize(this.isCompactLayout() ? 34 : 42)
        .fontWeight(FontWeight.Bolder)
        .fontColor('#FFF6E6')
        .fontFamily('HarmonyOS Sans SC')

      Text(`围绕 ${SNAIL_LEVELS.length} 个手工设计关卡重新整理的正式版：流程更完整，反馈更稳定，通关评级和最近游玩进度都会自动保存在本机。`)
        .fontSize(15)
        .lineHeight(24)
        .fontColor('#E6DEC8')
        .width(this.isCompactLayout() ? '100%' : '76%')

      if (this.isCompactLayout()) {
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            this.metricCard('已完成', `${this.completedLevelCount()} / ${SNAIL_LEVELS.length}`, '#EBCB74')
            this.metricCard('总评级', `${this.totalStarCount()} / ${SNAIL_LEVELS.length * 3}`, '#7BC19A')
          }
          Row({ space: 10 }) {
            this.metricCard('推荐关卡', `第 ${this.recommendedLevelIndex() + 1} 关`, '#DFAE6B')
            this.metricCard('当前记录', this.homeRecordSummary(), '#9FC5E8')
          }
        }
        .width('100%')
      } else {
        Row({ space: 10 }) {
          this.metricCard('已完成', `${this.completedLevelCount()} / ${SNAIL_LEVELS.length}`, '#EBCB74')
          this.metricCard('总评级', `${this.totalStarCount()} / ${SNAIL_LEVELS.length * 3}`, '#7BC19A')
          this.metricCard('推荐关卡', `第 ${this.recommendedLevelIndex() + 1} 关`, '#DFAE6B')
          this.metricCard('当前记录', this.homeRecordSummary(), '#9FC5E8')
        }
        .width('100%')
      }

      if (this.isCompactLayout()) {
        Column({ space: 10 }) {
          this.heroButton(this.hasAnyRecord() ? '继续冒险' : '开始游戏', '#E0B457', true, true, () => this.continueAdventure())
          this.heroButton('挑战推荐关卡', '#2E6A4E', true, true, () => this.playRecommendedLevel())
        }
        .width('100%')
      } else {
        Row({ space: 10 }) {
          this.heroButton(this.hasAnyRecord() ? '继续冒险' : '开始游戏', '#E0B457', true, false, () => this.continueAdventure())
          this.heroButton('挑战推荐关卡', '#2E6A4E', true, false, () => this.playRecommendedLevel())
        }
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(this.isCompactLayout() ? 18 : 22)
    .backgroundColor('#1B3B2D')
    .borderRadius(28)
  }

  @Builder
  private levelOverviewCard() {
    Column({ space: 14 }) {
      Text('关卡总览')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFF6E6')

      Text(`当前一共 ${SNAIL_LEVELS.length} 关。每一关都支持重玩、通关评级和自动进度保存。`)
        .fontSize(14)
        .fontColor('#D8D3C3')

      ForEach(this.levelIndices(), (levelIndex: number) => {
        this.levelCard(levelIndex, false)
      }, (levelIndex: number) => `home-level-${levelIndex}`)
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#183126')
    .borderRadius(26)
  }

  @Builder
  private featureCard() {
    Column({ space: 12 }) {
      Text('系统特色')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFF6E6')

      if (this.isCompactLayout()) {
        Column({ space: 10 }) {
          this.featureItem('稳定规则', '墙体、空洞、推箱判定分离处理，避免走出棋盘。')
          this.featureItem('局内反馈', '支持撤销、重开、死角提示和即时状态说明。')
          this.featureItem('发布级流程', '首页总览、自由选关、评级纪录和自动保存都已接通。')
        }
      } else {
        Row({ space: 10 }) {
          this.featureItem('稳定规则', '墙体、空洞、推箱判定分离处理，避免走出棋盘。')
          this.featureItem('局内反馈', '支持撤销、重开、死角提示和即时状态说明。')
          this.featureItem('发布级流程', '首页总览、自由选关、评级纪录和自动保存都已接通。')
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#183126')
    .borderRadius(26)
  }

  @Builder
  private playHeader() {
    Column({ space: 12 }) {
      if (this.isCompactLayout()) {
        Column({ space: 8 }) {
          Row({ space: 10 }) {
            Button('返回总览')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .backgroundColor('#2D4C3B')
              .border({ width: 1, color: '#E6D5A844' })
              .borderRadius(16)
              .height(42)
              .shadow({ radius: 8, color: '#00000024', offsetX: 0, offsetY: 3 })
              .onClick(() => this.returnHome())

            this.pill(`第 ${this.levelIndex + 1} 关`, '#7A4D2C')
          }
          Row({ space: 8 }) {
            this.pill(this.currentLevel().difficulty, this.difficultyColor(this.currentLevel().difficulty))
            this.pill(this.isCleared ? '已通关' : '进行中', this.isCleared ? '#2C7A51' : '#74603B')
          }
        }
        .width('100%')
      } else {
        Row({ space: 10 }) {
          Button('返回总览')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .backgroundColor('#2D4C3B')
            .border({ width: 1, color: '#E6D5A844' })
            .borderRadius(16)
            .height(42)
            .shadow({ radius: 8, color: '#00000024', offsetX: 0, offsetY: 3 })
            .onClick(() => this.returnHome())

          this.pill(`第 ${this.levelIndex + 1} 关`, '#7A4D2C')
          this.pill(this.currentLevel().difficulty, this.difficultyColor(this.currentLevel().difficulty))
          this.pill(this.isCleared ? '已通关' : '进行中', this.isCleared ? '#2C7A51' : '#74603B')
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }

      Text(this.currentLevelTitle())
        .fontSize(this.isCompactLayout() ? 28 : 32)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFF6E6')

      Text(this.currentLevel().subtitle)
        .fontSize(14)
        .lineHeight(22)
        .fontColor('#D8D3C3')

      if (this.isCompactLayout()) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            this.pill(`目标 ${this.coveredGoalsText()}`, '#436A4F')
            this.pill(`标杆 ${this.currentLevel().parMoves} 步`, '#61523A')
          }
          Row({ space: 8 }) {
            this.pill(this.currentBestLabel(), '#345A73')
          }
        }
        .width('100%')
      } else {
        Row({ space: 8 }) {
          this.pill(`目标 ${this.coveredGoalsText()}`, '#436A4F')
          this.pill(`标杆 ${this.currentLevel().parMoves} 步`, '#61523A')
          this.pill(this.currentBestLabel(), '#345A73')
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
    }
    .width('100%')
  }

  @Builder
  private controlCard() {
    Column({ space: 14 }) {
      Text('局内控制')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#241C14')

      Row({ space: 8 }) {
        this.actionButton('上一关', '#6A5A47', this.levelIndex > 0, () => this.previousLevel())
        this.actionButton('下一关', '#2F6A4B', this.canEnterNextLevel(), () => this.nextLevel())
      }
      .width('100%')

      Row({ space: 8 }) {
        this.actionButton('撤销', '#8A633C', this.history.length > 0, () => this.undoMove())
        this.actionButton('重开', '#A04F2F', true, () => this.resetLevel())
      }
      .width('100%')

      this.currentLevelInfoRow()
      this.infoRow('步数', `${this.moveCount}`)
      this.infoRow('推箱', `${this.pushCount}`)
      this.infoRow('完成度', this.coveredGoalsText())
      this.infoRow('评级标杆', `${this.currentLevel().parMoves} 步`)
      this.infoRow('最好成绩', this.currentBestLabel())

      Text(this.statusText)
        .fontSize(13)
        .lineHeight(20)
        .fontColor(this.statusFontColor())
        .width('100%')
        .padding(14)
        .backgroundColor(this.statusBackgroundColor())
        .borderRadius(14)
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#F1E4CD')
    .borderRadius(22)
  }

  @Builder
  private currentLevelInfoRow() {
    Row({ space: 12 }) {
      Text('关卡')
        .fontSize(13)
        .fontColor('#6B5B48')
        .width(74)

      Text(`第 ${this.levelIndex + 1} / ${SNAIL_LEVELS.length} 关 · ${this.currentLevel().name}`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#241C14')
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }

  @Builder
  private ruleCard() {
    Column({ space: 10 }) {
      Text('玩法与提示')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#241C14')

      Text('1. 蜗牛每次只能移动一格，木箱只能推不能拉。')
        .fontSize(13)
        .lineHeight(20)
        .fontColor('#4B3D2B')

      Text('2. 如果箱子后方是墙、木箱或空洞，当前步就会被阻止。')
        .fontSize(13)
        .lineHeight(20)
        .fontColor('#4B3D2B')

      Text('3. 死角提示只负责提醒明显的角落卡死，最优解仍然需要自己规划。')
        .fontSize(13)
        .lineHeight(20)
        .fontColor('#4B3D2B')

      Text(`本关提示：${this.currentLevel().hint}`)
        .fontSize(13)
        .lineHeight(20)
        .fontColor('#56742B')

      Text('说明：通关纪录、评级和最近游玩进度会自动保存。')
        .fontSize(13)
        .lineHeight(20)
        .fontColor('#6A573C')
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#F1E4CD')
    .borderRadius(22)
  }

  @Builder
  private boardCard() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text('棋盘')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFF6E6')
        this.pill(this.boardFooterLabel(), '#3F6A55')
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      Stack() {
        Column({ space: 0 }) {
          ForEach(this.rowIndices(), (row: number) => {
            Row({ space: 0 }) {
              ForEach(this.colIndices(), (col: number) => {
                this.boardCell(row, col)
              }, (col: number) => `col-${row}-${col}`)
            }
          }, (row: number) => `row-${row}`)
        }
        .padding(14)
        .backgroundColor('#DCC9A5')
        .borderRadius(22)

        if (this.isCleared) {
          this.clearOverlay()
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#21382B')
      .borderRadius(24)

      this.boardControlTray()

      Text(this.boardHintText())
        .fontSize(13)
        .lineHeight(20)
        .fontColor('#D8D3C3')
        .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#173126')
    .borderRadius(24)
  }

  @Builder
  private clearOverlay() {
    Column({ space: 12 }) {
      Text('关卡完成')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFF6E6')

      Row({ space: 6 }) {
        ForEach([0, 1, 2], (starIndex: number) => {
          Text('★')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(starIndex < this.lastClearStars ? '#FFD86A' : '#6D7A5A')
            .opacity(this.clearOverlayStarOpacity(starIndex))
        }, (starIndex: number) => `clear-star-${starIndex}`)
      }
      .justifyContent(FlexAlign.Center)

      Text(this.clearOverlayLabel())
        .fontSize(14)
        .lineHeight(22)
        .fontColor('#E8F6E8')
        .textAlign(TextAlign.Center)

      Row({ space: 8 }) {
        this.overlayButton(this.hasNextLevel() ? '下一关' : '回到总览', '#2E7A52', true, () => {
          if (this.hasNextLevel()) {
            this.nextLevel();
          } else {
            this.returnHome();
          }
        })
        this.overlayButton('重玩本关', '#A05A33', true, () => this.resetLevel())
      }
    }
    .padding({ left: 24, right: 24, top: 22, bottom: 22 })
    .backgroundColor('#163927F2')
    .border({ width: 1, color: '#9CD78A66' })
    .borderRadius(20)
    .opacity(this.clearOverlayOpacity())
    .scale({ x: this.clearOverlayScale(), y: this.clearOverlayScale() })
    .translate({ y: this.clearOverlayTranslateY() })
    .shadow({ radius: 20, color: '#00000055', offsetX: 0, offsetY: 8 })
  }

  @Builder
  private boardControlTray() {
    Column({ space: 10 }) {
      Text('棋盘旁控制')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFF6E6')
        .width('100%')

      this.directionPad()
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#203528')
    .borderRadius(18)
  }

  @Builder
  private levelRailCard() {
    Column({ space: 12 }) {
      Text('路线总览')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.currentView === VIEW_PLAY ? '#241C14' : '#FFF6E6')

      Text(this.campaignSummaryText())
        .fontSize(13)
        .lineHeight(20)
        .fontColor(this.currentView === VIEW_PLAY ? '#5C4B38' : '#D8D3C3')

      ForEach(this.levelIndices(), (levelIndex: number) => {
        this.levelCard(levelIndex, true)
      }, (levelIndex: number) => `rail-level-${levelIndex}`)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.currentView === VIEW_PLAY ? '#F1E4CD' : '#183126')
    .borderRadius(24)
  }

  @Builder
  private levelCard(levelIndex: number, compact: boolean) {
    Column({ space: compact ? 8 : 10 }) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(`第 ${levelIndex + 1} 关`)
            .fontSize(12)
            .fontColor('#7A6A57')

          Text(SNAIL_LEVELS[levelIndex].name)
            .fontSize(compact ? 16 : 18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#201912')

          if (!compact) {
            Text(SNAIL_LEVELS[levelIndex].subtitle)
              .fontSize(12)
              .lineHeight(18)
              .fontColor('#5B4B39')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          this.pill(SNAIL_LEVELS[levelIndex].difficulty, this.difficultyColor(SNAIL_LEVELS[levelIndex].difficulty))
          this.pill(this.levelStateLabel(levelIndex), this.levelStateColor(levelIndex))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row({ space: 8 }) {
        this.metaCard('目标', `${this.levelGoalCount(levelIndex)} 箱`)
        this.metaCard('标杆', `${SNAIL_LEVELS[levelIndex].parMoves} 步`)
        this.metaCard('纪录', this.levelRecordShortLabel(levelIndex))
      }
      .width('100%')

      if (!compact) {
        Text(SNAIL_LEVELS[levelIndex].hint)
          .fontSize(12)
          .lineHeight(18)
          .fontColor('#587035')
          .width('100%')
      }

      Text(this.levelActionHint(levelIndex))
        .fontSize(12)
        .fontColor('#305B46')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(compact ? 14 : 16)
    .backgroundColor(this.levelCardBackground(levelIndex))
    .borderRadius(18)
    .onClick(() => this.openLevel(levelIndex))
  }

  @Builder
  private directionPad() {
    Column({ space: 10 }) {
      Text('方向键')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#241C14')

      Row({ space: 8 }) {
        Blank()
          .width(72)
          .height(48)
        this.directionButton('上', () => this.moveSnail(-1, 0))
        Blank()
          .width(72)
          .height(48)
      }
      .width(this.directionPadWidth())

      Row({ space: 8 }) {
        this.directionButton('左', () => this.moveSnail(0, -1))
        this.directionButton('下', () => this.moveSnail(1, 0))
        this.directionButton('右', () => this.moveSnail(0, 1))
      }
      .width(this.directionPadWidth())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private boardCell(row: number, col: number) {
    if (!this.isBoardCell(row, col)) {
      Blank()
        .width(this.cellSize())
        .height(this.cellSize())
    } else {
      Stack() {
        Column() {
          Blank()
        }
        .width(this.cellSize())
        .height(this.cellSize())
        .backgroundColor(this.cellBackgroundColor(row, col))
        .border({ width: 1, color: this.cellBorderColor(row, col) })
        .borderRadius(this.isWallCell(row, col) ? 12 : 7)

        if (this.isGoalCell(row, col) && !this.isWallCell(row, col)) {
          this.goalToken(this.cellSize())
        }

        if (this.hasBoxAt(row, col)) {
          this.boxToken(this.cellSize(), this.isGoalCell(row, col), this.isDeadlockedBoxCell(row, col))
        }

        if (this.isPlayerAt(row, col)) {
          this.snailToken(this.cellSize())
        }
      }
      .width(this.cellSize())
      .height(this.cellSize())
    }
  }

  @Builder
  private goalToken(size: number) {
    Stack() {
      Column() {
        Blank()
      }
      .width(size * 0.76)
      .height(size * 0.48)
      .backgroundColor('#7FBF58')
      .opacity(0.52)
      .border({ width: 2, color: '#3E7635' })
      .borderRadius(size * 0.28)

      Column() {
        Blank()
      }
      .width(size * 0.44)
      .height(size * 0.06)
      .backgroundColor('#E6F5A6')
      .opacity(0.7)
      .borderRadius(999)

      Column() {
        Blank()
      }
      .width(size * 0.14)
      .height(size * 0.14)
      .backgroundColor('#F6D36C')
      .border({ width: 1, color: '#8A6A23' })
      .borderRadius(size * 0.07)
    }
  }

  @Builder
  private boxToken(size: number, onGoal: boolean, deadlocked: boolean) {
    Stack() {
      Column() {
        Blank()
      }
      .width(size * 0.74)
      .height(size * 0.74)
      .backgroundColor(deadlocked ? '#B55B45' : onGoal ? '#D9AE47' : '#B87B35')
      .border({ width: 2, color: deadlocked ? '#6E2D1E' : onGoal ? '#7A5A16' : '#744918' })
      .borderRadius(9)

      Column() {
        Blank()
      }
      .width(size * 0.68)
      .height(size * 0.12)
      .backgroundColor(deadlocked ? '#E2A091' : '#F6D089')
      .opacity(0.8)
      .borderRadius(4)

      Row({ space: 0 }) {
        Blank()
          .width(size * 0.12)
          .height(size * 0.66)
          .backgroundColor(deadlocked ? '#8A3A2C' : '#8B5420')
          .opacity(0.72)
        Blank()
          .width(size * 0.16)
          .height(size * 0.66)
          .opacity(0)
        Blank()
          .width(size * 0.12)
          .height(size * 0.66)
          .backgroundColor(deadlocked ? '#8A3A2C' : '#8B5420')
          .opacity(0.72)
      }

      Text('X')
        .fontSize(size * 0.42)
        .fontWeight(FontWeight.Bold)
        .fontColor(deadlocked ? '#FFE7DA' : '#5C3517')
        .opacity(deadlocked ? 0.82 : 0.42)

      if (deadlocked) {
        Text('!')
          .fontSize(size * 0.24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFF7EE')
      }
    }
  }

  @Builder
  private snailToken(size: number) {
    Row({ space: size * 0.02 }) {
      Stack() {
        Column() {
          Blank()
        }
        .width(size * 0.42)
        .height(size * 0.42)
        .backgroundColor('#7B4324')
        .border({ width: 2, color: '#4A2817' })
        .borderRadius(size * 0.21)

        Column() {
          Blank()
        }
        .width(size * 0.26)
        .height(size * 0.26)
        .border({ width: 2, color: '#DDA857' })
        .borderRadius(size * 0.13)

        Column() {
          Blank()
        }
        .width(size * 0.1)
        .height(size * 0.1)
        .backgroundColor('#F8DC97')
        .borderRadius(size * 0.05)
      }

      Column({ space: size * 0.02 }) {
        Row({ space: size * 0.14 }) {
          Blank()
            .width(size * 0.04)
            .height(size * 0.2)
            .backgroundColor('#F1B75C')
            .borderRadius(999)
          Blank()
            .width(size * 0.04)
            .height(size * 0.2)
            .backgroundColor('#F1B75C')
            .borderRadius(999)
        }
        .height(size * 0.14)

        Blank()
          .width(size * 0.34)
          .height(size * 0.2)
          .backgroundColor('#E39E3F')
          .border({ width: 1, color: '#9F6123' })
          .borderRadius(size * 0.1)

        Row({ space: size * 0.05 }) {
          Blank()
            .width(size * 0.06)
            .height(size * 0.06)
            .backgroundColor('#241C14')
            .borderRadius(size * 0.03)
          Blank()
            .width(size * 0.06)
            .height(size * 0.06)
            .backgroundColor('#241C14')
            .borderRadius(size * 0.03)
        }
      }
    }
    .padding({ left: size * 0.06, right: size * 0.04 })
  }

  @Builder
  private metricCard(label: string, value: string, accentColor: string) {
    Column({ space: 8 }) {
      Text(label)
        .fontSize(12)
        .fontColor('#E6DEC8')

      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFF6E6')

      Blank()
        .width('100%')
        .height(4)
        .backgroundColor(accentColor)
        .borderRadius(999)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(14)
    .backgroundColor('#244537')
    .borderRadius(18)
  }

  @Builder
  private featureItem(title: string, body: string) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFF6E6')

      Text(body)
        .fontSize(13)
        .lineHeight(20)
        .fontColor('#D8D3C3')
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(14)
    .backgroundColor('#214133')
    .borderRadius(18)
  }

  @Builder
  private infoRow(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(13)
        .fontColor('#6B5B48')
        .width(74)

      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#241C14')
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }

  @Builder
  private metaCard(label: string, value: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontColor('#7A6A57')

      Text(value)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#241C14')
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(10)
    .backgroundColor('#F5ECD8')
    .borderRadius(14)
  }

  @Builder
  private pill(label: string, color: string) {
    Text(label)
      .fontSize(12)
      .fontColor('#FFFDF7')
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(color)
      .borderRadius(999)
  }

  @Builder
  private heroButton(label: string, color: string, enabled: boolean, block: boolean, handler: () => void) {
    if (block) {
      Button(label)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .backgroundColor(color)
        .border({ width: 1, color: '#FFF4CF55' })
        .borderRadius(16)
        .width('100%')
        .height(48)
        .opacity(enabled ? 1 : 0.4)
        .shadow({ radius: 10, color: '#00000033', offsetX: 0, offsetY: 4 })
        .onClick(() => {
          if (enabled) {
            handler();
          }
        })
    } else {
      Button(label)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .backgroundColor(color)
        .border({ width: 1, color: '#FFF4CF55' })
        .borderRadius(16)
        .layoutWeight(1)
        .height(48)
        .opacity(enabled ? 1 : 0.4)
        .shadow({ radius: 10, color: '#00000033', offsetX: 0, offsetY: 4 })
        .onClick(() => {
          if (enabled) {
            handler();
          }
        })
    }
  }

  @Builder
  private actionButton(label: string, color: string, enabled: boolean, handler: () => void) {
    Button(label)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .backgroundColor(color)
      .border({ width: 1, color: '#FFF4CF44' })
      .borderRadius(16)
      .layoutWeight(1)
      .height(44)
      .opacity(enabled ? 1 : 0.4)
      .shadow({ radius: 8, color: '#0000002E', offsetX: 0, offsetY: 3 })
      .onClick(() => {
        if (enabled) {
          handler();
        }
      })
  }

  @Builder
  private overlayButton(label: string, color: string, enabled: boolean, handler: () => void) {
    Button(label)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .backgroundColor(color)
      .border({ width: 1, color: '#FFF4CF44' })
      .borderRadius(16)
      .layoutWeight(1)
      .height(44)
      .opacity(enabled ? 1 : 0.4)
      .shadow({ radius: 8, color: '#00000033', offsetX: 0, offsetY: 3 })
      .onClick(() => {
        if (enabled) {
          handler();
        }
      })
  }

  @Builder
  private directionButton(label: string, handler: () => void) {
    Button(label)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .backgroundColor('#4B6F40')
      .border({ width: 1, color: '#DCE9B855' })
      .width(72)
      .height(48)
      .borderRadius(16)
      .shadow({ radius: 7, color: '#0000002A', offsetX: 0, offsetY: 3 })
      .onClick(() => handler())
  }

  private currentLevel(): SnailLevel {
    return SNAIL_LEVELS[this.levelIndex];
  }

  private currentLevelTitle(): string {
    return `第 ${this.levelIndex + 1} 关 · ${this.currentLevel().name}`;
  }

  private setStatus(text: string, tone: number): void {
    this.statusText = text;
    this.statusTone = tone;
  }

  private statusBackgroundColor(): string {
    if (this.statusTone === 1) {
      return '#D7F0D4';
    }
    if (this.statusTone === 2) {
      return '#F1E3C4';
    }
    if (this.statusTone === 3) {
      return '#F0CFC9';
    }
    return '#E8DEC7';
  }

  private statusFontColor(): string {
    if (this.statusTone === 1) {
      return '#28523A';
    }
    if (this.statusTone === 2) {
      return '#694D1D';
    }
    if (this.statusTone === 3) {
      return '#6B251A';
    }
    return '#4A3A2A';
  }

  private readSaveData(): SaveData {
    try {
      const raw = JSON.parse(this.saveDataText) as SaveData;
      const records = this.normalizeRecords(raw.records);
      return {
        lastPlayedLevelIndex: this.safeLevelIndex(raw.lastPlayedLevelIndex),
        records
      };
    } catch (error) {
      return this.defaultSaveData();
    }
  }

  private writeSaveData(saveData: SaveData): void {
    const normalized: SaveData = {
      lastPlayedLevelIndex: this.safeLevelIndex(saveData.lastPlayedLevelIndex),
      records: this.normalizeRecords(saveData.records)
    };
    this.saveDataText = JSON.stringify(normalized);
  }

  private ensureSaveData(): void {
    this.writeSaveData(this.readSaveData());
  }

  private defaultSaveData(): SaveData {
    return {
      lastPlayedLevelIndex: 0,
      records: []
    };
  }

  private normalizeRecords(records: LevelRecord[]): LevelRecord[] {
    const next: LevelRecord[] = [];
    if (!Array.isArray(records)) {
      return next;
    }

    for (let index = 0; index < records.length; index++) {
      const item = records[index];
      if (!item) {
        continue;
      }
      const levelId = Number(item.levelId);
      const bestMoves = Number(item.bestMoves);
      const bestPushes = Number(item.bestPushes);
      const bestStars = Number(item.bestStars);
      const attemptCount = Number(item.attemptCount);
      if (Number.isNaN(levelId) || levelId <= 0) {
        continue;
      }
      next.push({
        levelId,
        bestMoves: Number.isNaN(bestMoves) || bestMoves <= 0 ? 0 : bestMoves,
        bestPushes: Number.isNaN(bestPushes) || bestPushes <= 0 ? 0 : bestPushes,
        bestStars: Number.isNaN(bestStars) || bestStars <= 0 ? 0 : bestStars,
        attemptCount: Number.isNaN(attemptCount) || attemptCount <= 0 ? 1 : attemptCount
      });
    }

    return next;
  }

  private safeLevelIndex(index: number): number {
    if (Number.isNaN(index) || index < 0) {
      return 0;
    }
    if (index >= SNAIL_LEVELS.length) {
      return SNAIL_LEVELS.length - 1;
    }
    return index;
  }

  private updateLastPlayedLevel(levelIndex: number): void {
    const saveData = this.readSaveData();
    saveData.lastPlayedLevelIndex = levelIndex;
    this.writeSaveData(saveData);
  }

  private persistChallengeRecord(levelIndex: number): void {
    const saveData = this.readSaveData();
    saveData.lastPlayedLevelIndex = levelIndex;

    const levelId = SNAIL_LEVELS[levelIndex].id;
    let matched = false;
    for (let recordIndex = 0; recordIndex < saveData.records.length; recordIndex++) {
      if (saveData.records[recordIndex].levelId !== levelId) {
        continue;
      }
      matched = true;
      saveData.records[recordIndex].attemptCount += 1;
    }

    if (!matched) {
      saveData.records.push({
        levelId,
        bestMoves: 0,
        bestPushes: 0,
        bestStars: 0,
        attemptCount: 1
      });
    }

    this.writeSaveData(saveData);
  }

  private persistClearRecord(levelIndex: number, moves: number, pushes: number, stars: number): void {
    const saveData = this.readSaveData();
    saveData.lastPlayedLevelIndex = levelIndex;

    const levelId = SNAIL_LEVELS[levelIndex].id;
    let matched = false;
    for (let recordIndex = 0; recordIndex < saveData.records.length; recordIndex++) {
      if (saveData.records[recordIndex].levelId !== levelId) {
        continue;
      }
      matched = true;
      const record = saveData.records[recordIndex];
      record.bestMoves = record.bestMoves === 0 ? moves : Math.min(record.bestMoves, moves);
      record.bestPushes = record.bestPushes === 0 ? pushes : Math.min(record.bestPushes, pushes);
      record.bestStars = Math.max(record.bestStars, stars);
      record.attemptCount = Math.max(1, record.attemptCount);
    }

    if (!matched) {
      saveData.records.push({
        levelId,
        bestMoves: moves,
        bestPushes: pushes,
        bestStars: stars,
        attemptCount: 1
      });
    }

    this.writeSaveData(saveData);
  }

  private findRecordForLevel(levelIndex: number): LevelRecord | undefined {
    const levelId = SNAIL_LEVELS[levelIndex].id;
    const records = this.readSaveData().records;
    for (let index = 0; index < records.length; index++) {
      if (records[index].levelId === levelId) {
        return records[index];
      }
    }
    return undefined;
  }

  private hasAnyRecord(): boolean {
    return this.readSaveData().records.length > 0;
  }

  private completedLevelCount(): number {
    let count = 0;
    const records = this.readSaveData().records;
    for (let index = 0; index < records.length; index++) {
      if (this.isClearedRecord(records[index])) {
        count += 1;
      }
    }
    return count;
  }

  private challengedLevelCount(): number {
    return this.readSaveData().records.length;
  }

  private totalStarCount(): number {
    let total = 0;
    const records = this.readSaveData().records;
    for (let index = 0; index < records.length; index++) {
      total += records[index].bestStars;
    }
    return total;
  }

  private recommendedLevelIndex(): number {
    for (let levelIndex = 0; levelIndex < SNAIL_LEVELS.length; levelIndex++) {
      if (!this.isLevelCleared(levelIndex)) {
        return levelIndex;
      }
    }
    return SNAIL_LEVELS.length - 1;
  }

  private homeRecordSummary(): string {
    if (!this.hasAnyRecord()) {
      return '等待首通';
    }
    const record = this.findRecordForLevel(this.readSaveData().lastPlayedLevelIndex);
    if (!record) {
      return `${this.totalStarCount()} 星`;
    }
    if (!this.isClearedRecord(record)) {
      return `挑战 ${record.attemptCount} 次`;
    }
    return `${record.bestMoves} 步`;
  }

  private campaignSummaryText(): string {
    return `已挑战 ${this.challengedLevelCount()} / ${SNAIL_LEVELS.length} 关，已完成 ${this.completedLevelCount()} / ${SNAIL_LEVELS.length} 关，累计评级 ${this.totalStarCount()} / ${SNAIL_LEVELS.length * 3} 星。`;
  }

  private levelGoalCount(levelIndex: number): number {
    return parseLevel(SNAIL_LEVELS[levelIndex]).boxKeys.length;
  }

  private levelRecordShortLabel(levelIndex: number): string {
    const record = this.findRecordForLevel(levelIndex);
    if (!record) {
      return '未挑战';
    }
    if (!this.isClearedRecord(record)) {
      return `挑战 ${record.attemptCount} 次`;
    }
    return `${record.bestStars} 星`;
  }

  private currentBestLabel(): string {
    const record = this.findRecordForLevel(this.levelIndex);
    if (!record) {
      return '尚未挑战';
    }
    if (!this.isClearedRecord(record)) {
      return `已挑战 ${record.attemptCount} 次`;
    }
    return `${record.bestMoves} 步 · ${record.bestStars} 星`;
  }

  private bestStarsForLevel(levelIndex: number): number {
    const record = this.findRecordForLevel(levelIndex);
    return record ? record.bestStars : 0;
  }

  private starRating(levelIndex: number, moves: number): number {
    const parMoves = SNAIL_LEVELS[levelIndex].parMoves;
    const silverLimit = parMoves + this.starAllowance(parMoves);
    if (moves <= parMoves) {
      return 3;
    }
    if (moves <= silverLimit) {
      return 2;
    }
    return 1;
  }

  private starAllowance(parMoves: number): number {
    return Math.max(2, Math.floor(parMoves / 4));
  }

  private isLevelCleared(levelIndex: number): boolean {
    const record = this.findRecordForLevel(levelIndex);
    return record !== undefined && this.isClearedRecord(record);
  }

  private isLevelChallenged(levelIndex: number): boolean {
    return this.findRecordForLevel(levelIndex) !== undefined;
  }

  private isClearedRecord(record: LevelRecord): boolean {
    return record.bestStars > 0 && record.bestMoves > 0;
  }

  private levelStateLabel(levelIndex: number): string {
    if (this.isLevelCleared(levelIndex)) {
      return '已通关';
    }
    if (this.isLevelChallenged(levelIndex)) {
      return '已挑战';
    }
    return '可挑战';
  }

  private levelStateColor(levelIndex: number): string {
    if (this.isLevelCleared(levelIndex)) {
      return '#2F7A51';
    }
    if (this.isLevelChallenged(levelIndex)) {
      return '#496D7C';
    }
    return '#8B6637';
  }

  private difficultyColor(difficulty: string): string {
    if (difficulty === '入门') {
      return '#5E8A2F';
    }
    if (difficulty === '挑战') {
      return '#915032';
    }
    return '#496D7C';
  }

  private levelActionHint(levelIndex: number): string {
    if (this.currentView === VIEW_PLAY && levelIndex === this.levelIndex) {
      return '当前正在挑战';
    }
    if (this.isLevelCleared(levelIndex)) {
      return '点击重玩并刷新成绩';
    }
    return '点击进入关卡';
  }

  private levelCardBackground(levelIndex: number): string {
    if (this.currentView === VIEW_PLAY && levelIndex === this.levelIndex) {
      return '#E9DCC0';
    }
    return '#F1E4CD';
  }

  private canEnterNextLevel(): boolean {
    return this.levelIndex < SNAIL_LEVELS.length - 1;
  }

  private hasNextLevel(): boolean {
    return this.levelIndex < SNAIL_LEVELS.length - 1;
  }

  private coveredGoalsText(): string {
    return `${countGoalsCovered(this.boxKeys, this.goalKeys)} / ${this.goalKeys.length}`;
  }

  private clearOverlayLabel(): string {
    return `当前成绩 ${this.moveCount} 步，推箱 ${this.pushCount} 次，评级 ${this.lastClearStars} 星。`;
  }

  private clearOverlayOpacity(): number {
    return 0.88 + this.clearOverlayProgress * 0.12;
  }

  private clearOverlayScale(): number {
    return 0.92 + this.clearOverlayProgress * 0.08;
  }

  private clearOverlayTranslateY(): number {
    return 14 - this.clearOverlayProgress * 14;
  }

  private clearOverlayStarOpacity(starIndex: number): number {
    const revealProgress = this.clearOverlayProgress * 3;
    if (revealProgress >= starIndex + 1) {
      return 1;
    }
    return 0.32;
  }

  private boardFooterLabel(): string {
    if (this.deadlockedBoxKeys.length > 0) {
      return '死角预警';
    }
    if (this.isCleared) {
      return '通关完成';
    }
    if (this.currentLevel().orientation === 'vertical') {
      return '竖版地图';
    }
    return '移动规划';
  }

  private boardHintText(): string {
    if (this.deadlockedBoxKeys.length > 0) {
      return '检测到明显死角：当前有木箱被顶进角落，建议尽快使用撤销。';
    }
    if (this.isCleared) {
      return '本关记录已保存，可以继续下一关或重刷更高评级。';
    }
    return `本关提示：${this.currentLevel().hint}`;
  }

  private isBoardCell(row: number, col: number): boolean {
    return this.isWallCell(row, col) || this.isFloorCell(row, col);
  }

  private isFloorCell(row: number, col: number): boolean {
    return hasKey(this.floorKeys, keyFor(row, col));
  }

  private isWallCell(row: number, col: number): boolean {
    return hasKey(this.wallKeys, keyFor(row, col));
  }

  private isGoalCell(row: number, col: number): boolean {
    return hasKey(this.goalKeys, keyFor(row, col));
  }

  private hasBoxAt(row: number, col: number): boolean {
    return hasKey(this.boxKeys, keyFor(row, col));
  }

  private isDeadlockedBoxCell(row: number, col: number): boolean {
    return hasKey(this.deadlockedBoxKeys, keyFor(row, col));
  }

  private isPlayerAt(row: number, col: number): boolean {
    return this.playerKey === keyFor(row, col);
  }

  private cellBackgroundColor(row: number, col: number): string {
    if (this.isWallCell(row, col)) {
      return '#5A6E48';
    }
    if (this.isGoalCell(row, col)) {
      return (row + col) % 2 === 0 ? '#E9E2AE' : '#E2D99A';
    }
    return (row + col) % 2 === 0 ? '#F3E4C4' : '#EBDAB6';
  }

  private cellBorderColor(row: number, col: number): string {
    if (this.isWallCell(row, col)) {
      return '#3F5136';
    }
    if (this.isGoalCell(row, col)) {
      return '#B8B16B';
    }
    return '#D5C39E';
  }

  private rowIndices(): number[] {
    const rows: number[] = [];
    for (let row = 0; row < this.boardHeight; row++) {
      rows.push(row);
    }
    return rows;
  }

  private colIndices(): number[] {
    const cols: number[] = [];
    for (let col = 0; col < this.boardWidth; col++) {
      cols.push(col);
    }
    return cols;
  }

  private levelIndices(): number[] {
    const indices: number[] = [];
    for (let index = 0; index < SNAIL_LEVELS.length; index++) {
      indices.push(index);
    }
    return indices;
  }

  private cellSize(): number {
    if (this.layoutWidth <= 0) {
      return 48;
    }
    const availableWidth = this.isCompactLayout() ? this.layoutWidth - 124 : this.layoutWidth * 0.36 - 92;
    const nextSize = Math.floor(availableWidth / Math.max(this.boardWidth, 1));
    return Math.max(20, Math.min(56, nextSize));
  }

  private isCompactLayout(): boolean {
    return this.layoutWidth > 0 && this.layoutWidth < 960;
  }

  private directionPadWidth(): number {
    return 72 * 3 + 8 * 2;
  }

  private updateLayoutWidth(width: number | string): void {
    const nextWidth = typeof width === 'number' ? width : Number.parseFloat(width);
    if (!Number.isNaN(nextWidth) && nextWidth > 0) {
      this.layoutWidth = nextWidth;
    }
  }
}
