/* 
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import "BXInputControllerPrivate.h"
#import "BXSession+BXUIControls.h"
#import "BXBaseAppController.h"
#import "BXJoypadController.h"
#import "BXJoypadLayout.h"
#import "JoypadSDK.h"
#import "BXEmulatedKeyboard.h"
#import "BXBezelController.h"
#import "BXVideoHandler.h"


//Deadzone for Joypad wheel emulation: devices within +/- this deadzone
//will be treated as centered.
#define BXJoypadRotationDeadzone 0.15f

//The maximum scale of movement for the analog stick.
//(used to be 55.0 in previous versions of the Joypad SDK, now normalised to 1.0.)
#define BXJoypadAnalogStickMaxDistance 1.0f

//How much of the analog stick's travel to treat as deadzone.
#define BXJoypadAnalogStickDeadzone 0.25f

//What fraction of the accelerometer input to mix with the previous input,
//to derive a smoothed value. Used by joypadDevice:didAccelerate:.
#define BXJoypadAccelerationFilter 0.2f


@implementation BXInputController (BXJoypadInput)

#pragma mark -
#pragma mark Helper class methods

+ (BXEmulatedJoystickButton) emulatedJoystickButtonForJoypadButton: (JoyInputIdentifier)button
{
    switch (button)
    {
        case kJoyInputAButton:
            return BXEmulatedJoystickButton1;
            
        case kJoyInputBButton:
            return BXEmulatedJoystickButton2;
            
        case kJoyInputXButton:
            return BXEmulatedJoystickButton3;
            
        case kJoyInputYButton:
            return BXEmulatedJoystickButton4;
            
        default:
            return BXEmulatedJoystickUnknownButton;
    }
}

+ (BXEmulatedPOVDirection) emulatedPOVDirectionForDPadButton: (JoyDpadButton)dpadButton
{
    BXEmulatedPOVDirection direction = BXEmulatedPOVCentered;
	switch (dpadButton)
	{
		case kJoyDpadButtonUp:
			direction = BXEmulatedPOVNorth; break;
            
		case kJoyDpadButtonDown:
			direction = BXEmulatedPOVSouth; break;
            
		case kJoyDpadButtonRight:
			direction = BXEmulatedPOVEast; break;
			
		case kJoyDpadButtonLeft:
			direction = BXEmulatedPOVWest; break;
	}
	return direction;
}


#pragma mark -
#pragma mark Housekeeping

+ (NSSet *) keyPathsForValuesAffectingCurrentJoypadLayout
{
    return [NSSet setWithObject: @"preferredJoystickType"];
}

- (JoypadControllerLayout *) currentJoypadLayout
{
    Class joystickType = [self preferredJoystickType];
    if (joystickType)
    {
        return [BXJoypadLayout layoutForJoystickType: joystickType];
    }
    else return nil;
}

- (BOOL) joypadControllersAvailable
{
    return [(BXBaseAppController *)[NSApp delegate] joypadController].hasJoypadDevices;
}

- (void) _warnIfJoystickInactive
{
    //If the game seems to be ignoring joystick input right now,
    //and the user is poking away in Joypad, show a notification
    if ([self _activeProgramIsIgnoringJoystick])
    {
        [[BXBezelController controller] showJoystickIgnoredBezel];
    }
}

//Passed on by BXJoypadController whenever a device is connected/disconnected
- (void) joypadManager: (JoypadManager *)manager
      deviceDidConnect: (JoypadDevice *)device
                player: (unsigned int)player
{
    [self _resetJoypadTrackingValues];
}

- (void) joypadManager: (JoypadManager *)manager
   deviceDidDisconnect: (JoypadDevice *)device
                player: (unsigned int)player
{
    [self _resetJoypadTrackingValues];
}

- (void) _resetJoypadTrackingValues
{
    _joypadFilteredAcceleration.x = 0.0f;
    _joypadFilteredAcceleration.y = 0.0f;
    _joypadFilteredAcceleration.z = 0.0f;
}


#pragma mark -
#pragma mark Accelerometer handling

- (void) joypadDevice: (JoypadDevice *)device
        didAccelerate: (JoypadAcceleration)accel
{
    float roll, pitch;
    
    //Low-pass filter to smooth out accelerometer movement, so that
    //shaking the device doesn't mess us around.
    //Copypasta from Apple's Event Handling Guide for iOS: Motion Events
    float   filterNew = BXJoypadAccelerationFilter,
            filterOld = 1.0f - filterNew;
    _joypadFilteredAcceleration.x = (accel.x * filterNew) + (_joypadFilteredAcceleration.x * filterOld);
    _joypadFilteredAcceleration.y = (accel.y * filterNew) + (_joypadFilteredAcceleration.y * filterOld);
    _joypadFilteredAcceleration.z = (accel.z * filterNew) + (_joypadFilteredAcceleration.z * filterOld);
    
    //These will have a range in radians from PI to -PI.
    double roll_in_radians  = atan2(_joypadFilteredAcceleration.y, -_joypadFilteredAcceleration.x);
    double pitch_in_radians = atan2(_joypadFilteredAcceleration.z, -_joypadFilteredAcceleration.x);
    
    //PI/2 (90 degrees counterclockwise) to -PI/2 (90 degrees clockwise)
    //is what we want to map to the -1.0 to 1.0 range of the emulated joystick.
    //(We don't need to worry about the overflow to -+2.0, because the emulated
    //joystick automatically crops axis values to +-1.0)
    roll = -(float)(roll_in_radians / M_PI_2);
    pitch = -(float)(pitch_in_radians / M_PI_2);
    
    id joystick = self.emulatedJoystick;
    
    //Map roll to steering
    if ([joystick conformsToProtocol: @protocol(BXEmulatedWheel)])
    {
        //Apply a deadzone to the center of the wheel range
        if (ABS(roll) < BXJoypadRotationDeadzone) roll = 0.0f;
        
        [joystick setWheelAxis: roll];
    }
    //Map roll and pitch to X and Y axes
    else if ([joystick supportsAxis: BXAxisX] && [joystick supportsAxis: BXAxisY])
    {
        //Normally 0.0 pitch is completely vertical, +1.0 pitch is horizontal.
        //We want our pitch's 0 resting position to be at about 45 degrees,
        //and to avoid the user having to push all the way to horizontal as
        //that will prevent us taking roll readings.
        //The calculation below will give us 0 at 45 degrees from horizontal,
        //-1.0 at about 80 degrees from horizontal and 1.0 at about 10 degrees
        //from horizontal.
        pitch = (pitch - 0.5f) * 2.5f;
        
        //Apply a deadzone to the center of each axis
        if (ABS(roll) < BXJoypadRotationDeadzone)   roll = 0.0f;
        if (ABS(pitch) < BXJoypadRotationDeadzone)  pitch = 0.0f;
        
        [joystick setXAxis: roll];
        [joystick setYAxis: pitch];
    }
}

#pragma mark -
#pragma mark D-pad handling

- (void) joypadDevice: (JoypadDevice *)device
                 dPad: (JoyInputIdentifier)dpad
             buttonUp: (JoyDpadButton)dpadButton
{
    id joystick = self.emulatedJoystick;
    
    if ([joystick conformsToProtocol: @protocol(BXEmulatedFlightstick)])
    {
        BXEmulatedPOVDirection direction = [[self class] emulatedPOVDirectionForDPadButton: dpadButton];
        [joystick POV: 0 directionUp: direction];
    }
    else if ([joystick supportsAxis: BXAxisX] && [joystick supportsAxis: BXAxisY])
    {
        switch (dpadButton)
        {
            case kJoyDpadButtonUp:
            case kJoyDpadButtonDown:
                [joystick setYAxis: 0.0f];
                break;
                
            case kJoyDpadButtonLeft:
            case kJoyDpadButtonRight:
                [joystick setXAxis: 0.0f];
                break;
        }
    } 
}

- (void) joypadDevice: (JoypadDevice *)device
                 dPad: (JoyInputIdentifier)dpad
           buttonDown: (JoyDpadButton)dpadButton
{
    [self _warnIfJoystickInactive];
    
    id joystick = self.emulatedJoystick;
    
    if ([joystick conformsToProtocol: @protocol(BXEmulatedFlightstick)])
    {
        BXEmulatedPOVDirection direction = [[self class] emulatedPOVDirectionForDPadButton: dpadButton];
        [joystick POV: 0 directionDown: direction];
    }
    else if ([joystick supportsAxis: BXAxisX] && [joystick supportsAxis: BXAxisY])
    {
        switch (dpadButton)
        {
            case kJoyDpadButtonUp:
                [joystick setYAxis: -1.0f];
                break;
            case kJoyDpadButtonDown:
                [joystick setYAxis: 1.0f];
                break;
            case kJoyDpadButtonLeft:
                [joystick setXAxis: -1.0f];
                break;
            case kJoyDpadButtonRight:
                [joystick setXAxis: 1.0f];
                break;
        }
    }  
}


#pragma mark -
#pragma mark Button handling

- (void) joypadDevice: (JoypadDevice *)device
             buttonUp: (JoyInputIdentifier)button
{
    id <BXEmulatedJoystick> joystick = self.emulatedJoystick;
    BXEmulatedKeyboard *keyboard = self.emulatedKeyboard;
    
    BOOL isWheel = [joystick conformsToProtocol: @protocol(BXEmulatedWheel)];
    BOOL isFlightstick = [joystick conformsToProtocol: @protocol(BXEmulatedFlightstick)];
    switch ((NSInteger)button) //Cast suppresses warnings about case values not being enumerated
    {
        case kJoyInputRButton:
            //Gas pedal
            if (isWheel) [(id <BXEmulatedWheel>)joystick setAcceleratorAxis: 0.0f];
            break;
        
        case kJoyInputLButton:
            //Brake pedal
            if (isWheel) [(id <BXEmulatedWheel>)joystick setBrakeAxis: 0.0f];
            break;
            
        case kJoyInputSelectButton:
            //Pause button
            //Do nothing on button up: this is a toggle
            break;
            
        case kJoyInputStartButton:
            //ESC button
            [keyboard keyUp: KBD_esc];
            break;
            
        //'Fake' d-pad buttons for compact flightstick hat switch layouts.
        //These do not correspond to any enumerated constants, but are still
        //round-tripped by the Joypad API successfully.
        case BXJoyInputFakeDPadButtonUp:
            if (isFlightstick) [(id <BXEmulatedFlightstick>)joystick POV: 0 directionUp: BXEmulatedPOVNorth];
            break;
            
        case BXJoyInputFakeDPadButtonDown:
            if (isFlightstick) [(id <BXEmulatedFlightstick>)joystick POV: 0 directionUp: BXEmulatedPOVSouth];
            break;
            
        case BXJoyInputFakeDPadButtonLeft:
            if (isFlightstick) [(id <BXEmulatedFlightstick>)joystick POV: 0 directionUp: BXEmulatedPOVWest];
            break;
            
        case BXJoyInputFakeDPadButtonRight:
            if (isFlightstick) [(id <BXEmulatedFlightstick>)joystick POV: 0 directionUp: BXEmulatedPOVEast];
            break;
        
        default:
        {
            BXEmulatedJoystickButton joyButton = [self.class emulatedJoystickButtonForJoypadButton: button];
        
            if (joyButton != BXEmulatedJoystickUnknownButton)
                [joystick buttonUp: joyButton];
        }
    }
}

- (void) joypadDevice: (JoypadDevice *)device
           buttonDown: (JoyInputIdentifier)button
{
    [self _warnIfJoystickInactive];

    id <BXEmulatedJoystick> joystick = self.emulatedJoystick;
    BXEmulatedKeyboard *keyboard = self.emulatedKeyboard;
    
    BOOL isWheel = [joystick conformsToProtocol: @protocol(BXEmulatedWheel)];
    BOOL isFlightstick = [joystick conformsToProtocol: @protocol(BXEmulatedFlightstick)];
    switch ((NSInteger)button) //Cast suppresses warnings about case values not being enumerated
    {
        case kJoyInputRButton:
            //Gas pedal
            if (isWheel) [(id <BXEmulatedWheel>)joystick setAcceleratorAxis: 1.0f];
            break;
            
        case kJoyInputLButton:
            //Brake pedal
            if (isWheel) [(id <BXEmulatedWheel>)joystick setBrakeAxis: 1.0f];
            break;
            
        case kJoyInputSelectButton:
            //Pause button
            [self.representedObject togglePaused: self];
            break;
            
        case kJoyInputStartButton:
            //ESC button
            [keyboard keyDown: KBD_esc];
            break;
            
        //'Fake' d-pad buttons for compact flightstick hat switch layouts.
        //These do not correspond to any enumerated constants, but are still
        //round-tripped by the Joypad API successfully.
        case BXJoyInputFakeDPadButtonUp:
            if (isFlightstick) [(id <BXEmulatedFlightstick>)joystick POV: 0 directionDown: BXEmulatedPOVNorth];
            break;
            
        case BXJoyInputFakeDPadButtonDown:
            if (isFlightstick) [(id <BXEmulatedFlightstick>)joystick POV: 0 directionDown: BXEmulatedPOVSouth];
            break;
            
        case BXJoyInputFakeDPadButtonLeft:
            if (isFlightstick) [(id <BXEmulatedFlightstick>)joystick POV: 0 directionDown: BXEmulatedPOVWest];
            break;
            
        case BXJoyInputFakeDPadButtonRight:
            if (isFlightstick) [(id <BXEmulatedFlightstick>)joystick POV: 0 directionDown: BXEmulatedPOVEast];
            break;

        default:
        {
            BXEmulatedJoystickButton joyButton = [self.class emulatedJoystickButtonForJoypadButton: button];
            
            if (joyButton != BXEmulatedJoystickUnknownButton)
                [joystick buttonDown: joyButton];
        }
    }
}

- (void) joypadDevice: (JoypadDevice *)device
          analogStick: (JoyInputIdentifier)stick
              didMove: (JoypadStickPosition)newPosition
{
    [self _warnIfJoystickInactive];

    id joystick = self.emulatedJoystick;
    
    if ([joystick supportsAxis: BXAxisX] && [joystick supportsAxis: BXAxisY])
    {
        //Joypad SDK provides stick position as polar coordinates
        //(angle and distance); we need to convert this to cartesian
        //(x, y) coordinates for the emulated joystick.
        float ratio = newPosition.distance / BXJoypadAnalogStickMaxDistance;
        float x = cosf(newPosition.angle) * ratio;
        float y = -sinf(newPosition.angle) * ratio;
        
        //Stretch the circular travel out to a square one.
        float maxDim = fmaxf(ABS(x), ABS(y));
        if (maxDim > 0)
        {
            x *= ratio / maxDim;
            y *= ratio / maxDim;
        }
        
        //Apply a deadzone to the stick to reduce small unintentional movements.
        if (ABS(x) < BXJoypadAnalogStickDeadzone)
            x = 0;
        
        if (ABS(y) < BXJoypadAnalogStickDeadzone)
            y = 0;
        
        [joystick setXAxis: x];
        [joystick setYAxis: y];
    }
}

@end
