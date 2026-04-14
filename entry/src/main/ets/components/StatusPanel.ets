import { Pose3D, RunState } from '../model/Types';
import { poseText, yawText } from '../utils/Formatters';

@Component
export struct StatusPanel {
  @Prop pose: Pose3D;
  @Prop runState: RunState;
  @Prop sceneStatusText: string;
  @Prop viewModeText: string;

  build() {
    Column({ space: 10 }) {
      Text('Runtime Status')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F8FAFC')

      this.row('Pose', poseText(this.pose))
      this.row('Yaw', yawText(this.pose.yaw))
      this.row('State', this.runState)
      this.row('Mode', this.viewModeText)
      this.row('Scene', this.sceneStatusText)
    }
    .padding(14)
    .backgroundColor('#111827')
    .borderRadius(8)
    .width('100%')
  }

  @Builder
  private row(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(13)
        .fontColor('#94A3B8')
        .width(56)
      Text(value)
        .fontSize(13)
        .fontColor('#E2E8F0')
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }
}
