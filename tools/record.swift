// Records a USB-connected iPhone's screen (the same capture path QuickTime uses) and writes
// every frame as a PNG, so animations can be inspected frame by frame.
//
//   swift tools/record.swift <seconds> <output-dir> [scale]
//
// Run it in the background, then drive the phone with tools/probe.sh.
import AVFoundation
import CoreImage
import CoreMediaIO
import Foundation

var allow: UInt32 = 1
var address = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
)
CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)

let arguments = CommandLine.arguments
let seconds = arguments.count > 1 ? Double(arguments[1]) ?? 5 : 5
let output = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "/tmp/lune-record")
let scale = arguments.count > 3 ? Double(arguments[3]) ?? 0.5 : 0.5
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func findDevice() -> AVCaptureDevice? {
    let session = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.external], mediaType: .muxed, position: .unspecified
    )
    return session.devices.first { $0.modelID.contains("iOS") || $0.localizedName.contains("iPhone") }
        ?? session.devices.first
}

var device: AVCaptureDevice?
for _ in 0..<40 {
    device = findDevice()
    if device != nil { break }
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
}
guard let device else {
    FileHandle.standardError.write("no screen capture device found\n".data(using: .utf8)!)
    exit(1)
}

final class Writer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let output: URL
    let scale: Double
    let context = CIContext()
    var start: CMTime?
    var count = 0
    let queue = DispatchQueue(label: "write", attributes: .concurrent)
    let group = DispatchGroup()

    init(output: URL, scale: Double) {
        self.output = output
        self.scale = scale
    }

    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if start == nil { start = time }
        let ms = Int((CMTimeGetSeconds(time) - CMTimeGetSeconds(start!)) * 1000)
        let image = CIImage(cvPixelBuffer: buffer).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(image, from: image.extent) else { return }
        let url = output.appendingPathComponent(String(format: "%06d.png", ms))
        count += 1
        group.enter()
        queue.async {
            if let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, cg, nil)
                CGImageDestinationFinalize(destination)
            }
            self.group.leave()
        }
    }
}

let session = AVCaptureSession()
let input = try AVCaptureDeviceInput(device: device)
session.addInput(input)
let videoOutput = AVCaptureVideoDataOutput()
videoOutput.alwaysDiscardsLateVideoFrames = false
let writer = Writer(output: output, scale: scale)
videoOutput.setSampleBufferDelegate(writer, queue: DispatchQueue(label: "frames"))
session.addOutput(videoOutput)
session.startRunning()
print("recording \(device.localizedName) for \(seconds)s")
RunLoop.current.run(until: Date().addingTimeInterval(seconds))
session.stopRunning()
writer.group.wait()
print("\(writer.count) frames -> \(output.path)")
