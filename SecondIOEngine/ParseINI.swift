//
//  Config.swift
//  FirstIOEngine
//
//  Created by Richard McNeal on 11/2/17.
//  Copyright © 2017 Richard McNeal. All rights reserved.
//

import Foundation
import Cocoa

typealias sectionData = [String:String]
extension UInt8 {
	var char: Character {
		return Character(UnicodeScalar(self))
	}
}

public class ParseINIConfig {
	private var fileName:String = ""
	private var handle:FileHandle?
	private var currentLine:String = ""
	private var configStrings:[String]
	private var sections:[String:sectionData] = [:]
	private var verbose = false
	private let GlobalSection = "global"
	
	init(_ file:URL) throws {
		configStrings = [String]()
		do {
			try handle = FileHandle(forReadingFrom: file)
		} catch {
			throw FileErrors.openFailure(name: "Oops, failed to open FileHandle for '\(file)'", error_num: 0)
		}
	}
	
	private func appendToCurrent(b:UInt8) {
		if b.char == "\n" {
			configStrings.append(currentLine)
			currentLine.removeAll()
		} else {
			currentLine.append(b.char)
		}
	}
	
	private func boundedName(str:String, beg:String, end:String) -> String? {
		if str.hasPrefix(beg) && str.hasSuffix(end) {
			let startIdx = str.index(str.startIndex, offsetBy: 1)
			let endIdx = str.index(str.endIndex, offsetBy: -1)
			let strRange = Range(uncheckedBounds: (lower: startIdx, upper: endIdx))
			return String(str[strRange])
		} else {
			return nil
		}
	}
	func enableParseDisplay() { verbose = true }
	func isValid() -> Bool { return handle != nil }
	func parse() -> Bool {
		if handle == nil {
			return false
		}
		let d = handle?.readDataToEndOfFile()
		var workingSection = "FUBAR"
		d?.forEach { byte in appendToCurrent(b: byte) }
		if currentLine.count != 0 {
			configStrings.append(currentLine)
		}
		for l in configStrings {
			if let sec = boundedName(str: l, beg: "[", end: "]") {
				switch sec {
				case GlobalSection:
					workingSection = sec
				default:
					let possibleJob = sec.split(separator: " ")
					if possibleJob.count == 2 {
						if let jobSection = boundedName(str: String(possibleJob[1]),
										beg: "\"", end: "\"") {
							workingSection = jobSection
						} else {
							return false
						}
					} else {
						return false
					}
				}
				sections[workingSection] = sectionData()
			} else if l != "" {
				let opts = l.split(separator: "=")
				if opts.count == 2 {
					sections[workingSection]![String(opts[0])] = String(opts[1])
				} else {
					sections[workingSection]![String(opts[0])] = "true"
				}
			}
		}
		if verbose {
			print("---- Dumping results of config ----")
			for (k, v) in sections {
				print("Section: \(k)")
				for (d, v1) in v {
					print("    \(d)" + " = " + "\(v1)")
				}
			}
		}
		return true
	}
	
	func setParam(_ section:String, _ param:String, process: ((String) -> Void)) {
		if let p = requestParam(section: section, param: param) {
			process(p)
		}
	}
	
	private func requestParam(section:String, param:String) -> String? {
		if let s = sections[section] {
			if let p = s[param] {
				return p
			} else {
				// If the request isn't in the current section see
				// if the global section has the parameter set and if
				// so return that one.
				if let p = sections[GlobalSection]![param] {
					return p
				}
			}
		}
		return nil
	}
	
	func jobNameValid(_ name:String) -> Bool {
		if sections[name] != nil {
			return true
		} else {
			return false
		}
	}
	
	func requestJobs() -> [String] {
		var rval = [String]()
		for (k, _) in sections {
			if k != GlobalSection {
				rval.append(k)
			}
		}
		return rval
	}
}
