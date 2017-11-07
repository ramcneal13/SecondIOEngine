//
//  ProgTypes.swift
//  SecondIOEngine
//
//  Created by Richard McNeal on 11/4/17.
//  Copyright © 2017 Richard McNeal. All rights reserved.
//

import Foundation

public enum OpType {
	case RandRead
	case RandWrite
	case RandRW
	case SeqRead
	case SeqWrite
	case None
	case FileRead
	case FileWrite
}

struct accessEntry {
	var percentage:Int = 0
	var op:OpType = .None
	var blockSize:Int = 0
	var start:Int64 = 0
	var len:Int64 = 0
}

enum AccessEntryError: Error {
	case InvalidPatternCount
	case InvalidPercentage
	case InvalidOp
	case InvalidBlock
	case Over100Percent
}

public struct ioRequest {
	var op:OpType
	var size:Int
	var block:Int64
}

