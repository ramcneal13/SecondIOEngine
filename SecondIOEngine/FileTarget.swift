//
//  FileTarget.swift
//  FirstIOEngine
//
//  Created by Richard McNeal on 10/29/17.
//  Copyright © 2017 Richard McNeal. All rights reserved.
//

import Foundation

public enum FileErrors: Error {
	case openFailure(name:String, error_num:Int32)
	case statFailure(error_num:Int32)
	case badFileSize
	case invalidType
	case readFailure(block:Int64)
	case writeFailure(block:Int64)
}

enum FileMode {
	case RegFile
	case Dir
	case Block
	case Char
	case Link
	case Unknown
}

public class FileTarget {
	private var fileName:String
	private var fileFD:Int32 = 0
	private var statData:stat
	private var bufData:UnsafeMutablePointer<Int64>
	private var bufSize = 1024
	private var removeOnClose = false

	private var size:Int64 = 0
	var sizeStr:String {
		get {return ByteCountFormatter.string(fromByteCount: size, countStyle: .binary)}
		set(input) { size = convertHumanSize(input)}
	}
	func getSize() -> Int64 { return size }
	
	init(name:String) throws {
		fileName = name
		var flags = O_RDWR
		statData = stat()
		if stat(fileName, &statData) < 0 {
			flags |= O_CREAT
			removeOnClose = true
		}
		fileFD = open(fileName, flags, 0o666)
		if fileFD < 0 {
			throw FileErrors.openFailure(name: fileName, error_num: errno)
		}
		guard stat(fileName, &statData) == 0 else {
			throw FileErrors.statFailure(error_num: errno)
		}
		size = statData.st_size
		bufData = UnsafeMutablePointer.allocate(capacity: bufSize)
	}
	deinit {
		self.close()
	}
	func close() {
		bufData.deallocate(capacity: bufSize)
		Darwin.close(fileFD)
		if removeOnClose{
			unlink(fileName)
		}
	}
	
	private func mode() -> FileMode {
		let m = Int32(statData.st_mode) & Int32(S_IFMT)
		switch m {
		case Int32(S_IFREG): return .RegFile
		case Int32(S_IFDIR): return .Dir
		case Int32(S_IFBLK): return .Block
		case Int32(S_IFCHR): return .Char
		case Int32(S_IFLNK): return .Link
		default: return .Unknown
		}
	}
	
	func prepFile() -> Bool {
		if mode() == .RegFile {
			if statData.st_size > size {
				/* --- File exists and is larger than we need, we're done ---- */
				size = statData.st_size
				return true
			} else if statData.st_size == 0 && size == 0 {
				return false
			} else if statData.st_size == size {
				/* ---- File with existing data is good to go ---- */
				return true
			}
			let initHandle = FileHandle(fileDescriptor: fileFD)
			let initSize = 1024 * 1024
			var initData = Data(capacity: initSize)
			for pos in 0..<initSize {
				initData.append(UInt8(pos&0xff))
			}
			for _ in stride(from: 0, to: size, by: initSize) {
				initHandle.write(initData)
			}
			initHandle.synchronizeFile()
			initHandle.seek(toFileOffset: 0)
		}
		return true
	}
	func prepBuffers(max size:Int) {
		bufData.deallocate(capacity: bufSize)
		bufData = UnsafeMutablePointer.allocate(capacity: size)
		bufData.initialize(to: 0xbad_cafe_dead_beef, count: size / 8)
		bufSize = size
	}
	
	func doOp(request ior:ioRequest) throws {
		switch ior.op {
		case .FileRead:
			guard pread(fileFD, bufData, Int(ior.size), ior.block) == ior.size else {
				throw FileErrors.readFailure(block: ior.block)
			}
		case .FileWrite:
			guard pwrite(fileFD, bufData, Int(ior.size), ior.block) == ior.size else {
				throw FileErrors.writeFailure(block: ior.block)
			}
		default: print("Oops!")
		}
	}
}
