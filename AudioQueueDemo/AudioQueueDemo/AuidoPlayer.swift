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
    var fileURL: NSURL

    var URLSession: NSURLSession!
    var audioFileStreamID: AudioFileStreamID = nil
    var audioQueue: AudioQueueRef = nil
    var streamDescription: AudioStreamBasicDescription?

    var packets = [NSData]()
    
    var readHead: Int = 0
    var loaded = false
    var stopped = false
    
    init(URL: NSURL) {
        self.fileURL = URL
        super.init()
        
        let selfPointer = unsafeBitCast(self, UnsafeMutablePointer<Void>.self)
        AudioFileStreamOpen(selfPointer, AudioFileStreamPropertyListener, AudioFileStreamPacketsCallback, kAudioFileMP3Type, &self.audioFileStreamID)
        
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        self.URLSession = NSURLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = self.URLSession.dataTaskWithURL(URL)
        task.resume()
    }
    
    deinit {
        if self.audioQueue != nil {
            AudioQueueReset(audioQueue)
        }
        AudioFileStreamClose(audioFileStreamID)
    }
    
    var framePerSecond: Double {
        get {
            if let streamDescription = self.streamDescription where streamDescription.mFramesPerPacket > 0 {
                return Double(streamDescription.mSampleRate) / Double(streamDescription.mFramesPerPacket)
            }
            return 44100.0 / 1152.0
        }
    }
    
    func play() {
        if self.audioQueue == nil {
            return
        }
        
        AudioQueueStart(audioQueue, nil)
    }
    func pause() {
        if self.audioQueue == nil {
        }
        
        AudioQueuePause(audioQueue)
    }
    
    private func parseData(data: NSData) {
        AudioFileStreamParseBytes(self.audioFileStreamID, UInt32(data.length), data.bytes, AudioFileStreamParseFlags(rawValue: 0))
    }
    
    
    private func createAudioQueue(audioStreamDescription: AudioStreamBasicDescription) {
        var audioStreamDescription = audioStreamDescription
        self.streamDescription = audioStreamDescription
        var status: OSStatus = 0
        let selfPointer = unsafeBitCast(self, UnsafeMutablePointer<Void>.self)
        status = AudioQueueNewOutput(&audioStreamDescription, AudioQueueOutputCallback, selfPointer, CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &self.audioQueue)
        assert(noErr == status)
        status = AudioQueueAddPropertyListener(self.audioQueue, kAudioQueueProperty_IsRunning, AudioQueueRunningListener, selfPointer)
        assert(noErr == status)
        AudioQueuePrime(self.audioQueue, 0, nil)
        AudioQueueStart(self.audioQueue, nil)
    }
    private func storePackets(numberOfPackets: UInt32, numberOfBytes: UInt32, data: UnsafePointer<Void>, packetDescription: UnsafeMutablePointer<AudioStreamPacketDescription>) {
        for i in 0 ..< Int(numberOfPackets) {
            let packetStart = packetDescription[i].mStartOffset
            let packetSize = packetDescription[i].mDataByteSize
            let packetData = NSData(bytes: data.advancedBy(Int(packetStart)), length: Int(packetSize))
            self.packets.append(packetData)
        }
        if readHead == 0 && Double(packets.count) > self.framePerSecond * 3 {
            AudioQueueStart(self.audioQueue, nil)
            self.enqueueDataWithPacketsCount(Int(self.framePerSecond * 3))
        }
    }
    private func enqueueDataWithPacketsCount(packetCount: Int) {
        if self.audioQueue == nil {
            return
        }
        var packetCount = packetCount
        if readHead + packetCount > packets.count {
            packetCount = packets.count - readHead
        }
        let totalSize = packets[readHead ..< readHead + packetCount].reduce(0, combine: { $0 + $1.length })
        var status: OSStatus = 0
        var buffer: AudioQueueBufferRef = nil
        status = AudioQueueAllocateBuffer(audioQueue, UInt32(totalSize), &buffer)
        assert(noErr == status)
        buffer.memory.mAudioDataByteSize = UInt32(totalSize)
        let selfPointer = unsafeBitCast(self, UnsafeMutablePointer<Void>.self)
        buffer.memory.mUserData = selfPointer
        var copiedSize = 0
        var packetDescs = [AudioStreamPacketDescription]()
        for i in 0 ..< packetCount {
            let readIndex = readHead + i
            let packetData = packets[readIndex]
            memcpy(buffer.memory.mAudioData.advancedBy(copiedSize), packetData.bytes, packetData.length)
            let description = AudioStreamPacketDescription(mStartOffset: Int64(copiedSize), mVariableFramesInPacket: 0, mDataByteSize: UInt32(packetData.length))
            packetDescs.append(description)
            copiedSize += packetData.length
        }
        status = AudioQueueEnqueueBuffer(audioQueue, buffer, UInt32(packetCount), packetDescs);
        readHead += packetCount
    }
    
}

extension AudioPlayer: NSURLSessionDelegate {
    func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
        self.parseData(data)
    }
}

func AudioFileStreamPropertyListener(clientData: UnsafeMutablePointer<Void>, audioFileStream: AudioFileStreamID, propertyID: AudioFileStreamPropertyID, ioFlag: UnsafeMutablePointer<AudioFileStreamPropertyFlags>) {
    let this = Unmanaged<AudioPlayer>.fromOpaque(COpaquePointer(clientData)).takeUnretainedValue()
    if propertyID == kAudioFileStreamProperty_DataFormat {
        var status: OSStatus = 0
        var dataSize: UInt32 = 0
        var writable: DarwinBoolean = false
        status = AudioFileStreamGetPropertyInfo(audioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &writable)
        assert(noErr == status)
        var audioStreamDescription: AudioStreamBasicDescription = AudioStreamBasicDescription()
        status = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &audioStreamDescription)
        assert(noErr == status)
        dispatch_async(dispatch_get_main_queue()) {
            this.createAudioQueue(audioStreamDescription)
        }
    }
}

func AudioFileStreamPacketsCallback(clientData: UnsafeMutablePointer<Void>, numberBytes: UInt32, numberPackets: UInt32, ioData: UnsafePointer<Void>, packetDescription: UnsafeMutablePointer<AudioStreamPacketDescription>) {
    
    let this = Unmanaged<AudioPlayer>.fromOpaque(COpaquePointer(clientData)).takeUnretainedValue()
    this.storePackets(numberPackets, numberOfBytes: numberBytes, data: ioData, packetDescription: packetDescription)
}

func AudioQueueOutputCallback(clientData: UnsafeMutablePointer<Void>, AQ: AudioQueueRef, buffer: AudioQueueBufferRef) {
    let this = Unmanaged<AudioPlayer>.fromOpaque(COpaquePointer(clientData)).takeUnretainedValue()
    AudioQueueFreeBuffer(AQ, buffer)
    this.enqueueDataWithPacketsCount(Int(this.framePerSecond * 5))
}

func AudioQueueRunningListener(clientData: UnsafeMutablePointer<Void>, AQ: AudioQueueRef, propertyID: AudioQueuePropertyID) {
    let this = Unmanaged<AudioPlayer>.fromOpaque(COpaquePointer(clientData)).takeUnretainedValue()
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