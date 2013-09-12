//
//  WatchTowerController.m
//  WatchTower
//
//  Created by Ilter Cengiz on 12/09/2013.
//  Copyright (c) 2013 Alexander Zats. All rights reserved.
//

#import "WatchTowerController.h"

#pragma mark -
#import "AZAPreviewController.h"
#import "AZAPreviewItem.h"

#pragma mark - Pods
#import <SVProgressHUD/SVProgressHUD.h>

@interface WatchTowerController () <QLPreviewControllerDataSource, QLPreviewControllerDelegate, AZAPreviewControllerDelegate>

@property (nonatomic, strong) NSArray *previewItems;

@end

@implementation WatchTowerController

- (void)viewDidLoad {
    
    [super viewDidLoad];
    
    // Add progress hud
    [SVProgressHUD showWithStatus:@"Fetching..." maskType:SVProgressHUDMaskTypeClear];
    
    // Remote files
	NSURL *docPreviewItemURL = [NSURL URLWithString:@"http://www.ada.gov/briefs/housebr.doc"];
	AZAPreviewItem *docPreviewItem = [AZAPreviewItem previewItemWithURL:docPreviewItemURL title:@"Microsoft Word"];
    
	NSURL *pdfPreviewItemURL = [NSURL URLWithString:@"http://www.tug.org/texshowcase/ShowcaseCircular.pdf"];
	AZAPreviewItem *pdfPreviewItem = [AZAPreviewItem previewItemWithURL:pdfPreviewItemURL title:@"PDF"];
	
	// Local files
	NSURL *localImageURL = [[NSBundle mainBundle] URLForResource:@"dribbble_debut" withExtension:@"png"];
	AZAPreviewItem *localImagePreviewItem = [AZAPreviewItem previewItemWithURL:localImageURL title:@"Local image"];
    
	NSMutableArray *previewItems = [NSMutableArray arrayWithObjects:docPreviewItem, pdfPreviewItem, localImagePreviewItem, nil];
    
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
		// Fetching list of popular photos from 500px
		NSURL *URL = [NSURL URLWithString:@"https://api.500px.com/v1/photos?feature=popular&image_size=4&consumer_key=LY4KTEfkrtFCI5bH8huv9WIU3HMV0sbMCZxYPOJk"];
		NSData *photos = [NSData dataWithContentsOfURL:URL];
		NSDictionary *response = [NSJSONSerialization JSONObjectWithData:photos options:0 error:nil];
		dispatch_async(dispatch_get_main_queue(), ^{
            
			// Parsing photos
			for (NSDictionary *photoDictionary in response[@"photos"]) {
				NSString *title = photoDictionary[@"name"];
				NSString *photoURLString = photoDictionary[@"image_url"];
				NSURL *photoURL = [NSURL URLWithString:photoURLString];
				AZAPreviewItem *previewItem = [AZAPreviewItem previewItemWithURL:photoURL title:title];
                
				// Adding to the data provider
				[previewItems addObject:previewItem];
			}
            
			self.previewItems = previewItems;
			
			// Enabling UI
            [SVProgressHUD showSuccessWithStatus:nil];
            self.showButton.enabled = YES;
		});
	});
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (IBAction)show:(id)sender {
    
    // Preview controller
    AZAPreviewController *previewController = [AZAPreviewController new];
    previewController.dataSource = self;
    previewController.delegate = self;
    
    [self presentViewController:previewController animated:YES completion:nil];
}

#pragma mark - QLPreviewControllerDataSource
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return self.previewItems.count;
}
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return self.previewItems[index];
}

#pragma mark - AZAPreviewControllerDelegate
- (void)AZA_previewController:(AZAPreviewController *)controller failedToLoadRemotePreviewItem:(id<QLPreviewItem>)previewItem withError:(NSError *)error {
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Failed to load file %@", previewItem.previewItemURL]
                                                    message:[error localizedDescription]
                                                   delegate:nil
                                          cancelButtonTitle:@"O.K."
                                          otherButtonTitles:nil, nil];
    [alert show];
}

@end
