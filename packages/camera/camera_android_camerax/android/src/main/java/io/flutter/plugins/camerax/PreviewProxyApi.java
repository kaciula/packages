// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camerax;

import android.hardware.camera2.CaptureRequest;
import android.util.Range;
import android.view.Surface;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.camera.camera2.interop.Camera2Interop;
import androidx.camera.camera2.interop.ExperimentalCamera2Interop;
import androidx.camera.core.Preview;
import androidx.camera.core.ResolutionInfo;
import androidx.camera.core.SurfaceRequest;
import androidx.camera.core.resolutionselector.ResolutionSelector;
import io.flutter.view.TextureRegistry;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * ProxyApi implementation for {@link Preview}. This class may handle instantiating native object
 * instances that are attached to a Dart instance or handle method calls on the associated native
 * class or an instance of that class.
 */
class PreviewProxyApi extends PigeonApiPreview {
  // Stores the SurfaceProducer when it is used as a SurfaceProvider for a Preview.
  private final Map<Preview, TextureRegistry.SurfaceProducer> surfaceProducers = new HashMap<>();

  PreviewProxyApi(@NonNull ProxyApiRegistrar pigeonRegistrar) {
    super(pigeonRegistrar);
  }

  @NonNull
  @Override
  public ProxyApiRegistrar getPigeonRegistrar() {
    return (ProxyApiRegistrar) super.getPigeonRegistrar();
  }

  // Range<?> is defined as Range<Integer> in pigeon.
  @SuppressWarnings("unchecked")
  @OptIn(markerClass = ExperimentalCamera2Interop.class)
  @NonNull
  @Override
  public Preview pigeon_defaultConstructor(
      @Nullable ResolutionSelector resolutionSelector,
      @Nullable Long targetRotation,
      @Nullable Range<?> targetFpsRange) {
    final Preview.Builder builder = new Preview.Builder();
    if (targetRotation != null) {
      builder.setTargetRotation(targetRotation.intValue());
    }
    if (resolutionSelector != null) {
      builder.setResolutionSelector(resolutionSelector);
    }

    if (targetFpsRange != null) {
      Camera2Interop.Extender<Preview> extender = new Camera2Interop.Extender<>(builder);
      extender.setCaptureRequestOption(
          CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, (Range<Integer>) targetFpsRange);
    }

    return builder.build();
  }

  @Override
  public long setSurfaceProvider(
      @NonNull Preview pigeonInstance, @NonNull SystemServicesManager systemServicesManager) {
    final TextureRegistry.SurfaceProducer surfaceProducer =
        getPigeonRegistrar().getTextureRegistry().createSurfaceProducer();
    final Preview.SurfaceProvider surfaceProvider =
        createSurfaceProvider(surfaceProducer, systemServicesManager);

    pigeonInstance.setSurfaceProvider(surfaceProvider);
    surfaceProducers.put(pigeonInstance, surfaceProducer);

    return surfaceProducer.id();
  }

  @Override
  public void releaseSurfaceProvider(@NonNull Preview pigeonInstance) {
    final TextureRegistry.SurfaceProducer surfaceProducer = surfaceProducers.remove(pigeonInstance);
    if (surfaceProducer != null) {
      surfaceProducer.release();
      return;
    }
    throw new IllegalStateException(
        "releaseFlutterSurfaceTexture() cannot be called if the flutterSurfaceProducer for the"
            + " camera preview has not yet been initialized.");
  }

  @Override
  public boolean surfaceProducerHandlesCropAndRotation(@NonNull Preview pigeonInstance) {
    final TextureRegistry.SurfaceProducer surfaceProducer = surfaceProducers.get(pigeonInstance);
    if (surfaceProducer != null) {
      return surfaceProducer.handlesCropAndRotation();
    }
    throw new IllegalStateException(
        "surfaceProducerHandlesCropAndRotation() cannot be called if the flutterSurfaceProducer for"
            + " the camera preview has not yet been initialized.");
  }

  @Nullable
  @Override
  public ResolutionInfo getResolutionInfo(Preview pigeonInstance) {
    return pigeonInstance.getResolutionInfo();
  }

  @Override
  public void setTargetRotation(Preview pigeonInstance, long rotation) {
    pigeonInstance.setTargetRotation((int) rotation);
  }

  @NonNull
  Preview.SurfaceProvider createSurfaceProvider(
      @NonNull TextureRegistry.SurfaceProducer surfaceProducer,
      @NonNull SystemServicesManager systemServicesManager) {
    return request -> {
      // Set callback for surfaceProducer to invalidate Surfaces that it produces when they
      // get destroyed.
      surfaceProducer.setCallback(
          new TextureRegistry.SurfaceProducer.Callback() {
            @Override
            public void onSurfaceAvailable() {
              // Do nothing. The Preview.SurfaceProvider will handle this whenever a new
              // Surface is needed.
            }

            @Override
            public void onSurfaceCleanup() {
              // Invalidate the SurfaceRequest so that CameraX knows to to make a new request
              // for a surface.
              request.invalidate();
            }
          });

      surfaceProducer.setSize(
          request.getResolution().getWidth(), request.getResolution().getHeight());
      final Surface flutterSurface = surfaceProducer.getForcedNewSurface();
      final AtomicBoolean surfaceProvided = new AtomicBoolean(false);
      final Runnable provideSurface =
          () -> {
            if (!surfaceProvided.compareAndSet(false, true)) {
              return;
            }
            request.provideSurface(
                flutterSurface,
                Executors.newSingleThreadExecutor(),
                (result) -> {
                  // See
                  // https://developer.android.com/reference/androidx/camera/core/SurfaceRequest.Result
                  // for documentation.
                  // Always attempt a release.
                  flutterSurface.release();
                  int resultCode = result.getResultCode();
                  switch (resultCode) {
                    case SurfaceRequest.Result.RESULT_REQUEST_CANCELLED:
                    case SurfaceRequest.Result.RESULT_WILL_NOT_PROVIDE_SURFACE:
                    case SurfaceRequest.Result.RESULT_SURFACE_ALREADY_PROVIDED:
                    case SurfaceRequest.Result.RESULT_SURFACE_USED_SUCCESSFULLY:
                      // Only need to release, do nothing.
                      break;
                    case SurfaceRequest.Result.RESULT_INVALID_SURFACE: // Intentional fall through.
                    default:
                      systemServicesManager.onCameraError(
                          getProvideSurfaceErrorDescription(resultCode));
                  }
                });
          };

      // Forward transformation info updates to Dart so the preview widget can
      // compensate correctly. Notably, when CameraX engages stream sharing
      // (e.g. binding Preview + VideoCapture + ImageAnalysis on devices that
      // cannot stream all three concurrently), frames are pre-rotated by an
      // OpenGL pipeline and no longer carry the camera sensor transform, which
      // is reported here via hasCameraTransform=false.
      //
      // The surface is provided only after Dart has applied the first
      // transformation info of this request. CameraX cannot deliver frames
      // into a session before its surface is provided, so frames of a new
      // session (e.g. stream sharing engaging when a recording starts) can
      // never be rendered with the previous session's rotation compensation.
      request.setTransformationInfoListener(
          Executors.newSingleThreadExecutor(),
          transformationInfo ->
              systemServicesManager.onPreviewTransformationInfoChanged(
                  transformationInfo.getRotationDegrees(),
                  transformationInfo.hasCameraTransform(),
                  provideSurface));
    };
  }

  /**
   * Returns an error description for each {@link SurfaceRequest.Result} that represents an error
   * with providing a surface.
   */
  String getProvideSurfaceErrorDescription(int resultCode) {
    if (resultCode == SurfaceRequest.Result.RESULT_INVALID_SURFACE) {
      return resultCode + ": Provided surface could not be used by the camera.";
    }
    return resultCode + ": Attempt to provide a surface resulted with unrecognizable code.";
  }

  @Nullable
  @Override
  public ResolutionSelector resolutionSelector(@NonNull Preview pigeonInstance) {
    return pigeonInstance.getResolutionSelector();
  }
}
