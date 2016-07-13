//
//  AudioQueueSample.swift
//  AudioQueueDemo
//
//  Created by zhongzhendong on 7/12/16.
//  Copyright © 2016 zerdzhong. All rights reserved.
//

import Foundation
import AudioToolbox

let kSampleRate: Float64 = 44100.0
let kBufferByteSize: UInt32 = 2048

class AudioQueueSample: NSObject {
    
    var audioQueue: AudioQueueRef = nil
    
    var noteFrequency: Double = 0
    var noteAmplitude: Double = 0
    var noteDecay: Double = 0
    var noteFrame: Double = 0
    
    override init() {
        super.init()
        
        startOutputAudioQueue()
    }
    
    func startOutputAudioQueue() -> Void {
        var streamFormat = AudioStreamBasicDescription()
        streamFormat.mSampleRate = 44100.0
        streamFormat.mFormatID = kAudioFormatLinearPCM;
        streamFormat.mFormatFlags = kLinearPCMFormatFlagIsFloat | kAudioFormatFlagsNativeEndian;
        streamFormat.mBitsPerChannel = 32;
        streamFormat.mChannelsPerFrame = 1;
        streamFormat.mBytesPerPacket = 4 * streamFormat.mChannelsPerFrame;
        streamFormat.mBytesPerFrame = 4 * streamFormat.mChannelsPerFrame;
        streamFormat.mFramesPerPacket = 1;
        streamFormat.mReserved = 0;
        
        var status: OSStatus = 0
        let selfPointer = unsafeBitCast(self, UnsafeMutablePointer<Void>.self)
        status = AudioQueueNewOutput(&streamFormat, OutputCallback, selfPointer, CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &audioQueue)
        
        assert(noErr == status)
        
        var buffer: AudioQueueBufferRef = nil
        for _ in 0..<3 {
            status = AudioQueueAllocateBuffer(audioQueue, kBufferByteSize, &buffer)
            assert(noErr == status)
            
            generateTone(buffer)
            
            status = AudioQueueEnqueueBuffer(audioQueue, buffer, 0, nil)
            
            assert(noErr == status)
        }
        
        status = AudioQueueStart(audioQueue, nil)
        assert(noErr == status)
    }
    
    func playRandomNote() -> Void {
        
        let tag: Double = 2616
        
        noteFrame = 0;
        noteFrequency = tag / 10.0;
        noteAmplitude = 1.0;
        noteDecay = 1 / 44100.0;
    }
    
    private func generateTone(buffer: AudioQueueBufferRef) {
        if noteAmplitude == 0 {
            memset(buffer.memory.mAudioData, 0, Int(buffer.memory.mAudioDataBytesCapacity))
        } else {
            let count: Int = Int(buffer.memory.mAudioDataBytesCapacity) / sizeof(Float32)
            var x: Double = 0
            var y: Double = 0
            let audioData = UnsafeMutablePointer<Float32>(buffer.memory.mAudioData)
            
            for frame in 0..<count {
                x = noteFrame * noteFrequency / kSampleRate
                y = sin (x * 2.0 * M_PI) * noteAmplitude
                audioData[frame] = Float32(y)
                
                noteAmplitude -= noteDecay
                if noteAmplitude < 0.0 {
                    noteAmplitude = 0
                }
                
                noteFrame += 1
            }
        }
        
        buffer.memory.mAudioDataByteSize = buffer.memory.mAudioDataBytesCapacity
    }
    
    private func processOutputBuffer(buffer: AudioQueueBufferRef, withAudioQueue: AudioQueueRef) -> Void {
        var status: OSStatus = 0
        
        generateTone(buffer)
        
        status = AudioQueueEnqueueBuffer(withAudioQueue, buffer, 0, nil)
        
        assert(noErr == status)
    }
}

func OutputCallback(clientData: UnsafeMutablePointer<Void>, AQ: AudioQueueRef, buffer: AudioQueueBufferRef) {
    let this = Unmanaged<AudioQueueSample>.fromOpaque(COpaquePointer(clientData)).takeUnretainedValue()
    
    this.processOutputBuffer(buffer, withAudioQueue: AQ)
}
