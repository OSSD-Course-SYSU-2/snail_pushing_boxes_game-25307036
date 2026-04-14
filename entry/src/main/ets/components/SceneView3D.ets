@Component
export struct SceneView3D {
  @Prop sceneOptions: SceneOptions;
  @Prop statusText: string;
  @Prop showOverlay: boolean;

  build() {
    Stack() {
      Component3D(this.sceneOptions)
        .width('100%')
        .height('100%')
        .backgroundColor('#0B1120')

      if (this.showOverlay) {
        Column({ space: 8 }) {
          LoadingProgress()
            .color('#60A5FA')
          Text(this.statusText)
            .fontColor('#E2E8F0')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#0B1120')
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(18)
    .clip(true)
  }
}
