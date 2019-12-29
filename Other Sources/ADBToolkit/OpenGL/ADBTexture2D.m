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

#import "ADBTexture2D.h"
#import "ADBGeometry.h"
#import "ADBGLHelpers.h"
#import <OpenGL/gl.h>
#import <OpenGL/glu.h>
#import <OpenGL/CGLMacro.h>


@implementation ADBTexture2D
@synthesize context = _context;
@synthesize texture = _texture;
@synthesize type = _type;
@synthesize contentRegion = _contentRegion;
@synthesize textureSize = _textureSize;
@synthesize usesNormalizedTextureCoordinates = _usesNormalizedTextureCoordinates;

@synthesize horizontalWrapping = _horizontalWrapping;
@synthesize verticalWrapping = _verticalWrapping;
@synthesize minFilter = _minFilter;
@synthesize magFilter = _magFilter;

#pragma mark -
#pragma mark Internal helper methods

+ (CGSize) textureSizeNeededForContentSize: (CGSize)size withType: (GLenum)textureType
{
    if (textureType == GL_TEXTURE_RECTANGLE_ARB)
    {
        return size;
    }
    else
    {
        return CGSizeMake(fitToPowerOfTwo((NSInteger)size.width),
                          fitToPowerOfTwo((NSInteger)size.height));
    }
}

- (BOOL) _checkForGLError: (NSError **)outError
{
    if (outError)
    {
        *outError = latestErrorInCGLContext(_context);
        return (*outError == nil);
    }
    return YES;
}

#pragma mark -
#pragma mark Initialization and deallocation

+ (id) textureWithType: (GLenum)type
           contentSize: (CGSize)contentSize
                 bytes: (const GLvoid *)bytes
           inGLContext: (CGLContextObj)context
                 error: (NSError **)outError
{
    return [[self alloc] initWithType: type
                          contentSize: contentSize
                                bytes: bytes
                          inGLContext: context
                                error: outError];
}
         
- (void)_regenDisplayListWithContentSize:(CGSize)contentSize
{
    CGLContextObj cgl_ctx = _context;

    if (glIsList(_displayList)) glDeleteLists(_displayList, 1);
    _displayList = glGenLists(1);
    glNewList(_displayList, GL_COMPILE);
    glClear(GL_COLOR_BUFFER_BIT);
    glBindTexture(_type, _texture);
    
    glBegin(GL_TRIANGLES);
    // upper left
    glTexCoord2f(0,0); glVertex2f(-1.0f, 1.0f);
    // lower left
    glTexCoord2f(0,contentSize.height*2); glVertex2f(-1.0f,-3.0f);
    // upper right
    glTexCoord2f(contentSize.width*2,0); glVertex2f(3.0f, 1.0f);
    glEnd();

    glEndList();
}

- (id) initWithType: (GLenum)type
        contentSize: (CGSize)contentSize
              bytes: (const GLvoid *)bytes
        inGLContext: (CGLContextObj)context
              error: (NSError **)outError
{
    NSAssert(contentSize.width > 0 && contentSize.height > 0, @"Invalid content size provided: %@", NSStringFromCGSize(contentSize));
    
    self = [self init];
    if (self)
    {
        _context = context;
        CGLRetainContext(context);
        
        CGLContextObj cgl_ctx = _context;
        
        _type = type;
        _contentRegion = CGRectMake(0, 0, contentSize.width, contentSize.height);
        
        //Choose suitable default wrapping modes based on the texture type,
        //and check what texture size we'll need.
        //(For rectangle textures, we can use the content size as the size
        //of the texture itself; otherwise, we need a power of two texture
        //size large enough to accommodate the content size.)
        _textureSize = [self.class textureSizeNeededForContentSize: contentSize withType: type];
        
        if (_type == GL_TEXTURE_RECTANGLE_ARB)
        {
            _usesNormalizedTextureCoordinates = NO;
            _horizontalWrapping = GL_CLAMP_TO_EDGE;
            _verticalWrapping = GL_CLAMP_TO_EDGE;
        }
        else
        {
            _usesNormalizedTextureCoordinates = YES;
            _horizontalWrapping = GL_REPEAT;
            _verticalWrapping = GL_REPEAT;
        }
        _minFilter = GL_LINEAR;
        _magFilter = GL_LINEAR;
        
        //Create a new texture and bind it as the current target.
        glGenTextures(1, &_texture);
        glBindTexture(_type, _texture);
        
        //Set the initial texture parameters.
        glTexParameteri(_type, GL_TEXTURE_WRAP_S, _horizontalWrapping);
        glTexParameteri(_type, GL_TEXTURE_WRAP_T, _verticalWrapping);
        glTexParameteri(_type, GL_TEXTURE_MIN_FILTER, _minFilter);
        glTexParameteri(_type, GL_TEXTURE_MAG_FILTER, _magFilter);
        
        [self _regenDisplayListWithContentSize:contentSize];
        
        
        //If the texture size is the same as the content size, then we can provide the texture
        //data in the initial call already. Otherwise, we'll have to fill it in a separate pass.
        BOOL canWriteTextureData = (bytes != NULL) && CGSizeEqualToSize(_textureSize, contentSize);

        GLvoid *initialData;
        BOOL createdOwnData = NO;
        if (canWriteTextureData)
        {
            initialData = (GLvoid *)bytes;
        }        
        //If we don't have any bytes to fill the texture with, or we'll only be filling a subregion,
        //then fill the texture initially with pure black.
        else
        {
            size_t numBytes = _textureSize.width * _textureSize.height * 4;
            initialData = (GLvoid *)malloc(numBytes);
            if (initialData)
            {
                bzero(initialData, numBytes);
                createdOwnData = YES;
            }
        }
        
        glTexImage2D(_type,                         //Texture target
                     0,								//Mipmap level
                     GL_RGBA8,						//Internal texture format
                     _textureSize.width,			//Width
                     _textureSize.height,			//Height
                     0,								//Border (unused)
                     GL_BGRA,						//Byte ordering
                     GL_UNSIGNED_INT_8_8_8_8_REV,	//Byte packing
                     initialData);                  //Texture data
        
        if (createdOwnData)
        {
            free(initialData);
            initialData = NULL;
        }
        
        BOOL succeeded = [self _checkForGLError: outError];
        
        //If we couldn't fill in any texture data in the initial call, do so now.
        if (succeeded)
        {
            if (!canWriteTextureData && bytes)
            {
                succeeded = [self fillRegion: _contentRegion
                                   withBytes: bytes
                                       error: outError];
            }
        }
        
        //If texture creation failed, clean up after ourselves and return nil.
        if (!succeeded)
        {
            return nil;
        }        
    }
    return self;
}

- (void) deleteTexture
{
    if (_texture)
    {
        CGLContextObj cgl_ctx = _context;
        
        glDeleteTextures(1, &_texture);
        _texture = 0;
    }
    
    if (_displayList) {
        CGLContextObj cgl_ctx = _context;
        
        if (glIsList(_displayList)) {
            glDeleteLists(_displayList, 1);
        }
        _displayList = 0;
    }
}

- (void) dealloc
{
    [self deleteTexture];
    
    if (_context)
    {
        CGLReleaseContext(_context);
        _context = NULL;
    }
}


- (BOOL) fillRegion: (CGRect)region
          withBytes: (const GLvoid *)bytes
              error: (NSError **)outError
{
    CGRect textureRegion = CGRectMake(0, 0, _textureSize.width, _textureSize.height);
    NSAssert1(CGRectContainsRect(textureRegion, region),
              @"Region out of bounds: %@", NSStringFromRect(NSRectFromCGRect(region)));
    
    CGLContextObj cgl_ctx = _context;
    
    glBindTexture(_type, _texture);
    
    glTexSubImage2D(_type,
                    0,                              //Mipmap level
                    region.origin.x,                //X offset
                    region.origin.y,                //Y offset
                    region.size.width,              //Width
                    region.size.height,             //Height
                    GL_BGRA,                        //Byte ordering
                    GL_UNSIGNED_INT_8_8_8_8_REV,	//Byte packing
                    bytes);                         //Texture data
    
    BOOL succeeded = [self _checkForGLError: outError];
    return succeeded;
}

- (BOOL) fillRegion: (CGRect)region
            withRed: (CGFloat)red
              green: (CGFloat)green
               blue: (CGFloat)blue
              alpha: (CGFloat)alpha
              error: (NSError **)outError
{
    //We upload bytes in BGRA format
    GLubyte components[4] = {
        blue * 255,
        green * 255,
        red * 255,
        alpha * 255
    };
    
    size_t numBytes = _textureSize.width * _textureSize.height * 4;
    GLvoid *colorData = (GLvoid *)malloc(numBytes);
    BOOL succeeded = NO;
    if (colorData)
    {
        //Write the color data in stripes into the buffer
        memset_pattern4(colorData, components, numBytes);
        
        succeeded = [self fillRegion: region withBytes: colorData error: outError];
        free(colorData);
    }
    return succeeded;
}

#pragma mark -
#pragma mark Behaviour

- (void) setIntValue: (GLint)value forParameter: (GLenum)parameter
{
    CGLContextObj cgl_ctx = _context;
    
    glBindTexture(_type, _texture);
    glTexParameteri(_type, parameter, value);
}

- (void) setMinFilter: (GLenum)minFilter
{
    if (_minFilter != minFilter)
    {
        _minFilter = minFilter;
        [self setIntValue: (GLint)minFilter forParameter: GL_TEXTURE_MIN_FILTER];
    }
}

- (void) setMagFilter: (GLenum)magFilter
{
    if (_magFilter != magFilter)
    {
        _magFilter = magFilter;
        [self setIntValue: (GLint)magFilter forParameter: GL_TEXTURE_MAG_FILTER];
    }
}

- (void) setHorizontalWrapping: (GLenum)horizontalWrapping
{
    if (_horizontalWrapping != horizontalWrapping)
    {
        _horizontalWrapping = horizontalWrapping;
        [self setIntValue: (GLint)horizontalWrapping forParameter: GL_TEXTURE_WRAP_S];
    }
}

- (void) setVerticalWrapping: (GLenum)verticalWrapping
{
    if (_verticalWrapping != verticalWrapping)
    {
        _verticalWrapping = verticalWrapping;
        [self setIntValue: (GLint)verticalWrapping forParameter: GL_TEXTURE_WRAP_T];
    }
}

- (void) setMinFilter: (GLenum)minFilter
            magFilter: (GLenum)magFilter
             wrapping: (GLenum)wrapping
{
    if (_minFilter != minFilter || _magFilter != magFilter || _horizontalWrapping != wrapping || _verticalWrapping != wrapping)
    {
        CGLContextObj cgl_ctx = _context;
        
        glBindTexture(_type, _texture);
        glTexParameteri(_type, GL_TEXTURE_MIN_FILTER, minFilter);
        glTexParameteri(_type, GL_TEXTURE_MAG_FILTER, magFilter);
        glTexParameteri(_type, GL_TEXTURE_WRAP_S, wrapping);
        glTexParameteri(_type, GL_TEXTURE_WRAP_T, wrapping);
        
        _minFilter = minFilter;
        _magFilter = magFilter;
        _horizontalWrapping = _verticalWrapping = wrapping;
    }
}


#pragma mark -
#pragma mark Framebuffers

- (BOOL) bindToFrameBuffer: (GLuint)framebuffer
                attachment: (GLenum)attachment
                     level: (GLint)level
                     error: (NSError **)outError
{
    CGLContextObj cgl_ctx = _context;
    
    //Record what the current framebuffer is, so that we can reset it after attachment.
    GLuint currentFramebuffer;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING_EXT, (GLint *)&currentFramebuffer);
    
    if (currentFramebuffer != framebuffer)
        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, framebuffer);
    
    glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT,
                              attachment,
                              _type,
                              _texture,
                              level);
    
    BOOL succeeded = YES;
    if (outError)
    {
        GLenum status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
        if (status != GL_FRAMEBUFFER_COMPLETE_EXT)
        {
            *outError = errorForGLFramebufferExtensionStatus(status);
            succeeded = NO;
        }
    }
    
    if (currentFramebuffer != framebuffer)
        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, currentFramebuffer);
        
    return succeeded;
}



#pragma mark -
#pragma mark Coordinates

- (BOOL) containsRegion: (CGRect)region
{
    CGRect textureRegion = CGRectMake(0, 0, _textureSize.width, _textureSize.height);
    return CGRectContainsRect(textureRegion, region);
}

- (BOOL) canAccommodateContentSize: (CGSize)contentSize
{
    return (contentSize.width <= self.textureSize.width) && (contentSize.height <= self.textureSize.height);
}

- (CGRect) nativeRectFromTexelRect: (CGRect)rect
{
    if (_usesNormalizedTextureCoordinates)
        return [self normalizedRectFromTexelRect: rect];
    else
        return rect;
}

- (CGRect) nativeRectFromNormalizedRect: (CGRect)rect
{
    if (_usesNormalizedTextureCoordinates)
        return rect;
    else
        return [self texelRectFromNormalizedRect: rect];
}

- (CGRect) normalizedRectFromTexelRect: (CGRect)rect
{
    return CGRectMake(rect.origin.x / _textureSize.width,
                      rect.origin.y / _textureSize.height,
                      rect.size.width / _textureSize.width,
                      rect.size.height / _textureSize.height);
}

- (CGRect) texelRectFromNormalizedRect: (CGRect)rect
{
    return CGRectMake(rect.origin.x * _textureSize.width,
                      rect.origin.y * _textureSize.height,
                      rect.size.width * _textureSize.width,
                      rect.size.height * _textureSize.height);
}

- (CGSize) normalizedSizeFromTexelSize: (CGSize)size
{
    return CGSizeMake(size.width / _textureSize.width,
                      size.height / _textureSize.height);
}

- (CGSize) texelSizeFromNormalizedSize: (CGSize)size
{
    return CGSizeMake(size.width * _textureSize.width,
                      size.height * _textureSize.height);
}

- (CGPoint) normalizedPointFromTexelPoint: (CGPoint)point
{
    return CGPointMake(point.x / _textureSize.width,
                       point.y / _textureSize.height);
}

- (CGPoint) texelPointFromNormalizedPoint: (CGPoint)point
{
    return CGPointMake(point.x * _textureSize.width,
                       point.y * _textureSize.height);
}

- (CGRect) normalizedContentRegion
{
    return [self normalizedRectFromTexelRect: self.contentRegion];
}

- (void) setNormalizedContentRegion: (CGRect)region
{
    self.contentRegion = [self texelRectFromNormalizedRect: region];
}


#pragma mark -
#pragma mark Drawing

//! Inner method for the below, which treats the region as being
//! expressed in the standard coordinate system for our texture type:
//! texels for GL_TEXTURE_RECTANGLE_ARB, normalized coordinates for GL_TEXTURE_2D.
//! No coordinate translation is done.
- (BOOL) _drawFromNativeRegion: (CGRect)region
                  ontoVertices: (GLfloat *)vertices
                         error: (NSError **)outError
{
    GLfloat minX = CGRectGetMinX(region),
    minY = CGRectGetMinY(region),
    maxX = CGRectGetMaxX(region),
    maxY = CGRectGetMaxY(region);
    
    GLfloat texCoords[8] = {
        minX,	minY,
        maxX,	minY,
        maxX,	maxY,
        minX,	maxY
    };
    
    CGLContextObj cgl_ctx = _context;
    
    glEnable(_type);
    glBindTexture(_type, _texture);
    
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glTexCoordPointer(2, GL_FLOAT, 0, texCoords);
    
    glEnableClientState(GL_VERTEX_ARRAY);
    glVertexPointer(2, GL_FLOAT, 0, vertices);
    
    glUnmapBufferARB(GL_PIXEL_UNPACK_BUFFER_ARB);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0,
            NSWidth(region), NSHeight(region), GL_BGRA_EXT,
            GL_UNSIGNED_INT_8_8_8_8_REV, 0);
    glBindBufferARB(GL_PIXEL_UNPACK_BUFFER_ARB, 0);

    glCallList(_displayList);
    
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
    glDisable(_type);
    
    BOOL succeeded = [self _checkForGLError: outError];
    return succeeded;
}

- (BOOL) drawFromNormalizedRegion: (CGRect)region
                     ontoVertices: (GLfloat *)vertices
                            error: (NSError **)outError
{
    CGRect nativeRegion = [self nativeRectFromNormalizedRect: region];
    return [self _drawFromNativeRegion: nativeRegion ontoVertices: vertices error: outError]; 
}

- (BOOL) drawFromTexelRegion: (CGRect)region
                ontoVertices: (GLfloat *)vertices
                       error: (NSError **)outError
{
    CGRect nativeRegion = [self nativeRectFromTexelRect: region];
    return [self _drawFromNativeRegion: nativeRegion ontoVertices: vertices error: outError];
}


- (BOOL) drawOntoVertices: (GLfloat *)vertices
                    error: (NSError **)outError
{
    CGRect nativeRegion = [self nativeRectFromTexelRect: self.contentRegion];
    return [self _drawFromNativeRegion: nativeRegion ontoVertices: vertices error: outError];
}
@end
