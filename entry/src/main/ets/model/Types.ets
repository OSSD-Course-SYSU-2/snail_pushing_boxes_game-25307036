export class Point3D {
  x: number;
  y: number;
  z: number;

  constructor(x: number, y: number, z: number) {
    this.x = x;
    this.y = y;
    this.z = z;
  }
}

export class Pose3D extends Point3D {
  yaw: number;

  constructor(x: number, y: number, z: number, yaw: number) {
    super(x, y, z);
    this.yaw = yaw;
  }
}

export enum RunState {
  Idle = 'Idle',
  Running = 'Running',
  Paused = 'Paused',
  Completed = 'Completed',
  Loading = 'Loading',
  Error = 'Error'
}
