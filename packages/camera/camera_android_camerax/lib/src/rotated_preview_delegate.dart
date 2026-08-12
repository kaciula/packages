// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'camerax_library.g.dart';
import 'image_reader_rotated_preview.dart';
import 'surface_texture_rotated_preview.dart';

/// Widget that rotates the camera preview to be upright according to the
/// current user interface orientation based on whether or not the device
/// uses an Impeller backend that handles crop and rotation of Surfaces
/// correctly automatically.
@internal
final class RotatedPreviewDelegate extends StatefulWidget {
  /// Creates [RotatedPreviewDelegate] that will build the correctly
  /// rotated preview widget depending on whether or not the Impeller
  /// backend handles crop and rotation automatically.
  const RotatedPreviewDelegate({
    super.key,
    required this.handlesCropAndRotation,
    required this.initialDeviceOrientation,
    required this.initialDefaultDisplayRotation,
    required this.deviceOrientationStream,
    required this.sensorOrientationDegrees,
    required this.cameraIsFrontFacing,
    required this.deviceOrientationManager,
    required this.initialHasCameraTransform,
    required this.hasCameraTransformStream,
    required this.child,
  });

  /// Whether or not the Android surface producer automatically handles
  /// correcting the rotation of camera previews for the device this plugin
  /// runs on.
  final bool handlesCropAndRotation;

  /// The initial orientation of the device when the camera is created.
  final DeviceOrientation initialDeviceOrientation;

  /// The initial rotation of the Android default display when the camera is created,
  /// in terms of a Surface rotation constant.
  final int initialDefaultDisplayRotation;

  /// Stream of changes to the device orientation.
  final Stream<DeviceOrientation> deviceOrientationStream;

  /// The orientation of the camera sensor in degrees.
  final double sensorOrientationDegrees;

  /// Whether or not the camera is front facing.
  final bool cameraIsFrontFacing;

  /// The camera's device orientation manager.
  ///
  /// Instance required to check the current rotation of the default Android display.
  final DeviceOrientationManager deviceOrientationManager;

  /// Whether frames currently delivered to the preview surface still carry the
  /// camera sensor transform.
  final bool initialHasCameraTransform;

  /// Stream of changes to whether preview frames carry the camera sensor
  /// transform.
  ///
  /// CameraX reports false when it delivers pre-transformed frames, e.g. via
  /// stream sharing when the bound use case combination exceeds the device's
  /// supported surface combinations, which can change as use cases are bound
  /// and unbound (like a video recording starting and stopping).
  final Stream<bool> hasCameraTransformStream;

  /// The camera preview [Widget] to rotate.
  final Widget child;

  @override
  State<RotatedPreviewDelegate> createState() => _RotatedPreviewDelegateState();
}

final class _RotatedPreviewDelegateState extends State<RotatedPreviewDelegate> {
  late bool _hasCameraTransform;
  late final StreamSubscription<bool> _hasCameraTransformSubscription;

  @override
  void initState() {
    super.initState();
    _hasCameraTransform = widget.initialHasCameraTransform;
    _hasCameraTransformSubscription = widget.hasCameraTransformStream.listen((
      bool hasCameraTransform,
    ) {
      setState(() {
        _hasCameraTransform = hasCameraTransform;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_hasCameraTransformSubscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pre-transformed frames (no camera transform) are already upright with
    // respect to the display, so sensor orientation compensation must be
    // skipped and only disagreement between the user interface orientation
    // and the display rotation needs correcting.
    if (widget.handlesCropAndRotation || !_hasCameraTransform) {
      return SurfaceTextureRotatedPreview(
        widget.initialDeviceOrientation,
        widget.initialDefaultDisplayRotation,
        widget.deviceOrientationStream,
        widget.deviceOrientationManager,
        child: widget.child,
      );
    }

    if (widget.cameraIsFrontFacing) {
      return ImageReaderRotatedPreview.frontFacingCamera(
        widget.initialDeviceOrientation,
        widget.initialDefaultDisplayRotation,
        widget.deviceOrientationStream,
        widget.sensorOrientationDegrees,
        widget.deviceOrientationManager,
        child: widget.child,
      );
    } else {
      return ImageReaderRotatedPreview.backFacingCamera(
        widget.initialDeviceOrientation,
        widget.initialDefaultDisplayRotation,
        widget.deviceOrientationStream,
        widget.sensorOrientationDegrees,
        widget.deviceOrientationManager,
        child: widget.child,
      );
    }
  }
}
