//
//  AudioQueueLocalFileSample.swift
//  AudioQueueDemo
//
//  Created by zhongzhendong on 7/12/16.
//  Copyright © 2016 zerdzhong. All rights reserved.
//

import Foundation
import AudioToolbox

let kNumberBuffers: Int = 3

class  AudioPlayerState {
    var dataFormat = AudioStreamBasicDescription()
    var audioQueue: AudioQueueRef? = nil
    var buffers = Array<AudioQueueBufferRef?>(repeating: nil, count: kNumberBuffers)
    var audioFile: AudioFileID? = nil
    var bufferByteSize: UInt32 = 0
    var currentPacket: Int = 0
    var numPacketsToRead: UInt32 = 0
    var packetDescs: UnsafeMutablePointer<AudioStreamPacketDescription>? = nil
    var isRunning: Bool = false
}

class AudioQueueFileSample: NSObject {
    
    var playerState = AudioPlayerState()
    
    func openAudioFile(_ fileURL: URL) -> Void {
        
        var status: OSStatus = 0
        
        status = AudioFileOpenURL(fileURL as CFURL, .readPermission, 0, &playerState.audioFile)
        assert(noErr == status)
        
        var dataFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioFileGetProperty(playerState.audioFile!, kAudioFilePropertyDataFormat, &dataFormatSize, &playerState.dataFormat)
        assert(noErr == status)
        
        let inUserPointer = unsafeBitCast(playerState, to: UnsafeMutableRawPointer.self)
        status = AudioQueueNewOutput(&playerState.dataFormat, HandleOutputCallback, inUserPointer, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue, 0, &playerState.audioQueue)
        assert(noErr == status)
        
        var maxPacketSize: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        
        status = AudioFileGetProperty(playerState.audioFile!, kAudioFilePropertyPacketSizeUpperBound, &propertySize, &maxPacketSize)
        assert(noErr == status)
        
        let (bufferSize, numPacketsToRead) = deriveBufferSize(playerState.dataFormat, maxPacketSize: maxPacketSize, seconds: 0.5)
        
        playerState.bufferByteSize = bufferSize
        playerState.numPacketsToRead = numPacketsToRead
        
        let isFormatVBR: Bool = (playerState.dataFormat.mBytesPerPacket == 0 || playerState.dataFormat.mFramesPerPacket == 0)
        
        if isFormatVBR {
            playerState.packetDescs = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: (Int(playerState.numPacketsToRead) * MemoryLayout<AudioStreamPacketDescription>.size))
        }
        
        var cookieSize = UInt32(MemoryLayout<UInt32>.size)
        
        let couldNotGetProperty = (AudioFileGetProperty(playerState.audioFile!, kAudioFilePropertyMagicCookieData, &cookieSize, UnsafeMutableRawPointer.allocate(bytes: 1, alignedTo: 0)) == 0)
        
        if !couldNotGetProperty && cookieSize > 0 {
            let magicCookie = malloc(Int(cookieSize))
            
            AudioFileGetProperty(playerState.audioFile!, kAudioFilePropertyMagicCookieData, &cookieSize, magicCookie!)
            AudioFileSetProperty(playerState.audioFile!, kAudioQueueProperty_MagicCookie, cookieSize, magicCookie!)
            
            free(magicCookie)
        }
        
        playerState.currentPacket = 0
        
        for index in 0..<kNumberBuffers {
            status = AudioQueueAllocateBuffer(playerState.audioQueue!, playerState.bufferByteSize, &playerState.buffers[index])
            assert(noErr == status)
        }
        
        let gain: Float = 1.0
        
        AudioQueueSetParameter(playerState.audioQueue!, kAudioQueueParam_Volume, gain)
    }
    
    func play() -> Void {
        playerState.isRunning = true
        
        
        let status = AudioQueueStart(playerState.audioQueue!, nil)
        
        assert(noErr == status)
        
        let inUserPointer = unsafeBitCast(playerState, to: UnsafeMutableRawPointer.self)
        
        for index in 0..<kNumberBuffers {
            HandleOutputCallback(inUserPointer, AQ: playerState.audioQueue!, buffer: playerState.buffers[index]!)
        }
        
//        repeat {
//            CFRunLoopRunInMode (                           // 6
//                kCFRunLoopDefaultMode,                     // 7
//                0.25,                                      // 8
//                false                                      // 9
//            )
//        } while playerState.isRunning
//        
//        CFRunLoopRunInMode (                               // 10
//            kCFRunLoopDefaultMode,
//            1,
//            false
//        )
    }
    
    fileprivate func deriveBufferSize(_ audioStreamDesc: AudioStreamBasicDescription,
                          maxPacketSize: UInt32,
                          seconds: Float64) -> (bufferSize: UInt32, numPacketsToRead: UInt32)
    {
        let maxBufferSize: UInt32 = 0x50000
        let minBufferSize: UInt32 = 0x4000
        
        var bufferSize: UInt32 = 0
        
        if audioStreamDesc.mFramesPerPacket != 0 {
            let numPacketsForTime = audioStreamDesc.mSampleRate / Double(audioStreamDesc.mFramesPerPacket) * seconds
            bufferSize = UInt32(numPacketsForTime) * maxPacketSize
        } else {
            bufferSize = max(maxBufferSize, maxPacketSize)
        }
        
        if bufferSize > maxBufferSize && bufferSize > maxPacketSize {
            bufferSize = maxBufferSize
        }else if bufferSize < minBufferSize {
            bufferSize = minBufferSize
        }
        
        return (bufferSize, bufferSize / maxPacketSize)
    }
}

func HandleOutputCallback(_ clientData: UnsafeMutableRawPointer?, AQ: AudioQueueRef, buffer: AudioQueueBufferRef) {
    
    guard let clientData = clientData else {
        return
    }
    
    let this = Unmanaged<AudioPlayerState>.fromOpaque(clientData).takeUnretainedValue()
    
    if !this.isRunning{
        return
    }
    
    var numBytesReadFromFile: UInt32 = buffer.pointee.mAudioDataBytesCapacity
    var numPackets: UInt32 = this.numPacketsToRead

    let status = AudioFileReadPacketData(this.audioFile!, false, &numBytesReadFromFile, this.packetDescs, Int64(this.currentPacket), &numPackets, buffer.pointee.mAudioData)
    
    assert(noErr == status)
    
    if numPackets > 0 {
        buffer.pointee.mAudioDataByteSize = numBytesReadFromFile
        buffer.pointee.mPacketDescriptionCount = numPackets
        
        AudioQueueEnqueueBuffer(this.audioQueue!, buffer, (this.packetDescs == nil ? 0 : numPackets), this.packetDescs)
        this.currentPacket += Int(numPackets)
    } else {
        AudioQueueStop(this.audioQueue!, false)
        this.isRunning = false
    }
}
