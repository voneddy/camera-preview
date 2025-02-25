import Foundation
import Capacitor
import AVFoundation
/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitor.ionicframework.com/docs/plugins/ios
 */
@objc(CameraPreview)
public class CameraPreview: CAPPlugin {
    
    var previewView: UIView?
    var cameraPosition = String()
    let cameraController = CameraController()
    var x: CGFloat?
    var y: CGFloat?
    var width: CGFloat?
    var height: CGFloat?
    var paddingBottom: CGFloat?
    var rotateWhenOrientationChanged: Bool?
    var toBack: Bool?
    var storeToFile: Bool?
    var enableZoom: Bool?
    var highResolutionOutput: Bool = false
    var disableAudio: Bool = false
    
    @objc func rotated() {
        let height = self.paddingBottom != nil ? self.height! - self.paddingBottom!: self.height!;
        
        if UIApplication.shared.statusBarOrientation.isLandscape {
            self.previewView?.frame = CGRect(x: self.y!, y: self.x!, width: max(height, self.width!), height: min(height, self.width!))
            
            guard let frame = self.previewView?.frame else {
                return;
            }
            
            self.cameraController.previewLayer?.frame = frame
        }
        
        if UIApplication.shared.statusBarOrientation.isPortrait {
            if (self.previewView != nil && self.x != nil && self.y != nil && self.width != nil && self.height != nil) {
                self.previewView?.frame = CGRect(x: self.x!, y: self.y!, width: min(height, self.width!), height: max(height, self.width!))
            }
            
            guard let frame = self.previewView?.frame else {
                return;
            }
            
            self.cameraController.previewLayer?.frame = frame
        }
        
        cameraController.updateVideoOrientation()
    }
    
    @objc func start(_ call: CAPPluginCall) {
        self.cameraPosition = call.getString("position") ?? "rear"
        self.highResolutionOutput = call.getBool("enableHighResolution") ?? false
        self.cameraController.highResolutionOutput = self.highResolutionOutput
        
        if call.getInt("width") != nil {
            self.width = CGFloat(call.getInt("width")!)
        } else {
            self.width = UIScreen.main.bounds.size.width
        }
        if call.getInt("height") != nil {
            self.height = CGFloat(call.getInt("height")!)
        } else {
            self.height = UIScreen.main.bounds.size.height
        }
        self.x = call.getInt("x") != nil ? CGFloat(call.getInt("x")!)/UIScreen.main.scale: 0
        self.y = call.getInt("y") != nil ? CGFloat(call.getInt("y")!)/UIScreen.main.scale: 0
        if call.getInt("paddingBottom") != nil {
            self.paddingBottom = CGFloat(call.getInt("paddingBottom")!)
        }
        
        self.rotateWhenOrientationChanged = call.getBool("rotateWhenOrientationChanged") ?? true
        self.toBack = call.getBool("toBack") ?? false
        self.storeToFile = call.getBool("storeToFile") ?? false
        self.enableZoom = call.getBool("enableZoom") ?? false
        self.disableAudio = call.getBool("disableAudio") ?? false
        
        AVCaptureDevice.requestAccess(for: .video, completionHandler: { (granted: Bool) in
            guard granted else {
                call.reject("permission failed")
                return
            }
            
            DispatchQueue.main.async {
                if self.cameraController.captureSession?.isRunning ?? false {
                    call.reject("camera already started")
                } else {
                    self.cameraController.prepare(cameraPosition: self.cameraPosition, disableAudio: self.disableAudio){error in
                        if let error = error {
                            print(error)
                            call.reject(error.localizedDescription)
                            return
                        }
                        
                        
                        let height = self.paddingBottom != nil ? self.height! - self.paddingBottom!: self.height!
                        self.previewView = UIView(frame: CGRect(x: self.x ?? 0, y: self.y ?? 0, width: self.width!, height: height))
                        self.webView?.isOpaque = false
                        self.webView?.backgroundColor = UIColor.clear
                        self.webView?.scrollView.backgroundColor = UIColor.clear
                        
                        guard let previewView = self.previewView else {
                            call.reject("!previewView")
                            return;
                        }
                        
                        self.webView?.superview?.addSubview(previewView)
                        if self.toBack! {
                            self.webView?.superview?.bringSubviewToFront(self.webView!)
                        }
                        try? self.cameraController.displayPreview(on: previewView)
                        
                        let frontView = self.toBack! ? self.webView : previewView
                        self.cameraController.setupGestures(target: frontView ?? previewView, enableZoom: self.enableZoom!)
                        
                        if self.rotateWhenOrientationChanged == true {
                            NotificationCenter.default.addObserver(self, selector: #selector(CameraPreview.rotated), name: UIDevice.orientationDidChangeNotification, object: nil)
                        }
                        
                        call.resolve()
                        
                    }
                }
            }
        })
        
    }
    
    @objc func flip(_ call: CAPPluginCall) {
        do {
            try self.cameraController.switchCameras()
            call.resolve()
        } catch {
            call.reject("failed to flip camera")
        }
    }
    
    @objc func stop(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.cameraController.captureSession?.isRunning ?? false {
                self.cameraController.captureSession?.stopRunning()
                self.previewView?.removeFromSuperview()
                self.webView?.isOpaque = true
                call.resolve()
            } else {
                call.reject("camera already stopped")
            }
        }
    }
    // Get user's cache directory path
    @objc func getTempFilePath() -> URL {
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let identifier = UUID()
        let randomIdentifier = identifier.uuidString.replacingOccurrences(of: "-", with: "")
        let finalIdentifier = String(randomIdentifier.prefix(8))
        let fileName="cpcp_capture_"+finalIdentifier+".jpg"
        let fileUrl=path.appendingPathComponent(fileName)
        return fileUrl
    }
    
    @objc func capture(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            
            let quality: Int? = call.getInt("quality", 85)
            
            self.cameraController.captureImage { (image, error) in
                
                guard let image = image else {
                    print(error ?? "Image capture error")
                    guard let error = error else {
                        call.reject("Image capture error")
                        return
                    }
                    call.reject(error.localizedDescription)
                    return
                }
                let imageData: Data?
                if self.cameraController.currentCameraPosition == .front {
                    let flippedImage = image.withHorizontallyFlippedOrientation()
                    imageData = flippedImage.jpegData(compressionQuality: CGFloat(quality!/100))
                } else {
                    imageData = image.jpegData(compressionQuality: CGFloat(quality!/100))
                }
                
                if self.storeToFile == false {
                    let imageBase64 = imageData?.base64EncodedString()
                    call.resolve(["value": imageBase64!])
                } else {
                    do {
                        let fileUrl=self.getTempFilePath()
                        try imageData?.write(to: fileUrl)
                        call.resolve([
                            "value": fileUrl.absoluteString,
                            "fileUrl": fileUrl.absoluteString
                        ])
                    } catch {
                        call.reject("error writing image to file")
                    }
                }
            }
        }
    }
    
    @objc func captureSample(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let quality: Int? = call.getInt("quality", 85)
            
            self.cameraController.captureSample { image, error in
                guard let image = image else {
                    print("Image capture error: \(String(describing: error))")
                    call.reject("Image capture error: \(String(describing: error))")
                    return
                }
                
                let imageData: Data?
                if self.cameraPosition == "front" {
                    let flippedImage = image.withHorizontallyFlippedOrientation()
                    imageData = flippedImage.jpegData(compressionQuality: CGFloat(quality!/100))
                } else {
                    imageData = image.jpegData(compressionQuality: CGFloat(quality!/100))
                }
                
                if self.storeToFile == false {
                    let imageBase64 = imageData?.base64EncodedString()
                    call.resolve(["value": imageBase64!])
                } else {
                    do {
                        let fileUrl = self.getTempFilePath()
                        try imageData?.write(to: fileUrl)
                        call.resolve(["value": fileUrl.absoluteString])
                    } catch {
                        call.reject("Error writing image to file")
                    }
                }
            }
        }
    }
    
    @objc func getSupportedFlashModes(_ call: CAPPluginCall) {
        do {
            let supportedFlashModes = try self.cameraController.getSupportedFlashModes()
            call.resolve(["result": supportedFlashModes])
        } catch {
            call.reject("failed to get supported flash modes")
        }
    }
    
    @objc func setStabilizationMode(_ call: CAPPluginCall) {
        guard let mode = call.getString("stabilizationMode") else {
            call.reject("failed to set Stabalization mode. required parameter mode is missing")
            return
        }
        
        do {
            var modeAsEnum: AVCaptureVideoStabilizationMode? = nil
            
            switch mode {
            case "off" :
                modeAsEnum = AVCaptureVideoStabilizationMode.off
            case "auto":
                modeAsEnum = AVCaptureVideoStabilizationMode.auto
            case "standard":
                modeAsEnum = AVCaptureVideoStabilizationMode.standard
            case "cinematic":
                modeAsEnum = AVCaptureVideoStabilizationMode.cinematic
            case "cinematicExtended":
                modeAsEnum = AVCaptureVideoStabilizationMode.cinematicExtended
            default: break
            }
            
            if modeAsEnum != nil {
                let success = try self.cameraController.setStabalizationMode(mode: modeAsEnum!)
                // self.cameraController.obs()
                call.resolve(["stabilizationMode": success])
                return
            } else {
                call.reject("stabalizationMode not supported")
                return
            }
            call.resolve(["stabalizationMode": false])
        } catch {
            call.reject("failed to set stabalizationMode")
        }
    }
    
    @objc func getStabilizationMode (_ call: CAPPluginCall) {
        do {
            let mode = try self.cameraController.getStabilizationMode()
            var modeString = "error";
            switch mode {
            case "0" :
                modeString = "off"
            case "-1":
                modeString = "auto"
            case "1":
                modeString = "standard"
            case "2":
                modeString = "cinematic"
            case "3":
                modeString = "cinematicExtended"
            default: break
            }
            call.resolve(["stabalizationMode": modeString])
        } catch {
            call.reject("failed to set stabalizationMode")
        }
    }
    
    @available(iOS 15.0, *)
    @objc func showSystemUserInterface(_ call: CAPPluginCall) {
        do {
            // let enabled =
            try self.cameraController.showSystemUserInterface()
            call.resolve(["done": true])
        } catch {
            call.reject("failed to showSystemUserInterface")
        }
    }
    
    
    @objc func setLowLightBoost(_ call: CAPPluginCall) {
        guard let enable = call.getBool("enable") else {
            call.reject("failed to set low light boost. required parameter enable is missing")
            return
        }
        do {
            let enabled = try self.cameraController.setLowLightBoost(enable: enable)
            call.resolve(["enabled": enabled])
        } catch {
            call.reject("failed to set low light boost")
        }
    }
    
    
    @objc func setFlashMode(_ call: CAPPluginCall) {
        guard let flashMode = call.getString("flashMode") else {
            call.reject("failed to set flash mode. required parameter flashMode is missing")
            return
        }
        do {
            var flashModeAsEnum: AVCaptureDevice.FlashMode?
            switch flashMode {
            case "off" :
                flashModeAsEnum = AVCaptureDevice.FlashMode.off
            case "on":
                flashModeAsEnum = AVCaptureDevice.FlashMode.on
            case "auto":
                flashModeAsEnum = AVCaptureDevice.FlashMode.auto
            default: break
            }
            if flashModeAsEnum != nil {
                try self.cameraController.setFlashMode(flashMode: flashModeAsEnum!)
            } else if flashMode == "torch" {
                try self.cameraController.setTorchMode()
            } else {
                call.reject("Flash Mode not supported")
                return
            }
            call.resolve()
        } catch {
            call.reject("failed to set flash mode")
        }
    }
    
    @objc func startRecordVideo(_ call: CAPPluginCall) {
        
        AVCaptureDevice.requestAccess(for: .video, completionHandler: { (granted: Bool) in
            guard granted else {
                call.reject("permission failed")
                return
            }
            
            DispatchQueue.main.async {
                if !(self.cameraController.captureSession?.isRunning ?? false) {
                    call.reject("camera not already started")
                } else {
                    do {
                        try self.cameraController.captureVideo { (image, error) in
                            
                            guard let image = image else {
                                print(error ?? "Image capture error")
                                guard let error = error else {
                                    call.reject("Image capture error")
                                    return
                                }
                                call.reject(error.localizedDescription)
                                return
                            }
                            
                            // self.videoUrl = image
                            
                            call.resolve(["value": image.absoluteString])
                        }
                    } catch {
                        call.reject(error.localizedDescription)
                    }
                }
            }
        })
    }
    
    
    @objc func stopRecordVideo(_ call: CAPPluginCall) {
        
        self.cameraController.stopRecording { (_) in
            
        }
    }
    
}
