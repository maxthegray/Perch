#!/usr/bin/env swift
// Regenerates Tests/PerchTests/Fixtures/clip.mov, the checked-in source for
// ShelfTransformTests.testExtractAudioWritesM4AWithoutChangingSource.
//
// The fixture is a 1-second, 44.1 kHz mono QuickTime movie whose only track is
// AAC audio. It is committed rather than generated at test time so the test
// never depends on the host having a working AAC encoder.
//
//   swift Scripts/make-audio-fixture.swift Tests/PerchTests/Fixtures/clip.mov

import AVFoundation
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: outputURL)

let sampleRate = 44_100.0
let frameCount = AVAudioFrameCount(sampleRate)
let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
buffer.frameLength = frameCount
let samples = buffer.floatChannelData![0]
for frame in 0..<Int(frameCount) {
    samples[frame] = sin(2 * .pi * 440 * Float(frame) / Float(sampleRate)) * 0.25
}

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: sampleRate,
    AVNumberOfChannelsKey: 1,
    AVEncoderBitRateKey: 64_000
])
input.expectsMediaDataInRealTime = false
guard writer.canAdd(input) else { fatalError("writer rejected the audio input") }
writer.add(input)
guard writer.startWriting() else { fatalError("startWriting: \(writer.error!)") }
writer.startSession(atSourceTime: .zero)

guard let sample = buffer.toCMSampleBuffer() else { fatalError("no sample buffer") }
while !input.isReadyForMoreMediaData { usleep(1000) }
guard input.append(sample) else { fatalError("append: \(writer.error!)") }
input.markAsFinished()

let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError("finishWriting: \(writer.error!)") }

let size = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as! Int
print("wrote \(outputURL.lastPathComponent) (\(size) bytes)")

extension AVAudioPCMBuffer {
    func toCMSampleBuffer() -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: format.streamDescription,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &formatDescription
        ) == noErr else { return nil }

        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil,
            formatDescription: formatDescription, sampleCount: CMItemCount(frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: [CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: CMTimeScale(format.sampleRate)),
                presentationTimeStamp: .zero, decodeTimeStamp: .invalid
            )],
            sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer!, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
            bufferList: mutableAudioBufferList
        ) == noErr else { return nil }
        return sampleBuffer
    }
}
