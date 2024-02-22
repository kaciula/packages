// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

/// The direction the camera is facing.
enum CameraLensDirection {
  /// Front facing camera (a user looking at the screen is seen by the camera).
  front,

  /// Back facing camera (a user looking at the screen is not seen by the camera).
  back,

  /// External camera which may not be mounted to the device.
  external,
}

/// The mode of camera stabilization.
enum CameraStabilizationMode {
  /// No stabilization.
  off,

  /// Stabilization using digital video stabilization.
  digital, // Android only

  /// Stabilization using optical video stabilization (OIS).
  optical, // Android only

  /// A mode that uses the standard algorithm.
  standard, // iOS only

  /// A mode that uses the cinematic stabilization algorithm.
  cinematic, // iOS only

  /// A mode that uses the extended cinematic stabilization algorithm.
  cinematicExtended, // iOS only

  /// A mode that uses the preview optimized stabilization algorithm.
  previewOptimized, // iOS only

  /// A mode that indicates the system chooses the most appropriate video stabilization mode for the device and format.
  auto, // iOS only
}

/// Properties of a camera device.
@immutable
class CameraDescription {
  /// Creates a new camera description with the given properties.
  const CameraDescription({
    required this.name,
    required this.lensDirection,
    required this.sensorOrientation,
    required this.availableStabilizationModes,
  });

  /// The name of the camera device.
  final String name;

  /// The direction the camera is facing.
  final CameraLensDirection lensDirection;

  /// Clockwise angle through which the output image needs to be rotated to be upright on the device screen in its native orientation.
  ///
  /// **Range of valid values:**
  /// 0, 90, 180, 270
  ///
  /// On Android, also defines the direction of rolling shutter readout, which
  /// is from top to bottom in the sensor's coordinate system.
  final int sensorOrientation;

  /// The available stabilization modes for the camera.
  final List<CameraStabilizationMode> availableStabilizationModes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraDescription &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          lensDirection == other.lensDirection;

  @override
  int get hashCode => Object.hash(name, lensDirection);

  @override
  String toString() {
    return '${objectRuntimeType(this, 'CameraDescription')}('
        '$name, $lensDirection, $sensorOrientation)';
  }
}
