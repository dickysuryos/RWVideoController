//
//  RWVideoController.swift
//  RWVideoController
//
//  Created by Raditya Kurnianto on 7/2/19.
//  Copyright © 2019 raditya. All rights reserved.
//

import UIKit
import AVKit
import AVFoundation

enum PlayerState {
    case played
    case paused
    case buffer
    case finished
    case ready
}

enum SliderState {
    case sliderBeingSeek
    case sliderIdle
}

enum ScreenState {
    case normal
    case full
}

class RWVideoController: UIViewController {
    fileprivate var videoUrlString: String?
    fileprivate var videoPlayer: AVPlayer?
    fileprivate var videoItem: AVPlayerItem?
    fileprivate var videoLayer: AVPlayerLayer?
    fileprivate var currentPlayhead: CMTime = .zero
    fileprivate var timeObserverToken: Any?
    fileprivate var fullscreenController: RWVideoController?
    fileprivate var timer = Timer()
    fileprivate let timerDuration = 2.0
    
    lazy var tap: UITapGestureRecognizer = { [unowned self] in
        let gesture = UITapGestureRecognizer(target: self, action: #selector(didTap(sender:)))
        gesture.numberOfTapsRequired = 1
        gesture.numberOfTouchesRequired = 1
        print("gesture_created")
        return gesture
    }()
    
    var videoState: PlayerState = .ready
    var sliderState: SliderState = .sliderIdle
    var screenState: ScreenState = .normal
    var videoQualities: [[String: Any]]?
    var delegate: RWVideoDelegate?
    var autoplay: Bool = false {
        didSet {
            if autoplay {
                self.play()
            }
        }
    }
    
    var controlShow: Bool = false {
        didSet {
            if controlShow {
                self.showControl()
            } else {
                self.hideControl()
            }
        }
    }
    
    @IBOutlet weak var startTimeLabel: UILabel!
    @IBOutlet weak var endTimeLabel: UILabel!
    @IBOutlet weak var controlShadowView: UIView!
    @IBOutlet weak var controlButton: UIButton!
    @IBOutlet weak var controlLayerView: UIView!
    @IBOutlet weak var controlFullscreenButton: UIButton!
    @IBOutlet weak var controlQualityButton: UIButton!
    @IBOutlet weak var controlQualityView: UITableView!
    @IBOutlet weak var controlSlider: UISlider!
    @IBOutlet weak var controlQualityViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var controlQualityViewHeightConstraint: NSLayoutConstraint!
    
    convenience init(videoUrl: String) {
        self.init()
        let nib = loadNibController()
        if nib != nil{
            self.view = nib![0] as? UIView
        }
        
        self.videoUrlString = videoUrl
        self.createPlayer()
        self.setupQuality()
    }
    
    convenience init(defaultVideo: String, qualities: [[String: Any]]?) {
        self.init()
        let nib = loadNibController()
        if nib != nil{
            self.view = nib![0] as? UIView
        }
        
        self.videoUrlString = defaultVideo
        self.videoQualities = qualities
        self.setupQuality()
        self.createPlayer()
    }
    
    fileprivate func loadNibController() -> [AnyObject]?{
        let podBundle = Bundle(for: self.classForCoder)
        
        if let bundleURL = podBundle.url(forResource: "RWVideoController", withExtension: "bundle"){
            
            if let bundle = Bundle(url: bundleURL) {
                return bundle.loadNibNamed("RWVideoController", owner: self, options: nil) as [AnyObject]?
            }
            else {
                assertionFailure("Could not load the bundle")
            }
            
        }
        else if let nib = podBundle.loadNibNamed("RWVideoController", owner: self, options: nil) as [AnyObject]?{
            return nib
        }
        else{
            assertionFailure("Could not create a path to the bundle")
        }
        return nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        self.view.backgroundColor = .black
        self.controlFullscreenButton.setTitle(screenState == .normal ? "Fullscreen" : "Exit fullscreen", for: .normal)
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinish), name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(true)
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        guard let layer = self.videoLayer else { return }
        layer.frame = self.controlLayerView.frame
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override var shouldAutorotate: Bool {
        return true
    }
    
    @IBAction func controlButtonAction(_ sender: Any) {
        guard let player = self.videoPlayer else { return }
        
        stopTimer()
        if player.rate == 1 {
            pause()
        } else {
            play()
        }
        runTimer()
    }
    
    @IBAction func controllFullscreenAction(_ sender: Any) {
        if screenState == .full {
            exitFullscreen()
        } else {
            enterFullscreen()
        }
    }
    
    @IBAction func controlQualityAction(_ sender: Any) {
        showQualityControl()
    }
    
    @objc func canRotate() -> Void {
        // do nothing
    }
    
    @objc func playerDidFinish() -> Void {
        delegate?.video(didFinishPlaying: self)
    }
}

extension RWVideoController {
    fileprivate func createPlayer() {
        guard let rawVideoUrl = videoUrlString, let videoUrl = URL(string: rawVideoUrl)  else { return }
        
        self.videoItem = AVPlayerItem(url: videoUrl)
        self.videoPlayer = AVPlayer(playerItem: self.videoItem)
        self.videoLayer = AVPlayerLayer(player: videoPlayer)
        self.videoLayer?.frame = self.controlLayerView.frame
        
        guard let layer = self.videoLayer else { return }
        self.view.layer.insertSublayer(layer, at: 0)
        
        self.setupSlider()
        self.addTapGesture()
    }
    
    func runTimer() -> Void {
        timer = Timer.scheduledTimer(timeInterval: timerDuration, target: self, selector: #selector(hideControl), userInfo: nil, repeats: false)
    }
    
    func stopTimer() -> Void {
        timer.invalidate()
    }
    
    fileprivate func play() {
        guard let player = self.videoPlayer else { return }
        player.play()
        controlButton.setTitle("Pause", for: .normal)
        videoState = .played
        delegate?.videoStateDidChange(self, state: videoState)
    }
    
    fileprivate func pause() {
        guard let player = self.videoPlayer else { return }
        player.pause()
        controlButton.setTitle("Play", for: .normal)
        videoState = .paused
        delegate?.videoStateDidChange(self, state: videoState)
    }
    
    fileprivate func seekPlayhead(to: CMTime) {
        guard let player = self.videoPlayer else { return }
        player.seek(to: to, toleranceBefore: .zero, toleranceAfter: .zero) { (status) in
            self.play()
        }
    }
    
    fileprivate func enterFullscreen() -> Void {
        guard let videoUrl = self.videoUrlString else { return }
        
        DispatchQueue.main.async {
            self.fullscreenController = RWVideoController(defaultVideo: videoUrl, qualities: self.videoQualities)
            self.fullscreenController?.delegate = self.delegate
            self.fullscreenController?.videoLayer?.frame = CGRect(x: 0, y: 0, width: self.view.frame.width, height: self.view.frame.width * 0.5625)
            self.fullscreenController?.screenState = .full
            self.fullscreenController?.seekPlayhead(to: self.currentPlayhead)
            
            self.pause()
            self.delegate?.videoDidEnterFullscreen()
            
            if let controller = self.fullscreenController {
                self.parent?.present(controller, animated: true, completion: nil)
            }
        }
    }
    
    fileprivate func exitFullscreen() -> Void {
        screenState = .normal
        delegate?.videoDidExitFullscreen()
        self.pause()
        self.dismiss(animated: true) {
            self.fullscreenController?.delegate = nil
            self.fullscreenController = nil
            self.delegate?.videoDidExitFullscreen()
            UIDevice.current.setValue(Int(UIInterfaceOrientation.portrait.rawValue), forKey: "orientation")
        }
    }
}

extension RWVideoController {
    fileprivate func setupQuality() {
        // qualities
        controlQualityView.isHidden = true
        guard let qualities = self.videoQualities else {
            controlQualityButton.isEnabled = false
            controlQualityView.isHidden = true
            return
        }
        
        if qualities.count > 0 {
            controlQualityViewHeightConstraint.constant = CGFloat(qualities.count * 44)
            controlQualityButton.isEnabled = true
        }
    }
    
    fileprivate func changeQuality(videoUrl: String) {
        guard let url = URL(string: videoUrl) else { return }
        let playerItem = AVPlayerItem(url: url)
        self.videoPlayer?.replaceCurrentItem(with: playerItem)
        self.seekPlayhead(to: self.currentPlayhead)
    }
    
    fileprivate func showQualityControl() {
        if controlQualityViewBottomConstraint.constant == 0 {
            guard let qualities = self.videoQualities else {
                controlQualityView.isHidden = false
                controlQualityViewBottomConstraint.constant = 0
                return
            }
            
            controlQualityView.isHidden = true
            controlQualityViewBottomConstraint.constant = CGFloat(qualities.count * 44)
            return
        }
        
        controlQualityView.isHidden = false
        controlQualityViewBottomConstraint.constant = 0
    }
    
    fileprivate func setupSlider() {
        self.controlSlider.minimumValue = 0
        self.controlSlider.addTarget(self, action: #selector(playbackSliderChanged(_:)), for: .valueChanged)
        guard let player = self.videoPlayer, let duration = player.currentItem?.asset.duration else { return }
        
        let seconds = Float(CMTimeGetSeconds(duration))
        
        if !seconds.isNaN {
            self.controlSlider.maximumValue = seconds
            self.getReadableFormat(currendSeconds: 0, duration: Int(seconds))
            
            timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTimeMakeWithSeconds(1, preferredTimescale: 1), queue: DispatchQueue.main) { (timeInterval) in
                if player.currentItem?.status == .readyToPlay {
                    if self.sliderState == .sliderIdle {
                        let currentDuration = CMTimeGetSeconds(player.currentTime())
                        self.currentPlayhead = player.currentTime()
                        self.controlSlider.setValue(Float(currentDuration), animated: true)
                        self.getReadableFormat(currendSeconds: Int(currentDuration), duration: Int(seconds))
                        
                        self.delegate?.video(self, currentDuration: self.currentPlayhead, totalDuration: duration)
                    }
                }
            }
        } else {
            self.controlSlider.isHidden = true
            self.startTimeLabel.isHidden = true
            self.endTimeLabel.text = "Live"
        }
    }
    
    func convertSecondsToReadableFormat(seconds: Int) -> (Int, Int, Int) {
        return (seconds / 3600, (seconds % 3600) / 60, (seconds % 3600) % 60)
    }
    
    func getReadableFormat(currendSeconds: Int, duration: Int) {
        let currentTime = convertSecondsToReadableFormat(seconds: currendSeconds)
        let endTime = convertSecondsToReadableFormat(seconds: duration)
        
        let currentHour = currentTime.0 < 10 ? "0\(currentTime.0)" : "\(currentTime.0)"
        let currentMinute = currentTime.1 < 10 ? "0\(currentTime.1)" : "\(currentTime.1)"
        let currentSecond = currentTime.2 < 10 ? "0\(currentTime.2)" : "\(currentTime.2)"
        
        let startTimeString = "\(currentHour):\(currentMinute):\(currentSecond)"
        self.startTimeLabel.text = startTimeString
        
        let endHour = endTime.0
        let endMinute = endTime.1
        let endSecond = endTime.2
        
        let endTimeString = "\(endHour > 0 ? "\(endHour):": "")\(endMinute):\(endSecond)"
        self.endTimeLabel.text = endTimeString
    }
    
    @objc fileprivate func playbackSliderChanged(_ playbackSlider: UISlider) {
        guard let player = self.videoPlayer else { return }
        
        if playbackSlider.isTracking {
            stopTimer()
            pause()
            sliderState = .sliderBeingSeek
            delegate?.video(self, sliderState: sliderState)
            return
        }
        
        let seconds: Int64 = Int64(playbackSlider.value)
        let targetTime: CMTime = CMTimeMakeWithSeconds(Float64(Float(seconds)), preferredTimescale: 1)
        
        player.seek(to: targetTime) { (seekComplete) in
            if player.rate == 0 {
                self.play()
                self.runTimer()
                self.sliderState = .sliderIdle
                self.delegate?.video(self, sliderState: self.sliderState)
            }
        }
    }
}

extension RWVideoController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let qualities = self.videoQualities else { return 0 }
        return qualities.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        guard let qualities = self.videoQualities else { return cell }
        
        let item = qualities[indexPath.row]
        cell.textLabel?.text = item.keys.first
        return cell
    }
}

extension RWVideoController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let qualities = self.videoQualities else { return }
        
        let item = qualities[indexPath.row]
        if let key = item.keys.first, let content = item[key] as? String {
            changeQuality(videoUrl: content)
        }
        
        showQualityControl()
    }
}

extension AppDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if let rootViewController = self.topViewControllerWithRootViewController(rootViewController: window?.rootViewController) as? RWVideoController {
            if rootViewController.responds(to: #selector(RWVideoController.canRotate)) {
                // Unlock landscape view orientations for this view controller
                return .allButUpsideDown
            }
        }
        
        // Only allow portrait (standard behaviour)
        return .portrait;
    }
    
    func topViewControllerWithRootViewController(rootViewController: UIViewController!) -> UIViewController? {
        if (rootViewController == nil) { return nil }
        if rootViewController.isKind(of: UITabBarController.self) {
            return topViewControllerWithRootViewController(rootViewController: (rootViewController as! UITabBarController).selectedViewController)
        } else if (rootViewController.isKind(of: UINavigationController.self)) {
            return topViewControllerWithRootViewController(rootViewController: (rootViewController as! UINavigationController).visibleViewController)
        } else if (rootViewController.presentedViewController != nil) {
            return topViewControllerWithRootViewController(rootViewController: rootViewController.presentedViewController)
        }
        return rootViewController
    }
}
