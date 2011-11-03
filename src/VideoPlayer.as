/****************************************************************
* Video Player
* Based on code from https://github.com/cpak/flash-video_player
****************************************************************/

package {	

	import flash.display.*;
	import flash.utils.*;
//	import flash.utils.Timer;
	import flash.net.NetConnection;
	import flash.net.NetStream;
	import flash.net.URLRequest;
	import flash.events.TimerEvent;
	import flash.events.Event;
	import flash.events.MouseEvent;
	import flash.events.FullScreenEvent;
	import flash.events.NetStatusEvent;
	import flash.events.AsyncErrorEvent;
	import flash.geom.Rectangle;
	import flash.media.SoundTransform;
	import fl.transitions.*;
	import fl.transitions.easing.*;
	import flash.external.ExternalInterface;
	import flash.system.Capabilities;
	
	public class VideoPlayer extends MovieClip{
		
		// CONSTANTS
		const BUFFER_TIME:Number = 8;			// sec
		const DEFAULT_VOLUME:Number = 0.6;		// 0.0 - 1.0
		const DISPLAY_REFRESH_TIMER:int = 10;	// ms
		const VIDEO_SMOOTHING:Boolean = true;	// Set false for slow computers
		
		// VARIABLES
		private var _autoLoad:Boolean = true;
		private var _autoPlay:Boolean = false;
		private var _controlBarOnTop:Boolean = false;
		private var _hideControls:Boolean = true;
		private var _videoLoaded:Boolean = false;
		private var _volumeScrub:Boolean = false;
		private var _progressScrub:Boolean = false;
		private var _lastVolume:int = DEFAULT_VOLUME;
		private var _connection:NetConnection;
		private var _stream:NetStream;
		private var _metaInfo:Object;
		private var _displayTimer:Timer;
		private var _controlBarTimerId:uint;
		private var _previewLoader:Loader = new Loader();
		private var _videoDisplay:Object;
		private var _bigPlayBtn:SimpleButton;
		private var _preview:MovieClip;
		private var _controlBar:MovieClip;
		private var _externalAvailable:Boolean;
		
		// FLASHVARS
		private var _videoSource:String = "../videos/video1.flv";
		private var _previewSource:String = "../images/btn_search.png";
		private var _videoWidth:int = 744;
		private var _videoHeight:int = 416;
		
		public function VideoPlayer(){		
			all_mc.visible=false;
			init();
		}
		
		private function init(){
			_externalAvailable = ExternalInterface.available;
			
			setupReferences();
			getLoaderValues();
			setupStage();
			setupVideo();
			setupTimers();
			setupExternalInterface();
			setupPreview();		
			setupControls();
			autoLoadOrPlay();
			
			all_mc.visible=true;
			if (_externalAvailable) {
				ExternalInterface.call("log","videoPlayerLoaded");
			}
		}
		
		private function setupReferences():void{
			_videoDisplay = all_mc.videoDisplay;
			_bigPlayBtn = all_mc.bigPlayBtn;
			_controlBar = all_mc.controlBar;
			_preview = all_mc.preview;
		}
		
		private function getLoaderValues(){
		
			var videoSource:String = String(root.loaderInfo.parameters.source);
			var previewSource:String = String(root.loaderInfo.parameters.preview)
			var videoWidth:int = parseInt(root.loaderInfo.parameters.width);
			var videoHeight:int = parseInt(root.loaderInfo.parameters.height);
			var autoPlay:String = String(root.loaderInfo.parameters.autoPlay);
			var autoLoad:String = String(root.loaderInfo.parameters.autoLoad);
			var hideControls:String = String(root.loaderInfo.parameters.hideControls);
			//var controlsOnTop:String = String(root.loaderInfo.parameters.controlsOnTop);
			
			if(videoSource!="undefined") _videoSource = videoSource;
			if(previewSource!="undefined") _previewSource = previewSource;
			if(videoWidth!=0) _videoWidth = videoWidth;
			if(videoHeight!=0) _videoHeight = videoHeight;
			
			if(autoPlay=='true') _autoPlay = true;
			if(autoPlay=='false') _autoPlay = false;
			if(autoLoad=='true') _autoLoad = true;
			if(autoLoad=='false') _autoLoad = false;
			if(hideControls=='true') _hideControls = true;
			if(hideControls=='false') _hideControls = false;
			
//			if(controlsOnTop=='true') _controlBarOnTop = true;
			
			//debug_txt.text = String(_videoWidth);
			
			if(_autoPlay) _autoLoad=true;
			
		}
		
		private function setupStage(){
			//events
			stage.addEventListener(MouseEvent.MOUSE_UP, mouseReleased);
			stage.addEventListener(FullScreenEvent.FULL_SCREEN, onFullscreen);
			// Setup stage for fullscreen
			//stage.scaleMode = StageScaleMode.NO_SCALE;//this causes the flash movie not to scale in the browser
			stage.align = StageAlign.TOP_LEFT;
			// Show/hide controls on MOUSE_MOVE
			stage.addEventListener(MouseEvent.MOUSE_MOVE, showControls);
		}
		
		private function setupVideo(){
			_connection = new NetConnection();
			_connection.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);
			_connection.connect(null);
			
			_stream = new NetStream(_connection);
			_stream.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);
			_stream.addEventListener(AsyncErrorEvent.ASYNC_ERROR, asyncErrorHandler);
			_stream.client = this;
			_stream.bufferTime = BUFFER_TIME;
			
			_videoDisplay.attachNetStream(_stream);
			_videoDisplay.smoothing = VIDEO_SMOOTHING;
		}
		
		private function setupTimers(){
			_displayTimer = new Timer(DISPLAY_REFRESH_TIMER);
			_displayTimer.addEventListener(TimerEvent.TIMER, updateDisplay);
		}
		
		private function setupExternalInterface(){
			if (ExternalInterface.available) {
				try{
					ExternalInterface.addCallback("pauseVideo", pauseVideo);
					ExternalInterface.addCallback("playVideo", playVideo);
					ExternalInterface.addCallback("stopVideo", stopVideo);
				}catch(e:Error){
					trace("XIF error: " + e.name + " - " + e.message);
				}
			}
		}
		
		private function setupPreview():void{
			_previewLoader.contentLoaderInfo.addEventListener(Event.INIT, formatPreview);
			_previewLoader.load(new URLRequest(_previewSource));
			_preview.addChild(_previewLoader);
		}
		
		private function setupControls():void{
		
			_bigPlayBtn.addEventListener(MouseEvent.CLICK, playVideo);
			_controlBar.btnPlay.addEventListener(MouseEvent.CLICK, playVideo);
			_controlBar.btnPause.addEventListener(MouseEvent.CLICK, pauseVideo);
			_controlBar.btnStop.addEventListener(MouseEvent.CLICK, stopVideo);
			_controlBar.progressBar.scrubber.btnScrubber.addEventListener(MouseEvent.MOUSE_DOWN, scrubProgress);
			_controlBar.progressBar.btnInvisible.addEventListener(MouseEvent.MOUSE_DOWN, scrubProgress);
			_controlBar.mc_volume_bar.scrubber.btnScrubber.addEventListener(MouseEvent.MOUSE_DOWN, scrubVolume);
			_controlBar.mc_volume_bar.btnInvisible.addEventListener(MouseEvent.MOUSE_DOWN, scrubVolume);
			_controlBar.btn_fullscreen_on.addEventListener(MouseEvent.CLICK, fullscreenOn);
			_controlBar.btn_fullscreen_off.addEventListener(MouseEvent.CLICK, fullscreenOff);
			
			if(_hideControls) _controlBar.visible = false;
		
			_controlBar.y = stage.stageHeight - _controlBar.height ;
			_controlBar.btnPause.visible = false;
			_controlBar.btn_fullscreen_off.visible = false;
			_controlBar.progressBar.loadBar.width = 1;
			_controlBar.progressBar.playBar.width = 1;
			_controlBar.mc_volume_bar.scrubber.x = _controlBar.mc_volume_bar.width * DEFAULT_VOLUME;
			_controlBar.mc_volume_bar.mc_fill.width = _controlBar.mc_volume_bar.width * (_controlBar.mc_volume_bar.scrubber.x / 	_controlBar.mc_volume_bar.width);
			setVolume(DEFAULT_VOLUME);
			
			_controlBar.mc_volume_bar.visible=false;
			_controlBar.btn_fullscreen_off.visible=false;
			_controlBar.btn_fullscreen_on.visible=false;
			_controlBar.btnStop.visible=false;
			
			updateControlsPosition();
		}
		
		private function autoLoadOrPlay(){
			if(_autoPlay){
				playVideo();
				return;
			}
			if(_autoLoad){
				//_videoPlayback.load(_vUrl);
				//_videoPlayback.addEventListener(VideoEvent.READY, loadPlayerComplete);
				_stream.play(_videoSource);
				_stream.pause();
				_videoLoaded = true;
			}
		}

		private function formatPreview(e:Event):void{
			_previewLoader.width = _videoWidth;
			_previewLoader.height = _videoHeight;
			_previewLoader.addEventListener(MouseEvent.CLICK, playVideo);
		}
		
		public function playVideo(e:MouseEvent=null):void{
			_preview.visible=false;
			_bigPlayBtn.visible=false;
			if(!_videoLoaded){
				_stream.play(_videoSource);
				_videoLoaded = true;
			}else{
				_stream.resume();
			}
			_videoDisplay.visible = true;
			_controlBar.btnPlay.visible = false;
			_controlBar.btnPause.visible = true;
		}
		
		//public function extPlayVideo():void{
		//	playVideo(null);
		//}
		
		//function jsPauseVideo():void{
		//	pauseVideo(null);
		//}
		
		public function pauseVideo(e:MouseEvent=null):void{
			_stream.pause();
			_controlBar.btnPlay.visible = true;
			_controlBar.btnPause.visible = false;
		}
		
		public function stopVideo(e:MouseEvent=null):void{
			stopVideoPlayback();
		}
		
		private function scrubProgress(e:MouseEvent):void{
			_progressScrub = true;
			_controlBar.progressBar.scrubber.startDrag(true, new Rectangle(0, 0, getProgressWidth() , 0));
		}
		
		private function scrubVolume(e:MouseEvent):void{
			_volumeScrub = true;
			_controlBar.mc_volume_bar.scrubber.startDrag(true, new Rectangle(0, 0, _controlBar.mc_volume_bar.width, 0));
		}
		
		private function mouseReleased(e:MouseEvent):void{
			_volumeScrub = false;
			_progressScrub = false;
			
			_controlBar.progressBar.scrubber.stopDrag();
			_controlBar.mc_volume_bar.scrubber.stopDrag();
		}
		
		private function stopVideoPlayback():void {
			_stream.pause();
			_stream.seek(0);
		
			_videoDisplay.visible = false;
		
			_controlBar.btnPause.visible = false;
			_controlBar.btnPlay.visible = true;
		}
		
		private function setVolume(intVolume:Number = 0):void {
			var sndTransform = new SoundTransform(intVolume);
			_stream.soundTransform	= sndTransform;
		}
		
		private function getProgressWidth():Number{
			return _controlBar.progressBar.bgBar.width;
		}
		
		// UI
		private function updateDisplay(e:TimerEvent):void{
			var progressWidth:Number = getProgressWidth();
			if(_progressScrub){
				_stream.seek(Math.round((_controlBar.progressBar.scrubber.x / progressWidth) * _metaInfo.duration));
				_controlBar.progressBar.playBar.width = _controlBar.progressBar.scrubber.x;
			}else{
				_controlBar.progressBar.scrubber.x = Math.round((_stream.time / _metaInfo.duration) * progressWidth);
				_controlBar.progressBar.playBar.width = _controlBar.progressBar.scrubber.x;
				_controlBar.progressBar.loadBar.width = Math.round((_stream.bytesLoaded / _stream.bytesTotal) * progressWidth);
			}
			if(_volumeScrub){
				setVolume(_controlBar.mc_volume_bar.scrubber.x / _controlBar.mc_volume_bar.width);
				_controlBar.mc_volume_bar.mc_fill.width = _controlBar.mc_volume_bar.width * (_controlBar.mc_volume_bar.scrubber.x/_controlBar.mc_volume_bar.width);
			}
		}
		
		private function updateControlsPosition():void{
			var height;
			var width;
			if(stage.displayState == "fullScreen"){
				width = Capabilities.screenResolutionX;
				height = Capabilities.screenResolutionY;
				//_videoDisplay.width = Capabilities.screenResolutionX;
				//_videoDisplay.height = Capabilities.screenResolutionX * (_videoHeight / _videoWidth);
				//_videoDisplay.y = (Capabilities.screenResolutionY - _videoDisplay.height) / 2;
			}else{
				width = _videoWidth;
				height = _videoHeight;
			}
			_controlBar.x = 0; 
			_controlBar.y = height - _controlBar.height;
			_controlBar.mc_bg.width = width;
			_bigPlayBtn.x = width/2;
			_bigPlayBtn.y = height/2;
			
			_videoDisplay.x = 0;
			_videoDisplay.y = 0;
			_videoDisplay.height = height;
			_videoDisplay.width = width;
		}
		
		private function showControls(e:MouseEvent):void{	
			_controlBar.visible = true;
			if(_hideControls) _controlBarTimerId = setTimeout(hideControls, 2000);
		}
		
		private function hideControls():void{
			TransitionManager.start(_controlBar, {type:Fade, direction:Transition.OUT, duration:1, easing:Strong.easeIn});
		}
		
		private function fullscreenOn(e:MouseEvent):void{
			stage.displayState = StageDisplayState.FULL_SCREEN;
			updateControlsPosition();
		}
		
		private function fullscreenOff(e:MouseEvent):void{
			stage.displayState = StageDisplayState.NORMAL;
			updateControlsPosition();
		}
		
		private function onFullscreen(e:FullScreenEvent):void{
			if(e.fullScreen){
				_controlBar.btn_fullscreen_on.visible = false;
				_controlBar.btn_fullscreen_off.visible = true;
			}else{
				_controlBar.btn_fullscreen_on.visible = true;
				_controlBar.btn_fullscreen_off.visible = false;
			}
			updateControlsPosition();
		}
		
		public function onMetaData(info:Object):void{
			_metaInfo = info;
			_displayTimer.start();
		}
		
		public function onXMPData(info:Object):void{

		}
		
		private function netStatusHandler(event:NetStatusEvent):void{
			switch(event.info.code){
				case "NetStream.Play.StreamNotFound":
					trace("Stream not found: " + _videoSource);
				break;
				case "NetStream.Play.Stop":
					stopVideoPlayback();
					broadcastMessage("videoCompleted");
				break;
			}
		}
		
		private function broadcastMessage(msg){
			if(_externalAvailable){
				ExternalInterface.call(msg);
			}
		}
		
		private function asyncErrorHandler(event:AsyncErrorEvent):void {
 	   trace(event.text);
		}
		
		private function formatTime(t:int):String {
			var s:int = Math.round(t);
			var m:int = 0;
			if (s > 0) {
				while (s > 59) {
					m++;
					s -= 60;
				}
				return String((m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s);
			} else {
				return "00:00";
			}
		}
		

	}	
}