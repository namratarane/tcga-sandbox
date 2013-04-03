﻿/**
* @class Chart3D
* @author FusionCharts Technologies LLP, www.fusioncharts.com
* @version 3.2
*
* Copyright (C) FusionCharts Technologies LLP, 2010*
* Chart3D chart extends the Chart2D class to use all 
* parameters obtained/evaluated in its Super class and
* formats them for use by the Engine instance. This is
* the class to  create the 3D chart by instantiating the 
* Engine and controlling it through the public API of
* the Engine.
*/
// import the Engine class
import com.fusioncharts.engine3D.Engine;
// import the Model class
import com.fusioncharts.engine3D.Model;
// import default values
import com.fusioncharts.engine3D.DefaultValues;
// import the Chart2D class
import com.fusioncharts.core.Chart2D;
//Import Logger Class
import com.fusioncharts.helper.Logger;
//import Delegate class
import mx.utils.Delegate;
// import the external package
import flash.external.*;
//import MathExt class
import com.fusioncharts.extensions.MathExt;
// class definition
class com.fusioncharts.core.Chart3D extends Chart2D {
	// Engine instance
	private var system3D;
	//
	// holds the latest z origin values for series
	private var zOrigin:Number;
	// mouse coordinates
	private var xmouse:Number;
	private var ymouse:Number;
	// Chart initialisation status (0 - yet to start, 1 - axesBox ready, 2 - finally ready)
	private var initStatus:Number = 0;
	//
	// container of the chart
	private var mcChart:MovieClip;
	//
	// last aview angles before animating rotation to change view
	private var objLastAngs:Object;
	// container of conglomerates of various chart related data
	private var objMultiData:Object;
	// event handler object
	private var objEventHandler:Object;
	// mouse listener object
	private var mouseListener:Object;
	// 
	// tooltip coordinate mapping
	private var arrToolTipMap:Array;
	// all series related data bundles
	private var arrSeries:Array;
	// zero plane coordinates for different series
	private var arrZeroPlanes:Array;
	// 
	// is mmouse down
	private var isMouseDown:Boolean;
	// is chart initiated
	private var initiated:Boolean;
	// is chart rendered
	private var rendered:Boolean;
	// is stage updated
	private var stageUpdated:Boolean;
	// if zero plane be rendered
	private var zeroPlane:Boolean;
	// is chart enabled currently
	private var chartEnabled:Boolean;
	// is chart best fitted currently
	private var bestFitted:Boolean;
	// if any link provided at all
	private var linksGiven:Boolean;
	//
	//Redraw specific restoration object
	private var objRedrawBackup:Object;
	//Resizing pending or not
	private var resizePending:Boolean;
	
	/**
	 * Chart3D class constructor called originally
	 */
	function Chart3D(targetMC:MovieClip, depth:Number, width:Number, height:Number, x:Number, y:Number, debugMode:Boolean, lang:String, _scaleMode:String, _registerWithJS:Boolean, _DOMId:String) {
		//Invoke the super class constructor
		super(targetMC, depth, width, height, x, y, debugMode, lang, _scaleMode, _registerWithJS, _DOMId);
		// containers initialised
		this.objMultiData = {};
		this.config.linkMode = false;
		this.arrZeroPlanes = [];
		this.chartEnabled = false;
		this.bestFitted = false;
		this.stageUpdated = false;
		//
		this.redrawing = false;
		this.resizePending = false;
		
		//
		this.objLastAngs = (this.params.animate3D) ? {xAng:this.params.endAngX, yAng:this.params.endAngY} : {xAng:this.params.cameraAngX, yAng:this.params.cameraAngY};
		//Expose functionalities to JS. 
		if (this.registerWithJS == true && ExternalInterface.available) {
			// to view 2D
			ExternalInterface.addCallback("view2D", this, JSview2D);
			// to view at last 3D angles
			ExternalInterface.addCallback("view3D", this, JSview3D);
			// to reset view to initial angles
			ExternalInterface.addCallback("resetView", this, JSresetView);
			// to rotate view to provided angles
			ExternalInterface.addCallback("rotateView", this, JSrotateView);
			// to get the current view angles
			ExternalInterface.addCallback("getViewAngles", this, JSgetCamAngles);
			// to get the current view angles
			ExternalInterface.addCallback("fitToStage", this, JSanimateToScaleFit);
			// to get the 100% view
			ExternalInterface.addCallback("view100Percent", this, JSanimateTo100Percent);
		}
		//Add external Interface APIs exposed by this chart
		extInfMethods += ",view2D,view3D,resetView,rotateView,getViewAngles,fitToStage";
		
		//setting watch on flag holding state of dimension change
		this.watch('chartEnabled', checkResizePendingForChartEnabled, this);
		
	}
	
	/**
	 * checkResizePendingForChartEnabled method responds on change in flag
	 * for chart enabling to check if resizing is on hold and be initiated 
	 * now.
	 * @params	prop		property watched
	 * @params	oldVal		old value of the property
	 * @params	newVal		new value of the property
	 * @returns				the new value
	 */
	private function checkResizePendingForChartEnabled(prop:String, oldVal:Boolean, newVal:Boolean, insRef:Chart3D):Boolean{
		//if new value for the flag is true indicating chart is enabled
		if(newVal && !oldVal){
			//if resize is pending
			if(insRef.resizePending){
				//call to render with params indicating that its resizing and is a late call.
				insRef.resizePending = false;
				insRef.reInit(true, true);
				insRef.render(true, true);
			}
		}
		return newVal;
	}
	/**
	 * storeDataForRedraw method is called during resizing prior to resizing
	 * process is on, to store certain current states of the chart to be used
	 * later after resizing is over, to maintain chart states.
	 */
	private function storeDataForRedraw():Void{
		//Object to store data in
		objRedrawBackup = {};
		//User triggered animation specific last angles
		objRedrawBackup.objLastAngs = this.objLastAngs;
		//Animation params
		objRedrawBackup.animation = this.params.animation;
		objRedrawBackup.animate3D = this.params.animate3D;
		//Camera angles
		objRedrawBackup.cameraAngX = this.params.cameraAngX;
		objRedrawBackup.cameraAngY = this.params.cameraAngY;
		//Autoscaling option
		objRedrawBackup.autoScaling = this.params.autoScaling;
		
		if(!this.params.worldLighting){
			//Get lighting angles from 3D engine
			var objLightAngs:Object = this.system3D.getLightAngs();
			objRedrawBackup.lightAngX = objLightAngs.xAng;
			objRedrawBackup.lightAngY = objLightAngs.yAng;
		}
		//To store the data states, to match with legend items' states
		var arrLgndItemStates:Array = [];
		var num:Number = this.dataset.length;
		//Iterating over each data item
		for(var i:Number = 1; i<num; ++i){
			//Storing the current showValues state for the dataset
			arrLgndItemStates[i] = this.dataset[i].showValues;
		}
		//Store it
		objRedrawBackup.arrLgndItemStates = arrLgndItemStates;
	}
	/**
	 * setDataForRedraw method is called to set caertain data in chart 
	 * prior to redrawing, facilitating chart state management.
	 */
	private function setDataForRedraw():Void{
		//Blocking initial animation for its resizing
		this.params.animation = false;
		this.params.animate3D = false;
		//Restoring previous last view angles
		var objAngs:Object = this.system3D.getCameraAngs();
		this.params.cameraAngX = objAngs.xAng;
		this.params.cameraAngY = objAngs.yAng;
		//Restoring last menu driven animation angles to revert back to.
		this.objLastAngs = objRedrawBackup.objLastAngs;
		//
		if(!this.params.worldLighting){
			this.params.lightAngX = objRedrawBackup.lightAngX;
			this.params.lightAngY = objRedrawBackup.lightAngY;
		}
		
		var arrLgndItemStates:Array = objRedrawBackup.arrLgndItemStates;
		var num:Number = this.dataset.length;
		//Iterating to set data specific state w.r.t. legend item interactivity.
		for(var i:Number = 1; i<num; ++i){
			this.dataset[i].showValues = arrLgndItemStates[i];
		}
	}
	
	/**
	 * restoreDataPostRedraw method is called to restore back certain data to chart
	 * after resizing is over, to facilitate seamless charting experience.
	 */
	private function restoreDataPostRedraw():Void{
		//Checking if method be called post resize
		if(this.redrawing){
			//Flag to false to indicate resizing process is over
			this.redrawing = false;
		}else{
			//The method shouldn't proceed further if not called post resize
			return;
		}
		//Restore animation params
		this.params.animation = objRedrawBackup.animation;
		this.params.animate3D = objRedrawBackup.animate3D;
		//Canmera angles
		this.params.cameraAngX = objRedrawBackup.cameraAngX;
		this.params.cameraAngY = objRedrawBackup.cameraAngY;
		//Autoscaling
		this.params.autoScaling = objRedrawBackup.autoScaling;
		
	}
	
	
	/**
	* render method is the single call method that does the rendering of chart:
	* - Parsing XML
	* - Calculating values and co-ordinates
	* - Visual layout and rendering
	* - Event handling
	* @param	isRedraw	is it to resize
	* @param	lateCall	is this a late resize call
	*/
	public function render(isRedraw:Boolean, lateCall:Boolean):Void {
		//Is resizing pending
		if(this.resizePending){
			return;
		}
		
		//Parse the XML Data document
		this.parseXML();
		
		//If it's a re-draw then set certain related data
		if (isRedraw){
			this.setDataForRedraw();
		}
		
		
		//Now, if the number of data elements is 0, we show pertinent
		//error.
		if (this.numDS*this.num*this.numData == 0) {
			tfAppMsg = this.renderAppMessage(_global.getAppMessage("NODATA", this.lang));
			//Add a message to log.
			this.log("No Data to Display", "No data was found in the XML data document provided. Possible cases can be: <LI>There isn't any data generated by your system. If your system generates data based on parameters passed to it using dataURL, please make sure dataURL is URL Encoded.</LI><LI>You might be using a Single Series Chart .swf file instead of Multi-series .swf file and providing multi-series data or vice-versa.</LI>", Logger.LEVEL.ERROR);
			//Also raise the no data event
			if (!isRedraw){
				this.raiseNoDataExternalEvent();
			}
		} else {
			// validate "clustered" setting
			this.validateClustered();
			// validate dataset
			this.validateDataset();
			//Detect number scales
			this.detectNumberScales();
			//Calculate the axis limits
			this.calculateAxisLimits();
			//Calculate exact number of div lines
			this.calcDivs();
			//Set Style defaults
			this.setStyleDefaults();
			//Validate trend lines
			this.validateTrendLines();
			//Allot the depths for various charts objects now
			this.allotDepths();
			//Calculate Points
			this.calculatePoints();
			//Calculate vLine Positions
			this.calcVLinesPos();
			//Calculate trend line positions
			this.calcTrendLinePos();
			//Feed macro values
			super.feedMacros();
			//Remove application message
			this.removeAppMessage(this.tfAppMsg);
			//Set tool tip parameter
			this.setToolTipParam();
			//-----Start Visual Rendering Now------//
			//Draw background
			this.drawBackground();
			//Set click handler
			this.drawClickURLHandler();
			//Load background SWF
			this.loadBgSWF();
			//Update timer
			this.timeElapsed = (this.params.animation) ? this.styleM.getMaxAnimationTime(this.objects.BACKGROUND) : 0;
			//Draw headers
			this.config.intervals.headers = setInterval(Delegate.create(this, drawHeaders), this.timeElapsed);
			//Legend
			this.config.intervals.legend = setInterval(Delegate.create(this, drawLegend), this.timeElapsed);
			//Update timer
			this.timeElapsed += (this.params.animation) ? this.styleM.getMaxAnimationTime(this.objects.CAPTION, this.objects.SUBCAPTION, this.objects.LEGEND) : 0;
			// draw chart 3D
			this.config.intervals.chart3D = setInterval(Delegate.create(this, drawChart3D), this.timeElapsed);
		}
	}
	/**
	* reInit method re-initializes the chart. This method is basically called
	* when the user changes chart data through JavaScript. In that case, we need
	* to re-initialize the chart, set new XML data and again render.
	* @param	isRedraw	is it to resize
	* @param	lateCall	is this a late resize call
	*/
	public function reInit(isRedraw:Boolean, lateCall:Boolean):Void {
		//If resizing and not a late call
		if(isRedraw && !lateCall){
			//If chart is not enabled, we can't resize
			if(!chartEnabled){
				//So, set resize as pending which leads to late call for resizing as and when chart gets enabled.
				this.resizePending = true;
				//Abort the method call.
				return;
			}
		}
		//If resizing
		if(isRedraw){
			//Set flag to indicate resizing process is on
			this.redrawing = true;
			//Store back some data prior to resize
			this.storeDataForRedraw();
		}
		
		
		//Invoke super class's reInit
		super.reInit();
		//Now initialize things that are pertinent to this class
		//but not defined in super class.
		this.arrZeroPlanes = [];
		this.objMultiData = {};
		//
		this.objLastAngs = (this.params.animate3D) ? {xAng:this.params.endAngX, yAng:this.params.endAngY} : {xAng:this.params.cameraAngX, yAng:this.params.cameraAngY};
		this.objEventHandler = null;
		//
		this.arrToolTipMap = null;
		this.arrSeries = null;
		//
		this.config.linkMode = false;
		//
		this.chartEnabled = false;
		this.bestFitted = false;
		this.stageUpdated = false;
		this.initiated = null;
		this.rendered = null
		this.isMouseDown = null;
		this.zeroPlane = null;
		//
		this.zOrigin = null;
		this.xmouse = null;
		this.ymouse = null;
		//
		this.resizePending = false;
	}
	/**
	* remove method removes the chart by clearing the chart movie clip
	* and removing any listeners.
	*/
	public function remove():Void {
		// invoke remove method of super class
		super.remove();
		// destroy Engine instance
		this.system3D.destroy();
		// delete reference of Engine instance
		delete this.system3D;
		// remove the chart container
		this.mcChart.removeMovieClip();
		// clear mouse interactivity
		Mouse.removeListener(this.mouseListener);
	}
	/**
	* allotDepths method allots the depths for various chart objects
	* to be rendered. We do this before hand, so that we can later just
	* go on rendering chart objects, without swapping.
	*/
	private function allotDepths():Void {
		//Background
		this.dm.reserveDepths("BACKGROUND", 1);
		//Click URL Handler
		this.dm.reserveDepths("CLICKURLHANDLER", 1);
		//Background SWF
		this.dm.reserveDepths("BGSWF", 1);
		// if param attribute is false
		if (!this.params.chartOnTop) {
			//chart3D Plot
			this.dm.reserveDepths("CHART3D", 1);
		}
		//Caption                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     
		this.dm.reserveDepths("CAPTION", 1);
		//Sub-caption
		this.dm.reserveDepths("SUBCAPTION", 1);
		//Legend
		this.dm.reserveDepths("LEGEND", 1);
		// if param attribute is true
		if (this.params.chartOnTop) {
			//chart3D Plot
			this.dm.reserveDepths("CHART3D", 1);
		}
	}
	//------------------------------ CHART MAKER --------------------------------//
	/**
	 * drawChart3D method is the primary one which arrange
	 * for and renders the chart via Engine instantiation.
	 */
	private function drawChart3D():Void {
		// trim of unnecessary trendlines
		this.validateTLines();
		// if rotation not allowed
		if (!this.params.allowRotation) {
			// set chart to link mode
			this.config.linkMode = true;
		}
		// starting z-origin value                                                          
		this.zOrigin = this.params.zGapPlot;
		// stage and axes metrics
		var objStage:Object = this.getStageParams();
		// axes plus params
		var objAxesPlus:Object = this.getAxesPlusParams();
		// label rendering params
		var objLabels:Object = this.getLabelsParams();
		// animation params
		var objAnimation:Object = this.getAnimationParams();
		// camera angles
		var objCam:Object = this.getCameraParams();
		// light params
		var objLight:Object = this.getLightParams();
		// text formatting params
		var objLabelProp:Object = this.getTextFormattingParams();
		// axes wall depths
		var arrAxesWallDepths:Array = this.getAxesWallDepths();
		// axes label gaps
		var arrLabelDistances:Array = this.getLabelDistances();
		// axes names
		var objAxesNames:Object = {xAxisName:this.params.xAxisName, yAxisName:this.params.yAxisName};
		//
		//-----------  AXES  -------------//
		// container for axes cosmetics
		var objAxesCosmetics:Object = {};
		// primary color
		objAxesCosmetics.axesColor = parseInt(this.params.canvasBgColor, 16);
		// alternate color
		objAxesCosmetics.alternateHGridColor = this.params.alternateHGridColor;
		// if HGrid be shown
		objAxesCosmetics.showAlternateHGridColor = this.params.showAlternateHGridColor;
		// effect of divLines
		objAxesCosmetics.divLineEffect = this.params.divLineEffect;
		//----------- Zero Plane ----------//
		// container for zero plane cosmetics
		var objZeroPlane:Object = {};
		// color
		objZeroPlane.color = this.params.zeroPlaneColor;
		// opacity
		objZeroPlane.alpha = this.params.zeroPlaneAlpha;
		// thickness
		objZeroPlane.thickness = this.params.zeroPlaneThickness;
		// mesh or plane
		objZeroPlane.mesh = this.params.zeroPlaneMesh;
		//------------- MISC ------------//
		// container for miscellaneous data
		var objMisc:Object = {};
		// if plot border be shown
		objMisc.dataPlotBorder = this.params.showPlotBorder;
		// if columns be clustered
		objMisc.clustered = this.config.clustered;
		//------------ PLOT -------------//
		// arrange series specific data conglomerates for stack sorting
		this.setPlotData();
		// sort stack
		this.sortCategory(this.arrSeries);
		// sorted data labels
		var arrDataLabels:Array = this.setDataItemLabels();
		// sorted data values
		var arrDataValues:Array = this.setDataValues();
		// data item plotting metrics for modelling
		this.objMultiData.arrPlot = [];
		// base color for each chart series
		this.objMultiData.arrColors = [];
		// tooltip values for data items
		this.objMultiData.arrToolTips = [];
		// axes name label positions
		this.objMultiData.arrAxesNamesPlot = this.getAxisNamePos();
		// chart series types
		this.objMultiData.arrCategory = this.getCategories(this.arrSeries);
		// label positions
		this.objMultiData.arrDataLabelsPlot = [];
		// go for data modelling
		this.setDataModel(this.config.clustered);
		// preparet the tooltip mapping
		this.setToolTipMap(this.objMultiData.arrPlot, this.arrSeries);
		// series whose data values be shown initially
		var arrActiveDataLabels:Array = this.getActiveDataLabels();
		//-----------------------------//
		// level of chart container MC
		var depth:Number = this.dm.getDepth("CHART3D");
		// chart container created
		this.mcChart = this.cMC.createEmptyMovieClip('mcChart', depth);
		// position set
		this.mcChart._x = objStage.x;
		this.mcChart._y = objStage.y;
		// Engine instantiated passing a host params
		this.system3D = new Engine(this.mcChart, objCam, objLight, objMultiData, objStage, objAnimation, objAxesCosmetics, objAxesPlus, objLabels, objLabelProp, arrDataLabels, arrDataValues, arrAxesWallDepths, arrLabelDistances, objAxesNames, this.arrZeroPlanes, objZeroPlane, arrActiveDataLabels, objMisc);
		//-----------------------------//
		// program the event dispatching model                                                          
		this.setEventDispatch();
		// post creation control:
		// for initial animatation
		if (this.params.animate3D) {
			// disable chart from any interactivity of user till initial animation ends
			this.chartEnabled = false;
			// go for initial animation
			this.system3D.iniAnimate();
		} else {
			// else, for non-animated initial appearance
			// render the chart
			this.system3D.recreate();
			// best fit in stage
			this.system3D.scaleToFitInit();
			// flag update to indicate that its best fitted
			this.bestFitted = true;
			// programm the tooltip interactivity
			this.setToolTipInteractions();
			// enable the chart for user interactivity
			this.chartEnabled = true;
			//
			this.initStatus = 2;
			this.exposeChartRendered();
			this.restoreDataPostRedraw();
		}
		//--------------------//  
		// program other interactivities like for rotation of chart
		this.setInteractivity();
		if (!this.initiated) {
			// update flag that chart is initialised
			this.initiated = true;
		}
		// check for if any link is defined for the data items
		this.linksGiven = this.areLinksSupplied();
		// program the context menu
		this.setContextMenu();
		// clear the interval
		clearInterval(this.config.intervals.chart3D);
	}
	//------------------------------ SET PARAM METHODS --------------------------------//
	/**
	 * getTextFormattingParams method returns a bundle of
	 * text formats for various type of labels.
	 * @return		text formats bundled
	 */
	private function getTextFormattingParams():Object {
		// chart object ids for labels to be handled
		var arrTextObjects:Array = ['DATALABELS', 'XAXISNAME', 'YAXISNAME', 'DATAVALUES', 'TRENDVALUES', 'YAXISVALUES'];
		// container to hold a format
		var objtxtProps:Object;
		// container to hold the formats
		var objTextParams:Object = {};
		// iterate over the label types
		for (var i = 0; i<arrTextObjects.length; ++i) {
			// get the format for the label
			objtxtProps = this.styleM.getTextStyle(this.objects[arrTextObjects[i]]);
			// format the color
			objtxtProps['color'] = parseInt(objtxtProps['color'], 16);
			// insert the format
			objTextParams[arrTextObjects[i]] = objtxtProps;
		}
		// return the formats
		return objTextParams;
	}
	/**
	 * getStageParams method returns a number of chart stage
	 * and axes metrics.
	 * @return		the metrics bundled
	 */
	private function getStageParams():Object {
		// container to hold the metrics
		var objStage:Object = {};
		// stage position
		objStage.xStage = this.params.chartLeftMargin;
		objStage.yStage = this.elements.canvas.y;
		// factors for evaluating stage height
		var a:Number = (isNaN(this.config.labelAreaHeight) || !this.labelOn) ? 0 : this.config.labelAreaHeight;
		var b:Number = (isNaN(this.elements.xAxisName.h)) ? 0 : this.elements.xAxisName.h;
		var c:Number = (isNaN(this.params.labelPadding) || (!this.labelOn && this.params.yAxisName == "")) ? 0 : this.params.labelPadding;
		var d:Number = (isNaN(this.params.xAxisNamePadding)) ? 0 : this.params.xAxisNamePadding;
		// stage width and height
		objStage.stageWidth = this.width-(this.params.chartLeftMargin+this.params.chartRightMargin);
		objStage.stageHeight = this.elements.canvas.h+(a+b+c+d)+this.params.yzWallDepth;
		// axes width and height
		objStage.axesWidth = this.elements.canvas.w;
		objStage.axesHeight = this.elements.canvas.h;
		// axes position
		objStage.x = this.elements.canvas.x;
		objStage.y = this.elements.canvas.y;
		// return the metrics
		return objStage;
	}
	/**
	 * getAxesPlusParams method returns the axes plus 
	 * rendering parameters.
	 * @return		axes plus params
	 */
	private function getAxesPlusParams():Object {
		// position of zero on y-axis
		var yZero:Number = this.getAxisPosition((this.config.yMin>0) ? this.config.yMin : 0, this.config.yMax, this.config.yMin, this.elements.canvas.y, this.elements.canvas.toY, true, 0);
		// container to hold the axes plus params
		var objAxesPlus:Object = {};
		// divlines specific params
		objAxesPlus["HLines"] = [];
		for (var i = 0; i<this.divLines.length; ++i) {
			objAxesPlus["HLines"][i] = {};
			objAxesPlus["HLines"][i]['y'] = yZero-this.getAxisPosition(this.divLines[i].value, this.config.yMax, this.config.yMin, this.elements.canvas.y, this.elements.canvas.toY, true, 0);
			objAxesPlus["HLines"][i]['color'] = parseInt(this.params.divLineColor, 16);
			objAxesPlus["HLines"][i]['thickness'] = this.params.divLineThickness;
			objAxesPlus["HLines"][i]['alpha'] = this.params.divLineAlpha;
		}
		// trendlines specific params
		objAxesPlus["TLines"] = [];
		for (var i = 1; i<this.trendLines.length; ++i) {
			var j:Number = i-1;
			objAxesPlus["TLines"][j] = {};
			// left end
			objAxesPlus["TLines"][j]['y1'] = yZero-this.trendLines[i].y;
			// right end
			objAxesPlus["TLines"][j]['y2'] = yZero-this.trendLines[i].toY;
			objAxesPlus["TLines"][j]['color'] = parseInt(this.trendLines[i].color, 16);
			objAxesPlus["TLines"][j]['thickness'] = this.trendLines[i].thickness;
			objAxesPlus["TLines"][j]['alpha'] = this.trendLines[i].alpha;
		}
		// return the axes plus params
		return objAxesPlus;
	}
	/**
	 * getAxisNamePos method returns the positions of the
	 * axes name labels.
	 * @return		axes name label positions
	 */
	private function getAxisNamePos():Array {
		// container to hold the axes name label positions
		var arrAxesNamesPlot:Array = [];
		// x-axis name label position
		var xAxisNameX:Number = this.elements.canvas.x+(this.elements.canvas.w/2);
		var xAxisNameY:Number = this.elements.canvas.toY;
		// y-axis name label position
		var yAxisNameX:Number = this.params.chartLeftMargin;
		var yAxisNameY:Number = this.elements.canvas.y+(this.elements.canvas.h/2);
		//  insert the positions
		arrAxesNamesPlot.push([xAxisNameX, xAxisNameY], [yAxisNameX, yAxisNameY]);
		// return
		return arrAxesNamesPlot;
	}
	/**
	 * getLabelsParams method returns axes label positioning
	 * params.
	 * @return		positioning params
	 */
	private function getLabelsParams():Object {
		// position of zero on y-axis
		var yZero:Number = this.getAxisPosition((this.config.yMin>0) ? this.config.yMin : 0, this.config.yMax, this.config.yMin, this.elements.canvas.y, this.elements.canvas.toY, true, 0);
		// container to hold the label positioning params
		var objLabels:Object = {};
		// 
		objLabels["yLabels"] = [];
		for (var i = 0; i<this.divLines.length; ++i) {
			objLabels["yLabels"][i] = {};
			objLabels["yLabels"][i]['y'] = yZero-this.getAxisPosition(this.divLines[i].value, this.config.yMax, this.config.yMin, this.elements.canvas.y, this.elements.canvas.toY, true, 0);
			objLabels["yLabels"][i]['label'] = this.divLines[i].displayValue;
			objLabels["yLabels"][i]['showLabel'] = this.divLines[i].showValue;
			// set y axis tick line properties.
			objLabels["yLabels"][i]['yAxisTickColor'] = parseInt(this.params.divLineColor, 16);
			objLabels["yLabels"][i]['yAxisTickThickness'] = this.params.divLineThickness;
			objLabels["yLabels"][i]['yAxisTickAlpha'] = this.params.divLineAlpha;
		}
		//
		objLabels["xLabels"] = [];
		for (var i = 1; i<this.categories.length; ++i) {
			var j:Number = i-1;
			objLabels["xLabels"][j] = {};
			objLabels["xLabels"][j]['x'] = this.categories[i]['x']-this.elements.canvas.x;
			objLabels["xLabels"][j]['label'] = this.categories[i]['label'];
			objLabels["xLabels"][j]['showLabel'] = this.categories[i]['showLabel'];
		}
		//
		objLabels["tLabels"] = [];
		for (var i = 1; i<this.trendLines.length; ++i) {
			var j:Number = i-1;
			objLabels["tLabels"][j] = {};
			objLabels["tLabels"][j]['y1'] = yZero-this.trendLines[i].y;
			objLabels["tLabels"][j]['y2'] = yZero-this.trendLines[i].toY;
			objLabels["tLabels"][j]['label'] = this.trendLines[i].displayValue;
			objLabels["tLabels"][j]['valueOnRight'] = this.trendLines[i].valueOnRight;
			objLabels["tLabels"][j]['showLabel'] = true;
			// set tick line properties.
			objLabels["tLabels"][j]['tLineTickColor'] = parseInt(this.trendLines[i].color, 16);
			objLabels["tLabels"][j]['tLineTickThickness'] = this.trendLines[i].thickness;
			objLabels["tLabels"][j]['tLineTickAlpha'] = this.trendLines[i].alpha;
		}			
		// set tick line param according to xlabel 
		var tickLines:Object = {}
		tickLines['xAxisTickColor'] =  parseInt(this.params.xAxisTickColor, 16);
		tickLines['xAxisTickAlpha'] =  this.params.xAxisTickAlpha;
		tickLines['xAxisTickThickness'] =  this.params.xAxisTickThickness;
		objLabels.tickLines = tickLines;
		return objLabels;
	}
	/**
	 * getAnimationParams method returns rotational animation
	 * controlling params.
	 * @return		animation params
	 */
	private function getAnimationParams():Object {
		// conatiner to hold the animation params
		var objAnimation:Object = {};
		// if chart be animated initially
		objAnimation.animate = this.params.animate3D;
		// animation execution time (in ms)
		objAnimation.exeTime = this.params.exeTime;
		// starting initial animation angles
		objAnimation.startAngX = this.params.startAngX;
		objAnimation.startAngY = this.params.startAngY;
		// ending initial animation angles
		objAnimation.endAngX = this.params.endAngX;
		objAnimation.endAngY = this.params.endAngY;
		// return
		return objAnimation;
	}
	/**
	 * getCameraParams method returns initial camera angles
	 * for no initial animation.
	 * @return 		camera angles
	 */
	private function getCameraParams():Object {
		var objCam:Object = {};
		objCam.angX = this.params.cameraAngX;
		objCam.angY = this.params.cameraAngY;
		return objCam;
	}
	/**
	 * getLightParams method returns lighting params.
	 * @return		lighting params
	 */
	private function getLightParams():Object {
		// container to hold lighting params
		var objLight:Object = {};
		// initial lighting angles
		objLight.lightAngX = this.params.lightAngX;
		objLight.lightAngY = this.params.lightAngY;
		// intensity of light
		objLight.intensity = this.params.intensity;
		// world lighting or not
		objLight.worldLighting = this.params.worldLighting;
		// if bright 2D view required
		objLight.bright2D = this.params.bright2D;
		// returns
		return objLight;
	}
	/**
	 * getAxesWallDepths method returns axes wall depths
	 * or thicknesses.
	 * @return		axes wall depths
	 */
	private function getAxesWallDepths():Array {
		return [this.params.yzWallDepth, this.params.zxWallDepth, this.params.xyWallDepth];
	}
	/**
	 * getLabelDistances method returns axes label gaps.
	 * @return		axes label gaps from axes edges
	 */
	private function getLabelDistances():Array {
		// container to hold the gaps
		var arrParams:Array = [];
		// gap of axes labels
		arrParams['xlabelGap'] = this.params.xGapLabel;
		arrParams['ylabelGap'] = this.params.yGapLabel;
		// gap of axes name labels
		arrParams['xAxisNameGap'] = this.params.xAxisNamePadding;
		arrParams['yAxisNameGap'] = this.params.yAxisNamePadding;
		// returns
		return arrParams;
	}
	/**
	 * getActiveDataLabels method returns flags for each 
	 * series to indicate if its data value labels be shown
	 * initially.
	 * @return 		data value label display flags for series
	 */
	private function getActiveDataLabels():Array {
		// container to hold the flags
		var arrActiveDataLabels:Array = [];
		// iterate over each series
		for (var i = 0; i<this.arrSeries.length; ++i) {
			// if data value labels be shown for the series
			if (this.arrSeries[i]['showValues']) {
				// insert the series id
				arrActiveDataLabels.push(i);
			}
		}
		// return
		return arrActiveDataLabels;
	}
	/**
	 * getToolTips method returns tooltips for each series.
	 * @return		tooltip texts for each series
	 */
	private function getToolTips():Array {
		// container for tooltips 
		var arrToolTip:Array = [];
		var chartType:String, arrData:Array;
		// iterate over each series
		for (var i = 1; i<this.dataset.length; ++i) {
			// chart type
			chartType = this.dataset[i].renderAs;
			// alias of current blank container created to hold the tooltips for the series
			arrData = arrToolTip[i]=[];
			// iterate over each data item in the series
			for (var j = 1; j<this.dataset[i]["data"].length; ++j) {
				// the tool tip text for the data item
				var tTip:String = (!isNaN(this.dataset[i]["data"][j]['value'])) ? this.dataset[i]["data"][j]['toolText'] : "";
				// insert the tooltip in container
				arrData.push(tTip);
			}
		}
		// return
		return arrToolTip;
	}
	/**
	 * getLinks method returns all links in the chart.
	 * @return		all links in the chart (series wise)
	 */
	private function getLinks():Array {
		// conatiner for the links
		var arrLinks:Array = [];
		// iterate over each series
		for (var i = 1; i<this.dataset.length; ++i) {
			// sub-container for links in the series 
			arrLinks[i] = [];
			// iterate over each data item in the series
			for (var j = 1; j<this.dataset[i]["data"].length; ++j) {
				// insert the link
				arrLinks[i].push(this.dataset[i]["data"][j]["link"]);
			}
		}
		// return
		return arrLinks;
	}
	/**
	 * getDataValues method returns the data item values
	 * from original repository.
	 * @return 		all data item values
	 */
	private function getDataValues():Array {
		// container for data item values
		var arrValues:Array = [];
		// iterate over each series
		for (var i = 1; i<this.dataset.length; ++i) {
			// sub-container for data item values in the series
			arrValues[i] = [];
			// iterate over each data item
			for (var j = 1; j<this.dataset[i]["data"].length; ++j) {
				// the data item value inserted
				arrValues[i].push(this.dataset[i]["data"][j]["value"]);
			}
		}
		// return
		return arrValues;
	}
	/**
	 * setDataValues method returns z-sorted data item values.
	 * @return		sorted data item values
	 */
	private function setDataValues():Array {
		// container for data item values
		var arrValues:Array = [];
		// iterate over each series
		for (var i = 0; i<this.arrSeries.length; ++i) {
			// data values for the series
			arrValues[i] = this.arrSeries[i]['arrDataValues'];
		}
		// reeturn
		return arrValues;
	}
	/**
	 * getDataItemLabels method returns data item labels from
	 * original repository.
	 * @return		data item labels
	 */
	private function getDataItemLabels():Array {
		// container to hold data item labels
		var arrLabels:Array = [];
		// iterate over each series
		for (var i = 1; i<this.dataset.length; ++i) {
			// sub-container for the series
			arrLabels[i] = [];
			// local reference of the series data
			var arrData:Array = this.dataset[i]["data"];
			// iterate over each data item
			for (var j = 1; j<arrData.length; ++j) {
				// data item label
				var objLabelData:Object = {value:arrData[j]["value"], labelValue:arrData[j]["displayValue"], showLabel:arrData[j]["showLabel"]};
				// insert it
				arrLabels[i].push(objLabelData);
			}
		}
		// return
		return arrLabels;
	}
	/**
	 * setDataItemLabels method returns z-sorted data item 
	 * labels.
	 * @return		sorted data item labels
	 */
	private function setDataItemLabels():Array {
		// container for data item labels
		var arrLabels:Array = [];
		// iterate over each series
		for (var i = 0; i<this.arrSeries.length; ++i) {
			// data labels for the series
			arrLabels[i] = this.arrSeries[i]['arrDataLabels'];
		}
		// return
		return arrLabels;
	}
	/**
	 * validateTLines method strips off not applicable trendlines.
	 */
	private function validateTLines():Void {
		var startValue:Number, endValue:Number;
		// extremes of y-axis
		var yMax:Number = this.config.yMax;
		var yMin:Number = this.config.yMin;
		// iterate over all trendlines
		for (var i = 1; i<this.trendLines.length; i++) {
			// start y-value of the trendline
			startValue = this.trendLines[i]['startValue'];
			// end y-value of the trendline
			endValue = this.trendLines[i]['endValue'];
			// if the starting and ending values are outside the valid range of chart y-axis
			if (startValue>yMax || startValue<yMin || endValue>yMax || endValue<yMin) {
				// remove the entry
				this.trendLines.splice(i, 1);
			}
		}
	}
	/**
	 * areLinksSupplied method returns a flag to indicate
	 * that links are at all provided for data items or not.
	 * @return		flag that links provided
	 */
	private function areLinksSupplied():Boolean {
		// number of series
		var num:Number = this.arrSeries.length;
		// iterate over each series
		for (var i = 0; i<num; ++i) {
			// local reference of the series data
			var arrSeriesData:Array = this.arrSeries[i];
			// number of data items in the series
			var num1:Number = arrSeriesData['arrLinks'].length;
			// iterate over each data item
			for (var j = 0; j<num1; ++j) {
				// checking for a valid link
				if (arrSeriesData['arrLinks'][j] != undefined && arrSeriesData['arrLinks'][j] != "") {
					// return that atleast one link is there in the chart for the data items
					return true;
				}
			}
		}
		// return that no link found in the chart data items
		return false;
	}
	//------------------------------ SET DATA STRUCTURE --------------------------------//
	/**
	 * setPlotData method arrange for z-sorting of series data
	 * prior to modelling of data items. The sorting helps for
	 * other data management like tooltip, labels etc.
	 * 
	 */
	private function setPlotData() {
		// getting various data from original repository
		// tooltip for data items
		var arrToolTips:Array = this.getToolTips();
		// data item labels
		var arrDataLabels:Array = this.getDataItemLabels();
		// data item values
		var arrDataValues:Array = this.getDataValues();
		// links for data items
		var arrLinks:Array = this.getLinks();
		// position of zero on y-axis
		var yZero:Number = this.getAxisPosition((this.config.yMin>0) ? this.config.yMin : 0, this.config.yMax, this.config.yMin, this.elements.canvas.y, this.elements.canvas.toY, true, 0);
		var includeInLegend:Boolean, seriesName:String;
		var variableLength:Number;
		// the container to fill in all data to be used in sorting process
		this.arrSeries = [];
		// variables declared
		var num:Number, color:Number, type:String, arrModelData:Array, arrSubData:Array, showValues:Boolean;
		var arrSubLabels:Array, arrSubLinks:Array, arrSubValues:Array, arrSubToolTip:Array;
		// iterate over each series
		for (var i = 1; i<this.dataset.length; ++i) {
			// series chart type
			type = this.dataset[i]["renderAs"];
			// series base color
			color = parseInt(this.dataset[i]["color"], 16);
			// number of data items in the series (one relative index in framework code)
			num = this.dataset[i]["data"].length-1;
			// if this series be included in the legend
			includeInLegend = this.dataset[i].includeInLegend;
			// series name
			seriesName = this.dataset[i].seriesName;
			// if data item labels be shown initially
			showValues = this.dataset[i].showValues;
			// series specific data item labels
			arrSubLabels = arrDataLabels[i];
			// series specific data item links
			arrSubLinks = arrLinks[i];
			// series specific data item values
			arrSubValues = arrDataValues[i];
			// series specific data item tooltips
			arrSubToolTip = arrToolTips[i];
			//-----------------//
			// container to hold data required to model the data items
			arrModelData = [];
			// set data for modelling .. iterate over each data
			for (var j = 1; j<this.dataset[i]["data"].length; ++j) {
				// local reference of data item specific data from original repository
				arrSubData = this.dataset[i]["data"][j];
				//  data inserted are x,y,w,h, i.e. starting position, width and height
				arrModelData.push({x:arrSubData["x"]-this.elements.canvas.x, y:yZero-arrSubData["y"], w:arrSubData["w"], h:arrSubData["h"]});
			}
			// if chart type is either LINE or AREA and null data item be managed
			if (this.params.connectNullData && type != 'COLUMN') {
				// array length initialed; its variable since the array is worked on in the loop
				variableLength = arrModelData.length;
				// iterate over each data item
				for (var m = 0; m<variableLength; ++m) {
					// for invalid item data 
					if (isNaN(arrModelData[m]['y'])) {
						// just shift those data be managed to the end of the series
						// model data
						arrModelData.push((arrModelData.splice(m, 1))[0]);
						// data item label
						arrSubLabels.push((arrSubLabels.splice(m, 1))[0]);
						// data item value
						arrSubValues.push((arrSubValues.splice(m, 1))[0]);
						// tooltips
						arrSubToolTip.push((arrSubToolTip.splice(m, 1))[0]);
						// links
						arrSubLinks.push((arrSubLinks.splice(m, 1))[0]);
						// decrement loop counter by one so that next time loop runs with the same value as now; this
						// is required since the next array element have come ahead by one step
						m--;
						// the element displaced to the array end is null data and need not work upon; so decrement
						// effective array length
						variableLength--;
					}
				}
			}
			// rearrangement of data structure for null COLUMN data    
			if (type == 'COLUMN') {
				// array length initialed; its variable since the array is worked on in the loop
				variableLength = arrModelData.length;
				// iterate over each data item
				for (var m = 0; m<variableLength; ++m) {
					// for invalid item data 
					if (isNaN(arrModelData[m]['h'])) {
						// just shift those data be managed to the end of the series
						// model data
						arrModelData.push((arrModelData.splice(m, 1))[0]);
						// data item label
						arrSubLabels.push((arrSubLabels.splice(m, 1))[0]);
						// data item value
						arrSubValues.push((arrSubValues.splice(m, 1))[0]);
						// links
						arrSubLinks.push((arrSubLinks.splice(m, 1))[0]);
						// tooltips
						arrSubToolTip.push((arrSubToolTip.splice(m, 1))[0]);
						// decrement loop counter by one so that next time loop runs with the same value as now; this
						// is required since the next array element have come ahead by one step
						m--;
						// the element displaced to the array end is null data and need not work upon; so decrement
						// effective array length
						variableLength--;
					}
				}
			}
			// --------------------//                                                           
			// sub-container to hold all series specific data
			var arrSeriesData:Array = [];
			// series specific param
			arrSeriesData['num'] = num;
			arrSeriesData['color'] = color;
			arrSeriesData['type'] = type;
			arrSeriesData['includeInLegend'] = includeInLegend;
			arrSeriesData['seriesName'] = seriesName;
			arrSeriesData['showValues'] = showValues;
			// data conglomerates for data items in the series
			arrSeriesData['arrData'] = arrModelData;
			arrSeriesData['arrLinks'] = arrSubLinks;
			arrSeriesData['arrDataLabels'] = arrSubLabels;
			arrSeriesData['arrDataValues'] = arrSubValues;
			arrSeriesData['arrToolTips'] = arrSubToolTip;
			// insert the series data with that of others
			this.arrSeries.push(arrSeriesData);
		}
	}
	/**
	 * setToolTipMap method is called to map mouse-tip interaction
	 * in 3D space to display tooltip text and/or access the links.
	 * @param	arrDataPlot3D	3D model vertices
	 * @param	arrDataSeries	conglomerate of various data for 
	 *							each series
	 */
	private function setToolTipMap(arrDataPlot3D:Array, arrDataSeries:Array):Void {
		// x adjustment value
		var addX:Number = 0;
		// container of the map
		this.arrToolTipMap = [];
		// for column clustering
		if (this.config.clustered) {
			// initialised to 0 (count of column series)
			var colSeriesId:Number = 0;
		}
		// number of series                                            
		var numSeries:Number = arrDataPlot3D.length;
		// iterate over each series
		for (var i = 0; i<numSeries; ++i) {
			// for clustering
			if (this.config.clustered) {
				// if this series is a COLUMN
				if (arrDataSeries[i]['type'] == 'COLUMN') {
					// update counter
					colSeriesId++;
				}
			}
			// sub-container for series specific map                                                                                                                                                                                                                                                                                                                       
			this.arrToolTipMap[i] = [];
			// local reference of the series model
			var arrTheSeries:Array = arrDataPlot3D[i];
			// get the z-extremeties of the series
			var objZRange:Object = this.getZRange(arrTheSeries);
			// store the z-extremities, for chart use for showing tooltip after due evaluation
			this.arrToolTipMap[i]['zRange'] = [];
			this.arrToolTipMap[i]['zRange']['zMin'] = objZRange['min'];
			this.arrToolTipMap[i]['zRange']['zMax'] = objZRange['max'];
			// container to store the x-extremities, for chart use for showing tooltip after due evaluation 
			this.arrToolTipMap[i]['xRange'] = [];
			// getting the 2D plotting params for the series
			var arrSeriesData2D:Array = arrDataSeries[i]['arrData'];
			// number of data items in the series
			var numSeriesElements:Number = arrSeriesData2D.length;
			var a:Number, b:Number, w:Number;
			// gap between 2 consecutive defined points for LINE or AREA
			w = this.config.lineSegmentWidth;
			// iterate over each data item
			for (var j = 0; j<numSeriesElements; ++j) {
				// sub-container for x-extremities for the data item
				this.arrToolTipMap[i]['xRange'][j] = [];
				// checking for chart type 
				switch (arrDataSeries[i]['type']) {
					// for LINE and AREA
				case 'AREA' :
				case 'LINE' :
					// for null data be managed
					if (this.params.connectNullData) {
						a = arrSeriesData2D[j]['x']-w/2;
						b = a+w;
					} else {
						// for first data item
						if (j == 0) {
							a = arrSeriesData2D[0]['x'];
							b = a+w/2;
							// caring the approximating issue
							a -= arrSeriesData2D[0]['x']/2;
						} else {
							// for in between data items
							a = b;
							b += w;
						}
						// for the last data item
						if (j == numSeriesElements-1) {
							// caring the approximating issue
							b += arrSeriesData2D[0]['x']/2;
						}
						// for singleton data  
						if (arrDataSeries[i]['num'] == 1) {
							b += w;
						}
					}
					break;
				case 'COLUMN' :
					// not in use currently
					// seriesId and blockId 
					a = arrSeriesData2D[j]['x']-arrSeriesData2D[j]['w']/2;
					b = arrSeriesData2D[j]['x']+arrSeriesData2D[j]['w']/2;
					// for clustering
					if (this.config.clustered) {
						if (colSeriesId == 1) {
							a -= addX/2;
						} else if (colSeriesId == this.numColDS) {
						} else {
						}
						//
						if (colSeriesId == this.numColDS) {
							b += addX/2;
						} else if (colSeriesId == 1) {
						} else {
						}
					} else {
						// caring the approximating issue 
						a -= addX/2;
						// caring the approximating issue
						b += addX/2;
					}
					break;
				}
				// data item x min
				this.arrToolTipMap[i]['xRange'][j]['xMin'] = a;
				// data item x max
				this.arrToolTipMap[i]['xRange'][j]['xMax'] = b;
				// the tooltip text
				this.arrToolTipMap[i]['xRange'][j]['tooltip'] = arrDataSeries[i]['arrToolTips'][j];
				// the link
				this.arrToolTipMap[i]['xRange'][j]['link'] = arrDataSeries[i]['arrLinks'][j];
			}
		}
	}
	/**
	 * evalToolTip method is call whenever mouse hovers over 
	 * the data items and returns the required entry for chart
	 * use.
	 * @param	arrData		3D data model of the MC under mouse
	 * @param	isLink		if link be returned
	 * @return 				tooltip text or link whichever required
	 */
	private function evalToolTip(arrData:Array, isLink:Boolean):String {
		// if mouse is over a COLUMN
		if (arrData['isColumn']) {
			// type of data to return - link or tooltip
			var returnDataType:String = (isLink) ? 'arrLinks' : 'arrToolTips';
			// return it
			return this.arrSeries[arrData[0]][returnDataType][arrData[1]];
		}
		// if a LINE or AREA                                           
		// x and z coordinate values 3D point under the mouse pointer
		var x:Number = arrData[0];
		var z:Number = arrData[2];
		// local reference of the map
		var arrToolData:Array = this.arrToolTipMap;
		// number of series
		var dataLength:Number = arrToolData.length;
		// iterate for each series
		for (var i = 0; i<dataLength; ++i) {
			// check to match the "z" value to ascertain to series under mouse
			if (arrToolData[i]['zRange']['zMin']<=z && arrToolData[i]['zRange']['zMax']>=z && z != undefined && !isNaN(z)) {
				// now seek for the particular data item under the mouse pointer using "x"
				// the x-extremities for all data items in the series
				var arrSubData:Array = arrToolData[i]['xRange'];
				// number of data items in the series
				var seriesDataLength:Number = arrSubData.length;
				// iterate for each data item
				for (var j = 0; j<seriesDataLength; ++j) {
					// check to match the "x" value to catch the data item under mouse
					if (arrSubData[j]['xMin']<=x && arrSubData[j]['xMax']>=x) {
						// return the required link or tooltip, as the case may be, for the matched data item
						return (isLink) ? arrSubData[j]['link'] : arrSubData[j]['tooltip'];
					}
				}
			}
		}
		// if none matched
		return '';
	}
	/**
	 * setDataModel method is called to initiate modelling
	 * of data items using z-sorted series data.
	 * @param	clustered	if columns be clustered
	 */
	private function setDataModel(clustered:Boolean):Void {
		// if zero plane be there
		this.zeroPlane = (this.config.yMax*this.config.yMin<0) ? true : false;
		// for clustering
		if (clustered) {
			// to store series ids associated with clustering start and end
			var clusterStart:Number, clusterEnd:Number;
			// number of series
			var lengthArr:Number = this.objMultiData.arrCategory.length;
			// iterate over each series to get start and end series id for clustering
			for (var i = 0; i<lengthArr; ++i) {
				// if series chart type is COLUMN
				if (this.objMultiData.arrCategory[i] == 'COLUMN') {
					// if clustering is yet to start
					if (clusterStart == undefined) {
						// start id
						clusterStart = i;
					}
					// if last series under process                                                     
					if (i == lengthArr-1) {
						// this is the end id
						clusterEnd = i;
					}
				} else {
					// else, if the current series is not a COLUMN
					// if clustering process already initiated
					if (clusterStart != undefined) {
						// this is the first non-COLUMN series and so clustering should end for the previous series
						// hence store the previous series id as the ending one
						clusterEnd = i-1;
						// clustering start and end ids obtained ... iteration should end
						break;
					}
				}
			}
			// flag to inidicate that clustering is done not; initialised to FALSE since modelling is yet to begin
			var clusterDone:Boolean = false;
			// iterate over each series to model its data items
			for (var i = 0; i<lengthArr; i++) {
				// chart type specific modelling
				switch (this.objMultiData.arrCategory[i]) {
				case 'AREA' :
				case 'LINE' :
					// model for AREA and LINE
					this.setOverlaidData(this.objMultiData.arrPlot, i, i);
					break;
				case 'COLUMN' :
					// if clustering not complete
					if (!clusterDone) {
						// model for COLUMNs clustered together 
						this.setClusteredData(this.objMultiData.arrPlot, clusterStart, clusterEnd);
						// update flag to indicate that model clustering is over
						clusterDone = true;
					}
					break;
				}
			}
		} else {
			// else, if no clustering in the chart
			// call to model all series
			this.setOverlaidData(this.objMultiData.arrPlot);
		}
	}
	/**
	 * setOverlaidData method is called to model series data
	 * in overlaid mode.
	 * @param	arrData		modelling data
	 * @param	startId		starting series id
	 * @param	endId		ending series id
	 * @return				
	 */
	private function setOverlaidData(arrData:Array, startId:Number, endId:Number):Void {
		// if starting id not specified
		if (startId == undefined) {
			// start from the very first series
			startId = 0;
		}
		// if ending id not specified                                                  
		if (endId == undefined) {
			// end by the last most series
			endId = arrSeries.length-1;
		}
		// number to series to model                                                  
		var seriesNum:Number = endId-startId+1;
		// variable declarations                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            
		var arrVertex3D:Array, arrLabels:Array, arrH:Array;
		var h:Number, h1:Number, seriesLength:Number, seriesId:Number, xOrigin:Number, xOriginNext:Number, xLabelGap:Number, yLabelGap:Number;
		var xFactor:Number, yFactor:Number, numValidData:Number, xPrev:Number, yPrev:Number, xPlot:Number, yPlot:Number, xNext:Number, yNext:Number;
		var strType:String;
		// loading the default width value for singleton LINE or AREA data
		var dotLineWidth:Number = DefaultValues.WIDTH_SINGLE_DATA;
		// gap for data item labels from the data item objects
		var gapValue:Number = this.params.valuePadding;
		// iterating over the series to model
		for (var j = 0; j<seriesNum; ++j) {
			// origin of x for both the current data item and te next one is initialised to zero
			xOrigin = 0;
			xOriginNext = 0;
			// the series id
			seriesId = startId+j;
			// array for a series
			arrData[seriesId] = [];
			// chart type
			strType = arrSeries[seriesId]['type'];
			// number of data items in the series
			seriesLength = arrSeries[seriesId]['num'];
			// base color of the series
			objMultiData.arrColors.push([arrSeries[seriesId]['color']]);
			// tooltips for the series
			objMultiData.arrToolTips.push(arrSeries[seriesId]['arrToolTips']);
			// container to store data label positions for this specific series
			arrLabels = [];
			// model params for the series
			arrH = arrSeries[seriesId]['arrData'];
			//-------------------------------------------//
			// finding the number of valid data per series
			numValidData = 0;
			for (var i = 0; i<seriesLength; ++i) {
				if (strType == 'COLUMN') {
					if (!isNaN(arrH[i]['h'])) {
						numValidData++;
					}
				} else {
					if (!isNaN(arrH[i]['y'])) {
						numValidData++;
					}
				}
			}
			//------------------------------------------//
			// series length can be one for LINE or AREA when a thin LINE or a thin PLANE is drawn
			if (strType != "COLUMN" && seriesLength != 1) {
				// decrease number of data models to be constructed by one
				seriesLength--;
			}
			//  for COLUMN and AREA                                                                                                                                                                                                                                                                                                                                  
			if (strType != "LINE") {
				// get the zero plane model
				var arrPlane3D:Array = Model.getPlaneVertices(0, 0, this.elements.canvas.w, 0, zOrigin-this.params.zGapPlot/2, this.params.zDepth+this.params.zGapPlot);
				// insert the model in containers for zero plane
				this.arrZeroPlanes.push(arrPlane3D);
			} else {
				// else pass a blank container for LINE (no zero plane for LINE)
				this.arrZeroPlanes.push([]);
			}
			//
			var validColumnFound:Boolean = false;
			// for COLUMN and LINE
			if (strType != "AREA") {
				// iterate over each data items
				for (var i = 0; i<seriesLength; ++i) {
					switch (strType) {
					case "COLUMN" :
						// gapValue negative means gap downwards and positive means gap upwards (cartesian coordinate system convention)          
						// label gap for the data item COLUMN
						yLabelGap = gapValue*((arrH[i]['h']<0) ? -1 : 1);
						// label position (3D)
						arrLabels.push([arrH[i]['x'], arrH[i]['y']+arrH[i]['h']+yLabelGap, zOrigin+this.params.zDepth/2]);
						// exit further processing for null data
						if (isNaN(arrH[i]['h'])) {
							continue;
						}
						// get the cuboid model for the COLUMN  
						arrVertex3D = Model.getCuboidVertices(arrH[i]['x'], arrH[i]['y'], zOrigin, arrH[i]['w'], arrH[i]['h'], this.params.zDepth);
						break;
					case "LINE" :
						// gapValue negative means gap downwards and positive means gap upwards (cartesian coordinate system convention)      
						// getting label gap for the LINE segment
						// if previous point is null
						if (isNaN(arrH[i-1]['y'])) {
							xLabelGap = 0;
							yLabelGap = gapValue*((arrH[i]['y']<arrH[i+1]['y']) ? -1 : -1);
							// if next point is null
						} else if (isNaN(arrH[i+1]['y'])) {
							xLabelGap = 0;
							yLabelGap = gapValue*((arrH[i]['y-1']<arrH[i]['y']) ? 1 : -1);
						} else {
							// evaluating characteristic values to ascertain the direction/sense of gaps
							var del1:Number = arrH[i-1]['y']-arrH[i]['y'];
							var testExp1:Number = (del1 != 0) ? Math.abs(del1)/del1 : 0;
							//
							var del2:Number = arrH[i]['y']-arrH[i+1]['y'];
							var testExp2:Number = (del2 != 0) ? Math.abs(del2)/del2 : 0;
							//
							switch (testExp1) {
								// decreasing
							case 1 :
								//decreasing;
								switch (testExp2) {
									// decreasing
								case 1 :
									//decreasing;
									xFactor = -1;
									yFactor = -1;
									break;
									// increasing
								case -1 :
									//increasing;
									xFactor = 0;
									yFactor = -1;
									break;
									// horizontal
								case 0 :
									//horizontal;
									xFactor = 0;
									yFactor = -1;
									break;
								}
								break;
								// increasing
							case -1 :
								//increasing;
								switch (testExp2) {
									// decreasing
								case 1 :
									//decreasing;
									xFactor = 0;
									yFactor = 1;
									break;
									// increasing
								case -1 :
									//increasing;
									xFactor = 1;
									yFactor = -1;
									break;
									// horizontal
								case 0 :
									//horizontal;
									xFactor = 0;
									yFactor = 1;
									break;
								}
								break;
								// horizontal
							case 0 :
								//horizontal;
								switch (testExp2) {
									// decreasing
								case 1 :
									//decreasing;
									xFactor = 0;
									yFactor = 1;
									break;
									// increasing
								case -1 :
									//increasing;
									xFactor = 0;
									yFactor = -1;
									break;
									// horizontal
								case 0 :
									//horizontal;
									xFactor = 0;
									yFactor = 1;
									break;
								}
								break;
							}
							// setting the gaps
							xLabelGap = gapValue*xFactor;
							yLabelGap = gapValue*yFactor;
						}
						// label postion (3D) for the LINE segment
						arrLabels.push([arrH[i]['x']+xLabelGap, arrH[i]['y']+yLabelGap, zOrigin+this.params.zDepth/2]);
						// value of seriesLength (variable) is decreased by one for line and area charts
						// so for the last iterator, push an addition position corresponding to the end LINE data plot
						if (i == seriesLength-1) {
							xLabelGap = 0;
							yLabelGap = gapValue*((arrH[i+1]['y']<arrH[i]['y']) ? -1 : 1);
							arrLabels.push([arrH[i+1]['x']+xLabelGap, arrH[i+1]['y']+yLabelGap, zOrigin+this.params.zDepth/2]);
						}
						//----------------------//                  
						// now, model the data
						// previous point
						xPrev = arrH[i-1]['x'];
						yPrev = arrH[i-1]['y'];
						// current point
						xPlot = arrH[i]['x'];
						yPlot = arrH[i]['y'];
						// next point
						xNext = arrH[i+1]['x'];
						yNext = arrH[i+1]['y'];
						//
						// when null data be not managed and/or singleton (valid) data - when isolated point be drawn
						// as a point in 2D view, with z-dimension only.
						if (!this.params.connectNullData || numValidData == 1) {
							// for data leaving the first one
							if (i != 0) {
								// if next point is null
								if (isNaN(yNext)) {
									// if previous point is null too
									if (isNaN(yPrev)) {
										// isolated point found
										xNext = xPlot+dotLineWidth;
										yNext = yPlot;
									} else {
										// nothing to do more
										continue;
									}
								}
								// for the first data  
							} else {
								// if next point is null - isolated data situation
								xNext = (isNaN(yNext)) ? xPlot+dotLineWidth : xNext;
								yNext = (isNaN(yNext)) ? yPlot : yNext;
							}
						}
						//    
						// get the plane model for the LINE segment
						arrVertex3D = Model.getPlaneVertices(xPlot, yPlot, xNext, yNext, zOrigin, this.params.zDepth);
						// checking if the last data is isolated
						if (i == seriesLength-1 && isNaN(yPlot) && !isNaN(yNext)) {
							// get the thin LINE model for the isolated data
							arrVertex3D = Model.getPlaneVertices(xNext-dotLineWidth, yNext, xNext, yNext, zOrigin, this.params.zDepth);
						}
						break;
					}
					// add the model in container
					arrData[seriesId].push(arrVertex3D);
				}
			} else {
				// --- modelling  for AREA --- //
				// flag denoting if next loop be skipped from processing
				var skipNext:Boolean = false;
				xLabelGap = 0;
				// iterate to get the final "arrH" holding valid data to be rendered as 3D AREA
				for (var i = 0; i<arrH.length; ++i) {
					// if this phase of the loop be skipped
					if (skipNext) {
						// update flag
						skipNext = false;
						// skip
						continue;
					}
					// set the label gap for the   
					yLabelGap = gapValue*((arrH[i]['y']>=0) ? 1 : -1);
					arrLabels.push([arrH[i]['x']+xLabelGap, arrH[i]['y']+yLabelGap, zOrigin+this.params.zDepth/2]);
					// previous point
					xPrev = arrH[i-1]['x'];
					yPrev = arrH[i-1]['y'];
					// current point
					xPlot = arrH[i]['x'];
					yPlot = arrH[i]['y'];
					// next point
					xNext = arrH[i+1]['x'];
					yNext = arrH[i+1]['y'];
					//
					// when null data be not managed and/or singleton (valid) data - when isolated point be drawn
					// as a line in 2D view, with y and z dimensions only.
					if (!this.params.connectNullData || numValidData == 1) {
						// for data leaving the first one
						if (i != 0) {
							// if next point is null
							if (isNaN(yNext)) {
								// if previous point is null too
								if (isNaN(yPrev)) {
									// isolated point found
									xNext = xPlot+dotLineWidth;
									yNext = yPlot;
									// add entry to manage the isolated data plot
									arrH.splice(i+1, 0, {x:xNext, y:yNext});
									// next loop should be skipped as arr length increments due addition at next index
									skipNext = true;
								}
							}
							// for the first data  
						} else {
							// if next point is null - isolated data situation
							if (isNaN(yNext)) {
								// isolated point found
								xNext = xPlot+dotLineWidth;
								yNext = yPlot;
								// add entry to manage the isolated data plot
								arrH.splice(i+1, 0, {x:xNext, y:yNext});
								// next loop should be skipped as arr length increments due addition at next index
								skipNext = true;
							}
						}
					}
				}
				//            
				// get the overall AREA3D models for all blocks to be formed accomodating the zero plane
				arrVertex3D = Model.getArea3DVertices(arrH, zOrigin, this.params.zDepth);
				// add the model conglomerate
				arrData[seriesId] = arrVertex3D;
			}
			// add label position conglomerate to the basic container
			this.objMultiData.arrDataLabelsPlot.push(arrLabels);
			// update the z-origin value to be used by the next series
			zOrigin += this.params.zDepth+this.params.zGapPlot;
		}
	}
	/**
	 * setClusteredData method is called to model series data
	 * in clustered mode.
	 * @param	arrData		modelling data
	 * @param	startId		starting series id
	 * @param	endId		ending series id
	 * @return				
	 */
	private function setClusteredData(arrData:Array, startId:Number, endId:Number):Void {
		// if starting id not specified
		if (startId == undefined) {
			// start from the very first series
			startId = 0;
		}
		// if ending id not specified                                                  
		if (endId == undefined) {
			// end by the last most series
			endId = arrSeries.length-1;
		}
		// number to series to model                                                
		var clusterLength:Number = endId-startId+1;
		// local reference of gap of data labels
		var gapValue:Number = this.params.valuePadding;
		// variable declarations                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    
		var arrVertex3D:Array, arrPlane3D:Array, arrLabels:Array, arrH:Array;
		var h:Number, seriesLength:Number, seriesId:Number, yLabelGap:Number;
		// iterating over each series to be modelled
		for (var j = 0; j<clusterLength; ++j) {
			// zero plane for clustered columns
			arrPlane3D = Model.getPlaneVertices(0, 0, this.elements.canvas.w, 0, zOrigin-this.params.zGapPlot/2, this.params.zDepth+this.params.zGapPlot);
			// add the zero plane model to the container
			this.arrZeroPlanes.push(arrPlane3D);
			// series id
			seriesId = startId+j;
			// sub-container for data item models
			arrData[seriesId] = [];
			// number of data items to be modelled
			seriesLength = arrSeries[seriesId]['num'];
			// base color of the series
			objMultiData.arrColors.push([arrSeries[seriesId]['color']]);
			// tooltips of the series
			objMultiData.arrToolTips.push(arrSeries[seriesId]['arrToolTips']);
			// container to store label positions for this specific series
			arrLabels = [];
			// modelling params for data items of the series
			arrH = arrSeries[seriesId]['arrData'];
			// iterating over each data item
			for (var i = 0; i<seriesLength; ++i) {
				// gapValue negative means gap downwards and positive means gap upwards (cartesian coordinate system convention)                
				// sense of label shift about y-axis
				yLabelGap = gapValue*((arrH[i]['h']<0) ? -1 : 1);
				// label position (3D) added
				arrLabels.push([arrH[i]['x'], arrH[i]['y']+arrH[i]['h']+yLabelGap, zOrigin+this.params.zDepth/2]);
				// get the CUBOID model for the COLUMN data item  
				arrVertex3D = Model.getCuboidVertices(arrH[i]['x'], arrH[i]['y'], zOrigin, arrH[i]['w'], arrH[i]['h'], this.params.zDepth);
				// add the model in the container
				arrData[seriesId].push(arrVertex3D);
			}
			// add the data label positions of the series in the basic container
			this.objMultiData.arrDataLabelsPlot.push(arrLabels);
		}
		// update the z-origin to be used by the next series
		zOrigin += this.params.zDepth+this.params.zGapPlot;
	}
	//------------------------------ UTILITY --------------------------------------//
	/**
	 * updateSystemAngles method is called to update the chart
	 * view angles w.r.t. to user's mouse drag.
	 * @return 		flag to indicate that angles are updated
	 *				which is not always necessary
	 */
	private function updateSystemAngles():Boolean {
		var mcRoot:MovieClip = this.cMC;
		// alias
		var UM:Function = MathExt.minimiseAngle;
		// if last mouse drag position is not available
		if (this.xmouse == undefined) {
			// apply the current mouse position
			this.xmouse = mcRoot._xmouse;
			this.ymouse = mcRoot._ymouse;
		}
		// difference in last and current mouse ordinate                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         
		var yDiff:Number = mcRoot._ymouse-this.ymouse;
		// change in angle of rotation about x-axis
		var xAng:Number = MathExt.roundUp((yDiff/(Stage.height/2))*180);
		// if contrain be there for rotation about x-axis
		if (this.params.constrainXRotation) {
			// current camera angles
			var objCamAngs:Object = this.system3D.getCameraAngs();
			var xAngCam:Number = UM(objCamAngs.xAng);
			var yAngCam:Number = UM(objCamAngs.yAng);
			// next camera x angle
			var newXAngCam:Number = UM(xAngCam+xAng);
			// new angle goes beyond limitation, get the required change in x angle that can be applied
			if (newXAngCam<=this.params.minXRotAngle) {
				xAng = this.params.minXRotAngle-xAngCam;
			} else if (newXAngCam>=this.params.maxXRotAngle) {
				xAng = this.params.maxXRotAngle-xAngCam;
			}
		}
		// difference in last and current mouse abscissa                                                                                                                                                                                                                                                                                                                                                                                                                                                           
		var xDiff:Number = mcRoot._xmouse-this.xmouse;
		// change in angle of rotation about y-axis
		var yAng:Number = MathExt.roundUp((xDiff/(Stage.width/2))*180);
		// if contrain be there for rotation about y-axis
		if (this.params.constrainYRotation) {
			// current camera angles
			var objCamAngs:Object = this.system3D.getCameraAngs();
			var xAngCam:Number = UM(objCamAngs.xAng);
			var yAngCam:Number = UM(objCamAngs.yAng);
			// next camera y angle
			var newYAngCam:Number = UM(yAngCam+yAng);
			// new angle goes beyond limitation, get the required change in y angle that can be applied
			if (newYAngCam<=this.params.minYRotAngle) {
				yAng = this.params.minYRotAngle-yAngCam;
			} else if (newYAngCam>=this.params.maxYRotAngle) {
				yAng = this.params.maxYRotAngle-yAngCam;
			}
		}
		// if either of the 2 change in angles about the axes is not equal to zero                                                                                                                                                                                                                                                                                                                                                                                                                                             
		if (xAng != 0 || yAng != 0) {
			// update the view/camera angles in the Engine instance
			this.system3D.updateCameraBy(MathExt.roundUp(xAng), MathExt.roundUp(yAng));
			// update light for non-world lighting
			if (!this.params.worldLighting) {
				this.system3D.updateLightBy(xAng, yAng);
			}
		} else {
			// return to indicate that view angles aren't changed
			return false;
		}
		// update last mouse position for next call
		this.xmouse = mcRoot._xmouse;
		this.ymouse = mcRoot._ymouse;
		// return to indicate that view angles are changed
		return true;
	}
	/**
	 * getZRange method returns the z-extremities for the 
	 * series model passed.
	 * @param	arrSeriesData3D		series data
	 * @return						z-extremes
	 */
	private function getZRange(arrSeriesData3D:Array):Object {
		// extreme values possible
		var min:Number = Number.MAX_VALUE;
		var max:Number = -Number.MAX_VALUE;
		// conatiner to hold the extremes for return
		var objRange:Object = {};
		// checking only one element is sufficient, since in model coordinates
		// first element in the series
		var arrFirstElement:Array = this.getFirstValidData(arrSeriesData3D);
		// number of vertices in the first element
		var numSubElements:Number = arrFirstElement.length;
		// iterate over all vertices of the first element
		for (var i = 0; i<numSubElements; ++i) {
			// the vertex (3D)
			var arrSubElement:Array = arrFirstElement[i];
			// z value is in third position ([2])
			// checking for max and min value z values
			min = (min>arrSubElement[2]) ? arrSubElement[2] : min;
			max = (max<arrSubElement[2]) ? arrSubElement[2] : max;
		}
		// an adjustment to cover the gap along z-axis between 2 consecutive series
		var addZ:Number = this.params.zGapPlot/2;
		// store the final values
		objRange['min'] = min-addZ;
		objRange['max'] = max+addZ;
		// return
		return objRange;
	}
	/**
	 * getFirstValidData method returns the first valid data 
	 * in the passed data structure.
	 * @param	arrData		passed data
	 * @return				array containing first valid data
	 */
	private function getFirstValidData(arrData:Array):Array {
		for (var i = 0; i<arrData.length; ++i) {
			if (!isNaN(arrData[i][1][0])) {
				break;
			}
		}
		return arrData[i];
	}
	/**
	 * getCategories method returns the series chart types
	 * from the passed dataset.
	 * @param	arrData		data about series set
	 * @return				chart types
	 */
	public function getCategories(arrData:Array):Array {
		// container to hold chart types of the series set
		var arrCategory:Array = [];
		// iterate over the number of series
		for (var i = 0; i<arrData.length; ++i) {
			// chart type stored
			arrCategory.push(arrData[i]['type']);
		}
		// return 
		return arrCategory;
	}
	/**
	 * sortCategory method sorts dataset for series set for 
	 * z-stack ordering of the series set.
	 * @param	arrData		dataset to sort
	 */
	public function sortCategory(arrData:Array):Void {
		// container to hold chart type map w.r.t ids which will determine the sorting
		var objId:Object = {};
		// iterate over chart types, ready in order
		for (var i = 0; i<this.params.arrChartOrder.length; ++i) {
			// map for the type
			objId[this.params.arrChartOrder[i]] = this.params.arrChartOrder.length-i;
		}
		// iterate over each series
		for (var i = 0; i<arrData.length; ++i) {
			// new id stored in series data w.r.t. type for sorting
			arrData[i]['id'] = objId[arrData[i]['type']];
		}
		// sort
		this.bubbleSort(arrData, 'id');
	}
	//------------------------------ INTERACTIVITY --------------------------------------//
	/**
	 * setInteractivity method is called program the chart
	 * for user interactivity.
	 */
	private function setInteractivity():Void {
		// MC to control the interactivity
		var mcControl:MovieClip = this.cMC.createEmptyMovieClip('controlMc', this.cMC.getNextHighestDepth());
		mcControl.onEnterFrame = Delegate.create(this, onEachFrame);
		mcControl.onMouseDown = Delegate.create(this, onMousePress);
		mcControl.onMouseUp = Delegate.create(this, onMouseRelease);
		//----------------//
		var thisRef = this;
		// if chart not yet initiated
		if (!this.initiated) {
			// if scaling is allowed for user
			if (this.params.allowScaling) {
				// mouse object listener
				this.mouseListener = {};
				// program to handle the event of mouse wheel scrolling
				this.mouseListener.onMouseWheel = function(delta, target) {
					// if chart disabled currently
					if (!thisRef.chartEnabled) {
						// no reaction
						return;
					}
					// to validate the chart instance to respond for the mouse event (for multi charts in a swf, since Mouse is a global                                
					// object and notifies the event invoked to all listeners in the movie, irrespective of chart instances).
					if (target._target.indexOf(thisRef.cMC._target) != 0) {
						return;
					}
					// else, scale up/down by the passed amount; true --> flag to indicate that scaling due mouse scrolling                                         
					thisRef.system3D.scale(delta, true);
					// best fitting must be upset due to this change in scaling
					thisRef.bestFitted = false;
				};
				// add listener
				Mouse.addListener(this.mouseListener);
			}
		}
	}
	/**
	 * legendClick method is the event handler for legend.
	*/
	private function legendClick(evtObj:Object):Void {
		//Getting the respective data index
		var arrdataLgnd:Array = this.arrdataLgndMap;
		var dataId:Number = arrdataLgnd[evtObj.index];
		//Updating the 'showValues' value
		this.dataset[dataId].showValues = !evtObj.active;
		
		this.system3D.handleLabelsOf(evtObj.index);
	}
	/**
	 * setToolTipInteractions is called to program mouse hovering
	 * and/or clicking event over the data items.
	 */
	private function setToolTipInteractions():Void {
		var thisRef = this;
		// MC paths for the data MCs 
		var arrMcBlocks:Array = this.system3D.getMcBlocks();
		// specific MC under mouse pointer
		var mcBlock:MovieClip;
		// iterate over all data MCs
		for (var i = 0; i<arrMcBlocks.length; ++i) {
			// the data MC to be programmed
			mcBlock = arrMcBlocks[i];
			// mouse release programmed
			mcBlock.onRelease = function() {
				// if chart in linking mode
				if (thisRef.config.linkMode) {
					// get the 3D position in the model space of the chart, that is under the mouse pointer
					var arrMouse3D:Array = thisRef.system3D.handleToolTip(this);
					// get the link
					var strLink:String = thisRef.evalToolTip(arrMouse3D, true);
					// invoke the link
					thisRef.invokeLink(strLink);
				}
			};
			// mouse rollover programmed
			mcBlock.onRollOver = function() {
				// no hand cursor, basically
				this.useHandCursor = false;
				// if tooltip enabled or chart in linking mode
				if (thisRef.params.showToolTip || thisRef.config.linkMode) {
					// get the 3D position in chart model space, that is under the mouse
					var arrMouse3D:Array = thisRef.system3D.handleToolTip(this);
				}
				// if tooltip be shown                                           
				if (thisRef.params.showToolTip) {
					// get the text to display
					var strDisplay:String = thisRef.evalToolTip(arrMouse3D, false);
					// 'strDisplay' may be blank string for certain side view for certain lineChart elements
					// if anything to be shown at all
					if (strDisplay != '') {
						// show tooltip
						thisRef.tTip.setText(strDisplay);
						thisRef.tTip.show();
					}
				}
				// if chart is in linking mode currently                                           
				if (thisRef.config.linkMode) {
					// get the link relevant to data item under mouse
					var strLink:String = thisRef.evalToolTip(arrMouse3D, true);
					// show hand cursor if any link be there for the data item
					this.useHandCursor = (strLink != '') ? true : false;
				}
				// mouse move programmed once each time mouse rollovers                                                                                                                                                                                                                                                                                                                                                 
				this.onMouseMove = function() {
					// if tooltip enabled or chart in linking mode
					if (thisRef.params.showToolTip || thisRef.config.linkMode) {
						// get the 3D position in chart model space, that is under the mouse
						var arrMouse3D:Array = thisRef.system3D.handleToolTip(this);
					}
					// if tooltip be shown                                           
					if (thisRef.params.showToolTip) {
						// get the text to display
						var strDisplay:String = thisRef.evalToolTip(arrMouse3D, false);
						// 'strDisplay' may be blank string for certain side view for certain lineChart elements
						// if anything to be shown at all
						if (strDisplay != '') {
							// show tooltip by repositioning text
							thisRef.tTip.setText(strDisplay);
							thisRef.tTip.rePosition();
							thisRef.tTip.show();
						} else {
							// hide tooltip
							thisRef.tTip.hide();
						}
					}
					// if chart is in linking mode currently                                           
					if (thisRef.config.linkMode) {
						// get link
						var strLink:String = thisRef.evalToolTip(arrMouse3D, true);
						// show hand cursor if link valid
						this.useHandCursor = (strLink != '') ? true : false;
					} else {
						// no hand cursor
						this.useHandCursor = false;
					}
				};
				//------------------------------//
			};
			// mouse rollout programmed
			mcBlock.onRollOut = function() {
				// no tooltip
				thisRef.tTip.hide();
				// delete the mouseMove handling program
				delete this.onMouseMove;
			};
		}
	}
	/**
	 * onEachFrame method is called by delegation model
	 * to handle mouse dragging primarily.
	 */
	private function onEachFrame() {
		// hide tooltip if chart disabled due animation
		if (!this.chartEnabled) {
			this.tTip.hide();
		}
		// if mouse is down                       
		if (this.isMouseDown) {
			// if rotation is allowed for the user
			if (this.params.allowRotation) {
				// if chart not in linking mode
				if (!this.config.linkMode) {
					// update chart view angles and get a boolean returned which indicates about if a new view
					// w.r.t camera angles is at all required
					var updateScreen:Boolean = this.updateSystemAngles();
					// if screen need be updated for a new set of camera angles
					if (updateScreen) {
						// hide tooltip
						this.tTip.hide();
						// recreate the chart
						this.system3D.recreate();
						// update flag about stage update
						this.stageUpdated = true;
					}
				}
			}
		}
	}
	/**
	 * onMousePress method is called by delegation model
	 * handle the event of mouse down on the chart.
	 */
	private function onMousePress() {
		// if chart is enabled currently
		if (this.chartEnabled) {
			// check hit on the chart
			if (this.mcChart.hitTest(_root._xmouse, _root._ymouse, true)) {
				// update flag to indicate mouse down
				this.isMouseDown = true;
				// update flag to indicate that stage may need to be updated
				this.stageUpdated = false;
			}
		}
	}
	/**
	 * onMouseRelease method is called by delegation model to
	 * handle the mouse release event.
	 */
	private function onMouseRelease() {
		// if mouse was down
		if (this.isMouseDown) {
			// update flag
			this.isMouseDown = false;
			// reset last mouse position to null
			this.xmouse = null;
			this.ymouse = null;
			// if stage is updated
			if (this.stageUpdated) {
				// if autoscling is opted
				if (this.params.autoScaling) {
					// get chart best fit in chart stage
					this.system3D.scaleToFit();
					// update flag
					this.bestFitted = true;
				}
				// set the mousetip interactions                                           
				this.setToolTipInteractions();
			}
		}
	}
	// ---------- EVENTDISPATCHER -----------------//
	/**
	 * setEventDispatch is the method called to handle 
	 * notification of custom event dispatching model.
	 */
	private function setEventDispatch():Void {
		// obect to listen for event notification and to handle them
		objEventHandler = {};
		// initial animation end event
		objEventHandler.iniAnimated = Delegate.create(this, onAnimationEnd);
		// animation end event
		objEventHandler.animated = Delegate.create(this, onAnimationEnd);
		
		objEventHandler.scaleAnimated = Delegate.create(this, onScaleAnimationEnd);
		
		// add listener for the events
		this.system3D.addEventListener('iniAnimated', objEventHandler);
		this.system3D.addEventListener('animated', objEventHandler);
		this.system3D.addEventListener('scaleAnimated', objEventHandler);
		
	}
	/**
	 * onScaleAnimationEnd method is called to handle scaling
	 * to fit during initial animation.
	 * @param	objEvent	event object
	 */
	private function onScaleAnimationEnd(objEvent:Object){
		// During initial animation, scaleToInit is called twice.
		// First time to scale fit the axesBox in the initial phase and
		// second time to scale fit the final status.
		// All other calls of this handler function is unnecessary.
		if(this.initStatus==0){
			this.initStatus++;
		} else if(this.initStatus == 1){
			this.initStatus++;
			this.exposeChartRendered();
		}
	}
	
	/**
	 * onAnimationEnd method handles the event of animation
	 * end.
	 * @param	objEvent	params about the event
	 */
	private function onAnimationEnd(objEvent:Object) {
		// enable the chart by updating flag
		this.chartEnabled = true;
		// irrespective of autoscaling is enabled or not
		if ((this.params.autoScaling && objEvent.type == 'animated') || objEvent.type == 'iniAnimated') {
			// get chart best fitted in chart stage
			this.system3D.scaleToFit();
			// update flag
			this.bestFitted = true;
		}
		// set the mousetip interactions                                           
		this.setToolTipInteractions();
	}
	//------------------------------ CONTEXT MENU --------------------------------------//
	/**
	 * animateTo2D method makes the chart animate
	 * to 2D mode.
	 */
	public function animateTo2D():Void {
		// no action if chart not enabled
		if (!this.chartEnabled) {
			return;
		}
		// chart disabled                                          
		this.chartEnabled = false;
		var objAnim:Object = {};
		objAnim.exeTime = this.params.exeTime;
		// starting angles not required
		objAnim.startAngX = null;
		objAnim.startAngY = null;
		// ending angles set to zeros
		objAnim.endAngX = 0;
		objAnim.endAngY = 0;
		// call to animate to the desired state and thereby returning the pre-animation angles if required to revert back
		this.objLastAngs = this.system3D.animate(objAnim);
	}
	/**
	 * animateTo3D method makes the chart animate
	 * to 3D mode w.r.t. last view angles.
	 */
	public function animateTo3D():Void {
		// no action if chart not enabled
		if (!this.chartEnabled) {
			return;
		}
		// chart disabled                                          
		this.chartEnabled = false;
		var objAnim:Object = {};
		objAnim.exeTime = this.params.exeTime;
		// starting angles not required
		objAnim.startAngX = null;
		objAnim.startAngY = null;
		// ending angles set to relevant values
		objAnim.endAngX = (this.objLastAngs.xAng == undefined) ? this.params.endAngX : this.objLastAngs.xAng;
		objAnim.endAngY = (this.objLastAngs.yAng == undefined) ? this.params.endAngY : this.objLastAngs.yAng;
		// call to animate to the desired state and thereby returning the pre-animation angles if required to revert back
		this.objLastAngs = this.system3D.animate(objAnim);
	}
	/**
	 * animateToResetView method animates the chart to initial
	 * view.
	 */
	public function animateToResetView():Void {
		// no action if chart not enabled
		if (!this.chartEnabled) {
			return;
		}
		// chart disabled                                          
		this.chartEnabled = false;
		var objAnim:Object = {};
		objAnim.exeTime = this.params.exeTime;
		// starting angles not required
		objAnim.startAngX = null;
		objAnim.startAngY = null;
		// ending angles set to relevant values
		objAnim.endAngX = (this.params.animate3D) ? this.params.endAngX : this.params.cameraAngX;
		objAnim.endAngY = (this.params.animate3D) ? this.params.endAngY : this.params.cameraAngY;
		// call to animate to the desired state and thereby returning the pre-animation angles if required to revert back
		this.objLastAngs = this.system3D.animate(objAnim);
	}
	/**
	 * animateToScale100 method animates chart to 100% 
	 * scaling.
	 */
	private function animateToScale100() {
		// no action if chart not enabled
		if (!this.chartEnabled) {
			return;
		}
		// scale to 100%                                          
		this.system3D.scaleTo100();
		// update flag
		this.bestFitted = false;
	}
	/**
	 * animateToScaleFit method animates chart to best fit in 
	 * the chart stage.
	 */
	private function animateToScaleFit() {
		// no action if chart not enabled
		if (!this.chartEnabled) {
			return;
		}
		// get best fitting                                          
		this.system3D.scaleToFit();
		// update flag
		this.bestFitted = true;
	}
	/**
	* setContextMenu method sets the context menu for the 
	* chart.
	*/
	private function setContextMenu():Void {
		// menu option labels
		var strImage:String = "Save as Image";
		var strFC:String = "About FusionCharts";
		var strPrint:String = "Print Chart";
		//
		var strRotation:String = "Enable rotation";
		var strLinks:String = "Enable links";
		//
		var str2D:String = "View 2D";
		var str3D:String = "View 3D";
		var strIni3D:String = "Reset view";
		var str100:String = "View 100%";
		var strFit:String = "View best fit";
		//
		var strEnableAuto:String = "Enable Auto-scaling";
		var strDisableAuto:String = "Disable Auto-scaling";
		// labels for animation related menu options
		var arrAnimCaptions:Array = [str2D, str3D, strIni3D, str100, strFit];
		//
		var thisRef = this;
		// custom contextMenu instantiated
		var chartMenu:ContextMenu = new ContextMenu();
		// hide built-in items
		chartMenu.hideBuiltInItems();
		//Create a print chart contenxt menu item
		var printCMI:ContextMenuItem = new ContextMenuItem(strPrint, Delegate.create(this, printChart));
		//Push print item.
		chartMenu.customItems.push(printCMI);
		//If the export data item is to be shown
		if (this.params.showExportDataMenuItem){
			chartMenu.customItems.push(super.returnExportDataMenuItem());
		}
		//-----------------------------------------------//
		// if any link be given for the chart
		if (this.linksGiven) {
			// initial chart mode is set for linking
			this.config.linkMode = true;
			//Create a contenxt menu item for rotation enabling
			var cmiRotation:ContextMenuItem = new ContextMenuItem(strRotation, rotationEnabler, true, true, true);
			//Create a contenxt menu item for link enabling
			var cmiLinks:ContextMenuItem = new ContextMenuItem(strLinks, linksEnabler, true, true, false);
			// push the context menu items
			chartMenu.customItems.push(cmiRotation);
			chartMenu.customItems.push(cmiLinks);
		}
		// function to handle option to enable rotation                                          
		function rotationEnabler(obj, item) {
			cmiRotation.visible = false;
			cmiLinks.visible = true;
			thisRef.config.linkMode = false;
		}
		// function to handle option to enable links
		function linksEnabler(obj, item) {
			cmiRotation.visible = true;
			cmiLinks.visible = false;
			thisRef.config.linkMode = true;
		}
		//-----------------------------------------------// 
		//Create a contenxt menu item for animation to 2D mode
		var cmiTo2D:ContextMenuItem = new ContextMenuItem(str2D, to2DHandler, true, true);
		//Create a contenxt menu item for animation to 3D mode
		var cmiTo3D:ContextMenuItem = new ContextMenuItem(str3D, to3DHandler, true, true, false);
		// push the context menu items
		chartMenu.customItems.push(cmiTo2D);
		chartMenu.customItems.push(cmiTo3D);
		//
		// function to handle option to view 2D mode
		function to2DHandler(obj, item) {
			cmiTo2D.visible = false;
			cmiTo3D.visible = true;
			thisRef.animateTo2D();
		}
		// function to handle option to view 3D mode
		function to3DHandler(obj, item) {
			cmiTo2D.visible = true;
			cmiTo3D.visible = false;
			thisRef.animateTo3D();
		}
		//-----------------------------------------------//
		//Create a contenxt menu item for animation to initial view
		var cmiToIni3D:ContextMenuItem = new ContextMenuItem(strIni3D, toIni3DHandler, false, true);
		// push the context menu item
		chartMenu.customItems.push(cmiToIni3D);
		// function to handle option to view initial mode
		function toIni3DHandler(obj, item) {
			thisRef.animateToResetView();
		}
		//-----------------------------------------------//   
		//Create a contenxt menu item for animation to 100% view
		var cmiToScale100:ContextMenuItem = new ContextMenuItem(str100, toScale100Handler, false, true);
		// push the context menu item
		chartMenu.customItems.push(cmiToScale100);
		// function to handle option to view 100%
		function toScale100Handler(obj, item) {
			thisRef.animateToScale100();
		}
		//-----------------------------------------------//
		//Create a contenxt menu item for animation to best fit view
		var cmiBestFit:ContextMenuItem = new ContextMenuItem(strFit, toBestFitHandler, false, true);
		// push the context menu item
		chartMenu.customItems.push(cmiBestFit);
		// function to handle option to view best fit
		function toBestFitHandler(obj, item) {
			thisRef.animateToScaleFit();
		}
		//-----------------------------------------------// 
		//Create a contenxt menu item for enabling autoscaling
		var cmiEnableAutoScaling:ContextMenuItem = new ContextMenuItem(strEnableAuto, enableAutoScalingHandler, true, true, !this.params.autoScaling);
		//Create a contenxt menu item for disabling autoscaling
		var cmiDisableAutoScaling:ContextMenuItem = new ContextMenuItem(strDisableAuto, disableAutoScalingHandler, true, true, this.params.autoScaling);
		// push the context menu items
		chartMenu.customItems.push(cmiEnableAutoScaling);
		chartMenu.customItems.push(cmiDisableAutoScaling);
		//
		// function to handle option to enable autoscaling
		function enableAutoScalingHandler(obj, item) {
			cmiEnableAutoScaling.visible = false;
			cmiDisableAutoScaling.visible = true;
			thisRef.params.autoScaling = true;
			thisRef.system3D.scaleToFit();
			thisRef.bestFitted = true;
		}
		// function to handle option to disable autoscaling
		function disableAutoScalingHandler(obj, item) {
			cmiEnableAutoScaling.visible = true;
			cmiDisableAutoScaling.visible = false;
			thisRef.params.autoScaling = false;
		}
		// function invoked to set menu options when context menu is invoked
		chartMenu.onSelect = function(obj, item) {
			// get current camera agles
			var objAngs:Object = thisRef.system3D.getCameraAngs();
			if (objAngs.xAng == 0 && objAngs.yAng == 0) {
				// chart in 2D view
				cmiTo2D.visible = false;
				cmiTo3D.visible = true;
			} else {
				// chart not in 2D view
				cmiTo2D.visible = true;
				cmiTo3D.visible = false;
			}
			if (thisRef.params.allowRotation) {
				// for rotation allowed
				var xAng:Number = (thisRef.params.animate3D) ? thisRef.params.endAngX : thisRef.params.cameraAngX;
				var yAng:Number = (thisRef.params.animate3D) ? thisRef.params.endAngY : thisRef.params.cameraAngY;
				cmiToIni3D.visible = (xAng == objAngs.xAng && yAng == objAngs.yAng) ? false : true;
			} else {
				// for rotation not allowed
				cmiRotation.visible = false;
				cmiLinks.visible = false;
				cmiToIni3D.visible = false;
			}
			cmiToScale100.visible = (thisRef.system3D.getScale() == 100) ? false : true;
			cmiBestFit.visible = (thisRef.bestFitted) ? false : true;
		};
		//---------------------------------------------//
		//Add export chart related menu items to the context menu
		this.addExportItemsToMenu(chartMenu);
		if (this.params.showFCMenuItem) {
			//Push "About FusionCharts" Menu Item
			chartMenu.customItems.push(super.returnAbtMenuItem());
		}
		//Assign the menu to cMC movie clip                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              
		this.cMC.menu = chartMenu;
	}
	//-----------------------------------------------//
	/**
	 * JSview2D method is called by javascript to change to 
	 * 2D view.
	 */
	public function JSview2D():Void {
		if(!this.chartEnabled){
			this.log("Call Ignored", "The chart is not in a state to switch to 2D view.", Logger.LEVEL.ERROR);
			return;
		}
		// if initial animation is opted
		if (this.params.animate3D) {
			// animate
			this.animateTo2D();
		} else {
			this.changeView(0, 0);
		}
	}
	/**
	 * JSview3D method is called by javascript to change to 
	 * last 3D view. 
	 */
	public function JSview3D():Void {
		if(!this.chartEnabled){
			this.log("Call Ignored", "The chart is not in a state to switch to 3D view.", Logger.LEVEL.ERROR);
			return;
		}
		this.animateTo3D();
	}
	/**
	 * JSresetView method is called by javascript to change to 
	 * initial view. 
	 */
	public function JSresetView():Void {
		if(!this.chartEnabled){
			this.log("Call Ignored", "The chart is not in a state to reset chart view.", Logger.LEVEL.ERROR);
			return;
		}
		// if initial animation is opted
		if (this.params.animate3D) {
			// animate
			this.animateToResetView();
		} else {
			this.changeView(this.params.cameraAngX, this.params.cameraAngY);
		}
	}
	/**
	 * JSrotateView method is called by javascript to rotate
	 * view to the specified angles.
	 */
	public function JSrotateView(xAng:Number, yAng:Number, custom:Boolean):Object {
		if(!this.chartEnabled){
			this.log("Call Ignored", "The chart is not in a state to rotate view.", Logger.LEVEL.ERROR);
			return;
		}
		// checking illegal params
		if (isNaN(xAng) || isNaN(yAng)) {
			this.log("Angles Ignored", "Invalid angles provided for rotating the chart to. Please check the same.", Logger.LEVEL.ERROR);
			// no action
			return;
		}
		// for change in view passing final angles (like for auto rotation via JS)                         
		if (custom) {
			this.changeView(xAng, yAng);
		} else if (this.params.animate3D) {
			// chart disabled                                          
			this.chartEnabled = false;
			var objAnim:Object = {};
			objAnim.exeTime = this.params.exeTime;
			objAnim.startAngX = null;
			objAnim.startAngY = null;
			objAnim.endAngX = MathExt.roundUp(xAng);
			objAnim.endAngY = MathExt.roundUp(yAng);
			// animate to the required angle
			this.objLastAngs = this.system3D.animate(objAnim);
		} else {
			this.changeView(xAng, yAng);
		}
	}
	/**
	 * JSgetCamAngles method is called by javascript to
	 * get the current camera angles.
	 */
	public function JSgetCamAngles():Object {
		if(!this.chartEnabled){
			this.log("Call Ignored", "The chart is not in a state to return view angles.", Logger.LEVEL.ERROR);
			return;
		}
		return this.system3D.getCameraAngs();
	}
	/**
	 * JSanimateToScaleFit method is called by javascript
	 * to best fit the chart in the available space.
	 */
	public function JSanimateToScaleFit():Void {
		if(!this.chartEnabled){
			this.log("Call Ignored", "The chart is not in a state to scale view to fit.", Logger.LEVEL.ERROR);
			return;
		}
		this.animateToScaleFit();
	}
	
	/**
	 * JSanimateTo100Percent method is called by javascript
	 * to show 100% view of the chart.
	 */
	 public function JSanimateTo100Percent():Void{
		 if(!this.chartEnabled){
			this.log("Call Ignored", "The chart is not in a state to scale view to 100%.", Logger.LEVEL.ERROR);
			return;
		}
		this.animateToScale100();
	 }
	 
	/**
	 * changeView method is called to change view angles
	 * without animation to specified angles.
	 */
	private function changeView(xAng:Number, yAng:Number) {
		// hide tooltip
		this.tTip.hide();
		// update camera to the angles specified
		this.system3D.updateCamera(MathExt.roundUp(xAng), MathExt.roundUp(yAng));
		// recreate chart
		this.system3D.recreate();
		// update flag
		this.stageUpdated = true;
		// set tooltip interactivity
		this.setToolTipInteractions();
	}
	//---------------DATA EXPORT HANDLERS-------------------//
	/**
	 * Returns the data of the chart in CSV/TSV format. The separator, qualifier and line
	 * break character is stored in params (during common parsing).
	 * @return	The data of the chart in CSV/TSV format, as specified in the XML.
	 */
	public function exportChartDataCSV():String {
		var strData:String = "";
		var strQ:String = this.params.exportDataQualifier;
		var strS:String = this.params.exportDataSeparator;
		var strLB:String = this.params.exportDataLineBreak;
		var i:Number, j:Number;
		strData = strQ + ((this.params.xAxisName!="")?(this.params.xAxisName):("Label")) + strQ + strS;
		//Add all the series names
		for (i = 1; i <= this.numDS; i++) {
			strData += strQ + ((this.dataset[i].seriesName != "")?(this.dataset[i].seriesName):("")) + strQ + ((i < this.numDS)?(strS):(strLB));
		}
		//Iterate through each data-items and add it to the output
		for (i = 1; i <= this.num; i ++)
		{
			//Add the category label
			strData += strQ + (this.categories [i].label)  + strQ + strS;
			//Add the individual value for datasets
			for (j = 1; j <= this.numDS; j ++)
			{
				 strData += strQ + ((this.dataset[j].data[i].isDefined==true)?((this.params.exportDataFormattedVal==true)?(this.dataset[j].data[i].formattedValue):(this.dataset[j].data[i].value)):(""))  + strQ + ((j<this.numDS)?strS:"");
			}
			if (i < this.num) {
				strData += strLB;
			}
		}
		break;
		return strData;
	}
}
