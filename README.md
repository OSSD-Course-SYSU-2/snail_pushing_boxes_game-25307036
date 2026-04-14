# HarmonyOS 最小三维地图交互 Demo（6.0.2(22)）

本项目是一个基于 **DevEco Studio + HarmonyOS + ArkTS** 的**最小可运行三维地图交互 Demo**。

它演示了以下内容：

- 基于 ArkUI 的 Stage 模型应用结构
- 使用 `Component3D` / ArkGraphics 3D 进行渲染
- 从 `resources/rawfile` 加载本地 `.glb` 场景
- 一个沿预设路径移动的对象
- Start / Pause / Reset 控制
- 坐标、朝向（yaw）和运行状态显示

## 三维场景中包含的内容

场景文件位于：

`entry/src/main/resources/rawfile/map_scene.glb`

其中包含：

- 地面平面
- 4 个橙色障碍物方块
- 一条蓝色分段路径
- 一个名为 **Mover** 的绿色球形移动对象节点

## 项目结构

```text
AppScope/
entry/
  src/main/ets/
    entryability/
    pages/
    components/
    data/
    model/
    utils/
  src/main/resources/
    base/
    rawfile/
```

## 打开与运行方法

1. 打开 **DevEco Studio**
2. 选择 **Open Project（打开项目）**
3. 选择本项目所在文件夹
4. 确保本地 SDK 版本为 **HarmonyOS 6.0.2(22)**
5. 如果 DevEco 提示同步依赖或刷新工程配置，请按提示完成
6. 在 HarmonyOS 模拟器或真机上运行项目

## 说明

- 本 Demo 有意保持为**本地、最小、简单**的实现
- **不连接** ROS、后端服务或外部传感器
- 三维场景提前制作成 GLB 文件，以降低运行时动态构建网格的复杂度
- 如果你本机是 DevEco Studio 6.0.2，对应的开发态 `modelVersion` 和工程 SDK 版本已经统一为 6.0.2 / 6.0.2(22)

## 控件说明

- **Start**：开始移动对象动画
- **Pause**：暂停移动对象动画
- **Reset**：将移动对象重置到第一个路径点

## 主要实现说明

- 使用 `Scene.load($rawfile('map_scene.glb'))` 加载 rawfile 中的 GLB 场景
- 通过 `Component3D` 结合 `ModelType.SURFACE` 渲染场景
- 代码会通过若干候选节点路径查找移动对象节点，例如 `rootNode_/Mover`
- 移动对象的位置由 `PathData.ets` 中硬编码的路径点数组驱动
- GLB 文件本身带有初始相机视角，因此场景加载后可以直接显示

## 如果找不到 Mover 节点

如果你本地 SDK 加载 GLB 后的节点路径和当前代码假设不完全一致，需要修改以下文件中的候选路径：

```text
entry/src/main/ets/pages/Index.ets
```

重点检查这段代码：

```ts
const moverCandidates: string[] = [
  'rootNode_/Mover',
  'rootNode_/map_scene/Mover',
  'Mover'
];
```

如果实际节点路径不同，请替换成你本地环境中正确的节点路径。

## 后续可扩展方向

- 增加历史轨迹显示
- 支持点击对象显示详细信息
- 增加多个移动对象
- 从 JSON/rawfile 中读取路径点
- 后续接入真实机器人遥测数据
