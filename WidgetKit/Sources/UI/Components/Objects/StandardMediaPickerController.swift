//
// StandardMediaPickerController.swift
//
// WidgetKit, Copyright (c) 2018 M8 Labs (http://m8labs.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import UIKit
import Photos
import Alamofire
import MobileCoreServices

public class PHAssetView: UIImageView {
    
    private static var imageCache = NSCache<NSString, UIImage>()
    
    @objc public var largestSide: CGFloat = 0
    
    @IBOutlet var progressView: UIProgressView?
    
    private var contentPixelWidth: Int {
        if let image = self.image {
            return Int(image.size.width * image.scale)
        } else if let asset = self.asset {
            return asset.pixelWidth
        }
        return 0
    }
    
    private var contentPixelHeight: Int {
        if let image = self.image {
            return Int(image.size.height * image.scale)
        } else if let asset = self.asset {
            return asset.pixelHeight
        }
        return 0
    }
    
    private var previewSize: CGSize {
        let w = contentPixelWidth
        let h = contentPixelHeight
        if largestSide > 0, w > 0, h > 0 {
            let maxS = max(w, h)
            let minS = min(w, h)
            let f = CGFloat(minS) / CGFloat(maxS) // f <= 1.0
            if w > h {
                return CGSize(width: largestSide, height: largestSide * f) // horizontal image
            } else {
                return CGSize(width: largestSide * f, height: largestSide) // vertical image
            }
        }
        return CGSize(width: self.bounds.size.width * UIScreen.main.scale, height: self.bounds.size.height * UIScreen.main.scale)
    }
    
    @objc public var asset: PHAsset? {
        didSet {
            guard let asset = self.asset else { return }
            if let image = PHAssetView.imageCache.object(forKey: asset.localIdentifier as NSString) {
                self.image = image
            } else {
                StandardMediaPickerController.requestImage(for: asset, targetSize: previewSize, progress: { [weak self] progress in
                    self?.progressView?.progress = progress
                }) { [weak self] image, error in
                    guard asset == self?.asset else { return }
                    self?.image = image
                    if image != nil {
                        PHAssetView.imageCache.setObject(image!, forKey: asset.localIdentifier as NSString)
                    }
                }
            }
        }
    }
    
    override public var intrinsicContentSize: CGSize {
        if image != nil || asset != nil {
            let size = previewSize
            return CGSize(width: size.width / UIScreen.main.scale, height: size.height / UIScreen.main.scale)
        }
        return CGSize.zero
    }
}

public class StandardMediaPickerController: ButtonActionController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @IBOutlet public weak var imageView: UIImageView?
    
    @objc public private(set) var pickerResult: MediaPickerResult? {
        didSet {
            if let assetView = imageView as? PHAssetView {
                assetView.asset = pickerResult?.asset
            } else {
                imageView?.image = pickerResult?.currentImage
            }
        }
    }
    
    @objc public var showOptions = true
    
    @objc public var imagesOnly = false
    
    @objc public var cameraOptionTitle = NSLocalizedString("Take With Camera", comment: "")
    
    @objc public var libraryOptionTitle = NSLocalizedString("Choose From Library", comment: "")
    
    @objc public var cancelOptionTitle = NSLocalizedString("Cancel", comment: "")
    
    public func pick(with sourceType: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = sourceType
        if !imagesOnly {
            picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary) ?? []
        }
        viewController.present(picker, animated: true)
    }
    
    public override func performAction(with object: Any? = nil) {
        let perform = {
            if self.showOptions && UIImagePickerController.isSourceTypeAvailable(.camera) {
                self.viewController.showActionSheet(message: nil, options: [
                    (self.cameraOptionTitle,  { [weak self] in self?.pick(with: .camera) }),
                    (self.libraryOptionTitle, { [weak self] in self?.pick(with: .photoLibrary) }),
                    (self.cancelOptionTitle,  nil)])
            } else {
                self.pick(with: .photoLibrary)
            }
        }
        let showError = {
            self.viewController.showAlert(message: NSLocalizedString("Photo access was not granted by the user.", comment: ""))
        }
        if PHPhotoLibrary.authorizationStatus() == .authorized {
            perform()
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized else { return showError() }
                perform()
            }
        }
    }
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String: Any]) {
        pickerResult = MediaPickerResult(info: info)
        picker.dismiss(animated: true)
    }
    
    public func resetSelection() {
        pickerResult = nil
    }
}

public extension StandardMediaPickerController {
    
    static func requestImage(for asset: PHAsset, targetSize: CGSize, progress: @escaping (Float)->Void, completion: @escaping (UIImage?, Error?)->Void) {
        let options = PHImageRequestOptions()
        options.version = .current
        options.isNetworkAccessAllowed = true
        options.progressHandler = { percent, error, _, _ in
            progress(Float(percent))
        }
        PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
            completion(image, info?[PHImageErrorKey] as? Error)
        }
    }
    
    static func requestImageData(for asset: PHAsset, targetSize: CGSize?, progress: @escaping (Float)->Void, completion: @escaping (Data?, Error?)->Void) {
        let options = PHImageRequestOptions()
        options.version = .current
        options.isNetworkAccessAllowed = true
        options.progressHandler = { percent, error, _, _ in
            progress(Float(percent))
        }
        if targetSize != nil {
            PHImageManager.default().requestImage(for: asset, targetSize: targetSize!, contentMode: .aspectFill, options: options) { image, info in
                guard let image = image else {
                    return completion(nil, info?[PHImageErrorKey] as? Error)
                }
                asyncGlobal {
                    let data = UIImageJPEGRepresentation(image, UIImage.defaultJPEGCompression)
                    asyncMain {
                        completion(data, nil)
                    }
                }
            }
        } else {
            PHImageManager.default().requestImageData(for: asset, options: options) { data, dataUti, orientation, info in
                guard let data = data else {
                    return completion(nil, info?[PHImageErrorKey] as? Error)
                }
                completion(data, nil)
            }
        }
    }
    
    static func requestImageFile(for asset: PHAsset, targetSize: CGSize?, progress: @escaping (Float)->Void, completion: @escaping (URL?, Error?)->Void) {
        let outputPath = asset.tmpImagePath(with: targetSize != nil ? "\(targetSize!.width)x\(targetSize!.height)" : "original")
        if FileManager.default.fileExists(atPath: outputPath) {
            return completion(URL(fileURLWithPath: outputPath), nil)
        }
        StandardMediaPickerController.requestImageData(for: asset, targetSize: targetSize, progress: progress) { data, error in
            guard let data = data else {
                return completion(nil, error)
            }
            asyncGlobal {
                do {
                    let url = URL(fileURLWithPath: outputPath)
                    try data.write(to: url, options: .atomic)
                    asyncMain {
                        completion(url, nil)
                    }
                } catch {
                    asyncMain {
                        completion(nil, error)
                    }
                }
            }
        }
    }
    
    static func requestVideoFile(for asset: PHAsset, quality: VideoQuality, progress: @escaping (Float)->Void, completion: @escaping (URL?, Error?)->Void) {
        let outputPath = asset.tmpVideoPath
        if FileManager.default.fileExists(atPath: outputPath) {
            return completion(URL(fileURLWithPath: outputPath), nil)
        }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.progressHandler = { percent, error, _, _ in
            progress(Float(percent))
        }
        PHImageManager.default().requestExportSession(forVideo: asset, options: options, exportPreset: quality.exportPreset) { exportSession, info in
            guard let session = exportSession else {
                return completion(nil, info?[PHImageErrorKey] as? Error)
            }
            session.outputURL = URL(fileURLWithPath: outputPath)
            session.outputFileType = .mov
            session.shouldOptimizeForNetworkUse = true
            session.exportAsynchronously {
                completion(session.outputURL, session.error)
            }
            asyncGlobal {
                while session.status == .waiting || session.status == .exporting {
                    asyncMain {
                        progress(session.progress)
                    }
                    sleep(500)
                }
            }
        }
    }
    
    static func requestMediaFile(for asset: PHAsset, imageSize: CGSize? = nil, videoQuality: VideoQuality = .medium, progress: @escaping (Float)->Void, completion: @escaping (URL?, Error?)->Void) {
        switch asset.mediaType {
        case .image:
            StandardMediaPickerController.requestImageFile(for: asset, targetSize: imageSize, progress: progress, completion: completion)
        case .video:
            StandardMediaPickerController.requestVideoFile(for: asset, quality: videoQuality, progress: progress, completion: completion)
        default:
            completion(nil, nil)
        }
    }
}

public class MediaPickerResult: NSObject {
    
    var info: [String: Any]
    
    public init(info: [String: Any]) {
        self.info = info
    }
    
    @objc public var mediaType: String { return info[UIImagePickerControllerMediaType] as! String }
    
    @objc public var editedImage: UIImage? { return info[UIImagePickerControllerEditedImage] as? UIImage }
    
    @objc public var originalImage: UIImage? { return info[UIImagePickerControllerOriginalImage] as? UIImage }
    
    @objc public var currentImage: UIImage? { return editedImage ?? originalImage }
    
    @objc public var asset: PHAsset? {
        if #available(iOS 11.0, *) {
            return info[UIImagePickerControllerPHAsset] as? PHAsset
        } else if let assetUrl = info[UIImagePickerControllerReferenceURL] as? URL {
            let result = PHAsset.fetchAssets(withALAssetURLs: [assetUrl], options: nil)
            return result.firstObject
        }
        return nil
    }
    
    @available(iOS 11.0, *)
    @objc public var imageUrl: URL? { return info[UIImagePickerControllerImageURL] as? URL }
    
    @objc public var mediaUrl: URL? { return info[UIImagePickerControllerMediaURL] as? URL }
    
    @objc public var isMovie: Bool { return mediaType == String(kUTTypeMovie) }
}

public enum VideoQuality {
    
    case unspecified, low, medium, max
    
    var exportPreset: String {
        switch self {
        case .low:
            return AVAssetExportPresetLowQuality
        case .max:
            return AVAssetExportPresetHighestQuality
        default:
            return AVAssetExportPresetMediumQuality
        }
    }
}

extension UIImage {
    
    public static let defaultJPEGCompression: CGFloat = 0.9
}

extension PHAsset {
    
    var tmpVideoPath: String {
        return NSTemporaryDirectory() + "tmp\(localIdentifier).mov"
    }
    
    func tmpImagePath(with tag: String) -> String {
        return NSTemporaryDirectory() + "tmp\(localIdentifier)-\(tag).jpeg"
    }
}
