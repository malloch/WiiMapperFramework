//
//  WiiRemote.h
//  DarwiinRemote
//
//  Created by KIMURA Hiroaki on 06/12/04.
//  Copyright 2006 KIMURA Hiroaki. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <IOBluetooth/objc/IOBluetoothDevice.h>
#import <IOBluetooth/objc/IOBluetoothL2CAPChannel.h>


typedef struct {
	int x, y, s;
} IRData;

typedef UInt16 WiiButtonType;
enum {
	kWiiRemoteTwoButton		= 0x0001,
	kWiiRemoteOneButton		= 0x0002,
	kWiiRemoteBButton		= 0x0004,
	kWiiRemoteAButton		= 0x0008,
	kWiiRemoteMinusButton	= 0x0010,
	kWiiRemoteHomeButton	= 0x0080,
	kWiiRemoteLeftButton	= 0x0100,
	kWiiRemoteRightButton	= 0x0200,
	kWiiRemoteDownButton	= 0x0400,
	kWiiRemoteUpButton		= 0x0800,
	kWiiRemotePlusButton	= 0x1000
};


@interface WiiRemote : NSObject {
	
	IOBluetoothDevice* wiiDevice;
	IOBluetoothL2CAPChannel *ichan;
	IOBluetoothL2CAPChannel *cchan;
	
	id _delegate;
	
	
	unsigned char accX;
	unsigned char accY;
	unsigned char accZ;
	unsigned short buttonData;
	
	float lowZ, lowX;
	int orientation;
	int leftPoint; // is point 0 or 1 on the left. -1 when not tracking.
	
	IRData	irData[4];
	double batteryLevel;
	double warningBatteryLevel;
	
	BOOL isMotionSensorEnabled, isIRSensorEnabled, isVibrationEnabled, isExpansionPortUsed;
	BOOL isLED1Illuminated, isLED2Illuminated, isLED3Illuminated, isLED4Illuminated;
	NSTimer* statusTimer;
	IOBluetoothUserNotification *disconnectNotification;
}

- (IOReturn)connectTo:(IOBluetoothDevice*)device;
- (void)setDelegate:(id)delegate;
- (double)batteryLevel;
- (BOOL)available;
- (IOReturn)closeConnection;
- (IOReturn)setIRSensorEnabled:(BOOL)enabled;
- (IOReturn)setForceFeedbackEnabled:(BOOL)enabled;
- (IOReturn)setMotionSensorEnabled:(BOOL)enabled;
- (IOReturn)setLEDEnabled1:(BOOL)enabled1 enabled2:(BOOL)enabled2 enabled3:(BOOL)enabled3 enabled4:(BOOL)enabled4;
- (IOReturn)writeData:(const unsigned char*)data at:(unsigned long)address length:(size_t)length;
- (IOReturn)sendCommand:(const unsigned char*)data length:(size_t)length;


@end


@interface NSObject( WiiRemoteDelegate )

- (void) dataChanged:(unsigned short)buttonData accX:(unsigned char)accX accY:(unsigned char)accY accZ:(unsigned char)accZ mouseX:(float)mx mouseY:(float)my;
- (void) wiiRemoteDisconnected;


@end