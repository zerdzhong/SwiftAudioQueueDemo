//
//  ViewController.swift
//  AudioQueueDemo
//
//  Created by zhongzhendong on 7/9/16.
//  Copyright © 2016 zerdzhong. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    var player: AudioPlayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        player = AudioPlayer(URL: NSURL(string: "https://archive.org/download/testmp3testfile/mpthreetest.mp3")!)
    }

    @IBAction func buttonClicked(sender: AnyObject) {
        if let player = self.player {
            player.play()
        }
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

