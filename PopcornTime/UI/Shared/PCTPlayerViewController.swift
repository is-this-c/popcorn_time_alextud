

import UIKit
import MediaPlayer
import PopcornTorrent
import PopcornKit

#if os(tvOS)
    import TVMLKitchen
#endif

protocol PCTPlayerViewControllerDelegate: class {
    func playNext(_ episode: Episode)
    
    #if os(iOS)
        func presentCastPlayer(_ media: Media, videoFilePath: URL, startPosition: TimeInterval)
    #endif
}

/// Optional functions:
extension PCTPlayerViewControllerDelegate {
    func playNext(_ episode: Episode) {}
}

class PCTPlayerViewController: UIViewController, VLCMediaPlayerDelegate, UIGestureRecognizerDelegate {
    
    // MARK: - IBOutlets
    @IBOutlet var movieView: UIView!
    @IBOutlet var loadingActivityIndicatorView: UIView!
    @IBOutlet var upNextView: UpNextView!
    @IBOutlet var progressBar: ProgressBar!
    
    @IBOutlet var overlayViews: [UIView]!
    
    #if os(tvOS)
    
        @IBOutlet var dimmerView: UIView!
        @IBOutlet var infoHelperView: UIView!
    
        var lastTranslation: CGFloat = 0.0
        let interactor = OptionsPercentDrivenInteractiveTransition()
    #elseif os(iOS)
        @IBOutlet var screenshotImageView: UIImageView!
    
        @IBOutlet var volumeSlider: BarSlider! {
            didSet {
                volumeSlider.setValue(AVAudioSession.sharedInstance().outputVolume, animated: false)
            }
        }
    
        internal var volumeView: MPVolumeView = {
            let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 100, height: 100))
            view.sizeToFit()
            return view
        }()
    
        @IBOutlet var playPauseButton: UIButton!
        @IBOutlet var subtitleSwitcherButton: UIButton!
        @IBOutlet var videoDimensionsButton: UIButton!
    
        @IBOutlet var tapOnVideoRecognizer: UITapGestureRecognizer!
        @IBOutlet var doubleTapToZoomOnVideoRecognizer: UITapGestureRecognizer!
    
        @IBOutlet var regularConstraints: [NSLayoutConstraint]!
        @IBOutlet var compactConstraints: [NSLayoutConstraint]!
        @IBOutlet var duringScrubbingConstraints: NSLayoutConstraint!
        @IBOutlet var finishedScrubbingConstraints: NSLayoutConstraint!
        @IBOutlet var subtitleSwitcherButtonWidthConstraint: NSLayoutConstraint!
    
        @IBOutlet var scrubbingSpeedLabel: UILabel!
    #endif
    
    
    
    // MARK: - Slider actions

    func positionSliderDidDrag() {
        let time = NSNumber(value: Float(progressBar.scrubbingProgress * streamDuration))
        let remainingTime = NSNumber(value: time.floatValue - Float(streamDuration))
        progressBar.remainingTimeLabel.text = VLCTime(number: remainingTime).stringValue
        progressBar.scrubbingTimeLabel.text = VLCTime(number: time).stringValue
        workItem?.cancel()
        workItem = DispatchWorkItem { [weak self] in
            if let image = self?.screenshotAtTime(time) {
                #if os(tvOS)
                    self?.progressBar.screenshot = image
                #elseif os(iOS)
                    self?.screenshotImageView.image = image
                #endif
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem!)
    }
    
    func positionSliderAction() {
        resetIdleTimer()
        mediaplayer.play()
        if mediaplayer.isSeekable {
            let time = NSNumber(value: Float(progressBar.scrubbingProgress * streamDuration))
            mediaplayer.time = VLCTime(number: time)
        }
    }
    
    // MARK: - Button actions
    
    @IBAction func playandPause() {
        #if os(tvOS)
            // Make fake gesture to trick clickGesture: into recognising the touch.
            let gesture = SiriRemoteGestureRecognizer(target: nil, action: nil)
            gesture.isClick = true
            gesture.state = .ended
            clickGesture(gesture)
        #elseif os(iOS)
            mediaplayer.isPlaying ? mediaplayer.pause() : mediaplayer.play()
        #endif
    }
    
    @IBAction func fastForward() {
        mediaplayer.jumpForward(30)
    }
    
    @IBAction func rewind() {
        mediaplayer.jumpBackward(30)
    }
    
    @IBAction func fastForwardHeld(_ sender: UIGestureRecognizer) {
        switch sender.state {
        case .began:
            fallthrough
        case .changed:
            #if os(tvOS)
            progressBar.hint = .fastForward
            #endif
            guard mediaplayer.rate == 1.0 else { break }
            mediaplayer.fastForward(atRate: 20.0)
        case .cancelled:
            fallthrough
        case .failed:
            fallthrough
        case .ended:
            #if os(tvOS)
            progressBar.hint = .none
            #endif
            mediaplayer.rate = 1.0
            resetIdleTimer()
        default:
            break
        }
    }
    
    @IBAction func rewindHeld(_ sender: UIGestureRecognizer) {
        switch sender.state {
        case .began:
            fallthrough
        case .changed:
            #if os(tvOS)
            progressBar.hint = .rewind
            #endif
            guard mediaplayer.rate == 1.0 else { break }
            mediaplayer.rewind(atRate: 20.0)
        case .cancelled:
            fallthrough
        case .failed:
            fallthrough
        case .ended:
            #if os(tvOS)
            progressBar.hint = .none
            #endif
            mediaplayer.rate = 1.0
            resetIdleTimer()
        default:
            break
        }
    }
    
    @IBAction func didFinishPlaying() {
        mediaplayer.delegate = nil
        mediaplayer.stop()
        
        PTTorrentStreamer.shared().cancelStreamingAndDeleteData(UserDefaults.standard.bool(forKey: "removeCacheOnPlayerExit"))
        
        (media is Movie ? WatchedlistManager.movie : WatchedlistManager.episode).setCurrentProgress(Float(progressBar.progress), forId: media.id, withStatus: .finished)
        
        #if os(tvOS)
            OperationQueue.main.addOperation {
                Kitchen.appController.navigationController.popViewController(animated: true)
            }
        #elseif os(iOS)
            dismiss(animated: true, completion: nil)
        #endif
    }
    
    // MARK: - Public vars
    
    weak var delegate: PCTPlayerViewControllerDelegate?
    var subtitles = [Subtitle]()
    var currentSubtitle: Subtitle? {
        didSet {
            if let subtitle = currentSubtitle {
                PopcornKit.downloadSubtitleFile(subtitle.link, downloadDirectory: directory, completion: { (subtitlePath, error) in
                    guard let subtitlePath = subtitlePath else { return }
                    self.mediaplayer.addPlaybackSlave(subtitlePath, type: .subtitle, enforce: true)
                })
            } else {
                mediaplayer.currentVideoSubTitleIndex = NSNotFound // Remove all subtitles
            }
        }
    }
    
    // MARK: - Private vars
    
    private (set) var mediaplayer = VLCMediaPlayer()
    private (set) var url: URL!
    private (set) var directory: URL!
    private (set) var localPathToMedia: URL!
    private (set) var media: Media!
    internal var nextEpisode: Episode?
    private var startPosition: Float = 0.0
    private var idleWorkItem: DispatchWorkItem?
    internal var shouldHideStatusBar = true
    private let NSNotFound: Int32 = -1
    private var imageGenerator: AVAssetImageGenerator!
    private var workItem: DispatchWorkItem?
    private var resumePlayback = false
    internal var streamDuration: Float {
        guard let remaining = mediaplayer.remainingTime?.value?.floatValue, let elapsed = mediaplayer.time?.value?.floatValue else { return 0.0 }
        return fabsf(remaining) + elapsed
    }
    
    // MARK: - Player functions
    
    func play(_ media: Media, fromURL url: URL, localURL local: URL, progress fromPosition: Float, nextEpisode: Episode? = nil, directory: URL) {
        self.url = url
        self.localPathToMedia = local
        self.media = media
        self.startPosition = fromPosition
        self.nextEpisode = nextEpisode
        self.directory = directory
        if let subtitles = media.subtitles {
            self.subtitles = subtitles
        }
        self.currentSubtitle = media.currentSubtitle
        self.imageGenerator = AVAssetImageGenerator(asset: AVAsset(url: local))
    }
    
    func didSelectSubtitle(_ subtitle: Subtitle?) {
        currentSubtitle = subtitle
    }
    
    func screenshotAtTime(_ time: NSNumber) -> UIImage? {
        guard let image = try? imageGenerator.copyCGImage(at: CMTimeMakeWithSeconds(time.doubleValue/1000.0, 1000), actualTime: nil) else { return nil }
        return UIImage(cgImage: image)
    }
    
    // MARK: - View Methods
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !mediaplayer.isPlaying else { return }
        if startPosition > 0.0 {
            let style: UIAlertControllerStyle = (traitCollection.horizontalSizeClass == .regular && traitCollection.verticalSizeClass == .regular) ? .alert : .actionSheet
            let continueWatchingAlert = UIAlertController(title: nil, message: nil, preferredStyle: style)
            continueWatchingAlert.addAction(UIAlertAction(title: "Resume Playing", style: .default, handler:{ action in
                self.resumePlayback = true
                self.mediaplayer.play()
            }))
            continueWatchingAlert.addAction(UIAlertAction(title: "Start from Begining", style: .default, handler: { action in
                self.mediaplayer.play()
            }))
            continueWatchingAlert.popoverPresentationController?.sourceView = progressBar
            present(continueWatchingAlert, animated: true, completion: nil)
        } else {
            mediaplayer.play()
        }
        ThemeSongManager.shared.stopTheme() // Make sure theme song isn't playing.
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        mediaplayer.delegate = self
        mediaplayer.drawable = movieView
        mediaplayer.media = VLCMedia(url: url)
        progressBar.progress = 0
        mediaplayer.audio.volume = 200
        
        let settings = SubtitleSettings()
        (mediaplayer as VLCFontAppearance).setTextRendererFontSize!(NSNumber(value: settings.size))
        (mediaplayer as VLCFontAppearance).setTextRendererFontColor!(NSNumber(value: settings.color.hexInt()))
        (mediaplayer as VLCFontAppearance).setTextRendererFont!(settings.font.familyName as NSString)
        (mediaplayer as VLCFontAppearance).setTextRendererFontForceBold!(NSNumber(booleanLiteral: settings.style == .bold || settings.style == .boldItalic))
        mediaplayer.media.addOptions([vlcSettingTextEncoding: settings.encoding])

//        if let nextMedia = nextMedia {
//            upNextView.delegate = self
//            upNextView.nextEpisodeInfoLabel.text = "Season \(nextMedia.season) Episode \(nextMedia.episode)"
//            upNextView.nextEpisodeTitleLabel.text = nextMedia.title
//            upNextView.nextShowTitleLabel.text = nextMedia.show!.title
//            TraktManager.shared.getEpisodeMetadata(nextMedia.show.id, episodeNumber: nextMedia.episode, seasonNumber: nextMedia.season, completion: { (image, _, imdb, error) in
//                guard let imdb = imdb else { return }
//                self.nextMedia?.largeBackgroundImage = image
//                if let image = image {
//                   self.upNextView.nextEpisodeThumbImageView.af_setImage(withURL: URL(string: image)!)
//                } else {
//                    self.upNextView.nextEpisodeThumbImageView.image = UIImage(named: "Placeholder")
//                }
//                    SubtitlesManager.shared.search(imdbId: imdb, completion: { (subtitles, error) in
//                        guard error == nil else { return }
//                        self.nextMedia?.subtitles = subtitles
//                    })
//            })
//        }
        #if os(iOS)
            view.addSubview(volumeView)
            if let slider = volumeView.subviews.flatMap({$0 as? UISlider}).first {
                slider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
            }
            tapOnVideoRecognizer.require(toFail: doubleTapToZoomOnVideoRecognizer)
            
            subtitleSwitcherButton.isHidden = subtitles.count == 0
            subtitleSwitcherButtonWidthConstraint.constant = subtitleSwitcherButton.isHidden == true ? 0 : 24
        #elseif os(tvOS)
            let gesture = SiriRemoteGestureRecognizer(target: self, action: #selector(touchLocationDidChange(_:)))
            gesture.delegate = self
            view.addGestureRecognizer(gesture)
            
            let clickGesture = SiriRemoteGestureRecognizer(target: self, action: #selector(clickGesture(_:)))
            clickGesture.delegate = self
            view.addGestureRecognizer(clickGesture)
        #endif
    }
    
    // MARK: - Player changes notifications
    
    func mediaPlayerTimeChanged(_ aNotification: Notification!) {
        if loadingActivityIndicatorView.isHidden == false {
            #if os(iOS)
                progressBar.subviews.first(where: {!$0.subviews.isEmpty})?.subviews.forEach({ $0.isHidden = false })
            #endif
            loadingActivityIndicatorView.isHidden = true
            
            if resumePlayback && mediaplayer.isSeekable {
                resumePlayback = false
                let time = NSNumber(value: startPosition * streamDuration)
                mediaplayer.time = VLCTime(number: time)
            }
            
            resetIdleTimer()
        }
        
        progressBar.isBuffering = false
        progressBar.bufferProgress = PTTorrentStreamer.shared().torrentStatus.totalProgreess
        progressBar.remainingTimeLabel.text = mediaplayer.remainingTime.stringValue
        progressBar.elapsedTimeLabel.text = mediaplayer.time.stringValue
        progressBar.progress = mediaplayer.position
        //        if nextMedia != nil && (mediaplayer.remainingTime.intValue/1000) == -30 {
        //            upNextView.show()
        //        } else if (mediaplayer.remainingTime.intValue/1000) < -30 && !upNextView.isHidden {
        //            upNextView.hide()
        //        }
    }
    
    func mediaPlayerStateChanged(_ aNotification: Notification!) {
        resetIdleTimer()
        progressBar.isBuffering = false
        let manager: WatchedlistManager = media is Movie ? .movie : .episode
        switch mediaplayer.state {
        case .error:
            fallthrough
        case .ended:
            fallthrough
        case .stopped:
            manager.setCurrentProgress(Float(progressBar.progress), forId: media.id, withStatus: .finished)
            didFinishPlaying()
        case .paused:
            manager.setCurrentProgress(Float(progressBar.progress), forId: media.id, withStatus: .paused)
            #if os(iOS)
                playPauseButton.setImage(UIImage(named: "Play"), for: .normal)
            #endif
        case .playing:
            #if os(iOS)
                playPauseButton.setImage(UIImage(named: "Pause"), for: .normal)
            #endif
            manager.setCurrentProgress(Float(progressBar.progress), forId: media.id, withStatus: .watching)
        case .buffering:
            progressBar.isBuffering = true
        default:
            break
        }
    }
    
    
    @IBAction func toggleControlsVisible() {
        shouldHideStatusBar = overlayViews.first!.isHidden
        UIView.animate(withDuration: 0.25, animations: {
            if self.overlayViews.first!.isHidden {
                self.overlayViews.forEach({
                    $0.alpha = 1.0
                    $0.isHidden = false
                })
            } else {
                self.overlayViews.forEach({ $0.alpha = 0.0 })
            }
            #if os(iOS)
            self.setNeedsStatusBarAppearanceUpdate()
            #endif
         }, completion: { finished in
            if self.overlayViews.first!.alpha == 0.0 {
                self.overlayViews.forEach({ $0.isHidden = true })
            }
            self.resetIdleTimer()
        }) 
    }
    
    // MARK: - Timers
    
    func resetIdleTimer() {
        idleWorkItem?.cancel()
        idleWorkItem = DispatchWorkItem() {
            if !self.progressBar.isHidden { self.toggleControlsVisible() }
        }
        
        let delay: TimeInterval = UIDevice.current.userInterfaceIdiom == .tv ? 3 : 5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: idleWorkItem!)
        
        if !mediaplayer.isPlaying || !loadingActivityIndicatorView.isHidden || progressBar.isScrubbing || progressBar.isBuffering || mediaplayer.rate != 1.0 // If paused, scrubbing, fast forwarding or loading, cancel work Item so UI doesn't disappear
        {
            idleWorkItem?.cancel()
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {    
        return true
    }
    
}
/**
 Protocol wrapper for private subtitle appearance API in MobileVLCKit. Can be toll free bridged from VLCMediaPlayer. Example for changing font:
 
        let mediaPlayer = VLCMediaPlayer()
        (mediaPlayer as VLCFontAppearance).setTextRendererFont!("HelveticaNueve")
 */
@objc protocol VLCFontAppearance {
    /**
     Change color of subtitle font.
     
     [All colors available here](http://www.nameacolor.com/Color%20numbers.htm)
     
     - Parameter fontColor: An `NSNumber` wrapped hexInt (`UInt32`) indicating the color. Eg. Black: 0, White: 16777215, etc.
     */
    @objc optional func setTextRendererFontColor(_ fontColor: NSNumber)
    /**
     Toggle bold on subtitle font.
     
     - Parameter fontForceBold: `NSNumber` wrapped `Bool`.
     */
    @objc optional func setTextRendererFontForceBold(_ fontForceBold: NSNumber)
    /**
     Change the subtitle font.
     
     - Parameter fontname: `NSString` representation of font name. Eg `UIFonts` familyName property.
     */
    @objc optional func setTextRendererFont(_ fontname: NSString)
    /**
     Change the subtitle font size.
     
     - Parameter fontname: `NSNumber` wrapped `Int` of the fonts size.
     
     - Important: Provide the font in reverse size as `libvlc` sets the text matrix to the identity matrix which reverses the font size. Ie. 5pt is really big and 100pt is really small.
     */
    @objc optional func setTextRendererFontSize(_ fontSize: NSNumber)
}

extension VLCMediaPlayer: VLCFontAppearance {}
