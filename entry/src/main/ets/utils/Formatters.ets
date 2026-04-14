import { Pose3D } from '../model/Types';

export function fmt(value: number): string {
  return value.toFixed(2);
}

export function poseText(pose: Pose3D): string {
  return `(${fmt(pose.x)}, ${fmt(pose.y)}, ${fmt(pose.z)})`;
}

export function yawText(yaw: number): string {
  return `${yaw.toFixed(1)}°`;
}
