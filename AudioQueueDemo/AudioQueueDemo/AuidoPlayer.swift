//
//  AuidoPlayer.swift
//  AudioQueueDemo
//
//  Created by zhongzhendong on 7/10/16.
//  Copyright © 2016 zerdzhong. All rights reserved.
//

import Foundation
import AudioToolbox

class AudioPlayer: NSObject {
    var fileURL: URL

    var URLSession: Foundation.URLSession!
    var audioFileStreamID: AudioFileStreamID? = nil
    var audioQueue: AudioQueueRef? = nil
    var streamDescription: AudioStreamBasicDescription?

    var packets = [Data]()
    
    var readHead: Int = 0
    var loaded = false
    var stopped = false
    
    init(URL: Foundation.URL) {
        self.fileURL = URL
        super.init()
        
        let selfPointer = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        AudioFileStreamOpen(selfPointer, AudioFileStreamPropertyListener, AudioFileStreamPacketsCallback, kAudioFileMP3Type, &self.audioFileStreamID)
        
        let configuration = URLSessionConfiguration.default
        self.URLSession = Foundation.URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = self.URLSession.dataTask(with: URL)
        task.resume()
    }
    
    deinit {
        if self.audioQueue != nil {
            AudioQueueReset(audioQueue!)
        }
        AudioFileStreamClose(audioFileStreamID!)
    }
    
    var framePerSecond: Double {
        get {
            if let streamDescription = self.streamDescription, streamDescription.mFramesPerPacket > 0 {
                return Double(streamDescription.mSampleRate) / Double(streamDescription.mFramesPerPacket)
            }
            return 44100.0 / 1152.0
        }
    }
    
    func play() {
        if self.audioQueue == nil {
            return
        }
        
        AudioQueueStart(audioQueue!, nil)
    }
    func pause() {
        if self.audioQueue == nil {
        }
        
        AudioQueuePause(audioQueue!)
    }
    
    fileprivate func parseData(_ data: Data) {
        AudioFileStreamParseBytes(self.audioFileStreamID!, UInt32(data.count), (data as NSData).bytes, AudioFileStreamParseFlags(rawValue: 0))
    }
    
    
    fileprivate func createAudioQueue(_ audioStreamDescription: AudioStreamBasicDescription) {
        var audioStreamDescription = audioStreamDescription
        self.streamDescription = audioStreamDescription
        var status: OSStatus = 0
        let selfPointer = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        status = AudioQueueNewOutput(&audioStreamDescription, AudioQueueOutputCallback as! AudioQueueOutputCallback, selfPointer, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue, 0, &self.audioQueue)
        assert(noErr == status)
        status = AudioQueueAddPropertyListener(self.audioQueue!, kAudioQueueProperty_IsRunning, AudioQueueRunningListener as! AudioQueuePropertyListenerProc, selfPointer)
        assert(noErr == status)
        AudioQueuePrime(self.audioQueue!, 0, nil)
        AudioQueueStart(self.audioQueue!, nil)
    }
    fileprivate func storePackets(_ numberOfPackets: UInt32, numberOfBytes: UInt32, data: UnsafeRawPointer, packetDescription: UnsafeMutablePointer<AudioStreamPacketDescription>) {
        for i in 0 ..< Int(numberOfPackets) {
            let packetStart = packetDescription[i].mStartOffset
            let packetSize = packetDescription[i].mDataByteSize
            let packetData = Data(bytes: data.advanced(by: Int(packetStart)), count: Int(packetSize))
            self.packets.append(packetData)
        }
        if readHead == 0 && Double(packets.count) > self.framePerSecond * 3 {
            AudioQueueStart(self.audioQueue!, nil)
            self.enqueueDataWithPacketsCount(Int(self.framePerSecond * 3))
        }
    }
    fileprivate func enqueueDataWithPacketsCount(_ packetCount: Int) {
        if self.audioQueue == nil {
            return
        }
        var packetCount = packetCount
        if readHead + packetCount > packets.count {
            packetCount = packets.count - readHead
        }
        let totalSize = packets[readHead ..< readHead + packetCount].reduce(0, { $0 + $1.count })
        var status: OSStatus = 0
        var buffer: AudioQueueBufferRef? = nil
        status = AudioQueueAllocateBuffer(audioQueue!, UInt32(totalSize), &buffer)
        assert(noErr == status)
        buffer?.pointee.mAudioDataByteSize = UInt32(totalSize)
        let selfPointer = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        buffer?.pointee.mUserData = selfPointer
        var copiedSize = 0
        var packetDescs = [AudioStreamPacketDescription]()
        for i in 0 ..< packetCount {
            let readIndex = readHead + i
            let packetData = packets[readIndex]
            memcpy(buffer?.pointee.mAudioData.advanced(by: copiedSize), (packetData as NSData).bytes, packetData.count)
            let description = AudioStreamPacketDescription(mStartOffset: Int64(copiedSize), mVariableFramesInPacket: 0, mDataByteSize: UInt32(packetData.count))
            packetDescs.append(description)
            copiedSize += packetData.count
        }
        status = AudioQueueEnqueueBuffer(audioQueue!, buffer!, UInt32(packetCount), packetDescs);
        readHead += packetCount
    }
    
}

extension AudioPlayer: URLSessionDelegate {
    func URLSession(_ session: Foundation.URLSession, dataTask: URLSessionDataTask, didReceiveData data: Data) {
        self.parseData(data)
    }
}

func AudioFileStreamPropertyListener(_ clientData: UnsafeMutableRawPointer, audioFileStream: AudioFileStreamID, propertyID: AudioFileStreamPropertyID, ioFlag: UnsafeMutablePointer<AudioFileStreamPropertyFlags>) {
    let this = Unmanaged<AudioPlayer>.fromOpaque(clientData).takeUnretainedValue()
    if propertyID == kAudioFileStreamProperty_DataFormat {
        var status: OSStatus = 0
        var dataSize: UInt32 = 0
        var writable: DarwinBoolean = false
        status = AudioFileStreamGetPropertyInfo(audioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &writable)
        assert(noErr == status)
        var audioStreamDescription: AudioStreamBasicDescription = AudioStreamBasicDescription()
        status = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &audioStreamDescription)
        assert(noErr == status)
        DispatchQueue.main.async {
            this.createAudioQueue(audioStreamDescription)
        }
    }
}

func AudioFileStreamPacketsCallback(_ clientData: UnsafeMutableRawPointer, numberBytes: UInt32, numberPackets: UInt32, ioData: UnsafeRawPointer, packetDescription: UnsafeMutablePointer<AudioStreamPacketDescription>) {
    
    let this = Unmanaged<AudioPlayer>.fromOpaque(clientData).takeUnretainedValue()
    this.storePackets(numberPackets, numberOfBytes: numberBytes, data: ioData, packetDescription: packetDescription)
}

func AudioQueueOutputCallback(_ clientData: UnsafeMutableRawPointer, AQ: AudioQueueRef, buffer: AudioQueueBufferRef) {
    let this = Unmanaged<AudioPlayer>.fromOpaque(clientData).takeUnretainedValue()
    AudioQueueFreeBuffer(AQ, buffer)
    this.enqueueDataWithPacketsCount(Int(this.framePerSecond * 5))
}

func AudioQueueRunningListener(_ clientData: UnsafeMutableRawPointer, AQ: AudioQueueRef, propertyID: AudioQueuePropertyID) {
    let this = Unmanaged<AudioPlayer>.fromOpaque(clientData).takeUnretainedValue()
    var status: OSStatus = 0
    var dataSize: UInt32 = 0
    status = AudioQueueGetPropertySize(AQ, propertyID, &dataSize);
    assert(noErr == status)
    if propertyID == kAudioQueueProperty_IsRunning {
        var running: UInt32 = 0
        status = AudioQueueGetProperty(AQ, propertyID, &running, &dataSize)
        this.stopped = running == 0
    }
}
