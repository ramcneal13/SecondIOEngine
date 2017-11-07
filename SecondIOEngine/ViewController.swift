//
//  ViewController.swift
//  SecondIOEngine
//
//  Created by Richard McNeal on 11/4/17.
//  Copyright © 2017 Richard McNeal. All rights reserved.
//

import Cocoa
import CoreGraphics

fileprivate enum cellName {
	static let nameCell = "ConfigKey"
	static let valueCell = "ConfigValue"
}

fileprivate let jobParams = ["name", "verbose", "runtime", "size", "iodepth", "pattern"]
extension NSViewController {
	var appDelegate:AppDelegate {
		return NSApplication.shared.delegate as! AppDelegate
	}
}

extension ViewController: NSTableViewDataSource {
	public func numberOfRows(in tableView: NSTableView) -> Int { return jobParams.count }
}

extension ViewController: NSTableViewDelegate {
	public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		if config == nil || config?.isValid() == false {
			return nil
		}
		
		var textStr: String = ""
		var cellID: String = ""
		if tableColumn == tableView.tableColumns[0] {
			textStr = jobParams[row]
			cellID = cellName.nameCell
		} else if tableColumn == tableView.tableColumns[1] {
			if let item = jobsArray.selectedItem {
				let job = item.title
				self.config?.setParam(job, jobParams[row]) { v in textStr = v }
			} else {
				textStr = ""
			}
			cellID = cellName.valueCell
		}
		if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: cellID), owner: nil) as? NSTableCellView {
			cell.textField?.stringValue = textStr
			cell.imageView?.image = nil
			return cell
		}
		return nil
	}
}

struct buttonNames {
	static let StartName = "Start"
	static let StopName = "Stop"
}

class ViewController: NSViewController {

	private var config:ParseINIConfig?
	private var curJob:Job?
	private let tick = DispatchSource.makeTimerSource(flags: [], queue: DispatchQueue.main)
	private var startTime = Date()
	private let dateFormat = DateComponentsFormatter()
	@IBAction func JobSelection(_ sender: NSPopUpButton) {
		let b = sender.selectedItem!
		loadJob(b.title)
	}
	@IBOutlet var jobsArray: NSPopUpButton!
	@IBOutlet var jobTable: NSTableView!
	@IBOutlet var statusMsg: StatusText!
	@IBOutlet var loadGraph: HistoGraph!
	@IBOutlet var startButton: NSButton!
	@IBOutlet var runtimeText: NSTextField!
	@IBOutlet var throughputText: NSTextField!
	@IBAction func startJob(_ sender: NSButton) {
		if sender.title == buttonNames.StartName {
			curJob = Job()
			if let item = jobsArray.selectedItem {
				let jobName = item.title
				config?.setParam(jobName, "name") { v in curJob?.fileNameStr = v}
				config?.setParam(jobName, "size") { v in curJob?.sizeStr = v}
				config?.setParam(jobName, "runtime") { v in curJob?.runTimeStr = v}
				config?.setParam(jobName, "iodepth") { v in curJob?.ioDepthStr = v}
				config?.setParam(jobName, "pattern") { v in curJob?.patternStr = v}
				if curJob?.prep() == false {
					statusMsg.addMsg(str: "job failed to prep")
					return
				}
				curJob?.execute(viewer: self)
				sender.title = buttonNames.StopName
				startTime = Date()
				tick.schedule(deadline: .now(), repeating: .seconds(1))
				tick.setEventHandler {
					
					let duration = self.dateFormat.string(from: self.startTime.timeIntervalSinceNow * -1)
					self.runtimeText.stringValue = duration ?? "(empty)"
				}
				tick.resume()
			}
		} else if sender.title == buttonNames.StopName {
			curJob?.stop()
			// curJob will use callback jobCompleted() so our ticker will be
			// canceled and the button name changed back to "Start"
		} else {
			statusMsg.addMsg(str: "sender.title='\(sender.title)'")
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()

		// Do any additional setup after loading the view.
		appDelegate.storeView(v: self)
		jobsArray.removeAllItems()
		jobTable.delegate = self
		jobTable.dataSource = self
		
		let homeDir = FileManager.default.homeDirectoryForCurrentUser
		let fileURL = homeDir.appendingPathComponent("engine").appendingPathExtension("ini")
		loadConfig(fileURL)
		loadGraph.needsDisplay = true
		loadGraph.displayIfNeeded()

		dateFormat.unitsStyle = .positional
		dateFormat.allowedUnits = [ .hour, .minute, .second ]
		dateFormat.zeroFormattingBehavior = [ .pad ]
	}

	override var representedObject: Any? {
		didSet {
		// Update the view, if already loaded.
		}
	}
	func loadConfig(_ file:URL) {
		do {
			try config = ParseINIConfig(file)
		} catch FileErrors.openFailure(let msg, _) {
			statusMsg.addMsg(str: msg)
			return
		} catch {
			statusMsg.addMsg(str: "unknown system error")
			return
		}
		if config?.parse() == false {
			statusMsg.addMsg(str: "Oops, syntax error")
			return
		}
		jobsArray.addItems(withTitles: config!.requestJobs())
		jobTable.reloadData()
	}
	func loadJob(_ name:String) {
		if config!.jobNameValid(name) {
			jobTable.reloadData()
			loadGraph.clear()
			runtimeText.stringValue = ""
			throughputText.stringValue = ""
		}
	}
	func jobCompleted() {
		tick.suspend()
		startButton.title = buttonNames.StartName
	}
	func addToGraph(throughput:Int64) {
		DispatchQueue.main.async {
			self.throughputText.stringValue = ByteCountFormatter.string(fromByteCount: throughput,
										    countStyle: .binary)
		}
		loadGraph.add(throughput)
	}
}

class HistoGraph: NSView {
	private let dateFormat = DateComponentsFormatter()
	private var dataPoints:[Int64] = [Int64]()
	
	func add(_ v:Int64) {
		dataPoints.append(v)
		if dataPoints.count >= Int64(frame.width - 10) {
			dataPoints.remove(at: 0)
		}
		needsDisplay = true
		displayIfNeeded()
	}
	
	func clear() {
		dataPoints.removeAll()
		needsDisplay = true
		displayIfNeeded()
	}
	
	func drawTimeLabels() {
		let bezier = NSBezierPath()
		
		dateFormat.unitsStyle = .positional
		dateFormat.allowedUnits = [ .hour, .minute, .second ]
		dateFormat.zeroFormattingBehavior = [ .pad ]
		
		let duration = dateFormat.string(from: TimeInterval(frame.width - 2))
		if let d = duration as NSString? {
			let strBox = d.size()
			let point = CGPoint(x: frame.width - strBox.width, y: 0)
			d.draw(at: point)
		}

		for i in stride(from: 60, to: frame.width, by: 60) {
			bezier.move(to: CGPoint(x: i, y: 15))
			bezier.line(to: CGPoint(x: i, y: 20))
			bezier.close()
			bezier.stroke()
		}
	}
	func drawGrid() {
		
	}
	override func draw(_ dirtyRect: NSRect) {
		NSColor.green.setStroke()
		let bezier = NSBezierPath(roundedRect: CGRect(origin: CGPoint(x: 1, y: 21),
							      size: NSSize(width: frame.width - 2,
									   height: frame.height - 22)),
					  xRadius: 5, yRadius: 5)
		bezier.lineWidth = 1
		bezier.stroke()
		NSColor.black.set()

		drawTimeLabels()
		drawGrid()
		
		let hiVal = dataPoints.reduce(Int64(0)) {
			if $1 > $0 { return $1 } else { return $0 }
		}
		var scaler = hiVal / Int64(frame.height - 30)
		if scaler == 0 {
			scaler = 1
		}
		bezier.move(to: NSPoint(x: 5, y: 25))
		for (k, v) in dataPoints.enumerated() {
			bezier.line(to: NSPoint(x: k + 5, y: Int(v) / Int(scaler) + 25))
		}
		bezier.stroke()
	}
}

class StatusText: NSTextField {
	private var msgArray:[String] = [String]()
	func addMsg(str:String) {
		msgArray.append(str)
		guard msgArray.count == 1 else { return }
		displayMsg()
	}
	func displayMsg() {
		guard msgArray.count != 0 else { return }
		self.stringValue = msgArray.remove(at: 0)
		DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
			self.stringValue = ""
			self.displayMsg()
		}
	}
}

