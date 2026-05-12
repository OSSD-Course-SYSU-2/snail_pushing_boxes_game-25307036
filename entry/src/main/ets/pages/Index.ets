import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { media } from '@kit.MediaKit';
import { SNAIL_LEVELS, SnailLevel } from '../data/SnailLevels';
import { Colors, FontSize, Radius, Shadow, Spacing } from '../theme/VisualTheme';
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
        Column({ space: this.currentView === VIEW_HOME ? Spacing.section : 18 }) {
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
        .padding(this.currentView === VIEW_HOME ? Spacing.pageRegular : this.isCompactLayout() ? Spacing.pageCompact : Spacing.pageRegular)
      }
      .width('100%')
      .height('100%')
      .id(GAME_FOCUS_ID)
      .focusable(true)
      .defaultFocus(true)
      .backgroundColor(Colors.forestBackground)
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
        Blank()
          .width('100%')
          .height('34%')
          .backgroundColor('#0E241A66')

        Blank()
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#00000000')

        Blank()
          .width('100%')
          .height('44%')
          .backgroundColor('#0E241ACC')
      }
      .width('100%')
      .height('100%')

      Image($r('app.media.sparkles'))
        .width(this.isCompactLayout() ? 210 : 320)
        .height(this.isCompactLayout() ? 110 : 170)
        .objectFit(ImageFit.Contain)
        .opacity(0.16)
        .margin({ bottom: this.isCompactLayout() ? 170 : 220 })

      Image($r('app.media.start_page_decoration'))
        .width(this.isCompactLayout() ? 150 : 220)
        .height(this.isCompactLayout() ? 88 : 128)
        .objectFit(ImageFit.Contain)
        .opacity(0.38)
        .margin({ bottom: this.isCompactLayout() ? 22 : 36, right: this.isCompactLayout() ? 210 : 380 })

      Column({ space: 12 }) {
        Text('慢慢推，也能抵达终点')
          .fontSize(this.isCompactLayout() ? 22 : 26)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.title)
          .fontFamily('HarmonyOS Sans SC')
          .shadow({ radius: 8, color: '#00000055', offsetX: 0, offsetY: 3 })

        Stack() {
          Image($r('app.media.ui_button_primary'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)

          Text('开始冒险')
            .fontSize(23)
            .fontWeight(FontWeight.Bold)
            .fontColor('#3A2407')
            .shadow({ radius: 3, color: '#FFF3B866', offsetX: 0, offsetY: 1 })
        }
        .width(this.isCompactLayout() ? '72%' : 360)
        .height(this.isCompactLayout() ? 64 : 70)
        .margin({ top: 14 })
        .shadow({ radius: Shadow.primaryRadius, color: Colors.blackPrimaryShadow, offsetX: 0, offsetY: Shadow.primaryOffsetY })
        .onClick(() => this.startGame())

        Text('支持关卡选择、通关评级和本地记录')
          .fontSize(13)
          .fontColor(Colors.body)
          .opacity(0.88)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ bottom: this.isCompactLayout() ? 54 : 78 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.forestBackground)
    .onAreaChange((oldValue, newValue) => {
      this.updateLayoutWidth(newValue.width as number | string);
    })
  }

  @Builder
  private homeHeroCard() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Image($r('app.media.start_page_decoration'))
        .width(this.isCompactLayout() ? 120 : 190)
        .height(this.isCompactLayout() ? 72 : 112)
        .objectFit(ImageFit.Contain)
        .opacity(0.35)
        .margin({ top: 10, right: 12 })

      Image($r('app.media.sparkles'))
        .width(this.isCompactLayout() ? 160 : 240)
        .height(this.isCompactLayout() ? 90 : 130)
        .objectFit(ImageFit.Contain)
        .opacity(0.12)
        .margin({ top: this.isCompactLayout() ? 118 : 132, right: this.isCompactLayout() ? 168 : 260 })

      Column({ space: 18 }) {
        if (this.isCompactLayout()) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              this.pill('发布版打磨', Colors.warning)
              this.pill(`${SNAIL_LEVELS.length} 个精选关卡`, Colors.cardDeepAlt)
            }
            Row({ space: 8 }) {
              this.pill('本地进度保存', Colors.successDark)
            }
          }
          .width('100%')
        } else {
          Row({ space: 8 }) {
            this.pill('发布版打磨', Colors.warning)
            this.pill(`${SNAIL_LEVELS.length} 个精选关卡`, Colors.cardDeepAlt)
            this.pill('本地进度保存', Colors.successDark)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
        }

        Text('蜗牛推箱子')
          .fontSize(this.isCompactLayout() ? FontSize.heroTitleCompact : FontSize.heroTitle)
          .fontWeight(FontWeight.Bolder)
          .fontColor(Colors.title)
          .fontFamily('HarmonyOS Sans SC')
          .shadow({ radius: 8, color: '#00000044', offsetX: 0, offsetY: 3 })

        Text(`围绕 ${SNAIL_LEVELS.length} 个手工设计关卡重新整理的正式版：流程更完整，反馈更稳定，通关评级和最近游玩进度都会自动保存在本机。`)
          .fontSize(15)
          .lineHeight(24)
          .fontColor(Colors.body)
          .width(this.isCompactLayout() ? '100%' : '70%')

        if (this.isCompactLayout()) {
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              this.metricCard('已完成', `${this.completedLevelCount()} / ${SNAIL_LEVELS.length}`, Colors.gold, 0)
              this.metricCard('总评级', `${this.totalStarCount()} / ${SNAIL_LEVELS.length * 3}`, Colors.success, 1)
            }
            Row({ space: 10 }) {
              this.metricCard('推荐关卡', `第 ${this.recommendedLevelIndex() + 1} 关`, Colors.warning, 2)
              this.metricCard('当前记录', this.homeRecordSummary(), Colors.goal, 3)
            }
          }
          .width('100%')
        } else {
          Row({ space: 10 }) {
            this.metricCard('已完成', `${this.completedLevelCount()} / ${SNAIL_LEVELS.length}`, Colors.gold, 0)
            this.metricCard('总评级', `${this.totalStarCount()} / ${SNAIL_LEVELS.length * 3}`, Colors.success, 1)
            this.metricCard('推荐关卡', `第 ${this.recommendedLevelIndex() + 1} 关`, Colors.warning, 2)
            this.metricCard('当前记录', this.homeRecordSummary(), Colors.goal, 3)
          }
          .width('100%')
        }

        if (this.isCompactLayout()) {
          Column({ space: 10 }) {
            this.heroButton(this.hasAnyRecord() ? '继续冒险' : '开始游戏', 0, true, true, () => this.continueAdventure())
            this.heroButton('挑战推荐关卡', 1, true, true, () => this.playRecommendedLevel())
          }
          .width('100%')
        } else {
          Row({ space: 10 }) {
            this.heroButton(this.hasAnyRecord() ? '继续冒险' : '开始游戏', 0, true, false, () => this.continueAdventure())
            this.heroButton('挑战推荐关卡', 1, true, false, () => this.playRecommendedLevel())
          }
          .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .padding(this.isCompactLayout() ? 20 : 26)
    .backgroundColor(Colors.cardDeep)
    .border({ width: 1, color: '#E6D5A822' })
    .borderRadius(Radius.heroCard)
    .shadow({ radius: Shadow.cardRadius, color: Colors.blackCardShadow, offsetX: 0, offsetY: Shadow.cardOffsetY })
  }

  @Builder
  private levelOverviewCard() {
    Column({ space: 14 }) {
      Text('关卡总览')
        .fontSize(FontSize.cardTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.title)

      Text(`当前一共 ${SNAIL_LEVELS.length} 关。每一关都支持重玩、通关评级和自动进度保存。`)
        .fontSize(14)
        .fontColor(Colors.body)

      ForEach(this.levelIndices(), (levelIndex: number) => {
        this.levelCard(levelIndex, false)
      }, (levelIndex: number) => `home-level-${levelIndex}`)
    }
    .width('100%')
    .padding(this.isCompactLayout() ? 18 : 22)
    .backgroundColor(Colors.cardMuted)
    .border({ width: 1, color: '#E6D5A81F' })
    .borderRadius(Radius.largeCard)
    .shadow({ radius: Shadow.cardRadius, color: Colors.blackCardShadow, offsetX: 0, offsetY: Shadow.cardOffsetY })
  }

  @Builder
  private featureCard() {
    Column({ space: 12 }) {
      Text('系统特色')
        .fontSize(FontSize.cardTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.title)

      if (this.isCompactLayout()) {
        Column({ space: 8 }) {
          this.featureItem('稳定规则', '边界和推箱判定更稳。', 0)
          this.featureItem('局内反馈', '撤销、重开和提示清楚。', 1)
          this.featureItem('发布流程', '选关、评级和记录完整。', 2)
        }
      } else {
        Row({ space: 10 }) {
          this.featureItem('稳定规则', '边界和推箱判定更稳。', 0)
          this.featureItem('局内反馈', '撤销、重开和提示清楚。', 1)
          this.featureItem('发布流程', '选关、评级和记录完整。', 2)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(this.isCompactLayout() ? 16 : 18)
    .backgroundColor(Colors.cardMuted)
    .border({ width: 1, color: '#E6D5A814' })
    .borderRadius(Radius.largeCard)
    .shadow({ radius: 14, color: '#00000024', offsetX: 0, offsetY: 5 })
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
              .fontColor(Colors.body)
              .backgroundColor('#2D4C3B99')
              .border({ width: 1, color: Colors.transparentPaperBorder })
              .borderRadius(Radius.smallCard)
              .height(42)
              .shadow({ radius: 8, color: '#00000024', offsetX: 0, offsetY: 3 })
              .onClick(() => this.returnHome())

            this.pill(`第 ${this.levelIndex + 1} 关`, Colors.warning)
          }
          Row({ space: 8 }) {
            this.pill(this.currentLevel().difficulty, this.difficultyColor(this.currentLevel().difficulty))
            this.pill(this.isCleared ? '已通关' : '进行中', this.isCleared ? Colors.successDark : Colors.boardWood)
          }
        }
        .width('100%')
      } else {
        Row({ space: 10 }) {
          Button('返回总览')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.body)
            .backgroundColor('#2D4C3B99')
            .border({ width: 1, color: Colors.transparentPaperBorder })
            .borderRadius(Radius.smallCard)
            .height(42)
            .shadow({ radius: 8, color: '#00000024', offsetX: 0, offsetY: 3 })
            .onClick(() => this.returnHome())

          this.pill(`第 ${this.levelIndex + 1} 关`, Colors.warning)
          this.pill(this.currentLevel().difficulty, this.difficultyColor(this.currentLevel().difficulty))
          this.pill(this.isCleared ? '已通关' : '进行中', this.isCleared ? Colors.successDark : Colors.boardWood)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }

      Text(this.currentLevelTitle())
        .fontSize(this.isCompactLayout() ? FontSize.playTitleCompact : FontSize.playTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.title)

      Text(this.currentLevel().subtitle)
        .fontSize(14)
        .lineHeight(22)
        .fontColor(Colors.body)

      if (this.isCompactLayout()) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            this.pill(`目标 ${this.coveredGoalsText()}`, Colors.cardDeepAlt)
            this.pill(`标杆 ${this.currentLevel().parMoves} 步`, Colors.boardWood)
          }
          Row({ space: 8 }) {
            this.pill(this.currentBestLabel(), Colors.warning)
          }
        }
        .width('100%')
      } else {
        Row({ space: 8 }) {
          this.pill(`目标 ${this.coveredGoalsText()}`, Colors.cardDeepAlt)
          this.pill(`标杆 ${this.currentLevel().parMoves} 步`, Colors.boardWood)
          this.pill(this.currentBestLabel(), Colors.warning)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
    }
    .width('100%')
    .padding(this.isCompactLayout() ? 16 : 18)
    .backgroundColor(Colors.cardHud)
    .border({ width: 1, color: '#E6D5A822' })
    .borderRadius(Radius.largeCard)
    .shadow({ radius: 14, color: '#0000002A', offsetX: 0, offsetY: 5 })
  }

  @Builder
  private controlCard() {
    Column({ space: 14 }) {
      Text('局内控制')
        .fontSize(FontSize.panelTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.textDark)

      Row({ space: 8 }) {
        this.actionButton('上一关', Colors.boardWood, this.levelIndex > 0, () => this.previousLevel())
        this.actionButton('下一关', Colors.cardDeepAlt, this.canEnterNextLevel(), () => this.nextLevel())
      }
      .width('100%')

      Row({ space: 8 }) {
        this.actionButton('撤销', Colors.warning, this.history.length > 0, () => this.undoMove())
        this.actionButton('重开', Colors.danger, true, () => this.resetLevel())
      }
      .width('100%')

      this.currentLevelInfoRow()
      this.infoRow('步数', `${this.moveCount}`)
      this.infoRow('推箱', `${this.pushCount}`)
      this.infoRow('完成度', this.coveredGoalsText())
      this.infoRow('评级标杆', `${this.currentLevel().parMoves} 步`)
      this.infoRow('最好成绩', this.currentBestLabel())

      Row({ space: 12 }) {
        Blank()
          .width(5)
          .height(46)
          .backgroundColor(this.statusAccentColor())
          .borderRadius(999)

        Text(this.statusText)
          .fontSize(13)
          .lineHeight(20)
          .fontColor(this.statusFontColor())
          .layoutWeight(1)
      }
      .width('100%')
      .padding(14)
      .backgroundColor(this.statusBackgroundColor())
      .border({ width: 1, color: '#8D5A1922' })
      .borderRadius(Radius.smallCard)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Colors.paper)
    .border({ width: 1, color: Colors.paperLine })
    .borderRadius(24)
    .shadow({ radius: 14, color: '#00000024', offsetX: 0, offsetY: 5 })
  }

  @Builder
  private currentLevelInfoRow() {
    Row({ space: 12 }) {
      Text('关卡')
        .fontSize(13)
        .fontColor(Colors.textMutedDark)
        .width(74)

      Text(`第 ${this.levelIndex + 1} / ${SNAIL_LEVELS.length} 关 · ${this.currentLevel().name}`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.textDark)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }

  @Builder
  private ruleCard() {
    Column({ space: 10 }) {
      Text('玩法与提示')
        .fontSize(FontSize.panelTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.textDark)

      Text('1. 蜗牛每次只能移动一格，木箱只能推不能拉。')
        .fontSize(13)
        .lineHeight(20)
        .fontColor(Colors.textBrown)

      Text('2. 如果箱子后方是墙、木箱或空洞，当前步就会被阻止。')
        .fontSize(13)
        .lineHeight(20)
        .fontColor(Colors.textBrown)

      Text('3. 死角提示只负责提醒明显的角落卡死，最优解仍然需要自己规划。')
        .fontSize(13)
        .lineHeight(20)
        .fontColor(Colors.textBrown)

      Text(`本关提示：${this.currentLevel().hint}`)
        .fontSize(13)
        .lineHeight(20)
        .fontColor(Colors.successDark)

      Text('说明：通关纪录、评级和最近游玩进度会自动保存。')
        .fontSize(13)
        .lineHeight(20)
        .fontColor(Colors.textMutedDark)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Colors.paper)
    .border({ width: 1, color: Colors.paperLine })
    .borderRadius(24)
    .shadow({ radius: 12, color: '#00000020', offsetX: 0, offsetY: 4 })
  }

  @Builder
  private boardCard() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text('棋盘')
          .fontSize(FontSize.panelTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.title)
        this.pill(this.boardFooterLabel(), Colors.cardDeepAlt)
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
        .padding(this.isCompactLayout() ? 8 : 12)
        .backgroundColor(Colors.boardInner)
        .border({ width: 2, color: '#E8C886' })
        .borderRadius(Radius.boardInner)

        if (this.isCleared) {
          this.clearOverlay()
        }
      }
      .width('100%')
      .padding(this.isCompactLayout() ? 10 : 14)
      .backgroundColor(Colors.boardWood)
      .border({ width: 2, color: '#D3B17A' })
      .borderRadius(Radius.boardFrame)
      .shadow({ radius: 18, color: '#00000044', offsetX: 0, offsetY: 7 })

      this.boardControlTray()

      Text(this.boardHintText())
        .fontSize(13)
        .lineHeight(20)
        .fontColor(Colors.body)
        .width('100%')
    }
    .width('100%')
    .padding(this.isCompactLayout() ? 16 : 20)
    .backgroundColor(Colors.boardFrame)
    .border({ width: 1, color: '#E6D5A824' })
    .borderRadius(Radius.boardFrame)
    .shadow({ radius: 24, color: '#00000044', offsetX: 0, offsetY: 9 })
  }

  @Builder
  private clearOverlay() {
    Column({ space: 12 }) {
      Image($r('app.media.sparkles'))
        .width(130)
        .height(48)
        .objectFit(ImageFit.Contain)
        .opacity(0.5)

      Text('关卡完成')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.textDark)

      Row({ space: 8 }) {
        ForEach([0, 1, 2], (starIndex: number) => {
          this.starAsset(starIndex < this.lastClearStars, 34, this.clearOverlayStarOpacity(starIndex))
        }, (starIndex: number) => `clear-star-${starIndex}`)
      }
      .justifyContent(FlexAlign.Center)

      Text(this.clearOverlayLabel())
        .fontSize(14)
        .lineHeight(22)
        .fontColor(Colors.textBrown)
        .textAlign(TextAlign.Center)

      Blank()
        .width('76%')
        .height(2)
        .backgroundColor('#C8944588')
        .borderRadius(999)

      Row({ space: 12 }) {
        this.overlayButton(this.hasNextLevel() ? '下一关' : '回到总览', Colors.gold, true, () => {
          if (this.hasNextLevel()) {
            this.nextLevel();
          } else {
            this.returnHome();
          }
        })
        this.overlayButton('重玩本关', Colors.boardWood, true, () => this.resetLevel())
      }
    }
    .padding({ left: 24, right: 24, top: 22, bottom: 22 })
    .backgroundColor('#F5E8C9EE')
    .backgroundImage($r('app.media.card_panel_parchment'))
    .backgroundImageSize({ width: '100%', height: '100%' })
    .border({ width: 1, color: Colors.goldBorder })
    .borderRadius(26)
    .opacity(this.clearOverlayOpacity())
    .scale({ x: this.clearOverlayScale(), y: this.clearOverlayScale() })
    .translate({ y: this.clearOverlayTranslateY() })
    .shadow({ radius: Shadow.overlayRadius, color: Colors.blackOverlayShadow, offsetX: 0, offsetY: Shadow.overlayOffsetY })
  }

  @Builder
  private boardControlTray() {
    Column({ space: 10 }) {
      Text('棋盘旁控制')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.title)
        .width('100%')

      this.directionPad()
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Colors.cardDeepAlt)
    .border({ width: 1, color: '#E6D5A81F' })
    .borderRadius(Radius.card)
  }

  @Builder
  private levelRailCard() {
    Column({ space: 12 }) {
      Text('路线总览')
        .fontSize(FontSize.panelTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.currentView === VIEW_PLAY ? Colors.textDark : Colors.title)

      Text(this.campaignSummaryText())
        .fontSize(13)
        .lineHeight(20)
        .fontColor(this.currentView === VIEW_PLAY ? Colors.textBrown : Colors.body)

      ForEach(this.levelIndices(), (levelIndex: number) => {
        this.levelCard(levelIndex, true)
      }, (levelIndex: number) => `rail-level-${levelIndex}`)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.currentView === VIEW_PLAY ? Colors.paper : Colors.cardMuted)
    .border({ width: 1, color: this.currentView === VIEW_PLAY ? Colors.paperLine : '#E6D5A81F' })
    .borderRadius(24)
    .shadow({ radius: 12, color: '#00000022', offsetX: 0, offsetY: 4 })
  }

  @Builder
  private levelCard(levelIndex: number, compact: boolean) {
    Column({ space: compact ? 8 : 10 }) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(`第 ${levelIndex + 1} 关`)
            .fontSize(12)
            .fontColor(Colors.textMutedDark)

          Text(SNAIL_LEVELS[levelIndex].name)
            .fontSize(compact ? 16 : 18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.textDark)

          if (!compact) {
            Text(SNAIL_LEVELS[levelIndex].subtitle)
              .fontSize(12)
              .lineHeight(18)
              .fontColor(Colors.textBrown)
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
        this.metaCard('目标', `${this.levelGoalCount(levelIndex)} 箱`, 0)
        this.metaCard('标杆', `${SNAIL_LEVELS[levelIndex].parMoves} 步`, 2)
        this.metaCard('纪录', this.levelRecordShortLabel(levelIndex), 1)
      }
      .width('100%')

      if (this.isLevelCleared(levelIndex)) {
        Row({ space: 3 }) {
          ForEach([0, 1, 2], (starIndex: number) => {
            this.starAsset(starIndex < this.bestStarsForLevel(levelIndex), 16, 1)
          }, (starIndex: number) => `level-star-${levelIndex}-${starIndex}`)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }

      if (!compact) {
        Text(SNAIL_LEVELS[levelIndex].hint)
          .fontSize(12)
          .lineHeight(18)
          .fontColor(Colors.successDark)
          .width('100%')
      }

      Text(this.levelActionHint(levelIndex))
        .fontSize(12)
        .fontColor(Colors.successDark)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(compact ? 14 : 16)
    .backgroundColor(this.levelCardBackground(levelIndex))
    .backgroundImage($r('app.media.card_panel_parchment'))
    .backgroundImageSize({ width: '100%', height: '100%' })
    .border({ width: this.currentView === VIEW_PLAY && levelIndex === this.levelIndex ? 2 : 1, color: this.levelCardBorderColor(levelIndex) })
    .borderRadius(Radius.button)
    .shadow({ radius: 10, color: '#00000022', offsetX: 0, offsetY: 4 })
    .onClick(() => this.openLevel(levelIndex))
  }

  @Builder
  private directionPad() {
    Column({ space: 10 }) {
      Text('方向键')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.title)

      Row({ space: 8 }) {
        Blank()
          .width(this.directionButtonSize())
          .height(this.directionButtonSize())
        this.directionButton('▲', () => this.moveSnail(-1, 0))
        Blank()
          .width(this.directionButtonSize())
          .height(this.directionButtonSize())
      }
      .width(this.directionPadWidth())

      Row({ space: 8 }) {
        this.directionButton('◀', () => this.moveSnail(0, -1))
        this.directionButton('▼', () => this.moveSnail(1, 0))
        this.directionButton('▶', () => this.moveSnail(0, 1))
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
        if (this.isWallCell(row, col)) {
          Image($r('app.media.moss_wall_tile'))
            .width(this.cellSize())
            .height(this.cellSize())
            .objectFit(ImageFit.Fill)
            .borderRadius(12)
        } else {
          Image($r('app.media.forest_floor_tile'))
            .width(this.cellSize())
            .height(this.cellSize())
            .objectFit(ImageFit.Fill)
            .borderRadius(Radius.cell)
        }

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
      .backgroundColor(this.cellBackgroundColor(row, col))
      .border({ width: 1, color: this.cellBorderColor(row, col) })
      .borderRadius(this.isWallCell(row, col) ? 12 : Radius.cell)
      .shadow({ radius: this.isWallCell(row, col) ? 3 : 1, color: '#00000018', offsetX: 0, offsetY: 1 })
    }
  }

  @Builder
  private goalToken(size: number) {
    Image($r('app.media.lily_goal'))
      .width(size * 0.78)
      .height(size * 0.78)
      .objectFit(ImageFit.Contain)
  }

  @Builder
  private boxToken(size: number, onGoal: boolean, deadlocked: boolean) {
    Stack() {
      if (deadlocked) {
        Column() {
          Blank()
        }
        .width(size * 0.88)
        .height(size * 0.88)
        .backgroundColor('#B45A4355')
        .borderRadius(size * 0.22)
      }

      if (deadlocked) {
        Image($r('app.media.wood_box_deadlock'))
          .width(size * 0.88)
          .height(size * 0.88)
          .objectFit(ImageFit.Contain)
          .shadow({ radius: 5, color: '#00000030', offsetX: 0, offsetY: 2 })
      } else {
        Image($r('app.media.wood_box'))
          .width(size * 0.86)
          .height(size * 0.86)
          .objectFit(ImageFit.Contain)
          .shadow({ radius: 5, color: '#00000030', offsetX: 0, offsetY: 2 })
      }
    }
  }

  @Builder
  private snailToken(size: number) {
    Image($r('app.media.snail_player'))
      .width(size * 0.94)
      .height(size * 0.94)
      .objectFit(ImageFit.Contain)
      .shadow({ radius: 6, color: '#00000038', offsetX: 0, offsetY: 2 })
  }

  @Builder
  private metricCard(label: string, value: string, accentColor: string, iconKind: number) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        this.metricIcon(iconKind, 28)

        Text(label)
          .fontSize(12)
          .fontColor(Colors.body)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(value)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.title)
        .maxLines(1)

      Blank()
        .width('100%')
        .height(4)
        .backgroundColor(accentColor)
        .borderRadius(999)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(14)
    .backgroundColor(Colors.cardDeepAlt)
    .border({ width: 1, color: '#E6D5A81F' })
    .borderRadius(Radius.button)
  }

  @Builder
  private featureItem(title: string, body: string, iconKind: number) {
    Row({ space: 10 }) {
      this.featureIcon(iconKind, 42)

      Column({ space: 5 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.title)

        Text(body)
          .fontSize(12)
          .lineHeight(18)
          .fontColor(Colors.bodyMuted)
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .alignItems(VerticalAlign.Center)
    .layoutWeight(1)
    .padding(14)
    .backgroundColor(Colors.cardDeepAlt)
    .border({ width: 1, color: '#E6D5A814' })
    .borderRadius(Radius.button)
  }

  @Builder
  private metricIcon(iconKind: number, size: number) {
    if (iconKind === 0) {
      Image($r('app.media.lily_goal'))
        .width(size)
        .height(size)
        .objectFit(ImageFit.Contain)
    } else if (iconKind === 1) {
      Image($r('app.media.gold_star'))
        .width(size)
        .height(size)
        .objectFit(ImageFit.Contain)
    } else if (iconKind === 2) {
      Image($r('app.media.snail_player'))
        .width(size)
        .height(size)
        .objectFit(ImageFit.Contain)
    } else {
      Image($r('app.media.wood_box'))
        .width(size)
        .height(size)
        .objectFit(ImageFit.Contain)
    }
  }

  @Builder
  private featureIcon(iconKind: number, size: number) {
    if (iconKind === 0) {
      Image($r('app.media.moss_wall_tile'))
        .width(size)
        .height(size)
        .objectFit(ImageFit.Cover)
        .borderRadius(12)
    } else if (iconKind === 1) {
      Image($r('app.media.snail_player'))
        .width(size)
        .height(size)
        .objectFit(ImageFit.Contain)
    } else {
      Image($r('app.media.gold_star'))
        .width(size)
        .height(size)
        .objectFit(ImageFit.Contain)
    }
  }

  @Builder
  private starAsset(earned: boolean, size: number, revealOpacity: number) {
    Image($r('app.media.gold_star'))
      .width(size)
      .height(size)
      .objectFit(ImageFit.Contain)
      .opacity(earned ? revealOpacity : 0.24)
  }

  @Builder
  private infoRow(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(13)
        .fontColor(Colors.textMutedDark)
        .width(74)

      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.textDark)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }

  @Builder
  private metaCard(label: string, value: string, iconKind: number) {
    Row({ space: 7 }) {
      this.metricIcon(iconKind, 22)

      Column({ space: 3 }) {
        Text(label)
          .fontSize(11)
          .fontColor(Colors.textMutedDark)

        Text(value)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.textDark)
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .alignItems(VerticalAlign.Center)
    .layoutWeight(1)
    .padding(10)
    .backgroundColor(Colors.paperAlt)
    .border({ width: 1, color: '#D9BE8A66' })
    .borderRadius(Radius.smallCard)
  }

  @Builder
  private pill(label: string, color: string) {
    Text(label)
      .fontSize(12)
      .fontColor(Colors.title)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(color)
      .border({ width: 1, color: '#FFF4CF33' })
      .borderRadius(Radius.pill)
  }

  @Builder
  private heroButton(label: string, style: number, enabled: boolean, block: boolean, handler: () => void) {
    if (block) {
      Stack() {
        if (style === 0) {
          Image($r('app.media.ui_button_primary'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
        } else {
          Image($r('app.media.ui_button_green'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
        }

        Text(label)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(style === 0 ? '#3A2407' : Colors.title)
      }
        .width('100%')
        .height(54)
        .opacity(enabled ? 1 : 0.4)
        .shadow({ radius: style === 0 ? Shadow.primaryRadius : Shadow.buttonRadius, color: style === 0 ? Colors.blackPrimaryShadow : Colors.blackButtonShadow, offsetX: 0, offsetY: style === 0 ? Shadow.primaryOffsetY : Shadow.buttonOffsetY })
        .onClick(() => {
          if (enabled) {
            handler();
          }
        })
    } else {
      Stack() {
        if (style === 0) {
          Image($r('app.media.ui_button_primary'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
        } else {
          Image($r('app.media.ui_button_green'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
        }

        Text(label)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(style === 0 ? '#3A2407' : Colors.title)
      }
        .layoutWeight(1)
        .height(54)
        .opacity(enabled ? 1 : 0.4)
        .shadow({ radius: style === 0 ? Shadow.primaryRadius : Shadow.buttonRadius, color: style === 0 ? Colors.blackPrimaryShadow : Colors.blackButtonShadow, offsetX: 0, offsetY: style === 0 ? Shadow.primaryOffsetY : Shadow.buttonOffsetY })
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
      .fontColor(this.buttonTextColor(color))
      .backgroundColor(color)
      .border({ width: 1, color: this.buttonBorderColor(color) })
      .borderRadius(Radius.button)
      .layoutWeight(1)
      .height(44)
      .opacity(enabled ? 1 : 0.4)
      .shadow({ radius: Shadow.buttonRadius, color: Colors.blackButtonShadow, offsetX: 0, offsetY: Shadow.buttonOffsetY })
      .onClick(() => {
        if (enabled) {
          handler();
        }
      })
  }

  @Builder
  private overlayButton(label: string, color: string, enabled: boolean, handler: () => void) {
    Stack() {
      if (color === Colors.gold) {
        Image($r('app.media.ui_button_primary'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
      } else {
        Image($r('app.media.ui_button_green'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
      }

      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(color === Colors.gold ? '#3A2407' : Colors.title)
    }
      .layoutWeight(1)
      .height(48)
      .opacity(enabled ? 1 : 0.4)
      .shadow({ radius: Shadow.buttonRadius, color: Colors.blackButtonShadow, offsetX: 0, offsetY: Shadow.buttonOffsetY })
      .onClick(() => {
        if (enabled) {
          handler();
        }
      })
  }

  @Builder
  private directionButton(label: string, handler: () => void) {
    Stack() {
      Image($r('app.media.ui_button_green'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Fill)

      Text(label)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.title)
        .shadow({ radius: 2, color: '#00000055', offsetX: 0, offsetY: 1 })
    }
      .width(this.directionButtonSize())
      .height(this.directionButtonSize())
      .borderRadius(18)
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
      return '#DDF2D7';
    }
    if (this.statusTone === 2) {
      return '#F4DFC0';
    }
    if (this.statusTone === 3) {
      return '#F2D0C8';
    }
    return '#F1E5CC';
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
    return Colors.textBrown;
  }

  private statusAccentColor(): string {
    if (this.statusTone === 1) {
      return Colors.success;
    }
    if (this.statusTone === 2) {
      return Colors.warning;
    }
    if (this.statusTone === 3) {
      return Colors.danger;
    }
    return Colors.successDark;
  }

  private buttonTextColor(color: string): string {
    if (color === Colors.gold) {
      return Colors.textDark;
    }
    return Colors.white;
  }

  private buttonBorderColor(color: string): string {
    if (color === Colors.gold) {
      return Colors.goldBorder;
    }
    return Colors.transparentGoldBorder;
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
      return Colors.successDark;
    }
    if (this.isLevelChallenged(levelIndex)) {
      return Colors.cardDeepAlt;
    }
    return Colors.warning;
  }

  private difficultyColor(difficulty: string): string {
    if (difficulty === '入门') {
      return Colors.successDark;
    }
    if (difficulty === '挑战') {
      return Colors.danger;
    }
    return Colors.warning;
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
      return '#F8E7BE';
    }
    if (!this.isLevelChallenged(levelIndex)) {
      return Colors.paper;
    }
    return '#F1E4CD';
  }

  private levelCardBorderColor(levelIndex: number): string {
    if (this.currentView === VIEW_PLAY && levelIndex === this.levelIndex) {
      return Colors.gold;
    }
    if (this.isLevelCleared(levelIndex)) {
      return '#9DBE72';
    }
    return '#D9BE8A88';
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
      return Colors.wall;
    }
    if (this.isGoalCell(row, col)) {
      return Colors.goal;
    }
    return (row + col) % 2 === 0 ? Colors.sandA : Colors.sandB;
  }

  private cellBorderColor(row: number, col: number): string {
    if (this.isWallCell(row, col)) {
      return Colors.wallBorder;
    }
    if (this.isGoalCell(row, col)) {
      return '#9CBA63';
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
    const availableWidth = this.isCompactLayout() ? this.layoutWidth - 116 : this.layoutWidth * 0.38 - 92;
    const nextSize = Math.floor(availableWidth / Math.max(this.boardWidth, 1));
    return Math.max(this.isCompactLayout() ? 24 : 22, Math.min(56, nextSize));
  }

  private isCompactLayout(): boolean {
    return this.layoutWidth > 0 && this.layoutWidth < 960;
  }

  private directionPadWidth(): number {
    return this.directionButtonSize() * 3 + 8 * 2;
  }

  private directionButtonSize(): number {
    return this.isCompactLayout() ? 56 : 60;
  }

  private updateLayoutWidth(width: number | string): void {
    const nextWidth = typeof width === 'number' ? width : Number.parseFloat(width);
    if (!Number.isNaN(nextWidth) && nextWidth > 0) {
      this.layoutWidth = nextWidth;
    }
  }
}
