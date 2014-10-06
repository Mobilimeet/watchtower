//
//  AZAPreviewController.m
//  RemoteQuickLook
//
//  Created by Alexander Zats on 2/17/13.
//  Copyright (c) 2013 Alexander Zats. All rights reserved.
//

#import "AZAPreviewController.h"
#import <CommonCrypto/CommonDigest.h>
#import "AFNetworking.h"
#import "AZAPreviewItem.h"

// As seen in SSToolkit
static NSString *AZAMD5StringFromNSString(NSString *string)
{
	NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char digest[CC_MD5_DIGEST_LENGTH], i;
	CC_MD5([data bytes], (CC_LONG)[data length], digest);
	NSMutableString *result = [NSMutableString string];
	for (i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
		[result appendFormat: @"%02x", (int)(digest[i])];
	}
	return [result copy];
}

static NSString *AZALocalFilePathForURL(NSURL *URL)
{
	NSString *fileExtension = [URL pathExtension];
	NSString *hashedURLString = AZAMD5StringFromNSString([URL absoluteString]);
	NSString *cacheDirectory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
	cacheDirectory = [cacheDirectory stringByAppendingPathComponent:@"com.zats.RemoteQuickLook"];
	BOOL isDirectory;
	if (![[NSFileManager defaultManager] fileExistsAtPath:cacheDirectory isDirectory:&isDirectory] || !isDirectory) {
		NSError *error = nil;
		BOOL isDirectoryCreated = [[NSFileManager defaultManager] createDirectoryAtPath:cacheDirectory
															withIntermediateDirectories:YES
																			 attributes:nil
																				  error:&error];
		if (!isDirectoryCreated) {
			NSException *exception = [NSException exceptionWithName:NSInternalInconsistencyException
															 reason:@"Failed to crate cache directory"
														   userInfo:@{ NSUnderlyingErrorKey : error }];
			@throw exception;
		}
	}
	NSString *temporaryFilePath = [[cacheDirectory stringByAppendingPathComponent:hashedURLString] stringByAppendingPathExtension:fileExtension];
	return temporaryFilePath;
}


@interface AZAPreviewController () <QLPreviewControllerDataSource, QLPreviewControllerDelegate>
@property (nonatomic, strong) AFHTTPRequestOperationManager *httpRequestManager;
@property (nonatomic, weak) id<QLPreviewControllerDataSource> actualDataSource;
@end

@implementation AZAPreviewController


#pragma mark - Properties

- (void)setDataSource:(id<QLPreviewControllerDataSource>)dataSource
{
	self.actualDataSource = dataSource;
	[super setDataSource:self];
}

- (id<QLPreviewControllerDataSource>)dataSource
{
	return self.actualDataSource;
}

- (AFHTTPRequestOperationManager *)httpRequestManager
{
  if(!_httpRequestManager)
  {
    _httpRequestManager = [AFHTTPRequestOperationManager manager];
  }

  return _httpRequestManager;
}

#pragma mark - QLPreviewControllerDataSource

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller
{
	return [self.actualDataSource numberOfPreviewItemsInPreviewController:controller];
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index
{
	id<QLPreviewItem> originalPreviewItem = [self.actualDataSource previewController:controller previewItemAtIndex:index];
	
	AZAPreviewItem *previewItemCopy = [AZAPreviewItem previewItemWithURL:originalPreviewItem.previewItemURL
																   title:originalPreviewItem.previewItemTitle];
	
	NSURL *originalURL = previewItemCopy.previewItemURL;
	if (!originalURL || [originalURL isFileURL]) {
		return previewItemCopy;
	}

	// If it's a remote file, check cache
	NSString *localFilePath = AZALocalFilePathForURL(originalURL);
	previewItemCopy.previewItemURL = [NSURL fileURLWithPath:localFilePath];
	if ([[NSFileManager defaultManager] fileExistsAtPath:localFilePath]) {
		return previewItemCopy;
	}

	// If it's not a local file, put a placeholder instead
	__block NSInteger capturedIndex = index;
	NSURLRequest *request = [NSURLRequest requestWithURL:originalURL];
	AFHTTPRequestOperation *operation = [self.httpRequestManager HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
		NSAssert([responseObject isKindOfClass:[NSData class]], @"Unexpected response: %@", responseObject);
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			NSError *error = nil;
			BOOL didWriteFile = [(NSData *)responseObject writeToFile:localFilePath
															  options:0
																error:&error];
			dispatch_async(dispatch_get_main_queue(), ^{
				if (!didWriteFile) {
					if ([self.delegate respondsToSelector:@selector(AZA_previewController:failedToLoadRemotePreviewItem:withError:)]) {
						[self.delegate AZA_previewController:self
						   failedToLoadRemotePreviewItem:originalPreviewItem
											   withError:error];
					}
					return;
				}
				// FIXME: Sometime remote preview item isn't getting updated
				// When pan gesture isn't finished so that two preview items can be seen at the same time upcomming item isn't getting updated, fixes are very welcome!
				if (controller.currentPreviewItemIndex == capturedIndex) {
					[controller refreshCurrentPreviewItem];
				}
			});
			
		});
	} failure:^(AFHTTPRequestOperation *operation, NSError *error) {
		if ([self.delegate respondsToSelector:@selector(AZA_previewController:failedToLoadRemotePreviewItem:withError:)]) {
			[self.delegate AZA_previewController:self
			   failedToLoadRemotePreviewItem:originalPreviewItem
								   withError:error];
		}
	}];

    /**
     * Add some acceptable Content-Types, haven't really tested all of these...
     *  A Quick Look preview controller can display previews for the following items:
     *  - iWork documents
     *  - Microsoft Office documents (Office ‘97 and newer)
     *  - Rich Text Format (RTF) documents
     *  - PDF files
     *  - Images
     *  - Text files whose uniform type identifier (UTI) conforms to the public.text type (see Uniform Type Identifiers Reference)
     *  - Comma-separated value (csv) files
     */
	NSSet *acceptableContentTypes = [NSSet setWithObjects:
	                                 @"application/x-iwork-keynote-sffkey",
	                                 @"application/x-iwork-pages-sffpages",
	                                 @"application/x-iwork-numbers-sffnumbers",
	                                 @"application/vnd.apple.keynote",
	                                 @"application/vnd.apple.pages",
	                                 @"application/msword",
	                                 @"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
	                                 @"application/vnd.ms-word.document.macroEnabled.12",
	                                 @"application/vnd.ms-excel",
	                                 @"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
	                                 @"application/vnd.ms-excel.sheet.macroEnabled.12",
	                                 @"application/vnd.ms-excel.addin.macroEnabled.12",
	                                 @"application/vnd.ms-excel.sheet.binary.macroEnabled.12",
	                                 @"application/vnd.ms-powerpoint",
	                                 @"application/vnd.openxmlformats-officedocument.presentationml.presentation",
	                                 @"application/vnd.openxmlformats-officedocument.presentationml.template",
	                                 @"application/vnd.openxmlformats-officedocument.presentationml.slideshow",
	                                 @"application/vnd.ms-powerpoint.addin.macroEnabled.12",
	                                 @"application/vnd.ms-powerpoint.presentation.macroEnabled.12",
	                                 @"application/vnd.ms-powerpoint.slideshow.macroEnabled.12",
	                                 @"text/rtf",
	                                 @"application/rtf",
	                                 @"text/rtfd",
	                                 @"application/rtfd",
	                                 @"application/pdf",
	                                 @"application/x-pdf",
	                                 @"application/x-bzpdf",
	                                 @"application/x-gzpdf",
	                                 @"application/vnd.fdf",
	                                 @"application/vnd.adobe.xfdf",
	                                 @"image/jpeg",
	                                 @"image/gif",
	                                 @"image/tiff",
	                                 @"image/x-tiff",
	                                 @"image/png",
	                                 @"image/bmp",
	                                 @"text/plain",
	                                 @"text/xml",
	                                 @"application/xml",
	                                 @"text/html",
	                                 nil];

    operation.responseSerializer = [AFHTTPResponseSerializer serializer];
    operation.responseSerializer.acceptableContentTypes = acceptableContentTypes;
    [operation start];
	
	return previewItemCopy;
}

@end
