// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// Transformation info of the preview `SurfaceRequest` as reported by CameraX.
@immutable
final class PreviewTransformationInfo {
  /// Creates [PreviewTransformationInfo].
  const PreviewTransformationInfo({
    required this.hasCameraTransform,
    required this.boundDisplayRotation,
  });

  /// Whether frames delivered to the preview surface still carry the camera
  /// sensor transform.
  ///
  /// CameraX reports false when it delivers pre-transformed frames, e.g. via
  /// stream sharing when the bound use case combination exceeds the device's
  /// supported surface combinations.
  final bool hasCameraTransform;

  /// The rotation of the default display when the preview use case was last
  /// bound, as a `Surface` rotation constant.
  ///
  /// CameraX targets this rotation for use cases bound without an explicit
  /// target rotation, so when [hasCameraTransform] is false, frames arrive
  /// already upright for a display with this rotation.
  final int boundDisplayRotation;

  @override
  bool operator ==(Object other) {
    return other is PreviewTransformationInfo &&
        other.hasCameraTransform == hasCameraTransform &&
        other.boundDisplayRotation == boundDisplayRotation;
  }

  @override
  int get hashCode => Object.hash(hasCameraTransform, boundDisplayRotation);
}
