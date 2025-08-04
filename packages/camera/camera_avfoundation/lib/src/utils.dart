// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';

import 'avfoundation_camera_description.dart';
import 'messages.g.dart';

/// Creates a [CameraDescription] from a Pigeon [PlatformCameraDescription].
AVCameraDescription cameraDescriptionFromPlatform(PlatformCameraDescription camera) {
  return AVCameraDescription(
    name: camera.name,
    lensDirection: cameraLensDirectionFromPlatform(camera.lensDirection),
    sensorOrientation: 90,
    lensType: cameraLensTypeFromPlatform(camera.lensType),
    availableStabilizationModes: camera.availableStabilizationModes
        .map((PlatformCameraStabilizationMode it) => stabilizationModeFromPlatform(it))
        .toList(),
    captureDeviceType: captureDeviceTypeFromPlatform(camera.captureDeviceType),
  );
}

/// Converts a Pigeon [PlatformCameraLensDirection] to a [CameraLensDirection].
CameraLensDirection cameraLensDirectionFromPlatform(PlatformCameraLensDirection direction) {
  return switch (direction) {
    PlatformCameraLensDirection.front => CameraLensDirection.front,
    PlatformCameraLensDirection.back => CameraLensDirection.back,
    PlatformCameraLensDirection.external => CameraLensDirection.external,
  };
}

/// Converts a Pigeon [PlatformCameraLensType] to a [CameraLensType].
CameraLensType cameraLensTypeFromPlatform(PlatformCameraLensType type) {
  return switch (type) {
    PlatformCameraLensType.wide => CameraLensType.wide,
    PlatformCameraLensType.telephoto => CameraLensType.telephoto,
    PlatformCameraLensType.ultraWide => CameraLensType.ultraWide,
    PlatformCameraLensType.unknown => CameraLensType.unknown,
  };
}

/// Convents the given device orientation to Pigeon.
PlatformDeviceOrientation serializeDeviceOrientation(DeviceOrientation orientation) {
  switch (orientation) {
    case DeviceOrientation.portraitUp:
      return PlatformDeviceOrientation.portraitUp;
    case DeviceOrientation.portraitDown:
      return PlatformDeviceOrientation.portraitDown;
    case DeviceOrientation.landscapeRight:
      return PlatformDeviceOrientation.landscapeRight;
    case DeviceOrientation.landscapeLeft:
      return PlatformDeviceOrientation.landscapeLeft;
  }
  // The enum comes from a different package, which could get a new value at
  // any time, so provide a fallback that ensures this won't break when used
  // with a version that contains new values. This is deliberately outside
  // the switch rather than a `default` so that the linter will flag the
  // switch as needing an update.
  // ignore: dead_code
  return PlatformDeviceOrientation.portraitUp;
}

/// Converts a Pigeon [PlatformDeviceOrientation] to a [DeviceOrientation].
DeviceOrientation deviceOrientationFromPlatform(PlatformDeviceOrientation orientation) {
  return switch (orientation) {
    PlatformDeviceOrientation.portraitUp => DeviceOrientation.portraitUp,
    PlatformDeviceOrientation.portraitDown => DeviceOrientation.portraitDown,
    PlatformDeviceOrientation.landscapeLeft => DeviceOrientation.landscapeLeft,
    PlatformDeviceOrientation.landscapeRight => DeviceOrientation.landscapeRight,
  };
}

/// Converts a Pigeon [PlatformExposureMode] to an [ExposureMode].
ExposureMode exposureModeFromPlatform(PlatformExposureMode mode) {
  return switch (mode) {
    PlatformExposureMode.auto => ExposureMode.auto,
    PlatformExposureMode.locked => ExposureMode.locked,
  };
}

/// Converts a Pigeon [PlatformFocusMode] to an [FocusMode].
FocusMode focusModeFromPlatform(PlatformFocusMode mode) {
  return switch (mode) {
    PlatformFocusMode.auto => FocusMode.auto,
    PlatformFocusMode.locked => FocusMode.locked,
  };
}

/// Converts a [CameraStabilizationMode] to a Pigeon [PlatformCameraStabilizationMode].
PlatformCameraStabilizationMode serializeStabilizationMode(
    CameraStabilizationMode mode) {
  switch (mode) {
    case CameraStabilizationMode.off:
      return PlatformCameraStabilizationMode.off;
    case CameraStabilizationMode.digital:
      return PlatformCameraStabilizationMode.digital;
    case CameraStabilizationMode.optical:
      return PlatformCameraStabilizationMode.optical;
    case CameraStabilizationMode.standard:
      return PlatformCameraStabilizationMode.standard;
    case CameraStabilizationMode.cinematic:
      return PlatformCameraStabilizationMode.cinematic;
    case CameraStabilizationMode.cinematicExtended:
      return PlatformCameraStabilizationMode.cinematicExtended;
    case CameraStabilizationMode.previewOptimized:
      return PlatformCameraStabilizationMode.previewOptimized;
    case CameraStabilizationMode.auto:
      return PlatformCameraStabilizationMode.auto;
  }
}

/// Parses a string into a corresponding CameraStabilizationMode.
CameraStabilizationMode stabilizationModeFromPlatform(
    PlatformCameraStabilizationMode mode) {
  switch (mode) {
    case PlatformCameraStabilizationMode.off:
      return CameraStabilizationMode.off;
    case PlatformCameraStabilizationMode.digital:
      return CameraStabilizationMode.digital;
    case PlatformCameraStabilizationMode.optical:
      return CameraStabilizationMode.optical;
    case PlatformCameraStabilizationMode.standard:
      return CameraStabilizationMode.standard;
    case PlatformCameraStabilizationMode.cinematic:
      return CameraStabilizationMode.cinematic;
    case PlatformCameraStabilizationMode.cinematicExtended:
      return CameraStabilizationMode.cinematicExtended;
    case PlatformCameraStabilizationMode.previewOptimized:
      return CameraStabilizationMode.previewOptimized;
    case PlatformCameraStabilizationMode.auto:
      return CameraStabilizationMode.auto;
  }
}

/// Converts a Pigeon [PlatformCameraLensDirection] to a [CameraLensDirection].
AVCaptureDeviceType captureDeviceTypeFromPlatform(
    PlatformAVCaptureDeviceType deviceType) {
  return switch (deviceType) {
    PlatformAVCaptureDeviceType.builtInWideAngleCamera =>
      AVCaptureDeviceType.builtInWideAngleCamera,
    PlatformAVCaptureDeviceType.builtInUltraWideCamera =>
      AVCaptureDeviceType.builtInUltraWideCamera,
    PlatformAVCaptureDeviceType.builtInTelephotoCamera =>
      AVCaptureDeviceType.builtInTelephotoCamera,
    PlatformAVCaptureDeviceType.builtInDualCamera =>
      AVCaptureDeviceType.builtInDualCamera,
    PlatformAVCaptureDeviceType.builtInDualWideCamera =>
      AVCaptureDeviceType.builtInDualWideCamera,
    PlatformAVCaptureDeviceType.builtInTripleCamera =>
      AVCaptureDeviceType.builtInTripleCamera,
    PlatformAVCaptureDeviceType.continuityCamera =>
      AVCaptureDeviceType.continuityCamera,
    PlatformAVCaptureDeviceType.external => AVCaptureDeviceType.external,
    PlatformAVCaptureDeviceType.builtInLiDARDepthCamera =>
      AVCaptureDeviceType.builtInLiDARDepthCamera,
    PlatformAVCaptureDeviceType.builtInTrueDepthCamera =>
      AVCaptureDeviceType.builtInTrueDepthCamera,
  };
}
