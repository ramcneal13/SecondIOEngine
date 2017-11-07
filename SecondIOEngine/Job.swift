//
//  Job.swift
//  SecondIOEngine
//
//  Created by Richard McNeal on 11/5/17.
//  Copyright © 2017 Richard McNeal. All rights reserved.
//

import Foundation

class Job {
	private var runTime:TimeInterval = 0.0
	private var fileName:String = ""
	private var target:FileTarget?
	private let formatter = DateComponentsFormatter()
	private var pattern:AccessPattern
	private var ioDepth = 1

	init() {
		formatter.unitsStyle = .full
		formatter.includesApproximationPhrase = true
		formatter.includesTimeRemainingPhrase = false
		formatter.allowedUnits = [.minute, .second, .hour, .day]
		pattern = AccessPattern()
		sizeStr = ""
	}
	
	var sizeStr:String {
		didSet {
			target?.sizeStr = sizeStr
		}
	}
	var fileNameStr:String {
		get { return fileName}
		set {
			do {
				try target = FileTarget(name: newValue)
			} catch {
				print("Failed to open \(newValue)")
			}
			fileName = newValue
			if sizeStr != "" {
				target?.sizeStr = sizeStr
			}
		}
	}
	var runTimeStr:String {
		get {return formatter.string(from: runTime)!}
		set { runTime = convertTimeStr(newValue)}
	}
	var patternStr:String {
		get {return pattern.text}
		set {pattern.text = newValue}
	}
	var ioDepthStr:String {
		get {return String(ioDepth)}
		set {ioDepth = Int(newValue) ?? 1}
	}
	
	deinit {
		self.close()
	}
	func close() {
		target?.close()
	}
	func prep() -> Bool {
		guard target != nil else { return false }
		var rval = target?.prepFile() ?? false
		if let size = target?.getSize() {
			pattern.setSize(v: size)
			pattern.text = patternStr
		} else {
			rval = false
		}
		target?.prepBuffers(max: pattern.getMaxBlockSize())
		return rval
	}
	private var graphView:ViewController?
	private var runQ:DispatchQueue = DispatchQueue(label: "Runners", attributes: .concurrent)
	private var currentTotal:Int64 = 0
	private var jobRunning = false

	private var jobs = [Runner]()
	func tallyStat(runnerStat:Int64) {
		currentTotal += runnerStat
	}

	// Need to maintain a strong reference to the timer. If it falls out of scope the timer will
	// not fire. For example, if the timer was declared inside of the method execute() will not
	// fire because execute completes and the scope ends. This is what I was doing and couldn't
	// figure it out for a long time. Whereas in goManGo() below the timer worked because
	// it never fell out of context. Thank heavens for Google.
	private let ticker = DispatchSource.makeTimerSource(flags: [], queue: DispatchQueue.main)
	func execute(viewer:ViewController) {
		guard target != nil else { return }
		ticker.schedule(deadline: .now(), repeating: .seconds(1))
		ticker.setEventHandler {
			self.graphView?.addToGraph(throughput: self.currentTotal)
			self.currentTotal = 0
		}
		ticker.resume()
		graphView = viewer

		for i in 0..<self.ioDepth {
			let r = Runner(id: i, p: self.pattern, t: self.target!)
			self.jobs.append(r)
			self.runQ.async {
				r.goManGo(self)
			}
		}

		jobRunning = true
		runQ.asyncAfter(deadline: .now() + runTime) {
			if self.jobRunning {
				self.stop()
			}
		}
	}
	
	// Will be called if the runtime for this job has expired or
	// the user presses the stop button.
	func stop() {
		jobRunning = false
		for j in jobs {
			j.stop()
		}
		ticker.suspend()
		DispatchQueue.main.async {
			self.graphView?.jobCompleted()
		}
	}
}

class Runner {
	private let ID:Int
	private let pattern:AccessPattern
	private let target:FileTarget
	private var bytesXfer:Int64 = 0
	private var lastXfer:Int64 = 0
	private var runLoop = true
	
	init(id:Int, p:AccessPattern, t:FileTarget) {
		ID = id
		pattern = p
		target = t
	}
	
	func stop() { runLoop = false }
	func goManGo(_ parent:Job) {
		let ticker = DispatchSource.makeTimerSource(flags: [], queue: DispatchQueue.main)
		ticker.schedule(deadline: .now(), repeating: .seconds(1))
		ticker.setEventHandler {
			let cur = self.bytesXfer
			parent.tallyStat(runnerStat: cur - self.lastXfer)
			self.lastXfer = cur
		}
		ticker.resume()
		var last:Int64 = 0
		while runLoop {
			let ior = pattern.gen(lastBlk: last)
			last = ior.block
			try? self.target.doOp(request: ior)
			bytesXfer += Int64(ior.size)
		}
	}
}

class AccessPattern {
	var rawPattern:String = ""
	var fileSize:Int64 = 0
	var valid:Bool = false
	var largestBlockRequest = 0
	var text:String {
		get {return rawPattern}
		set(newValue) {
			rawPattern = newValue
			do {
				try decodePattern()
				valid = true
			} catch {
				rawPattern = "Invalid Pattern"
				valid = false
			}
		}
	}
	var accessArray:[accessEntry]
	
	init() {
		accessArray = [accessEntry]()
	}
	
	func setSize(v:Int64) { fileSize = v }
	func isValid() -> Bool { return valid }
	func gen(lastBlk last:Int64) -> ioRequest {
		var r = Int(arc4random_uniform(100))
		for entry in accessArray {
			if r < entry.percentage {
				var newOp:OpType
				switch entry.op {
				case .RandRead, .SeqRead: newOp = .FileRead
				case .RandWrite, .SeqWrite: newOp = .FileWrite
				case .RandRW:
					switch arc4random_uniform(2) {
					case 0: newOp = .FileRead
					case 1: newOp = .FileWrite
					default: newOp = .None
					}
				default: newOp = .None
				}
				var blk:Int64
				switch entry.op {
				case .RandRead, .RandWrite, .RandRW:
					blk = Int64(arc4random_uniform(UInt32(entry.len) / UInt32(entry.blockSize))) *
						Int64(entry.blockSize)
				case .SeqRead, .SeqWrite: blk = last + 1
				default: blk = 0
				}
				return ioRequest(op: newOp, size: entry.blockSize, block: blk)
			}
			r -= entry.percentage
		}
		return ioRequest(op: .None, size: 0, block: 0)
	}
	
	func getMaxBlockSize() -> Int { return largestBlockRequest }
	private func decodePattern() throws {
		/* --- Start over each time ---- */
		accessArray.removeAll()
		
		let perSize = fileSize / 100
		var startBlock:Int64 = 0
		let totalPatterns = rawPattern.split(separator: ",")
		for pattern in totalPatterns {
			let tuple = pattern.split(separator: ":")
			var ae = accessEntry()
			if tuple.count != 3 {
				print("Invalid pattern \(pattern)")
				throw AccessEntryError.InvalidPatternCount
			}
			guard let per = Int(tuple[0]) else {
				throw AccessEntryError.InvalidPercentage
			}
			ae.percentage = per
			switch tuple[1] {
			case "randread": ae.op = .RandRead
			case "randwrite": ae.op = .RandWrite
			case "rw": ae.op = .RandRW
			case "seqread": ae.op = .SeqRead
			case "seqwrite": ae.op = .SeqWrite
			default: throw AccessEntryError.InvalidOp
			}
			ae.blockSize = Int(convertHumanSize(String(tuple[2])))
			if largestBlockRequest < ae.blockSize {
				largestBlockRequest = ae.blockSize
			}
			ae.start = startBlock
			ae.len = perSize * Int64(ae.percentage)
			startBlock += ae.len
			accessArray.append(ae)
		}
		
		/* ---- Make sure total of patterns doesn't go over 100% ---- */
		var totalPer = 0
		for ae in accessArray {
			totalPer += ae.percentage
		}
		if totalPer > 100 {
			throw AccessEntryError.Over100Percent
		} else if totalPer < 100 {
			var ae = accessEntry()
			ae.percentage = 100 - totalPer
			ae.op = .None
			ae.blockSize = 0
			accessArray.append(ae)
		}
	}
}
