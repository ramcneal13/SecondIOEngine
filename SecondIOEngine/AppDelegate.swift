//
//  AppDelegate.swift
//  SecondIOEngine
//
//  Created by Richard McNeal on 11/4/17.
//  Copyright © 2017 Richard McNeal. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

	var view:ViewController?
	func applicationDidFinishLaunching(_ aNotification: Notification) {
		// Insert code here to initialize your application
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		// Insert code here to tear down your application
	}

	func storeView(v:ViewController) { view = v }
	@IBAction func openConfig(_ sender: NSMenuItem) {
		let openPanel = NSOpenPanel()
		openPanel.allowsMultipleSelection = false;
		openPanel.canChooseDirectories = false;
		openPanel.canCreateDirectories = false;
		openPanel.canChooseFiles = true;
		if openPanel.runModal() == .OK {
			view?.loadConfig(openPanel.urls[0])
		}
	}
}

