import { SNAIL_LEVELS, SnailLevel } from '../data/SnailLevels';
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

const VIEW_HOME: number = 0;
const VIEW_PLAY: number = 1;
const SAVE_KEY: string = 'snail_publish_save_data';
const DEFAULT_SAVE_DATA_TEXT: string = '{"unlockedLevelCount":1,"lastPlayedLevelIndex":0,"records":[]}';

PersistentStorage.persistProp(SAVE_KEY, DEFAULT_SAVE_DATA_TEXT);

interface LevelRecord {
  levelId: number;
  bestMoves: number;
  bestPushes: number;
  bestStars: number;
}

interface SaveData {
  unlockedLevelCount: number;
  lastPlayedLevelIndex: number;
  records: LevelRecord[];
}

@Entry
@Component
struct Index {
  @StorageLink(SAVE_KEY) saveDataText: string = DEFAULT_SAVE_DATA_TEXT;
  @State currentView: number = VIEW_HOME;
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
  @State statusText: string = '欢迎来到蜗牛推箱子。';
  @State statusTone: number = 0;

  aboutToAppear(): void {
    this.ensureSaveData();
    this.loadLevel(this.readSaveData().lastPlayedLevelIndex);
    this.currentView = VIEW_HOME;
    this.setStatus('选择一个已经解锁的关卡，帮蜗牛把补给箱慢慢送回荷叶码头。', 0);
  }

  build() {
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
    .backgroundColor('#10261C')
    .scrollBar(BarState.Auto)
    .onAreaChange((oldValue, newValue) => {
      this.updateLayoutWidth(newValue.width as number | string);
    })
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
    this.updateLastPlayedLevel(nextIndex);
    this.setStatus(level.hint, 0);
  }

  private openLevel(levelIndex: number): void {
    if (!this.isLevelUnlocked(levelIndex)) {
      this.setStatus('这一关还没解锁，先完成前面的路线。', 2);
      this.currentView = VIEW_HOME;
      return;
    }
    this.loadLevel(levelIndex);
    this.currentView = VIEW_PLAY;
  }

  private continueAdventure(): void {
    const saveData = this.readSaveData();
    const nextIndex = this.isLevelUnlocked(saveData.lastPlayedLevelIndex) ?
      saveData.lastPlayedLevelIndex : this.recommendedLevelIndex();
    this.openLevel(nextIndex);
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
    this.deadlockedBoxKeys = [];
    this.persistClearRecord(this.levelIndex, moves, pushes, stars);

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

    if (!this.isLevelUnlocked(this.levelIndex + 1)) {
      this.setStatus('下一关尚未解锁，先完成当前关。', 2);
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

      Text(`围绕 ${SNAIL_LEVELS.length} 个手工设计关卡重新整理的正式版：流程更完整，反馈更稳定，通关评级和解锁进度都会自动保存在本机。`)
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
          this.featureItem('发布级流程', '首页总览、关卡解锁、评级纪录和自动保存都已接通。')
        }
      } else {
        Row({ space: 10 }) {
          this.featureItem('稳定规则', '墙体、空洞、推箱判定分离处理，避免走出棋盘。')
          this.featureItem('局内反馈', '支持撤销、重开、死角提示和即时状态说明。')
          this.featureItem('发布级流程', '首页总览、关卡解锁、评级纪录和自动保存都已接通。')
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
              .fontColor('#FFFFFF')
              .backgroundColor('#2D4C3B')
              .borderRadius(14)
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
            .fontColor('#FFFFFF')
            .backgroundColor('#2D4C3B')
            .borderRadius(14)
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

      this.infoRow('关卡', `${this.levelIndex + 1} / ${SNAIL_LEVELS.length}`)
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
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#F1E4CD')
    .borderRadius(22)
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

      Text('说明：通关纪录、评级和解锁进度会自动保存。')
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
          Column({ space: 10 }) {
            Text('关卡完成')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFF6E6')

            Text(this.clearOverlayLabel())
              .fontSize(14)
              .lineHeight(22)
              .fontColor('#E8F6E8')
              .textAlign(TextAlign.Center)

            Row({ space: 8 }) {
              this.overlayButton(this.hasNextUnlockedLevel() ? '下一关' : '回到总览', '#2E7A52', true, () => {
                if (this.hasNextUnlockedLevel()) {
                  this.nextLevel();
                } else {
                  this.returnHome();
                }
              })
              this.overlayButton('重玩本关', '#A05A33', true, () => this.resetLevel())
            }
          }
          .padding({ left: 24, right: 24, top: 20, bottom: 20 })
          .backgroundColor('#163927EE')
          .borderRadius(20)
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
        .fontColor(this.isLevelUnlocked(levelIndex) ? '#305B46' : '#73685A')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(compact ? 14 : 16)
    .backgroundColor(this.levelCardBackground(levelIndex))
    .borderRadius(18)
    .opacity(this.isLevelUnlocked(levelIndex) ? 1 : 0.58)
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
      .width(size * 0.7)
      .height(size * 0.7)
      .backgroundColor('#AACD72')
      .opacity(0.26)
      .border({ width: 3, color: '#587A32' })
      .borderRadius(size * 0.35)

      Column() {
        Blank()
      }
      .width(size * 0.22)
      .height(size * 0.22)
      .backgroundColor('#587A32')
      .borderRadius(size * 0.11)
    }
  }

  @Builder
  private boxToken(size: number, onGoal: boolean, deadlocked: boolean) {
    Stack() {
      Column() {
        Blank()
      }
      .width(size * 0.7)
      .height(size * 0.7)
      .backgroundColor(deadlocked ? '#B55B45' : onGoal ? '#D9AE47' : '#B87B35')
      .border({ width: 2, color: deadlocked ? '#6E2D1E' : onGoal ? '#7A5A16' : '#744918' })
      .borderRadius(10)

      Column() {
        Blank()
      }
      .width(size * 0.36)
      .height(size * 0.12)
      .backgroundColor('#FFF5DB')
      .borderRadius(999)

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
    Row({ space: size * 0.04 }) {
      Stack() {
        Column() {
          Blank()
        }
        .width(size * 0.38)
        .height(size * 0.38)
        .backgroundColor('#7B4324')
        .borderRadius(size * 0.19)

        Column() {
          Blank()
        }
        .width(size * 0.16)
        .height(size * 0.16)
        .backgroundColor('#F8DC97')
        .borderRadius(size * 0.08)
      }

      Column({ space: size * 0.04 }) {
        Blank()
          .width(size * 0.3)
          .height(size * 0.18)
          .backgroundColor('#E39E3F')
          .borderRadius(size * 0.08)

        Row({ space: size * 0.05 }) {
          Blank()
            .width(size * 0.05)
            .height(size * 0.05)
            .backgroundColor('#241C14')
            .borderRadius(size * 0.025)
          Blank()
            .width(size * 0.05)
            .height(size * 0.05)
            .backgroundColor('#241C14')
            .borderRadius(size * 0.025)
        }
      }
    }
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
        .borderRadius(16)
        .width('100%')
        .height(48)
        .opacity(enabled ? 1 : 0.4)
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
        .borderRadius(16)
        .layoutWeight(1)
        .height(48)
        .opacity(enabled ? 1 : 0.4)
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
      .fontColor('#FFFFFF')
      .backgroundColor(color)
      .borderRadius(14)
      .layoutWeight(1)
      .height(44)
      .opacity(enabled ? 1 : 0.4)
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
      .fontColor('#FFFFFF')
      .backgroundColor(color)
      .borderRadius(14)
      .layoutWeight(1)
      .opacity(enabled ? 1 : 0.4)
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
      .width(72)
      .height(48)
      .borderRadius(14)
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
        unlockedLevelCount: this.clampUnlockedCount(raw.unlockedLevelCount),
        lastPlayedLevelIndex: this.safeLevelIndex(raw.lastPlayedLevelIndex),
        records
      };
    } catch (error) {
      return this.defaultSaveData();
    }
  }

  private writeSaveData(saveData: SaveData): void {
    const normalized: SaveData = {
      unlockedLevelCount: this.clampUnlockedCount(saveData.unlockedLevelCount),
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
      unlockedLevelCount: 1,
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
      if (Number.isNaN(levelId) || levelId <= 0) {
        continue;
      }
      next.push({
        levelId,
        bestMoves: Number.isNaN(bestMoves) || bestMoves <= 0 ? 0 : bestMoves,
        bestPushes: Number.isNaN(bestPushes) || bestPushes <= 0 ? 0 : bestPushes,
        bestStars: Number.isNaN(bestStars) || bestStars <= 0 ? 0 : bestStars
      });
    }

    return next;
  }

  private clampUnlockedCount(count: number): number {
    if (Number.isNaN(count) || count < 1) {
      return 1;
    }
    if (count > SNAIL_LEVELS.length) {
      return SNAIL_LEVELS.length;
    }
    return count;
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

  private persistClearRecord(levelIndex: number, moves: number, pushes: number, stars: number): void {
    const saveData = this.readSaveData();
    saveData.lastPlayedLevelIndex = levelIndex;
    saveData.unlockedLevelCount = this.clampUnlockedCount(Math.max(saveData.unlockedLevelCount, levelIndex + 2));

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
    }

    if (!matched) {
      saveData.records.push({
        levelId,
        bestMoves: moves,
        bestPushes: pushes,
        bestStars: stars
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
    const unlockedLevelCount = this.readSaveData().unlockedLevelCount;
    for (let levelIndex = 0; levelIndex < unlockedLevelCount; levelIndex++) {
      if (!this.isLevelCleared(levelIndex)) {
        return levelIndex;
      }
    }
    return this.safeLevelIndex(unlockedLevelCount - 1);
  }

  private homeRecordSummary(): string {
    if (!this.hasAnyRecord()) {
      return '等待首通';
    }
    const record = this.findRecordForLevel(this.readSaveData().lastPlayedLevelIndex);
    if (!record) {
      return `${this.totalStarCount()} 星`;
    }
    return `${record.bestMoves} 步`;
  }

  private campaignSummaryText(): string {
    return `已完成 ${this.completedLevelCount()} / ${SNAIL_LEVELS.length} 关，累计评级 ${this.totalStarCount()} / ${SNAIL_LEVELS.length * 3} 星。`;
  }

  private levelGoalCount(levelIndex: number): number {
    return parseLevel(SNAIL_LEVELS[levelIndex]).boxKeys.length;
  }

  private levelRecordShortLabel(levelIndex: number): string {
    const record = this.findRecordForLevel(levelIndex);
    if (!record) {
      return this.isLevelUnlocked(levelIndex) ? '待完成' : '锁定';
    }
    return `${record.bestStars} 星`;
  }

  private currentBestLabel(): string {
    const record = this.findRecordForLevel(this.levelIndex);
    if (!record) {
      return '尚未通关';
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

  private isLevelUnlocked(levelIndex: number): boolean {
    return levelIndex < this.readSaveData().unlockedLevelCount;
  }

  private isLevelCleared(levelIndex: number): boolean {
    return this.findRecordForLevel(levelIndex) !== undefined;
  }

  private levelStateLabel(levelIndex: number): string {
    if (!this.isLevelUnlocked(levelIndex)) {
      return '未解锁';
    }
    if (this.isLevelCleared(levelIndex)) {
      return '已通关';
    }
    return '可挑战';
  }

  private levelStateColor(levelIndex: number): string {
    if (!this.isLevelUnlocked(levelIndex)) {
      return '#6B655F';
    }
    if (this.isLevelCleared(levelIndex)) {
      return '#2F7A51';
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
    if (!this.isLevelUnlocked(levelIndex)) {
      return '完成前一关后解锁';
    }
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
    if (this.isLevelUnlocked(levelIndex)) {
      return '#F1E4CD';
    }
    return '#D8CFBF';
  }

  private canEnterNextLevel(): boolean {
    return this.levelIndex < SNAIL_LEVELS.length - 1 && this.isLevelUnlocked(this.levelIndex + 1);
  }

  private hasNextUnlockedLevel(): boolean {
    return this.levelIndex < SNAIL_LEVELS.length - 1 && this.isLevelUnlocked(this.levelIndex + 1);
  }

  private coveredGoalsText(): string {
    return `${countGoalsCovered(this.boxKeys, this.goalKeys)} / ${this.goalKeys.length}`;
  }

  private clearOverlayLabel(): string {
    return `当前成绩 ${this.moveCount} 步，推箱 ${this.pushCount} 次，评级 ${this.lastClearStars} 星。`;
  }

  private boardFooterLabel(): string {
    if (this.deadlockedBoxKeys.length > 0) {
      return '死角预警';
    }
    if (this.isCleared) {
      return '通关完成';
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
    const availableWidth = this.isCompactLayout() ? this.layoutWidth - 76 : this.layoutWidth * 0.36;
    const nextSize = Math.floor(availableWidth / Math.max(this.boardWidth, 1));
    return Math.max(36, Math.min(56, nextSize));
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
