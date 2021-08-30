/* 
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

//BXThemedControls defines a set of simple NSControl and NSCell subclasses
//hardcoded to use our own BGHUDAppKit themes. These are for use in XCode 4+,
//which does not support the IB plugin BGHUDAppKit relies on for assigning themes.

#import <BGHUDAppKit/BGHUDAppKit.h>
#import "BXThemedButtonCell.h"
#import "BXThemedImageCell.h"
#import "BXThemes.h"

//Base classes for our BGHUDAppKit-themed control subclasses.

@interface BXThemedLabel : BGHUDLabel <BXThemable>
@end


//BGHUDAppKit control subclasses hardcoded to use BXHUDTheme.

@interface BXHUDLabel : BXThemedLabel
@end


//BGHUDAppKit control subclasses hardcoded to use BXBlueprintTheme
//and BXBlueprintHelpTextTheme.

@interface BXBlueprintLabel : BXThemedLabel
@end

@interface BXBlueprintHelpTextLabel : BXThemedLabel
@end


//BGHUDAppKit control subclasses hardcoded to use BXAboutTheme,
//BXAboutDarkTheme and BXAboutLightTheme.
@interface BXAboutLabel : BXThemedLabel
@end

@interface BXAboutDarkLabel : BXThemedLabel
@end

@interface BXAboutLightLabel : BXThemedLabel
@end
