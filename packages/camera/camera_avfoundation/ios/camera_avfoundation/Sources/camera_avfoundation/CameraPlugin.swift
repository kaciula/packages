// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Flutter
import ObjectiveC

// Import Objectice-C part of the implementation when SwiftPM is used.
#if canImport(camera_avfoundation_objc)
  import camera_avfoundation_objc
#endif

public final class CameraPlugin: NSObject, FlutterPlugin {
  private let registry: FlutterTextureRegistry
  private let messenger: FlutterBinaryMessenger
  private let globalEventAPI: FCPCameraGlobalEventApi
  private let deviceDiscoverer: FLTCameraDeviceDiscovering
  private let permissionManager: FLTCameraPermissionManager
  private let captureDeviceFactory: CaptureDeviceFactory
  private let captureSessionFactory: CaptureSessionFactory
  private let captureDeviceInputFactory: FLTCaptureDeviceInputFactory

  /// All FLTCam's state access and capture session related operations should be on run on this queue.
  private let captureSessionQueue: DispatchQueue

  /// An internal camera object that manages camera's state and performs camera operations.
  var camera: Camera?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CameraPlugin(
      registry: registrar.textures(),
      messenger: registrar.messenger(),
      globalAPI: FCPCameraGlobalEventApi(binaryMessenger: registrar.messenger()),
      deviceDiscoverer: FLTDefaultCameraDeviceDiscoverer(),
      permissionManager: FLTCameraPermissionManager(
        permissionService: FLTDefaultPermissionService()),
      deviceFactory: { name in
        // TODO(RobertOdrowaz) Implement better error handling and remove non-null assertion
        FLTDefaultCaptureDevice(device: AVCaptureDevice(uniqueID: name)!)
      },
      captureSessionFactory: { FLTDefaultCaptureSession(captureSession: AVCaptureSession()) },
      captureDeviceInputFactory: FLTDefaultCaptureDeviceInputFactory(),
      captureSessionQueue: DispatchQueue(label: "io.flutter.camera.captureSessionQueue")
    )

    SetUpFCPCameraApi(registrar.messenger(), instance)
  }

  init(
    registry: FlutterTextureRegistry,
    messenger: FlutterBinaryMessenger,
    globalAPI: FCPCameraGlobalEventApi,
    deviceDiscoverer: FLTCameraDeviceDiscovering,
    permissionManager: FLTCameraPermissionManager,
    deviceFactory: @escaping CaptureDeviceFactory,
    captureSessionFactory: @escaping CaptureSessionFactory,
    captureDeviceInputFactory: FLTCaptureDeviceInputFactory,
    captureSessionQueue: DispatchQueue
  ) {
    self.registry = registry
    self.messenger = messenger
    self.globalEventAPI = globalAPI
    self.deviceDiscoverer = deviceDiscoverer
    self.permissionManager = permissionManager
    self.captureDeviceFactory = deviceFactory
    self.captureSessionFactory = captureSessionFactory
    self.captureDeviceInputFactory = captureDeviceInputFactory
    self.captureSessionQueue = captureSessionQueue

    super.init()

    captureSessionQueue.setSpecific(
      key: captureSessionQueueSpecificKey, value: captureSessionQueueSpecificValue)

    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.addObserver(
      forName: UIDevice.orientationDidChangeNotification,
      object: UIDevice.current,
      queue: .main
    ) { [weak self] notification in
      self?.orientationChanged(notification)
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
  }

  private static func flutterErrorFromNSError(_ error: NSError) -> FlutterError {
    return FlutterError(
      code: "Error \(error.code)",
      message: error.localizedDescription,
      details: error.domain)
  }

  func orientationChanged(_ notification: Notification) {
    guard let device = notification.object as? UIDevice else { return }
    let orientation = device.orientation

    if orientation == .faceUp || orientation == .faceDown {
      // Do not change when oriented flat.
      return
    }

    self.captureSessionQueue.async { [weak self] in
      guard let strongSelf = self else { return }
      // `Camera.deviceOrientation` must be set on capture session queue.
      strongSelf.camera?.deviceOrientation = orientation
      // `CameraPlugin.sendDeviceOrientation` can be called on any queue.
      strongSelf.sendDeviceOrientation(orientation)
    }
  }

  func sendDeviceOrientation(_ orientation: UIDeviceOrientation) {
    DispatchQueue.main.async { [weak self] in
      self?.globalEventAPI.deviceOrientationChangedOrientation(
        FCPGetPigeonDeviceOrientationForOrientation(orientation)
      ) { _ in
        // Ignore errors; this is essentially a broadcast stream, and
        // it's fine if the other end doesn't receive the message
        // (e.g., if it doesn't currently have a listener set up).
      }
    }
  }
}

extension CameraPlugin: FCPCameraApi {
  private func mapStabilizationMode(_ mode: String) -> FCPPlatformCameraStabilizationMode {
    switch mode {
    case "off":
      return .off
    case "standard":
      return .standard
    case "cinematic":
      return .cinematic
    case "cinematicExtended":
      return .cinematicExtended
    case "previewOptimized":
      return .previewOptimized
    case "auto":
      return .auto
    default:
      return .off
    }
  }

  private func mapDeviceType(_ deviceType: AVCaptureDevice.DeviceType)
    -> FCPPlatformAVCaptureDeviceType
  {
    if deviceType == .builtInWideAngleCamera {
      return .builtInWideAngleCamera
    } else if deviceType == .builtInTelephotoCamera {
      return .builtInTelephotoCamera
    } else if deviceType == .builtInDualCamera {
      return .builtInDualCamera
    } else if deviceType == .builtInTrueDepthCamera {
      return .builtInTrueDepthCamera
    }

    if #available(iOS 13.0, *) {
      if deviceType == .builtInUltraWideCamera {
        return .builtInUltraWideCamera
      } else if deviceType == .builtInDualWideCamera {
        return .builtInDualWideCamera
      } else if deviceType == .builtInTripleCamera {
        return .builtInTripleCamera
      }
    }

    if #available(iOS 15.4, *) {
      if deviceType == .builtInLiDARDepthCamera {
        return .builtInLiDARDepthCamera
      }
    }

    if #available(iOS 17.0, *) {
      if deviceType == .external {
        return .external
      } else if deviceType == .continuityCamera {
        return .continuityCamera
      }
    }

    // Default fallback
    return .builtInDualCamera
  }

  public func availableCameras(
    completion: @escaping ([FCPPlatformCameraDescription]?, FlutterError?) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      guard let strongSelf = self else { return }

      var discoveryDevices: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera,
        .builtInTelephotoCamera,
        .builtInDualCamera,
        .builtInTrueDepthCamera,
      ]

      if #available(iOS 13.0, *) {
        discoveryDevices.append(.builtInUltraWideCamera)
        discoveryDevices.append(.builtInDualWideCamera)
        discoveryDevices.append(.builtInTripleCamera)
      }

      if #available(iOS 15.4, *) {
        discoveryDevices.append(.builtInLiDARDepthCamera)
      }

      if #available(iOS 17.0, *) {
        discoveryDevices.append(.external)
        discoveryDevices.append(.continuityCamera)
      }

      let devices = strongSelf.deviceDiscoverer.discoverySession(
        withDeviceTypes: discoveryDevices,
        mediaType: .video,
        position: .unspecified)

      var reply: [FCPPlatformCameraDescription] = []

      for device in devices {
        var lensFacing: FCPPlatformCameraLensDirection

        switch device.position {
        case .back:
          lensFacing = .back
        case .front:
          lensFacing = .front
        case .unspecified:
          lensFacing = .external
        @unknown default:
          lensFacing = .external
        }

        // Determine available stabilization modes based on iOS version
        let availableStabilizationModes: [String]
        if #available(iOS 17.0, *) {
          availableStabilizationModes = [
            "off", "standard", "cinematic", "cinematicExtended", "previewOptimized", "auto",
          ]
        } else {
          availableStabilizationModes = [
            "off", "standard", "cinematic", "cinematicExtended", "auto",
          ]
        }

        // Convert string array to FCPPlatformCameraStabilizationModeBox array
        let stabilizationModeBoxes = availableStabilizationModes.map { mode in
          FCPPlatformCameraStabilizationModeBox(value: strongSelf.mapStabilizationMode(mode))
        }

        let cameraDescription = FCPPlatformCameraDescription.make(
          withName: device.uniqueID,
          lensDirection: lensFacing,
          availableStabilizationModes: stabilizationModeBoxes,
          captureDeviceType: strongSelf.mapDeviceType(device.device.deviceType)
        )
        reply.append(cameraDescription)
      }

      completion(reply, nil)
    }
  }

  public func createCamera(
    withName cameraName: String,
    settings: FCPPlatformMediaSettings,
    stabilizationMode: FCPPlatformCameraStabilizationMode,
    completion: @escaping (NSNumber?, FlutterError?) -> Void
  ) {
    // Create FLTCam only if granted camera access (and audio access if audio is enabled)
    captureSessionQueue.async { [weak self] in
      self?.permissionManager.requestCameraPermission { error in
        guard let strongSelf = self else { return }

        if let error = error {
          completion(nil, error)
          return
        }

        // Request audio permission on `create` call with `enableAudio` argument instead of the
        // `prepareForVideoRecording` call. This is because `prepareForVideoRecording` call is
        // optional, and used as a workaround to fix a missing frame issue on iOS.
        if settings.enableAudio {
          // Setup audio capture session only if granted audio access.
          strongSelf.permissionManager.requestAudioPermission { [weak self] audioError in
            // cannot use the outter `strongSelf`
            guard let strongSelf = self else { return }

            if let audioError = audioError {
              completion(nil, audioError)
              return
            }

            strongSelf.createCameraOnSessionQueue(
              withName: cameraName,
              settings: settings,
              stabilizationMode: stabilizationMode,
              completion: completion)
          }
        } else {
          strongSelf.createCameraOnSessionQueue(
            withName: cameraName,
            settings: settings,
            stabilizationMode: stabilizationMode,
            completion: completion)
        }
      }
    }
  }

  func createCameraOnSessionQueue(
    withName: String,
    settings: FCPPlatformMediaSettings,
    stabilizationMode: FCPPlatformCameraStabilizationMode,
    completion: @escaping (NSNumber?, FlutterError?) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.sessionQueueCreateCamera(
        name: withName,
        settings: settings,
        stabilizationMode: stabilizationMode,
        completion: completion)
    }
  }

  private func convertToAVStabilizationMode(_ mode: FCPPlatformCameraStabilizationMode)
    -> AVCaptureVideoStabilizationMode
  {
    switch mode {
    case .off:
      return .off
    case .standard:
      return .standard
    case .cinematic:
      return .cinematic
    case .cinematicExtended:
      return .cinematicExtended
    case .previewOptimized:
      if #available(iOS 17.0, *) {
        return .previewOptimized
      } else {
        return .standard
      }
    case .auto:
      return .auto
    default:
      return .off
    }
  }

  // This must be called on captureSessionQueue. It is extracted from createCameraOnSessionQueue
  // to make it easier to reason about strong/weak self pointers.
  private func sessionQueueCreateCamera(
    name: String,
    settings: FCPPlatformMediaSettings,
    stabilizationMode: FCPPlatformCameraStabilizationMode,
    completion: @escaping (NSNumber?, FlutterError?) -> Void
  ) {
    let mediaSettingsAVWrapper = FLTCamMediaSettingsAVWrapper()

    let camConfiguration = FLTCamConfiguration(
      mediaSettings: settings,
      mediaSettingsWrapper: mediaSettingsAVWrapper,
      captureDeviceFactory: captureDeviceFactory,
      audioCaptureDeviceFactory: {
        FLTDefaultCaptureDevice(device: AVCaptureDevice.default(for: .audio)!)
      },
      captureSessionFactory: captureSessionFactory,
      captureSessionQueue: captureSessionQueue,
      captureDeviceInputFactory: captureDeviceInputFactory,
      initialCameraName: name,
      videoStabilizationMode: convertToAVStabilizationMode(stabilizationMode)
    )

    var error: NSError?
    let newCamera = DefaultCamera(configuration: camConfiguration, error: &error)

    if let error = error {
      completion(nil, CameraPlugin.flutterErrorFromNSError(error))
    } else {
      camera?.close()
      camera = newCamera

      FLTEnsureToRunOnMainQueue { [weak self] in
        guard let strongSelf = self else { return }
        completion(NSNumber(value: strongSelf.registry.register(newCamera)), nil)
      }
    }
  }

  public func initializeCamera(
    _ cameraId: Int,
    withImageFormat imageFormat: FCPPlatformImageFormatGroup,
    completion: @escaping (FlutterError?) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.sessionQueueInitializeCamera(
        cameraId,
        withImageFormat: imageFormat,
        completion: completion)
    }
  }

  // This must be called on captureSessionQueue. It is extracted from initializeCamera to make it
  // easier to reason about strong/weak self pointers.
  private func sessionQueueInitializeCamera(
    _ cameraId: Int,
    withImageFormat imageFormat: FCPPlatformImageFormatGroup,
    completion: @escaping (FlutterError?) -> Void
  ) {
    guard let camera = camera else { return }

    camera.videoFormat = FCPGetPixelFormatForPigeonFormat(imageFormat)

    camera.onFrameAvailable = { [weak self] in
      guard let camera = self?.camera else { return }
      if !camera.isPreviewPaused {
        FLTEnsureToRunOnMainQueue {
          self?.registry.textureFrameAvailable(Int64(cameraId))
        }
      }
    }

    camera.dartAPI = FCPCameraEventApi(
      binaryMessenger: messenger,
      messageChannelSuffix: "\(cameraId)"
    )

    camera.reportInitializationState()
    sendDeviceOrientation(UIDevice.current.orientation)
    camera.start()
    completion(nil)
  }

  public func startImageStream(completion: @escaping (FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      guard let strongSelf = self else {
        completion(nil)
        return
      }
      strongSelf.camera?.startImageStream(with: strongSelf.messenger, completion: completion)
    }
  }

  public func stopImageStream(completion: @escaping (FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.stopImageStream()
      completion(nil)
    }
  }

  public func receivedImageStreamData(completion: @escaping (FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.receivedImageStreamData()
      completion(nil)
    }
  }

  public func disposeCamera(_ cameraId: Int, completion: @escaping (FlutterError?) -> Void) {
    registry.unregisterTexture(Int64(cameraId))
    captureSessionQueue.async { [weak self] in
      if let strongSelf = self {
        strongSelf.camera?.close()
        strongSelf.camera = nil
      }
      completion(nil)
    }
  }

  public func lockCapture(
    _ orientation: FCPPlatformDeviceOrientation,
    completion: @escaping (FlutterError?) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.lockCaptureOrientation(orientation)
      completion(nil)
    }
  }

  public func unlockCaptureOrientation(completion: @escaping (FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.unlockCaptureOrientation()
      completion(nil)
    }
  }

  public func takePicture(completion: @escaping (String?, FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.captureToFile(completion: completion)
    }
  }

  public func prepareForVideoRecording(completion: @escaping (FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setUpCaptureSessionForAudioIfNeeded()
      completion(nil)
    }
  }

  public func startVideoRecording(
    withStreaming enableStream: Bool,
    completion: @escaping (FlutterError?) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      guard let strongSelf = self else { return }
      strongSelf.camera?.startVideoRecording(
        completion: completion,
        messengerForStreaming: enableStream ? strongSelf.messenger : nil)
    }
  }

  public func stopVideoRecording(completion: @escaping (String?, FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.stopVideoRecording(completion: completion)
    }
  }

  public func pauseVideoRecording(completion: @escaping (FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.pauseVideoRecording()
      completion(nil)
    }
  }

  public func resumeVideoRecording(completion: @escaping (FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.resumeVideoRecording()
      completion(nil)
    }
  }

  public func setFlashMode(
    _ mode: FCPPlatformFlashMode,
    completion: @escaping (FlutterError?) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setFlashMode(mode, withCompletion: completion)
    }
  }

  public func setExposureMode(
    _ mode: FCPPlatformExposureMode,
    completion: @escaping (FlutterError?) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setExposureMode(mode)
      completion(nil)
    }
  }

  public func setExposurePoint(
    _ point: FCPPlatformPoint?,
    completion: @escaping (FlutterError?) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setExposurePoint(point, withCompletion: completion)
    }
  }

  public func getMinimumExposureOffset(_ completion: @escaping (NSNumber?, FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      if let minOffset = self?.camera?.minimumExposureOffset {
        completion(NSNumber(value: minOffset), nil)
      } else {
        completion(nil, nil)
      }
    }
  }

  public func getMaximumExposureOffset(_ completion: @escaping (NSNumber?, FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      if let maxOffset = self?.camera?.maximumExposureOffset {
        completion(NSNumber(value: maxOffset), nil)
      } else {
        completion(nil, nil)
      }
    }
  }

  public func setExposureOffset(_ offset: Double, completion: @escaping (FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setExposureOffset(offset)
      completion(nil)
    }
  }

  public func setFocusMode(
    _ mode: FCPPlatformFocusMode,
    completion: @escaping (FlutterError?) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setFocusMode(mode)
      completion(nil)
    }
  }

  public func setFocus(_ point: FCPPlatformPoint?, completion: @escaping (FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setFocusPoint(point, completion: completion)
    }
  }

  public func getMinimumZoomLevel(_ completion: @escaping (NSNumber?, FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      if let minZoom = self?.camera?.minimumAvailableZoomFactor {
        completion(NSNumber(value: minZoom), nil)
      } else {
        completion(nil, nil)
      }
    }
  }

  public func getMaximumZoomLevel(_ completion: @escaping (NSNumber?, FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      if let maxZoom = self?.camera?.maximumAvailableZoomFactor {
        completion(NSNumber(value: maxZoom), nil)
      } else {
        completion(nil, nil)
      }
    }
  }

  public func setZoomLevel(_ zoom: Double, completion: @escaping (FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setZoomLevel(zoom, withCompletion: completion)
    }
  }

  public func pausePreview(completion: @escaping (FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.pausePreview()
      completion(nil)
    }
  }

  public func resumePreview(completion: @escaping (FlutterError?) -> Void) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.resumePreview()
      completion(nil)
    }
  }

  public func updateDescriptionWhileRecordingCameraName(
    _ cameraName: String,
    completion: @escaping (FlutterError?) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setDescriptionWhileRecording(cameraName, withCompletion: completion)
    }
  }

  public func setImageFileFormat(
    _ format: FCPPlatformImageFileFormat,
    completion: @escaping (FlutterError?) -> Void
  ) {
    captureSessionQueue.async { [weak self] in
      self?.camera?.setImageFileFormat(format)
      completion(nil)
    }
  }
}
