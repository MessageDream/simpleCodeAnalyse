#!/usr/bin/swift

//  codeAnalyse.swift
//  fileReader
//
//  Created by jayden on 15/8/30.
//  Copyright © 2015年 jayden. All rights reserved.
//

import Foundation
import Darwin

extension NSData{
	
	func rangeOfDataWith(dataToFind:NSData) -> NSRange {
	 
	 let bytes = self.bytes
	 let length = self.length
	 
	 let searchBytes = dataToFind.bytes
	 let searchLength = dataToFind.length
	 
	 var searchIndex = 0
	 
	 var foundRange = NSRange(location: NSNotFound, length: searchLength)
	 for index in 0..<length{
	     let by = unsafeBitCast(bytes,UnsafeMutablePointer<CChar>.self)
	     let searchBy = unsafeBitCast(searchBytes,UnsafeMutablePointer<CChar>.self)
	     if by[index] == searchBy[searchIndex] {
	         if (foundRange.location == NSNotFound) {
	             foundRange.location = index
	         }
	         searchIndex++;
	         if searchIndex >= searchLength { return foundRange}
	     }else{
	         searchIndex = 0
	         foundRange.location = NSNotFound
	     }
	 }
	 return foundRange;
	}
}

struct TextReader {
	
	var currentOffset:UInt64 = 0;
	let chunkSize = 10;
	let lineDelimiter = "\n"
	let fileHandle:NSFileHandle!
	
	var totalFileLength:UInt64 = 0
	
	init(path:String){
	 fileHandle = NSFileHandle(forReadingAtPath: path);
	 fileHandle.seekToEndOfFile();
	 totalFileLength = fileHandle.offsetInFile
	}
	
	init(fileHandler:NSFileHandle){
	 fileHandle = fileHandler
	 fileHandle.seekToEndOfFile();
	 totalFileLength = fileHandle.offsetInFile
	}
	
	mutating func readLine() -> String?{
	 if currentOffset >= totalFileLength { return nil }
	 
	 let newLineData = lineDelimiter.dataUsingEncoding(NSUTF8StringEncoding)
	 fileHandle!.seekToFileOffset(currentOffset)
	 let currentData = NSMutableData()
	 
	 var shouldReadMore = true
	 
	 while shouldReadMore {
	     if currentOffset >= totalFileLength { break }
	     var chunk = fileHandle?.readDataOfLength(chunkSize)
	     let newLineRange = chunk!.rangeOfDataWith(newLineData!)
	     if newLineRange.location != NSNotFound {
	 
	         chunk = chunk!.subdataWithRange(NSRange(location:0, length:newLineRange.location + newLineData!.length))
	         shouldReadMore = false
	     }
	     currentData.appendData(chunk!)
	     if let len = chunk?.length{
	         currentOffset += UInt64(len)
	     }
	 }
	 
	 return String(data: currentData, encoding: NSUTF8StringEncoding)
	}
}

func readFileWith(fileManager:NSFileManager, filePath:String,@noescape condition:(displayName:String) -> Bool, @noescape analyse:(path:String) -> (Int,Int,Int,Int)) -> (Int,Int,Int,Int){
	
	func isDir(path:String) -> Bool{
	 var isDirectory: ObjCBool = false
	 _ = fileManager.fileExistsAtPath(path , isDirectory:&isDirectory)
	 return isDirectory.boolValue
	}
	
	if condition(displayName: fileManager.displayNameAtPath(filePath)) {
	 if isDir(filePath){
	     do{
	         let contents = try fileManager.contentsOfDirectoryAtPath(filePath)
	         var r1=0,r2=0,r3=0,r4=0
	         for item in contents{
	             let itemPath = "\(filePath)/\(item)"
	             let (c1,c2,c3,c4) =  readFileWith(fileManager, filePath: itemPath, condition: condition, analyse: analyse)
	             r1 += c1
	             r2 += c2
	             r3 += c3
	             r4 += c4
	         }
	         return (r1,r2,r3,r4)
	     }catch let error {
	         print(error)
	         return (0,0,0,0)
	     }
	 
	 }else{
	     return analyse(path: filePath)
	 }
	}
	return (0,0,0,0)
}

func dropFirstArgument(arguments:[String]) -> [String]{
	var newArguments = [String]()
	for item in arguments{
	 if item != arguments[0] {
	     newArguments.append(item)
	 }
	}
	return newArguments;
}

let arguments = dropFirstArgument(Process.arguments)
let option = arguments[0]
if option == "-c"{
	let fpath = arguments[1]
	let author = arguments[2]
	
	let (fileCount,lineCount,findUserFileCount,findUserLineCount) = readFileWith(NSFileManager.defaultManager(),
	 filePath:fpath ,
	 condition: {
	     (!$0.containsString(".") && $0 != "open_api" && $0 != "resource_define") || $0.hasSuffix(".m") || $0.hasSuffix(".h")
	 }) { (path) -> (Int, Int, Int, Int) in
	 
	     var fileCount = 1,lineCount = 0,findUserFileCount = 0,findUserLineCount = 0
	     var isAuthor = false
	     var textReader = TextReader(path: path)
	     while let strLine = textReader.readLine(){
	         if(strLine == "\n") {
	             continue
	         }
	         lineCount++
	         if strLine.lowercaseString.containsString(author){
	             isAuthor = true
	         }
	     }
	 
	     print("\(path) => \(lineCount)")
	 
	     if isAuthor{
	         findUserFileCount = 1
	         findUserLineCount = lineCount
	     }
	     return (fileCount,lineCount,findUserFileCount,findUserLineCount)
	}
	
	print("\n dir -> \(fpath) \n totalFiles:\(fileCount),\n totalCodeLines:\(lineCount),\n totalFilesBy -> \(author):\(findUserFileCount), \n totalCodeLinesBy -> \(author):\(findUserLineCount)\n")
	
}else if option == "-h"{
	
	var changeCount = 0, insertCount = 0, deleteCount = 0
	
	let fpath = arguments[1]
	let author = arguments[2]
	
	let task = NSTask()
	task.launchPath = "/bin/sh"
	task.arguments = ["-c","git --git-dir=\(fpath)/.git log --author=\(author) --shortstat --pretty=format:\"\""]
	let pipe = NSPipe()
	task.standardOutput = pipe
	let outHandle = pipe.fileHandleForReading
	outHandle.waitForDataInBackgroundAndNotify()
	
	var obs1 : NSObjectProtocol!
	obs1 = NSNotificationCenter.defaultCenter().addObserverForName(NSFileHandleDataAvailableNotification,
	 object: outHandle, queue: nil) {  notification -> () in
	     let data = outHandle.availableData
	     if data.length > 0 {
	         if let str = String(data: data, encoding: NSUTF8StringEncoding) {
	             print("got output: \(str)")
	             let components = str.componentsSeparatedByCharactersInSet(NSCharacterSet(charactersInString: ",\n"))
//	             print(components)
	             for item in components{
	                 let com = item.componentsSeparatedByCharactersInSet(NSCharacterSet(charactersInString: " "))
	                 if com.count > 1{
	                     let key = com.last
	                     let v = Int(com[1])!
	                     switch key! {
	                     case "changed":
	                         changeCount += v
	                         break
	                     case "insertions(+)":
	                         insertCount += v
	                         break
	                     case "deletions(-)":
	                         deleteCount += v
	                     default:
	                         break
	                     }
	                 }
	             }
	         }
	         outHandle.waitForDataInBackgroundAndNotify()
	     } else {
	         print("EOF on stdout from process")
	         NSNotificationCenter.defaultCenter().removeObserver(obs1)
	     }
	}
	
	var obs2 : NSObjectProtocol!
	obs2 = NSNotificationCenter.defaultCenter().addObserverForName(NSTaskDidTerminateNotification,
	 object: task, queue: nil) { notification -> () in
	     print("terminated")
	     print(" \(changeCount) files changed\n \(insertCount) insertions(+)\n \(deleteCount) deletions(-)\n")
	     NSNotificationCenter.defaultCenter().removeObserver(obs2)
	}
	
	task.launch()
	task.waitUntilExit()
}
