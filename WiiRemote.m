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
	
	// unfortunately this shouldn't be required, but it keeps it from crashing.
	//[self retain];
	
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
	
	return self;
}

- (void)dealloc{
	NSLog(@"dealloc");
	[self closeConnection];

	NSLog(@"closed in dealloc");

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
	return ret;
}

- (void)disconnected: (IOBluetoothUserNotification*)note fromDevice: (IOBluetoothDevice*)device {
	NSLog(@"disconnected.");
	[self closeConnection];
	if (nil != _delegate)
		[_delegate wiiRemoteDisconnected];
	
}

- (IOReturn)sendCommand:(const unsigned char*)data length:(size_t)length{
	
	
	unsigned char buf[40];
	memset(buf,0,40);
	buf[0] = 0x52;
	memcpy(buf+1, data, length);
	if (buf[1] == 0x16) length=23;
	else				length++;
	
	int i;
	
/*	printf ("send%3d:", length);
	for(i=0 ; i<length ; i++) {
		printf(" %02X", buf[i]);
	}
	printf("\n");*/
	
	IOReturn ret;
	
	for (i = 0; i < 10; i++){
		ret = [cchan writeSync:buf length:length];
		if (kIOReturnSuccess == ret)
			break;
		usleep(10000);
	}
	
	
	
	return ret;
}


- (unsigned char)batteryLevel{
	
	return batteryLevel;
}


- (IOReturn)setMotionSensorEnabled:(BOOL)enabled{
	// these variables indicate a desire, and should be updated regardless of the sucess of sending the command
	isMotionSensorEnabled = enabled;
	
	unsigned char cmd[] = {0x12, 0x00, 0x30};
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

	}
	
	return kIOReturnSuccess;
}


- (IOReturn)writeData:(const unsigned char*)data at:(unsigned long)address length:(size_t)length{
	unsigned char cmd[22];
	int i;
	for(i=0 ; i<length ; i++) cmd[i+6] = data[i];
	for(;i<16 ; i++) cmd[i+6]= 0;
	cmd[0] = 0x16;
	cmd[1] = (address>>24)&0xFF;
	cmd[2] = (address>>16)&0xFF;
	cmd[3] = (address>> 8)&0xFF;
	cmd[4] = (address>> 0)&0xFF;
	cmd[5] = length;
	
	// and of course the vibration flag, as usual
	if (isVibrationEnabled)	cmd[1] |= 0x01;
	
	data = cmd;
	
	return [self sendCommand:cmd length:22];
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
		NSLog(@"cchan count: %d", [cchan retainCount] );
		[cchan release];
	}

	
	trycount = 0;
	
	if (ichan){
		if ([wiiDevice isConnected]) do {
			ret = [ichan closeChannel];
			trycount++;
		}while(ret != kIOReturnSuccess && trycount < 10);
		NSLog(@"ichan count: %d", [ichan retainCount] );
		[ichan release];
	}

	
	trycount = 0;
	
	if (wiiDevice){
		if ([wiiDevice isConnected]) do{
			ret = [wiiDevice closeConnection];
			trycount++;
		}while(ret != kIOReturnSuccess && trycount < 10);
		NSLog(@"closed");
	}
	
	ichan = cchan = nil;
	wiiDevice = nil;
	
	// no longer a delegate
	//[self release];
	if (statusTimer){
		[statusTimer invalidate];
		[statusTimer release];
		statusTimer = nil;
		NSLog(@"release timer");

	}

	
	return ret;
}


// thanks to Ian!
-(void)l2capChannelData:(IOBluetoothL2CAPChannel*)l2capChannel data:(void *)dataPointer length:(size_t)dataLength{
	if (!wiiDevice)
		return;
	unsigned char* dp = (unsigned char*)dataPointer;
	
	
	
	//controller status (expansion port and battery level data)
	if (dp[1] == 0x20 && dataLength >= 8){
		batteryLevel = (double)dp[7] / (double)0xC0;
		
		if (batteryLevel < warningBatteryLevel){
			[[NSNotificationCenter defaultCenter] postNotificationName:@"WiiRemoteBatteryLowNotification" object:self];
		}
		
		if ((dp[4] & 0x02)){
			isExpansionPortUsed = YES;
		}else{
			isExpansionPortUsed = NO;
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
		
		if (dp[1] & 0x01) {
			accX = dp[4];
			accY = dp[5];
			accZ = dp[6];
			
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
	
	if (nil != _delegate)
		[_delegate dataChanged:buttonData accX:accX accY:accY accZ:accZ mouseX:ox mouseY:oy];
	//[_delegate dataChanged:buttonData accX:irData[0].x/4 accY:irData[0].y/3 accZ:irData[0].s*16];
}

- (void)getCurrentStatus:(NSTimer*)timer{
	unsigned char cmd[] = {0x15, 0x00};
	[self sendCommand:cmd length:2];
}

@end
