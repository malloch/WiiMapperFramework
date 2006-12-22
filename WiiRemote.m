//
//  WiiRemote.m
//  DarwiinRemote
//
//  Created by KIMURA Hiroaki on 06/12/04.
//  Copyright 2006 KIMURA Hiroaki. All rights reserved.
//

#import "WiiRemote.h"

// this type is used a lot (data array):
typedef unsigned char darr[];






@implementation WiiRemote

- (id) init{

	
	accX = 0x10;
	accY = 0x10;
	accZ = 0x10;
	buttonData = 0;
	leftPoint = -1;
	batteryLevel = 0;
	warningBatteryLevel = 0.05;

	
	_delegate = nil;
	wiiDevice = nil;
	
	ichan = nil;
	cchan = nil;
	
	isIRSensorEnabled = NO;
	isMotionSensorEnabled = NO;
	isVibrationEnabled = NO;
	isExpansionPortUsed = NO;
	
	//buttonAIsEnabled = buttonBIsEnabled = buttonOneIsEnabled = buttonTwoIsEnabled = buttonMinusIsEnabled = buttonHomeIsEnabled = buttonPlusIsEnabled = buttonLeftIsEnabled = buttonRightIsEnabled = buttonUpIsEnabled = buttonDownIsEnabled = NO;
	
	return self;
}

- (void)dealloc{
	//NSLog(@"dealloc");
	[self closeConnection];

	//NSLog(@"closed in dealloc");

	[super dealloc];
}

- (void)setDelegate:(id)delegate{
	_delegate = delegate;
}

- (BOOL)available{
	if (wiiDevice != nil)
		return YES;
	
	return NO;
}

- (IOReturn)connectTo:(IOBluetoothDevice*)device{
	
	wiiDevice = device;
	
	int trycount = 0;
	IOReturn ret;
	
	if (wiiDevice == nil){
		return kIOReturnBadArgument;
	}
	
	trycount = 0;
	while ((ret = [wiiDevice openConnection]) != kIOReturnSuccess){
		if (trycount >= 10){
			NSLog(@"could not open the connection (%d)...", ret);
			return ret;
		}
		trycount++;
		usleep(10000); //  wait 10ms
	}
	
	//[self retain];
	
	disconnectNotification = [wiiDevice registerForDisconnectNotification:self selector:@selector(disconnected:fromDevice:)];
	
	trycount = 0;
	while ((ret = [wiiDevice performSDPQuery:nil]) != kIOReturnSuccess){
		if (trycount == 10){
			NSLog(@"could not perform SDP Query (%d)...", ret);
			[wiiDevice closeConnection];
			return ret;
		}
		trycount++;
		usleep(10000); //  wait 10ms
	}
	
	trycount = 0;
	while ((ret = [wiiDevice openL2CAPChannelSync:&cchan withPSM:17 delegate:self]) != kIOReturnSuccess){
		if (trycount == 10){
			NSLog(@"could not open L2CAP channel cchan (%d)", ret);
			cchan = nil;
			[wiiDevice closeConnection];
			return ret;			
		}
		trycount++;
		usleep(10000); //  wait 10ms
	}	
	[cchan retain];
	
	trycount = 0;
	while ((ret = [wiiDevice openL2CAPChannelSync:&ichan withPSM:19 delegate:self]) != kIOReturnSuccess){	// this "19" is magic number ;-)
		if (trycount == 10){
			NSLog(@"could not open L2CAP channel ichan");
			ichan = nil;
			[cchan closeChannel];
			[cchan release];
			[wiiDevice closeConnection];
			
			return ret;			
		}
		trycount++;
		usleep(10000); //  wait 10ms
	}
	[ichan retain];
	
	trycount = 0;
	
	//sensor enable...
	ret = [self setMotionSensorEnabled:NO];
	if (kIOReturnSuccess == ret)
		ret = [self setIRSensorEnabled:NO];
	//stop force feedback
	if (kIOReturnSuccess == ret)
		ret = [self setForceFeedbackEnabled:NO];
	//turn LEDs off
	if (kIOReturnSuccess == ret)
		ret = [self setLEDEnabled1:NO enabled2:NO enabled3:NO enabled4:NO];
	
	if (kIOReturnSuccess != ret)
		[self closeConnection];
	
	statusTimer = [[NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(getCurrentStatus:) userInfo:nil repeats:YES] retain];
	[self getCurrentStatus:nil];
	[self readData:0x16 length:7];
	return ret;
}

- (void)disconnected: (IOBluetoothUserNotification*)note fromDevice: (IOBluetoothDevice*)device {
	//NSLog(@"disconnected.");
	
	if ([[device getAddressString] isEqualToString:[self address]]){
		[self closeConnection];
		if (nil != _delegate)
			[_delegate wiiRemoteDisconnected:device];
	}
	
}

- (IOReturn)sendCommand:(const unsigned char*)data length:(size_t)length{
	
	
	unsigned char buf[40];
	memset(buf,0,40);
	buf[0] = 0x52;
	memcpy(buf+1, data, length);
	if (buf[1] == 0x16) length=23;
	else				length++;
	
	int i;
	/**
	printf ("send%3d:", length);
	for(i=0 ; i<length ; i++) {
		printf(" %02X", buf[i]);
	}
	printf("\n");
	**/
	IOReturn ret;
	
	for (i = 0; i < 10; i++){
		ret = [cchan writeSync:buf length:length];
		if (kIOReturnSuccess == ret)
			break;
		usleep(10000);
	}
	
	
	
	return ret;
}


- (double)batteryLevel{
	
	return batteryLevel;
}

- (NSString*)address{
	return [wiiDevice getAddressString];
}

- (IOReturn)setMotionSensorEnabled:(BOOL)enabled{
	// these variables indicate a desire, and should be updated regardless of the sucess of sending the command
	isMotionSensorEnabled = enabled;
	
	unsigned char cmd[] = {0x12, 0x02, 0x30};
	if (isVibrationEnabled)	cmd[1] |= 0x01;
	if (isMotionSensorEnabled)	cmd[2] |= 0x01;
	if (isIRSensorEnabled)	cmd[2] |= 0x02;
	
	return [self sendCommand:cmd length:3];
}


- (IOReturn)setForceFeedbackEnabled:(BOOL)enabled{
	// these variables indicate a desire, and should be updated regardless of the sucess of sending the command
	isVibrationEnabled = enabled;
	
	unsigned char cmd[] = {0x13, 0x00};
	if (isVibrationEnabled)	cmd[1] |= 0x01;
	if (isIRSensorEnabled)	cmd[1] |= 0x04;
	
	return [self sendCommand:cmd length:2];
}

- (IOReturn)setLEDEnabled1:(BOOL)enabled1 enabled2:(BOOL)enabled2 enabled3:(BOOL)enabled3 enabled4:(BOOL)enabled4{
	unsigned char cmd[] = {0x11, 0x00};
	if (isVibrationEnabled)	cmd[1] |= 0x01;
	if (enabled1)	cmd[1] |= 0x10;
	if (enabled2)	cmd[1] |= 0x20;
	if (enabled3)	cmd[1] |= 0x40;
	if (enabled4)	cmd[1] |= 0x80;
	
	isLED1Illuminated = enabled1;
	isLED2Illuminated = enabled2;
	isLED3Illuminated = enabled3;
	isLED4Illuminated = enabled4;
	
	return 	[self sendCommand:cmd length:2];
}

-(IOReturn)setNunchukEnabled:(BOOL)enabled{
	
	[self setIRSensorEnabled:isIRSensorEnabled];
	
	//hmm...
	if (!enabled || !isExpansionPortUsed)
		return kIOReturnSuccess;
	
	//unsigned char cmd[] = {0x16, 0x04, 0xA4, 0x00, 0x40, 0x41};
	unsigned char cmd[] = {0x00};
	IOReturn ret = [self writeData:(darr){0x00} at:(unsigned long)0x04A40040 length:1];
	
	//IOReturn ret = [self sendCommand:cmd length:6];
	
	if (ret == kIOReturnSuccess){
		//get calbdata
		[self readData:0x04A40020 length: 16];
	}
	return ret;
}


//based on Ian's codes. thanks!
- (IOReturn)setIRSensorEnabled:(BOOL)enabled{
	IOReturn ret;
	
	isIRSensorEnabled = enabled;

	// set register 0x12 (report type)
	if (ret = [self setMotionSensorEnabled:isMotionSensorEnabled]) return ret;
	
	// set register 0x13 (ir enable/vibe)
	if (ret = [self setForceFeedbackEnabled:isVibrationEnabled]) return ret;
	
	// set register 0x1a (ir enable 2)
	unsigned char cmd[] = {0x1a, 0x00};
	if (enabled)	cmd[1] |= 0x04;
	if (ret = [self sendCommand:cmd length:2]) return ret;
	
	if(enabled){
		// based on marcan's method, found on wiili wiki:
		// tweaked to include some aspects of cliff's setup procedure in the hopes
		// of it actually turning on 100% of the time (was seeing 30-40% failure rate before)
		// the sleeps help it it seems
		usleep(10000);
		if (ret = [self writeData:(darr){0x01} at:0x04B00030 length:1]) return ret;
		usleep(10000);
		if (ret = [self writeData:(darr){0x08} at:0x04B00030 length:1]) return ret;
		usleep(10000);
		if (ret = [self writeData:(darr){0x90} at:0x04B00006 length:1]) return ret;
		usleep(10000);
		if (ret = [self writeData:(darr){0xC0} at:0x04B00008 length:1]) return ret;
		usleep(10000);
		if (ret = [self writeData:(darr){0x40} at:0x04B0001A length:1]) return ret;
		usleep(10000);
		if (ret = [self writeData:(darr){0x33} at:0x04B00033 length:1]) return ret;
		usleep(10000);
		if (ret = [self writeData:(darr){0x08} at:0x04B00030 length:1]) return ret;
		
	}else{
		// probably should do some writes to power down the camera, save battery
		// but don't know how yet.

		//bug fix #1614587 
		[self setMotionSensorEnabled:isMotionSensorEnabled];
		[self setForceFeedbackEnabled:isVibrationEnabled];
	}
	
	return kIOReturnSuccess;
}


- (IOReturn)writeData:(const unsigned char*)data at:(unsigned long)address length:(size_t)length{
	unsigned char cmd[22];
	//unsigned long addr = CFSwapInt32HostToBig(address);
	unsigned long addr = address;

	int i;
	for(i=0 ; i<length ; i++) {
		cmd[i+6] = data[i];
	}
	for(; i<16; i++) {
		cmd[i+6]= 0;
	}
	cmd[0] = 0x16;
	cmd[1] = (addr>>24)&0xFF;
	cmd[2] = (addr>>16)&0xFF;
	cmd[3] = (addr>> 8)&0xFF;
	cmd[4] = (addr>> 0)&0xFF;
	cmd[5] = length;
	
	// and of course the vibration flag, as usual
	if (isVibrationEnabled)	cmd[1] |= 0x01;
	
	data = cmd;
	
	return [self sendCommand:cmd length:22];
}


- (IOReturn)readData:(unsigned long)address length:(unsigned short)length{
	
	unsigned char cmd[7];
	
	//unsigned long addr = CFSwapInt32HostToBig(address);
	unsigned long addr = address;
	unsigned short len = CFSwapInt16HostToBig(length);
	
	cmd[0] = 0x17;
	cmd[1] = (addr>>24)&0xFF;
	cmd[2] = (addr>>16)&0xFF;
	cmd[3] = (addr>> 8)&0xFF;
	cmd[4] = (addr>> 0)&0xFF;
	
	cmd[5] = (len >> 8)&0xFF;
	cmd[6] = (len >> 0)&0xFF;
	
	
	if (isVibrationEnabled)	cmd[1] |= 0x01;
	
	
	return [self sendCommand:cmd length:7];
}


- (IOReturn)closeConnection{
	IOReturn ret = 0;
	int trycount = 0;
	
	
	
	if (disconnectNotification!=nil){
		[disconnectNotification unregister];
		disconnectNotification = nil;
	}
	
	
	if (cchan){
		if ([wiiDevice isConnected]) do {
			ret = [cchan closeChannel];
			trycount++;
		}while(ret != kIOReturnSuccess && trycount < 10);
		//NSLog(@"cchan count: %d", [cchan retainCount] );
		[cchan release];
	}

	
	trycount = 0;
	
	if (ichan){
		if ([wiiDevice isConnected]) do {
			ret = [ichan closeChannel];
			trycount++;
		}while(ret != kIOReturnSuccess && trycount < 10);
		//NSLog(@"ichan count: %d", [ichan retainCount] );
		[ichan release];
	}

	
	trycount = 0;
	
	if (wiiDevice){
		if ([wiiDevice isConnected]) do{
			ret = [wiiDevice closeConnection];
			trycount++;
		}while(ret != kIOReturnSuccess && trycount < 10);
		//NSLog(@"closed");
	}
	
	ichan = cchan = nil;
	wiiDevice = nil;
	
	// no longer a delegate
	//[self release];
	if (statusTimer){
		[statusTimer invalidate];
		[statusTimer release];
		statusTimer = nil;
		//NSLog(@"release timer");

	}

	
	return ret;
}


// thanks to Ian!
-(void)l2capChannelData:(IOBluetoothL2CAPChannel*)l2capChannel data:(void *)dataPointer length:(size_t)dataLength{
	if (!wiiDevice)
		return;
	unsigned char* dp = (unsigned char*)dataPointer;
	
	/**
	if (dp[1] == 0x22){
		int i;
		
		printf ("ack%3d:", dataLength);
		for(i=0 ; i<dataLength ; i++) {
			printf(" %02X", dp[i]);
		}
		printf("\n");
	}**/
	
	//reading ram data
	if (dp[1] == 0x21){
				
		//wii calibration data
		if (dataLength >= 14 && dp[5] == 0x00 && dp[6] == 0x16){
			//NSLog(@"calibData");

			wiiCalibData.accX_zero = dp[7];
			wiiCalibData.accY_zero = dp[8];
			wiiCalibData.accZ_zero = dp[9];
			
			wiiCalibData.accX_1g = dp[11];
			wiiCalibData.accY_1g = dp[12];
			wiiCalibData.accZ_1g = dp[13];
		}
		
		//Nunchuk calibration data
		if (dataLength >= 14 && dp[5] == 0x04 && dp[6] == 0xA4){
			//NSLog(@"calibData");
			nunchukCalibData.accX_zero = dp[7];
			nunchukCalibData.accY_zero = dp[8];
			nunchukCalibData.accZ_zero = dp[9];
			
			nunchukCalibData.accX_1g = dp[11];
			nunchukCalibData.accY_1g = dp[12];
			nunchukCalibData.accZ_1g = dp[13];
		}
	}
	
	
	//controller status (expansion port and battery level data)
	if (dp[1] == 0x20 && dataLength >= 8){
		batteryLevel = (double)dp[7];
		batteryLevel /= (double)0xC0;
		
		if (batteryLevel < warningBatteryLevel){
			[[NSNotificationCenter defaultCenter] postNotificationName:@"WiiRemoteBatteryLowNotification" object:self];
		}
		
		if ((dp[4] & 0x02)){

			if (!isExpansionPortUsed){
				isExpansionPortUsed = YES;

				[[NSNotificationCenter defaultCenter] postNotificationName:@"WiiRemoteExpansionPortChangedNotification" object:self];
			}
		}else{

			if (isExpansionPortUsed){
				isExpansionPortUsed = NO;

				[[NSNotificationCenter defaultCenter] postNotificationName:@"WiiRemoteExpansionPortChangedNotification" object:self];
			}
		}
		
		if ((dp[4] & 0x10)){
			isLED1Illuminated = YES;
		}else{
			isLED1Illuminated = NO;
		}
		
		if ((dp[4] & 0x20)){
			isLED2Illuminated = YES;
		}else{
			isLED2Illuminated = NO;
		}
		
		if ((dp[4] & 0x40)){
			isLED3Illuminated = YES;
		}else{
			isLED3Illuminated = NO;
		}
		
		if ((dp[4] & 0x80)){
			isLED4Illuminated = YES;
		}else{
			isLED4Illuminated = NO;
		}

		//have to reset settings (vibration, motion, IR and so on...)
		[self setIRSensorEnabled:isIRSensorEnabled];
		
	}
	
	if ((dp[1]&0xF0) == 0x30) {
		buttonData = ((short)dp[2] << 8) + dp[3];
		[self sendWiiRemoteButtonEvent:buttonData];
		//retrieve nunchuk data
		if (dp[1] == 0x32 || dp[1] == 0x34 || dp[1] == 0x36 || dp[1] == 0x37 || dp[1] == 0x3D){
			//NSLog(@"data is coming!!!");
			/**
			xStick = (dp[16] ^ 0x17) + 0x17;
			yStick = (dp[17] ^ 0x17) + 0x17;
			nAccX = (dp[18] ^ 0x17) + 0x17;
			nAccY = (dp[19] ^ 0x17) + 0x17;
			nAccZ = (dp[20] ^ 0x17) + 0x17;
			nButtonData = (dp[21] ^ 0x17) + 0x17;
			
			if (isExpansionPortUsed){
				NSLog(@"nunchuk buttonData");
				[self sendWiiNunchukButtonEvent:nButtonData];
				[_delegate accelerationChanged:WiiNunchukAccelerationSensor accX:nAccX accY:nAccY accZ:nAccZ];
			}**/
		}
		
		
		
		if (dp[1] & 0x01) {
			accX = dp[4];
			accY = dp[5];
			accZ = dp[6];
			
			[_delegate accelerationChanged:WiiRemoteAccelerationSensor accX:accX accY:accY accZ:accZ];
			
			
			lowZ = lowZ*.9 + accZ*.1;
			lowX = lowX*.9 + accX*.1;
			
			float absx = abs(lowX-128), absz = abs(lowZ-128);
			
			if (orientation == 0 || orientation == 2) absx -= 5;
			if (orientation == 1 || orientation == 3) absz -= 5;
			
			if (absz >= absx) {
				if (absz > 5)
					orientation = (lowZ > 128)?0:2;
			} else {
				if (absx > 5)
					orientation = (lowX > 128)?3:1;
			}
			
			//	printf("orientation: %d\n", orientation);
		}
		
		if (dp[1] & 0x02) {
			int i;
			for(i=0 ; i<4 ; i++) {
				irData[i].x = dp[7+3*i];
				irData[i].y = dp[8+3*i];
				irData[i].s = dp[9+3*i];
				irData[i].x += (irData[i].s & 0x30)<<4;
				irData[i].y += (irData[i].s & 0xC0)<<2;
				irData[i].s &= 0x0F;
			} 
		}
	}
	
	float ox, oy;
	
	if (irData[0].s < 0x0F && irData[1].s < 0x0F) {
		int l = leftPoint, r;
		if (leftPoint == -1) {
			//	printf("Tracking.\n");
			switch (orientation) {
				case 0: l = (irData[0].x < irData[1].x)?0:1; break;
				case 1: l = (irData[0].y > irData[1].y)?0:1; break;
				case 2: l = (irData[0].x > irData[1].x)?0:1; break;
				case 3: l = (irData[0].y < irData[1].y)?0:1; break;
			}
			leftPoint = l;
		}
		r = 1-l;
		
		float dx = irData[r].x - irData[l].x;
		float dy = irData[r].y - irData[l].y;
		
		float d = sqrt(dx*dx+dy*dy);
		
		dx /= d;
		dy /= d;
		
		float cx = (irData[l].x+irData[r].x)/1024.0 - 1;
		float cy = (irData[l].y+irData[r].y)/1024.0 - .75;
		
		//		float angle = atan2(dy, dx);
		
		ox = -dy*cy-dx*cx;
		oy = -dx*cy+dy*cx;
		//		printf("x:%5.2f;  y: %5.2f;  angle: %5.1f\n", ox, oy, angle*180/M_PI);
		
		
		
	} else {
		ox = oy = -100;
		if (leftPoint != -1) {
			//	printf("Not tracking.\n");
			leftPoint = -1;
		}
	}
	
	
	[_delegate irPointMovedX:ox Y:oy];
	//if (nil != _delegate)
		//[_delegate dataChanged:buttonData accX:accX accY:accY accZ:accZ mouseX:ox mouseY:oy];
	//[_delegate dataChanged:buttonData accX:irData[0].x/4 accY:irData[0].y/3 accZ:irData[0].s*16];
}

- (void)sendWiiRemoteButtonEvent:(UInt16)data{

	if (data & kWiiRemoteTwoButton){
		if (!buttonState[WiiRemoteTwoButton]){
			buttonState[WiiRemoteTwoButton] = YES;
			[_delegate buttonChanged:WiiRemoteTwoButton isPressed:buttonState[WiiRemoteTwoButton]];
		}
	}else{
		if (buttonState[WiiRemoteTwoButton]){
			buttonState[WiiRemoteTwoButton] = NO;
			[_delegate buttonChanged:WiiRemoteTwoButton isPressed:buttonState[WiiRemoteTwoButton]];
		}
	}

	if (data & kWiiRemoteOneButton){
		if (!buttonState[WiiRemoteOneButton]){
			buttonState[WiiRemoteOneButton] = YES;
			[_delegate buttonChanged:WiiRemoteOneButton isPressed:buttonState[WiiRemoteOneButton]];
		}
	}else{
		if (buttonState[WiiRemoteOneButton]){
			buttonState[WiiRemoteOneButton] = NO;
			[_delegate buttonChanged:WiiRemoteOneButton isPressed:buttonState[WiiRemoteOneButton]];
		}
	}
	
	if (data & kWiiRemoteAButton){
		if (!buttonState[WiiRemoteAButton]){
			buttonState[WiiRemoteAButton] = YES;
			[_delegate buttonChanged:WiiRemoteAButton isPressed:buttonState[WiiRemoteAButton]];
		}
	}else{
		if (buttonState[WiiRemoteAButton]){
			buttonState[WiiRemoteAButton] = NO;
			[_delegate buttonChanged:WiiRemoteAButton isPressed:buttonState[WiiRemoteAButton]];
		}
	}
	
	if (data & kWiiRemoteBButton){
		if (!buttonState[WiiRemoteBButton]){
			buttonState[WiiRemoteBButton] = YES;
			[_delegate buttonChanged:WiiRemoteBButton isPressed:buttonState[WiiRemoteBButton]];
		}
	}else{
		if (buttonState[WiiRemoteBButton]){
			buttonState[WiiRemoteBButton] = NO;
			[_delegate buttonChanged:WiiRemoteBButton isPressed:buttonState[WiiRemoteBButton]];
		}
	}
	
	if (data & kWiiRemoteMinusButton){
		if (!buttonState[WiiRemoteMinusButton]){
			buttonState[WiiRemoteMinusButton] = YES;
			[_delegate buttonChanged:WiiRemoteMinusButton isPressed:buttonState[WiiRemoteMinusButton]];
		}
	}else{
		if (buttonState[WiiRemoteMinusButton]){
			buttonState[WiiRemoteMinusButton] = NO;
			[_delegate buttonChanged:WiiRemoteMinusButton isPressed:buttonState[WiiRemoteMinusButton]];
		}
	}
	
	if (data & kWiiRemoteHomeButton){
		if (!buttonState[WiiRemoteHomeButton]){
			buttonState[WiiRemoteHomeButton] = YES;
			[_delegate buttonChanged:WiiRemoteHomeButton isPressed:buttonState[WiiRemoteHomeButton]];
		}
	}else{
		if (buttonState[WiiRemoteHomeButton]){
			buttonState[WiiRemoteHomeButton] = NO;
			[_delegate buttonChanged:WiiRemoteHomeButton isPressed:buttonState[WiiRemoteHomeButton]];
		}
	}
	
	if (data & kWiiRemotePlusButton){
		if (!buttonState[WiiRemotePlusButton]){
			buttonState[WiiRemotePlusButton] = YES;
			[_delegate buttonChanged:WiiRemotePlusButton isPressed:buttonState[WiiRemotePlusButton]];
		}
	}else{
		if (buttonState[WiiRemotePlusButton]){
			buttonState[WiiRemotePlusButton] = NO;
			[_delegate buttonChanged:WiiRemotePlusButton isPressed:buttonState[WiiRemotePlusButton]];
		}
	}
	
	if (data & kWiiRemoteUpButton){
		if (!buttonState[WiiRemoteUpButton]){
			buttonState[WiiRemoteUpButton] = YES;
			[_delegate buttonChanged:WiiRemoteUpButton isPressed:buttonState[WiiRemoteUpButton]];
		}
	}else{
		if (buttonState[WiiRemoteUpButton]){
			buttonState[WiiRemoteUpButton] = NO;
			[_delegate buttonChanged:WiiRemoteUpButton isPressed:buttonState[WiiRemoteUpButton]];
		}
	}
	
	if (data & kWiiRemoteDownButton){
		if (!buttonState[WiiRemoteDownButton]){
			buttonState[WiiRemoteDownButton] = YES;
			[_delegate buttonChanged:WiiRemoteDownButton isPressed:buttonState[WiiRemoteDownButton]];
		}
	}else{
		if (buttonState[WiiRemoteDownButton]){
			buttonState[WiiRemoteDownButton] = NO;
			[_delegate buttonChanged:WiiRemoteDownButton isPressed:buttonState[WiiRemoteDownButton]];
		}
	}

	if (data & kWiiRemoteLeftButton){
		if (!buttonState[WiiRemoteLeftButton]){
			buttonState[WiiRemoteLeftButton] = YES;
			[_delegate buttonChanged:WiiRemoteLeftButton isPressed:buttonState[WiiRemoteLeftButton]];
		}
	}else{
		if (buttonState[WiiRemoteLeftButton]){
			buttonState[WiiRemoteLeftButton] = NO;
			[_delegate buttonChanged:WiiRemoteLeftButton isPressed:buttonState[WiiRemoteLeftButton]];
		}
	}
	
	
	if (data & kWiiRemoteRightButton){
		if (!buttonState[WiiRemoteRightButton]){
			buttonState[WiiRemoteRightButton] = YES;
			[_delegate buttonChanged:WiiRemoteRightButton isPressed:buttonState[WiiRemoteRightButton]];
		}
	}else{
		if (buttonState[WiiRemoteRightButton]){
			buttonState[WiiRemoteRightButton] = NO;
			[_delegate buttonChanged:WiiRemoteRightButton isPressed:buttonState[WiiRemoteRightButton]];
		}
	}
}

- (void)sendWiiNunchukButtonEvent:(UInt16)data{
	if (data & kWiiNunchukCButton){
		if (!buttonState[WiiNunchukCButton]){
			buttonState[WiiNunchukCButton] = YES;
			[_delegate buttonChanged:WiiNunchukCButton isPressed:buttonState[WiiNunchukCButton]];
		}
	}else{
		if (buttonState[WiiNunchukCButton]){
			buttonState[WiiNunchukCButton] = NO;
			[_delegate buttonChanged:WiiNunchukCButton isPressed:buttonState[WiiNunchukCButton]];
		}
	}
	
	if (data & kWiiNunchukZButton){
		if (!buttonState[WiiNunchukZButton]){
			buttonState[WiiNunchukZButton] = YES;
			[_delegate buttonChanged:WiiNunchukZButton isPressed:buttonState[WiiNunchukZButton]];
		}
	}else{
		if (buttonState[WiiNunchukZButton]){
			buttonState[WiiNunchukZButton] = NO;
			[_delegate buttonChanged:WiiNunchukZButton isPressed:buttonState[WiiNunchukZButton]];
		}
	}
}


- (void)getCurrentStatus:(NSTimer*)timer{
	unsigned char cmd[] = {0x15, 0x00};
	[self sendCommand:cmd length:2];
}

- (BOOL)isExpansionPortUsed{
	return isExpansionPortUsed;
}

- (BOOL)isButtonPressed:(WiiButtonType)type{
	return buttonState[type];
}


@end
