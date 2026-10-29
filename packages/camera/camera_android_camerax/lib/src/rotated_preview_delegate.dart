// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'camerax_library.g.dart';
import 'image_reader_rotated_preview.dart';
import 'preview_transformation_info.dart';
import 'rotated_preview_utils.dart';
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
    required this.initialTransformationInfo,
    required this.transformationInfoStream,
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

  /// The transformation info of the frames currently delivered to the preview
  /// surface.
  final PreviewTransformationInfo initialTransformationInfo;

  /// Stream of changes to the transformation info of the preview frames.
  ///
  /// CameraX delivers pre-transformed frames, e.g. via stream sharing when the
  /// bound use case combination exceeds the device's supported surface
  /// combinations, which can change as use cases are bound and unbound (like a
  /// video recording starting and stopping).
  final Stream<PreviewTransformationInfo> transformationInfoStream;

  /// The camera preview [Widget] to rotate.
  final Widget child;

  @override
  State<RotatedPreviewDelegate> createState() => _RotatedPreviewDelegateState();
}

final class _RotatedPreviewDelegateState extends State<RotatedPreviewDelegate> {
  late PreviewTransformationInfo _transformationInfo;
  late final StreamSubscription<PreviewTransformationInfo> _transformationInfoSubscription;

  @override
  void initState() {
    super.initState();
    _transformationInfo = widget.initialTransformationInfo;
    _transformationInfoSubscription = widget.transformationInfoStream.listen((
      PreviewTransformationInfo transformationInfo,
    ) {
      setState(() {
        _transformationInfo = transformationInfo;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_transformationInfoSubscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pre-transformed frames (no camera transform) are already upright with
    // respect to the display rotation the preview use case targeted when the
    // frames were prepared, so sensor orientation compensation must be
    // skipped, that rotation must be undone, and only disagreement between the
    // user interface orientation and the display rotation needs correcting.
    if (widget.handlesCropAndRotation || !_transformationInfo.hasCameraTransform) {
      return SurfaceTextureRotatedPreview(
        widget.initialDeviceOrientation,
        widget.initialDefaultDisplayRotation,
        widget.deviceOrientationStream,
        widget.deviceOrientationManager,
        preRotatedQuarterTurns: _transformationInfo.hasCameraTransform
            ? 0
            : getQuarterTurnsFromSurfaceRotationConstant(_transformationInfo.boundDisplayRotation),
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
