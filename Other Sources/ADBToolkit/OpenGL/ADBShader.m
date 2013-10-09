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


#import "ADBShader.h"
#import <OpenGL/gl.h>
#import <OpenGL/CGLMacro.h>


NSString * const ADBShaderErrorDomain = @"ADBShaderErrorDomain";
NSString * const ADBShaderErrorSourceKey = @"Source";
NSString * const ADBShaderErrorInfoLogKey = @"Info log";

//An NSString representing the name of the uniform.
NSString * const ADBShaderUniformNameKey = @"Name";

//An NSNumber representing the location at which values can be assigned to the uniform.
NSString * const ADBShaderUniformLocationKey = @"Location";

//An NSNumber representing the uniform's index in the list of active uniforms.
NSString * const ADBShaderUniformIndexKey = @"Index";

//An NSNumber representing the uniform's type.
NSString * const ADBShaderUniformTypeKey = @"Type";

//An NSNumber representing the uniform's size.
NSString * const ADBShaderUniformSizeKey = @"Size";



@interface ADBShader ()
@property (readwrite, nonatomic) GLhandleARB shaderProgram;
@end

@implementation ADBShader
@synthesize shaderProgram = _shaderProgram;
@synthesize context = _context;


#pragma mark -
#pragma mark Compilation helper methods

+ (NSString *) infoLogForObject: (GLhandleARB)objectHandle
                      inContext: (CGLContextObj)context
{   
    NSString *infoLog = nil;
    GLint infoLogLength = 0;
    
    CGLContextObj cgl_ctx = context;
    
    glGetObjectParameterivARB(objectHandle, GL_OBJECT_INFO_LOG_LENGTH_ARB, &infoLogLength);
    if (infoLogLength > 0) 
    {
        GLcharARB *infoLogChars = (GLcharARB *)malloc(infoLogLength);
        
        if (infoLogChars != NULL)
        {
            glGetInfoLogARB(objectHandle, infoLogLength, &infoLogLength, infoLogChars);
            
            infoLog = [NSString stringWithCString: (const char *)infoLogChars
                                         encoding: NSASCIIStringEncoding];
            
            free(infoLogChars);
        }
    }
    return infoLog;
}

+ (NSArray *) uniformDescriptionsForShaderProgram: (GLhandleARB)shaderProgram
                                        inContext: (CGLContextObj)context
{
    CGLContextObj cgl_ctx = context;
    
    GLint numUniforms = 0;
    
    glGetObjectParameterivARB(shaderProgram, GL_OBJECT_ACTIVE_UNIFORMS_ARB, &numUniforms);
    
    NSMutableArray *descriptions = [NSMutableArray arrayWithCapacity: numUniforms];
    
    if (numUniforms > 0)
    {
        GLint maxUniformNameLength = 0;
        glGetObjectParameterivARB(shaderProgram, GL_OBJECT_ACTIVE_UNIFORM_MAX_LENGTH_ARB, &maxUniformNameLength);
        
        GLcharARB *nameBuf = (maxUniformNameLength > 0) ? (GLcharARB *)malloc(maxUniformNameLength) : NULL;
        GLint index;
        for (index=0; index < numUniforms; index++)
        {
            GLint numBytes;
            GLint size;
            GLenum type;
            glGetActiveUniformARB(shaderProgram, index, maxUniformNameLength, &numBytes, &size, &type, nameBuf);
            
            if (numBytes > 0)
            {
                GLint location = glGetUniformLocationARB(shaderProgram, nameBuf);
                
                //A location of -1 will be reported for builtin uniforms, which cannot be addressed
                //with glUniformXxARB anyway. For clarity's sake we leave these out of the resulting
                //array.
                if (location != ADBShaderUnsupportedUniformLocation)
                {
                    NSString *name = [NSString stringWithCString: nameBuf encoding: NSASCIIStringEncoding];
                    NSDictionary *uniformData = @{
                        ADBShaderUniformNameKey:        name,
                        ADBShaderUniformTypeKey:        @(type),
                        ADBShaderUniformIndexKey:       @(index),
                        ADBShaderUniformSizeKey:        @(size),
                        ADBShaderUniformLocationKey:    @(location),
                    };
            
                    [descriptions addObject: uniformData];
                }
            }
        }
        
        free(nameBuf);
    }
    
    return descriptions;
}

+ (GLhandleARB) createShaderWithSource: (NSString *)source
                                  type: (GLenum)shaderType
                             inContext: (CGLContextObj)context
                                 error: (NSError **)outError
{
    CGLContextObj cgl_ctx = context;
    
    GLhandleARB shaderHandle = NULL;
    BOOL compiled = NO;
    
    if (source.length)
    {
        const GLcharARB *glSource = (const GLcharARB *)[source cStringUsingEncoding: NSASCIIStringEncoding];
    
        shaderHandle = glCreateShaderObjectARB(shaderType);
        
        glShaderSourceARB(shaderHandle, 1, &glSource, NULL);
        glCompileShaderARB(shaderHandle);
        
        //After compilation, check if compilation succeeded.
        GLint status = GL_FALSE;
        glGetObjectParameterivARB(shaderHandle, 
                                  GL_OBJECT_COMPILE_STATUS_ARB, 
                                  &status);
            
        compiled = (status != GL_FALSE);
    }

    if (!compiled)
    {   
        //Pass an error back up about what we couldn't compile.
        if (outError)
        {
            BOOL isVertexShader = (shaderType == GL_VERTEX_SHADER_ARB || shaderType == GL_VERTEX_SHADER);
            NSInteger compileError = (isVertexShader) ? ADBShaderCouldNotCompileVertexShader : ADBShaderCouldNotCompileFragmentShader;
            
            //Read out the info log to give some clue as to why compilation failed.
            NSString *infoLog;
            if (shaderHandle)
                infoLog = [self infoLogForObject: shaderHandle inContext: context];
            else
                infoLog = @"";
                
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                      infoLog, ADBShaderErrorInfoLogKey,
                                      source, ADBShaderErrorSourceKey,
                                      nil];
            
            
            *outError = [NSError errorWithDomain: ADBShaderErrorDomain
                                            code: compileError
                                        userInfo: userInfo];
        }
        
        //Clean up any leftover handle if we couldn't compile.
        if (shaderHandle)
        {
            glDeleteObjectARB(shaderHandle);
            shaderHandle = NULL;
        }
    }
    
    return shaderHandle;
}

+ (GLhandleARB) createProgramWithVertexShader: (NSString *)vertexSource
                              fragmentShaders: (NSArray *)fragmentSources
                                    inContext: (CGLContextObj)context
                                        error: (NSError **)outError
{
    CGLContextObj cgl_ctx = context;
    
    GLhandleARB programHandle = glCreateProgramObjectARB();
    
    NSAssert(vertexSource != nil || fragmentSources.count > 0, @"No vertex shader or fragment shader supplied for program.");
    
    if (vertexSource)
    {
        GLhandleARB vertexShader = [self createShaderWithSource: vertexSource
                                                           type: GL_VERTEX_SHADER_ARB
                                                      inContext: context
                                                          error: outError];

        if (vertexShader)
        {
            glAttachObjectARB(programHandle, vertexShader);
            glDeleteObjectARB(vertexShader);
        }
        else
        {
            //Bail if we couldn't compile a shader (in which case outError will have been populated).
            glDeleteObjectARB(programHandle);
            return NULL;
        }
    }
    
    for (NSString *fragmentSource in fragmentSources)
    {
        GLhandleARB fragmentShader = [self createShaderWithSource: fragmentSource
                                                             type: GL_FRAGMENT_SHADER_ARB
                                                        inContext: context
                                                            error: outError];
        
        if (fragmentShader)
        {
            glAttachObjectARB(programHandle, fragmentShader);
            glDeleteObjectARB(fragmentShader);
        }
        else
        {
            //Bail if we couldn't compile a shader (in which case outError will have been populated).
            glDeleteObjectARB(programHandle);
            return NULL;
        }
    }
    
    //Once we've attached all the shaders, try linking and validating the final program.
	glLinkProgramARB(programHandle);
	glValidateProgramARB(programHandle);
    
    GLint linked = GL_FALSE;
    GLint validated = GL_FALSE;
	glGetObjectParameterivARB(programHandle, GL_OBJECT_LINK_STATUS_ARB, &linked);
	glGetObjectParameterivARB(programHandle, GL_OBJECT_VALIDATE_STATUS_ARB, &validated);
	
    //If the program didn't link, throw an error upstream and clean up after ourselves.
	if (linked == GL_FALSE || validated == GL_FALSE)
	{
        if (outError)
        {
            //Read out the info log to give some clue as to why linking failed.
            NSString *infoLog;
            if (programHandle)
                infoLog = [self infoLogForObject: programHandle inContext: context];
            else
                infoLog = @"";
            
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                      infoLog, ADBShaderErrorInfoLogKey,
                                      nil];
            
            *outError = [NSError errorWithDomain: ADBShaderErrorDomain
                                            code: ADBShaderCouldNotCreateShaderProgram
                                        userInfo: userInfo];
        }
        
        if (programHandle)
        {
            glDeleteObjectARB(programHandle);
        }
        
        return NULL;
	}
    
    //If we got this far, everything's A-OK!
    return programHandle;
}


#pragma mark -
#pragma mark Initialization and deallocation

+ (id) shaderNamed: (NSString *)shaderName
           context: (CGLContextObj)context
             error: (NSError **)outError
{
    NSURL *vertexURL    = [[NSBundle mainBundle] URLForResource: shaderName withExtension: @"vert"];
    NSURL *fragmentURL  = [[NSBundle mainBundle] URLForResource: shaderName withExtension: @"frag"];
    
    return [[[self alloc] initWithContentsOfVertexShaderURL: vertexURL
                                         fragmentShaderURLs: [NSArray arrayWithObject: fragmentURL]
                                                  inContext: context
                                                      error: outError] autorelease];
}

+ (id) shaderNamed: (NSString *)shaderName
      subdirectory: (NSString *)subdirectory
           context: (CGLContextObj)context
             error: (NSError **)outError
{
    NSURL *vertexURL    = [[NSBundle mainBundle] URLForResource: shaderName
                                                  withExtension: @"vert"
                                                   subdirectory: subdirectory];
    NSURL *fragmentURL  = [[NSBundle mainBundle] URLForResource: shaderName
                                                  withExtension: @"frag"
                                                   subdirectory: subdirectory];
    
    return [[[self alloc] initWithContentsOfVertexShaderURL: vertexURL
                                         fragmentShaderURLs: [NSArray arrayWithObject: fragmentURL]
                                                  inContext: context
                                                      error: outError] autorelease];
}

- (id) initWithContentsOfVertexShaderURL: (NSURL *)vertexShaderURL
                      fragmentShaderURLs: (NSArray *)fragmentShaderURLs
                               inContext: (CGLContextObj)context
                                   error: (NSError **)outError
{
    NSString *vertexSource = nil;
    if (vertexShaderURL)
    {
        vertexSource = [NSString stringWithContentsOfURL: vertexShaderURL
                                                encoding: NSASCIIStringEncoding
                                                   error: outError];
        if (!vertexSource)
        {
            [self release];
            return nil;
        }
    }
    
    NSMutableArray *fragmentSources = [NSMutableArray arrayWithCapacity: fragmentShaderURLs.count];
    for (NSURL *fragmentShaderURL in fragmentShaderURLs)
    {
        NSString *fragmentSource = [NSString stringWithContentsOfURL: fragmentShaderURL
                                                            encoding: NSASCIIStringEncoding
                                                               error: outError];
        
        if (fragmentSource)
        {
            [fragmentSources addObject: fragmentSource];
        }
        else
        {
            [self release];
            return nil;
        }
    }
    
    return [self initWithVertexShader: vertexSource
                      fragmentShaders: fragmentSources
                            inContext: context
                                error: outError];
}

- (id) initWithVertexShader: (NSString *)vertexSource
            fragmentShaders: (NSArray *)fragmentSources
                  inContext: (CGLContextObj)context
                      error: (NSError **)outError
{
    if (self = [self init])
    {
        _context = context;
        CGLRetainContext(context);
        
        self.shaderProgram = [self.class createProgramWithVertexShader: vertexSource
                                                       fragmentShaders: fragmentSources
                                                             inContext: context
                                                                 error: outError];
        
        _freeProgramWhenDone = YES;
        
        //If we couldn't compile a shader program from the specified sources,
        //pack up and go home.
        if (!self.shaderProgram)
        {
            [self release];
            return nil;
        }
    }
    
    return self;
}

- (void) dealloc
{
    self.shaderProgram = NULL;
    
    [super dealloc];
}

- (void) deleteShaderProgram
{
    self.shaderProgram = NULL;
}

- (void) setShaderProgram: (GLhandleARB)shaderProgram
{
    if (_shaderProgram != shaderProgram)
    {
        if (_shaderProgram && _freeProgramWhenDone)
        {
            CGLContextObj cgl_ctx = _context;
            glDeleteObjectARB(_shaderProgram);
        }
        
        _shaderProgram = shaderProgram;
    }
}

- (void) setShaderProgram: (GLhandleARB)shaderProgram
             freeWhenDone: (BOOL)freeWhenDone
{
    self.shaderProgram = shaderProgram;
    _freeProgramWhenDone = freeWhenDone;
}

- (GLint) locationOfUniform: (const GLcharARB *)uniformName
{
    CGLContextObj cgl_ctx = _context;
    return glGetUniformLocationARB(_shaderProgram, uniformName);
}

- (NSArray *) uniformDescriptions
{
    return [self.class uniformDescriptionsForShaderProgram: _shaderProgram inContext: _context];
}

- (NSString *) infoLog
{
    return [self.class infoLogForObject: _shaderProgram inContext: _context];
}

@end
