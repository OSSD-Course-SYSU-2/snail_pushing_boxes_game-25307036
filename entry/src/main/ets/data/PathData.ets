import { Point3D, Pose3D } from '../model/Types';

export const PATH_POINTS: Point3D[] = [
  new Point3D(-4.5, -3.2, 0.22),
  new Point3D(-3.6, -2.8, 0.22),
  new Point3D(-2.6, -2.1, 0.22),
  new Point3D(-1.4, -1.0, 0.22),
  new Point3D(-0.2, 0.0, 0.22),
  new Point3D(1.0, 1.1, 0.22),
  new Point3D(2.2, 1.8, 0.22),
  new Point3D(3.1, 2.6, 0.22),
  new Point3D(4.0, 3.2, 0.22)
];

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function interpolate(start: Point3D, end: Point3D, t: number): Pose3D {
  const yaw = Math.atan2(end.y - start.y, end.x - start.x) * 180 / Math.PI;
  return new Pose3D(
    lerp(start.x, end.x, t),
    lerp(start.y, end.y, t),
    lerp(start.z, end.z, t),
    yaw
  );
}

export function firstPose(): Pose3D {
  const p = PATH_POINTS[0];
  return new Pose3D(p.x, p.y, p.z, 0);
}
