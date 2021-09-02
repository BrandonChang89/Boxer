/*
 *  Copyright (c) 2013, Alun Bestor (alun.bestor@gmail.com)
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without modification,
 *  are permitted provided that the following conditions are met:
 *
 *		Redistributions of source code must retain the above copyright notice, this
 *	    list of conditions and the following disclaimer.
 *
 *		Redistributions in binary form must reproduce the above copyright notice,
 *	    this list of conditions and the following disclaimer in the documentation
 *      and/or other materials provided with the distribution.
 *
 *	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *	ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 *	WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 *	IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 *	INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 *	BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
 *	OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 *	WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *	ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 *	POSSIBILITY OF SUCH DAMAGE.
 */

#import "NSError+ADBErrorHelpers.h"
#include <cxxabi.h> //For demangling

@implementation NSError (ADBErrorHelpers)

- (BOOL) matchesDomain: (NSString *)errorDomain code: (NSInteger)errorCode
{
    return (self.code == errorCode && [self.domain isEqualToString: errorDomain]);
}

- (BOOL) isUserCancelledError
{
    return [self matchesDomain: NSCocoaErrorDomain code: NSUserCancelledError];
}

@end


NSString * const ADBCallstackRawSymbol                  = @"ADBCallstackRawSymbol";
NSString * const ADBCallstackLibraryName                = @"ADBCallstackLibraryName";
NSString * const ADBCallstackAddress                    = @"ADBCallstackAddress";
NSString * const ADBCallstackFunctionName               = @"ADBCallstackFunctionName";
NSString * const ADBCallstackHumanReadableFunctionName  = @"ADBCallstackHumanReadableFunctionName";
NSString * const ADBCallstackSymbolOffset               = @"ADBCallstackSymbolOffset";

@implementation NSException (ADBExceptionHelpers)

+ (NSString *) demangledCPlusPlusFunctionName: (NSString *)functionName
{
    int status;
    const char *cSymbol = functionName.UTF8String;
    char *demangledName = abi::__cxa_demangle(cSymbol, NULL, NULL, &status);
    if (demangledName)
    {
        NSString *demangledFunctionName = [[NSString alloc] initWithBytesNoCopy: demangledName
                                                                         length: strlen(demangledName)
                                                                       encoding: NSASCIIStringEncoding
                                                                   freeWhenDone: YES];
        
        return demangledFunctionName;
    }
    else
    {
        return nil;
    }
}

@end
