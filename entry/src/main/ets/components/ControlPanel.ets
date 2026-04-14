import { Pose3D, RunState } from '../model/Types';
import { StatusPanel } from './StatusPanel';

@Component
export struct ControlPanel {
  @Prop pose: Pose3D;
  @Prop runState: RunState;
  @Prop sceneStatusText: string;
  @Prop viewModeText: string;
  @Prop modeDescriptionText: string;
  @Prop isCompactLayout: boolean;
  onStart: () => void = () => {};
  onPause: () => void = () => {};
  onReset: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Text(this.viewModeText === '2D Fallback' ? '2D Fallback Map Demo' : '3D Map Interaction Demo')
        .fontSize(this.isCompactLayout ? 20 : 22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F8FAFC')
        .maxLines(2)

      Text(this.modeDescriptionText)
        .fontSize(13)
        .fontColor('#CBD5E1')
        .maxLines(this.isCompactLayout ? 4 : 3)

      Row({ space: 8 }) {
        this.primaryButton('Start', this.onStart)
        this.primaryButton('Pause', this.onPause)
        this.primaryButton('Reset', this.onReset)
      }
      .width('100%')

      StatusPanel({
        pose: this.pose,
        runState: this.runState,
        sceneStatusText: this.sceneStatusText,
        viewModeText: this.viewModeText
      })

      Column({ space: 6 }) {
        Text('Legend')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F8FAFC')
        if (this.viewModeText === '2D Fallback') {
          Text('Orange blocks: obstacles')
            .fontSize(12)
            .fontColor('#CBD5E1')
          Text('Blue route: remaining path')
            .fontSize(12)
            .fontColor('#CBD5E1')
          Text('Green route: completed path')
            .fontSize(12)
            .fontColor('#CBD5E1')
          Text('S / E: start and end markers')
            .fontSize(12)
            .fontColor('#CBD5E1')
          Text('Green marker: current mover position')
            .fontSize(12)
            .fontColor('#CBD5E1')
        } else {
          Text('Gray plane: ground')
            .fontSize(12)
            .fontColor('#CBD5E1')
          Text('Orange boxes: obstacles')
            .fontSize(12)
            .fontColor('#CBD5E1')
          Text('Blue strips: planned path')
            .fontSize(12)
            .fontColor('#CBD5E1')
          Text('Green sphere: moving object')
            .fontSize(12)
            .fontColor('#CBD5E1')
        }
      }
      .padding(14)
      .backgroundColor('#111827')
      .borderRadius(8)
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private primaryButton(label: string, action: () => void) {
    Button(label)
      .type(ButtonType.Normal)
      .fontSize(14)
      .backgroundColor('#2563EB')
      .fontColor(Color.White)
      .layoutWeight(1)
      .borderRadius(8)
      .onClick(() => action())
  }
}
