import { Scene, Node } from '@kit.ArkGraphics3D';
import { ControlPanel } from '../components/ControlPanel';
import { SceneView3D } from '../components/SceneView3D';
import { SceneView2D } from '../components/SceneView2D';
import { PATH_POINTS, firstPose, interpolate } from '../data/PathData';
import { Pose3D, RunState } from '../model/Types';

@Entry
@Component
struct Index {
  @State pose: Pose3D = firstPose();
  @State runState: RunState = RunState.Loading;
  @State sceneStatusText: string = 'Loading 3D scene';
  @State modeDescriptionText: string = 'Trying to open the local GLB scene with 3D rendering.';
  @State isSceneReady: boolean = false;
  @State useFallback2D: boolean = false;
  @State layoutWidth: number = 0;
  @State activeSegmentIndex: number = 0;
  @State segmentProgress: number = 0;
  @State sceneOptions: SceneOptions = {
    modelType: ModelType.SURFACE
  } as SceneOptions;

  private scene?: Scene;
  private moverNode?: Node | null;
  private timerId: number = -1;
  private loadTimerId: number = -1;
  private hasStartedLoad: boolean = false;
  private loadAttemptCount: number = 0;
  private segmentIndex: number = 0;
  private progressInSegment: number = 0;
  private readonly stepsPerSegment: number = 24;
  private readonly tickMs: number = 80;
  private readonly sceneLoadDelayMs: number = 300;
  private readonly sceneRetryDelayMs: number = 800;
  private readonly maxSceneLoadAttempts: number = 2;

  aboutToAppear(): void {
    this.scheduleSceneLoad(0);
  }

  aboutToDisappear(): void {
    this.stopTimer();
    this.clearLoadTimer();
  }

  build() {
    Column() {
      if (this.isCompactLayout()) {
        Column({ space: 16 }) {
          Column() {
            this.controlPanelContent()
          }
          .width('100%')

          Column() {
            this.sceneContent()
          }
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
      }
      else {
        Row({ space: 16 }) {
          Column() {
            this.controlPanelContent()
          }
          .width('36%')
          .height('100%')

          Column() {
            this.sceneContent()
          }
          .width('64%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding(this.isCompactLayout() ? 12 : 18)
    .backgroundColor('#020617')
    .onAreaChange((oldValue, newValue) => {
      this.updateLayoutWidth(newValue.width.toString());
    })
  }

  private async loadScene(): Promise<void> {
    try {
      this.loadAttemptCount += 1;
      this.runState = RunState.Loading;
      this.sceneStatusText = this.loadAttemptCount === 1
        ? 'Loading 3D scene'
        : `Retrying 3D scene (${this.loadAttemptCount})`;
      this.modeDescriptionText = 'Trying to open the local GLB scene with 3D rendering.';
      this.scene = await this.loadSceneAfterDelay();
      this.sceneOptions = {
        scene: this.scene,
        modelType: ModelType.SURFACE
      } as SceneOptions;
      this.useFallback2D = false;
      this.isSceneReady = true;
      this.activeSegmentIndex = 0;
      this.segmentProgress = 0;
      this.sceneStatusText = 'Ready';
      this.modeDescriptionText = 'Rendering the local GLB scene with Component3D and the local GLB asset.';
      this.bindMoverNode();
      this.pose = this.createPose(firstPose());
      this.applyPose(this.pose);
      this.runState = RunState.Idle;
    } catch (err) {
      const errorText = this.formatSceneLoadError(err);
      const isEngineNotReady = this.isSceneEngineNotReadyError(err);
      const shouldRetry = isEngineNotReady &&
        this.loadAttemptCount < this.maxSceneLoadAttempts;

      if (shouldRetry) {
        this.sceneStatusText = 'Retrying 3D scene';
        this.scheduleSceneLoad(this.sceneRetryDelayMs);
        return;
      }

      this.useFallback2D = true;
      this.isSceneReady = false;
      this.scene = undefined;
      this.moverNode = null;
      this.runState = RunState.Idle;
      this.sceneStatusText = 'Ready';
      this.modeDescriptionText = isEngineNotReady
        ? '3D rendering is unavailable in the current simulator, so the app switched to the 2D fallback map.'
        : `3D scene failed to load, so the app switched to the 2D fallback map. ${errorText}`;
      console.error(errorText);
    }
  }

  private async loadSceneAfterDelay(): Promise<Scene> {
    await new Promise<void>((resolve) => {
      setTimeout(() => resolve(), this.sceneLoadDelayMs);
    });
    return Scene.load($rawfile('map_scene.glb'));
  }

  private isSceneEngineNotReadyError(err: Object): boolean {
    const errObj = err as Record<string, Object | string | number | boolean | undefined>;
    const rawMessage = typeof errObj['message'] === 'string' ? errObj['message'] : '';
    return rawMessage.toLowerCase().includes('creating scene manageer failed');
  }

  private scheduleSceneLoad(delayMs: number): void {
    if (this.isSceneReady || this.hasStartedLoad) {
      return;
    }
    this.clearLoadTimer();
    this.loadTimerId = setTimeout(() => {
      this.loadTimerId = -1;
      this.hasStartedLoad = true;
      void this.loadScene().finally(() => {
        this.hasStartedLoad = false;
      });
    }, delayMs);
  }

  private clearLoadTimer(): void {
    if (this.loadTimerId !== -1) {
      clearTimeout(this.loadTimerId);
      this.loadTimerId = -1;
    }
  }

  private formatSceneLoadError(err: Object): string {
    const errObj = err as Record<string, Object | string | number | boolean | undefined>;
    const rawMessage = typeof errObj['message'] === 'string' ? errObj['message'] : '';
    const rawCode = typeof errObj['code'] === 'number' || typeof errObj['code'] === 'string'
      ? `${errObj['code']}`
      : '';
    const jsonText = JSON.stringify(err);

    if (rawMessage.length > 0 && rawCode.length > 0) {
      return `Failed to load scene [${rawCode}]: ${rawMessage}`;
    }
    if (rawMessage.length > 0) {
      return `Failed to load scene: ${rawMessage}`;
    }
    if (jsonText !== undefined) {
      return `Failed to load scene: ${jsonText}`;
    }
    return `Failed to load scene: ${err}`;
  }

  private bindMoverNode(): void {
    if (!this.scene) {
      return;
    }
    const moverCandidates: string[] = [
      'rootNode_/world/Mover',
      'world/Mover',
      'rootNode_/Mover',
      'rootNode_/map_scene/Mover',
      'Mover'
    ];
    this.moverNode = this.resolveNode(moverCandidates);

    if (!this.moverNode) {
      this.sceneStatusText = 'Mover node missing';
      this.modeDescriptionText = 'The 3D scene loaded, but the mover node was not found in the GLB file.';
      this.runState = RunState.Error;
    }
  }

  private resolveNode(paths: string[]): Node | null {
    if (!this.scene) {
      return null;
    }
    for (const path of paths) {
      const node = this.scene.getNodeByPath(path);
      if (node) {
        return node;
      }
    }
    return null;
  }

  private start(): void {
    const canRunIn2D = this.useFallback2D;
    if ((!this.moverNode && !canRunIn2D) || this.runState === RunState.Loading || this.runState === RunState.Error) {
      return;
    }
    if (this.runState === RunState.Completed) {
      this.reset();
    }
    if (this.timerId !== -1) {
      this.runState = RunState.Running;
      return;
    }
    this.runState = RunState.Running;
    this.sceneStatusText = 'Ready';
    this.timerId = setInterval(() => {
      this.tick();
    }, this.tickMs);
  }

  private pause(): void {
    if (this.runState === RunState.Running) {
      this.runState = RunState.Paused;
      this.sceneStatusText = 'Ready';
    }
    this.stopTimer();
  }

  private reset(): void {
    this.stopTimer();
    this.segmentIndex = 0;
    this.progressInSegment = 0;
    this.activeSegmentIndex = 0;
    this.segmentProgress = 0;
    this.pose = this.createPose(firstPose());
    this.applyPose(this.pose);
    this.runState = RunState.Idle;
    this.sceneStatusText = 'Ready';
  }

  private tick(): void {
    if (this.runState !== RunState.Running) {
      return;
    }
    if (this.segmentIndex >= PATH_POINTS.length - 1) {
      this.stopTimer();
      this.runState = RunState.Completed;
      this.activeSegmentIndex = PATH_POINTS.length - 2;
      this.segmentProgress = 1;
      this.sceneStatusText = 'Ready';
      return;
    }

    const start = PATH_POINTS[this.segmentIndex];
    const end = PATH_POINTS[this.segmentIndex + 1];
    this.progressInSegment += 1;
    let localT = this.progressInSegment / this.stepsPerSegment;

    if (localT >= 1) {
      this.segmentIndex += 1;
      this.progressInSegment = 0;
      if (this.segmentIndex >= PATH_POINTS.length - 1) {
        const finalPose: Pose3D = this.createPose(new Pose3D(end.x, end.y, end.z, this.pose.yaw));
        this.pose = finalPose;
        this.activeSegmentIndex = PATH_POINTS.length - 2;
        this.segmentProgress = 1;
        this.applyPose(finalPose);
        this.stopTimer();
        this.runState = RunState.Completed;
        this.sceneStatusText = 'Ready';
        return;
      }
      localT = 0;
    }

    const pose = this.createPose(interpolate(start, end, localT));
    this.pose = pose;
    this.activeSegmentIndex = this.segmentIndex;
    this.segmentProgress = localT;
    this.applyPose(pose);
  }

  private applyPose(pose: Pose3D): void {
    if (!this.moverNode) {
      return;
    }
    let position = this.moverNode.position;
    position.x = pose.x;
    position.y = pose.y;
    position.z = pose.z;
    this.moverNode.position = position;
  }

  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  @Builder
  private controlPanelContent() {
    ControlPanel({
      pose: this.pose,
      runState: this.runState,
      sceneStatusText: this.sceneStatusText,
      viewModeText: this.viewModeText(),
      modeDescriptionText: this.modeDescriptionText,
      isCompactLayout: this.isCompactLayout(),
      onStart: () => this.start(),
      onPause: () => this.pause(),
      onReset: () => this.reset()
    })
  }

  @Builder
  private sceneContent() {
    if (this.useFallback2D) {
      SceneView2D({
        pose: this.pose,
        pathPoints: PATH_POINTS,
        runState: this.runState,
        statusText: this.activityText(),
        sceneStatusText: this.sceneStatusText,
        activeSegmentIndex: this.activeSegmentIndex,
        segmentProgress: this.segmentProgress
      })
    } else {
      SceneView3D({
        sceneOptions: this.sceneOptions,
        statusText: this.sceneStatusText === 'Ready' ? this.activityText() : this.sceneStatusText,
        showOverlay: !this.isSceneReady
      })
    }
  }

  private activityText(): string {
    switch (this.runState) {
      case RunState.Running:
        return 'Animation running';
      case RunState.Paused:
        return 'Paused';
      case RunState.Completed:
        return 'Reached final waypoint';
      case RunState.Loading:
        return this.useFallback2D ? 'Preparing fallback view' : 'Loading 3D scene';
      case RunState.Error:
        return 'Scene error';
      default:
        return this.useFallback2D ? 'Fallback scene ready' : 'Scene ready';
    }
  }

  private viewModeText(): string {
    return this.useFallback2D ? '2D Fallback' : '3D Scene';
  }

  private isCompactLayout(): boolean {
    return this.layoutWidth > 0 && this.layoutWidth < 900;
  }

  private updateLayoutWidth(width: number | string): void {
    const nextWidth = typeof width === 'number' ? width : Number.parseFloat(`${width}`);
    if (!Number.isNaN(nextWidth) && nextWidth > 0) {
      this.layoutWidth = nextWidth;
    }
  }

  private createPose(pose: Pose3D): Pose3D {
    return new Pose3D(pose.x, pose.y, pose.z, pose.yaw);
  }

}
