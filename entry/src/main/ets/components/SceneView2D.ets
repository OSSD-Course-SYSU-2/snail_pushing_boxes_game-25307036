import { Point3D, Pose3D, RunState } from '../model/Types';

@Component
export struct SceneView2D {
  @Prop pose: Pose3D;
  @Prop pathPoints: Point3D[];
  @Prop statusText: string;
  @Prop sceneStatusText: string;
  @Prop runState: RunState;
  @Prop activeSegmentIndex: number;
  @Prop segmentProgress: number;

  @State canvasSize: number = 320;

  private readonly pointSize: number = 8;
  private readonly moverSize: number = 32;
  private readonly pathDotSize: number = 8;
  private readonly boundsPadding: number = 40;
  private readonly obstacleData: ObstacleRect[] = [
    { centerX: -3.15, centerY: -1.75, width: 0.9, height: 0.9 },
    { centerX: -1.15, centerY: 1.05, width: 1.2, height: 0.7 },
    { centerX: 1.25, centerY: -0.25, width: 1.1, height: 1.0 },
    { centerX: 3.0, centerY: 2.0, width: 0.9, height: 0.8 }
  ];

  build() {
    Column({ space: 12 }) {
      Text('2D Fallback Map')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F8FAFC')
      Row({ space: 8 }) {
        this.badge('2D Fallback', '#0F766E')
        this.badge(this.statusText, this.statusColor())
      }
      .width('100%')

      Stack() {
        this.sceneBackground()
        ForEach(this.obstacleData, (obstacle: ObstacleRect, index: number) => {
          this.obstacleMarker(obstacle)
        }, (obstacle: ObstacleRect, index: number) => `obs-${index}`)

        ForEach(this.segmentIndices(), (index: number) => {
          this.baseSegmentDots(index)
        }, (index: number) => `base-${index}`)

        ForEach(this.completedSegmentIndices(), (index: number) => {
          this.completedSegmentDots(index)
        }, (index: number) => `done-${index}`)
        if (this.activeSegmentIndex >= 0 && this.activeSegmentIndex < this.pathPoints.length - 1 && this.segmentProgress > 0) {
          this.partialSegmentDots(this.activeSegmentIndex, this.segmentProgress)
        }

        ForEach(this.pathPoints, (point: Point3D, index: number) => {
          this.waypoint(point)
        }, (point: Point3D, index: number) => `point-${index}`)

        this.startOrEndMarker(this.pathPoints[0], 'S', '#0EA5E9')
        this.startOrEndMarker(this.pathPoints[this.pathPoints.length - 1], 'E', this.runState === RunState.Completed ? '#22C55E' : '#F97316')
        this.moverMarker(this.pose)
      }
      .width('100%')
      .aspectRatio(1)
      .backgroundColor('#0B1120')
      .borderRadius(8)
      .clip(true)
      .onAreaChange((oldValue, newValue) => {
        this.updateCanvasSize(newValue.width.toString());
      })

      Text(this.sceneStatusText === 'Ready'
        ? 'Fallback scene ready. Start the animation to watch the mover travel from S to E.'
        : this.sceneStatusText)
        .fontSize(13)
        .fontColor('#CBD5E1')
        .maxLines(2)
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#111827')
    .borderRadius(8)
  }
  @Builder
  private sceneBackground() {
    Stack() {
      Column() {
        Blank()
          .width('100%')
          .height('100%')
          .backgroundColor('#0F172A')
      }

      ForEach([0, 1, 2, 3, 4], (row: number) => {
        Divider()
          .vertical(false)
          .strokeWidth(1)
          .color('#1E293B')
          .width('100%')
          .position({ x: 0, y: `${20 + row * 20}%` })
      }, (row: number) => row.toString())

      ForEach([0, 1, 2, 3, 4], (col: number) => {
        Divider()
          .vertical(true)
          .strokeWidth(1)
          .color('#1E293B')
          .height('100%')
          .position({ x: `${20 + col * 20}%`, y: 0 })
      }, (col: number) => col.toString())
    }
    .width('100%')
    .height('100%')
  }
  @Builder
  private obstacleMarker(obstacle: ObstacleRect) {
    Column() {
      Blank()
        .width(this.projectWidth(obstacle.width))
        .height(this.projectHeight(obstacle.height))
        .backgroundColor('#F97316')
        .opacity(0.82)
        .borderRadius(6)
    }
    .position({ x: this.projectRectTopLeft(obstacle).x, y: this.projectRectTopLeft(obstacle).y })
  }
  @Builder
  private baseSegmentDots(index: number) {
    ForEach(this.segmentDots(this.pathPoints[index], this.pathPoints[index + 1], 16), (dot: Position2D, dotIndex: number) => {
      this.pathDot(dot, '#3B82F6')
    }, (dot: Position2D, dotIndex: number) => `${index}-base-${dotIndex}`)
  }
  @Builder
  private completedSegmentDots(index: number) {
    ForEach(this.segmentDots(this.pathPoints[index], this.pathPoints[index + 1], 16), (dot: Position2D, dotIndex: number) => {
      this.pathDot(dot, '#22C55E')
    }, (dot: Position2D, dotIndex: number) => `${index}-done-${dotIndex}`)
  }
  @Builder
  private partialSegmentDots(index: number, progress: number) {
    ForEach(this.segmentDots(this.pathPoints[index], this.pathPoints[index + 1], Math.max(1, Math.ceil(progress * 16))), (dot: Position2D, dotIndex: number) => {
      this.pathDot(dot, '#22C55E')
    }, (dot: Position2D, dotIndex: number) => `${index}-partial-${dotIndex}`)
  }
  @Builder
  private pathDot(dot: Position2D, color: string) {
    Column() {
      Blank()
        .width(this.pathDotSize)
        .height(this.pathDotSize)
        .backgroundColor(color)
        .borderRadius(this.pathDotSize / 2)
        .position({ x: dot.x - this.pathDotSize / 2, y: dot.y - this.pathDotSize / 2 })
    }
  }
  @Builder
  private waypoint(point: Point3D) {
    Column() {
      Blank()
        .width(this.pointSize)
        .height(this.pointSize)
        .backgroundColor('#E2E8F0')
        .opacity(0.95)
        .borderRadius(this.pointSize / 2)
    }
    .position({ x: this.projectPoint(point).x - this.pointSize / 2, y: this.projectPoint(point).y - this.pointSize / 2 })
  }
  @Builder
  private startOrEndMarker(point: Point3D, label: string, color: string) {
    Stack() {
      Column() {
        Blank()
          .width(26)
          .height(26)
          .backgroundColor(color)
          .borderRadius(13)
      }
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#020617')
    }
    .width(30)
    .height(30)
    .position({ x: this.projectPoint(point).x - 15, y: this.projectPoint(point).y - 15 })
  }
  @Builder
  private moverMarker(pose: Pose3D) {
    Stack() {
      Column() {
        Blank()
          .width(44)
          .height(44)
          .backgroundColor('#22C55E')
          .opacity(0.18)
          .borderRadius(22)
      }
      Column() {
        Blank()
          .width(this.moverSize)
          .height(this.moverSize)
          .backgroundColor('#22C55E')
          .borderRadius(this.moverSize / 2)
      }
      Text('M')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#052E16')
    }
    .width(48)
    .height(48)
    .position({ x: this.projectPoint(pose).x - 24, y: this.projectPoint(pose).y - 24 })
  }

  @Builder
  private badge(label: string, color: string) {
    Text(label)
      .fontSize(12)
      .fontColor('#F8FAFC')
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(color)
      .borderRadius(8)
  }

  private statusColor(): string {
    switch (this.runState) {
      case RunState.Running:
        return '#2563EB';
      case RunState.Paused:
        return '#B45309';
      case RunState.Completed:
        return '#15803D';
      default:
        return '#334155';
    }
  }

  private segmentIndices(): number[] {
    const items: number[] = [];
    for (let index = 0; index < this.pathPoints.length - 1; index++) {
      items.push(index);
    }
    return items;
  }

  private completedSegmentIndices(): number[] {
    const items: number[] = [];
    for (let index = 0; index < this.activeSegmentIndex; index++) {
      items.push(index);
    }
    if (this.runState === RunState.Completed && this.pathPoints.length >= 2) {
      items.push(this.pathPoints.length - 2);
    }
    return items;
  }

  private segmentDots(start: Point3D, end: Point3D, count: number): Position2D[] {
    const dots: Position2D[] = [];
    if (count <= 0) {
      return dots;
    }

    const startPos = this.projectPoint(start);
    const endPos = this.projectPoint(end);
    const divisor = count === 1 ? 1 : count - 1;
    for (let index = 0; index < count; index++) {
      const t = count === 1 ? this.segmentProgress : index / divisor;
      dots.push({
        x: startPos.x + (endPos.x - startPos.x) * t,
        y: startPos.y + (endPos.y - startPos.y) * t
      });
    }
    return dots;
  }

  private projectPoint(point: Point3D): Position2D {
    const bounds = this.sceneBounds();
    const width = this.canvasSize - this.boundsPadding * 2;
    const height = this.canvasSize - this.boundsPadding * 2;
    const normalizedX = bounds.maxX === bounds.minX ? 0.5 : (point.x - bounds.minX) / (bounds.maxX - bounds.minX);
    const normalizedY = bounds.maxY === bounds.minY ? 0.5 : (point.y - bounds.minY) / (bounds.maxY - bounds.minY);
    return {
      x: this.boundsPadding + normalizedX * width,
      y: this.canvasSize - this.boundsPadding - normalizedY * height
    };
  }

  private sceneBounds(): Bounds2D {
    const pathBounds = this.pathBounds();
    return {
      minX: pathBounds.minX - 0.8,
      maxX: pathBounds.maxX + 0.8,
      minY: pathBounds.minY - 0.8,
      maxY: pathBounds.maxY + 0.8
    };
  }

  private projectRectTopLeft(rect: ObstacleRect): Position2D {
    const center = this.projectPoint(new Point3D(rect.centerX, rect.centerY, 0));
    return {
      x: center.x - this.projectWidth(rect.width) / 2,
      y: center.y - this.projectHeight(rect.height) / 2
    };
  }

  private projectWidth(width: number): number {
    const bounds = this.sceneBounds();
    const sceneWidth = this.canvasSize - this.boundsPadding * 2;
    return (width / (bounds.maxX - bounds.minX)) * sceneWidth;
  }

  private projectHeight(height: number): number {
    const bounds = this.sceneBounds();
    const sceneHeight = this.canvasSize - this.boundsPadding * 2;
    return (height / (bounds.maxY - bounds.minY)) * sceneHeight;
  }

  private updateCanvasSize(width: number | string): void {
    const nextWidth = typeof width === 'number' ? width : Number.parseFloat(`${width}`);
    if (!Number.isNaN(nextWidth) && nextWidth > 0) {
      this.canvasSize = nextWidth;
    }
  }

  private pathBounds(): Bounds2D {
    let minX = this.pathPoints[0].x;
    let maxX = this.pathPoints[0].x;
    let minY = this.pathPoints[0].y;
    let maxY = this.pathPoints[0].y;

    for (let i = 1; i < this.pathPoints.length; i++) {
      const point = this.pathPoints[i];
      minX = Math.min(minX, point.x);
      maxX = Math.max(maxX, point.x);
      minY = Math.min(minY, point.y);
      maxY = Math.max(maxY, point.y);
    }

    return { minX, maxX, minY, maxY };
  }
}

interface Position2D {
  x: number;
  y: number;
}

interface Bounds2D {
  minX: number;
  maxX: number;
  minY: number;
  maxY: number;
}

interface ObstacleRect {
  centerX: number;
  centerY: number;
  width: number;
  height: number;
}
