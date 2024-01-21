//
//  ShareViewController.m
//  OpenWith - Share Extension
//

//
// The MIT License (MIT)
//
// Copyright (c) 2017 Jean-Christophe Hoelt
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import <UIKit/UIKit.h>
#import <Social/Social.h>
#import "ShareViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ShareViewController : SLComposeServiceViewController <UIAlertViewDelegate> {
    long _verbosityLevel;
    NSFileManager *_fileManager;
    NSUserDefaults *_userDefaults;
}
@property (nonatomic) long verbosityLevel;
@property (nonatomic,retain) NSFileManager *fileManager;
@property (nonatomic,retain) NSUserDefaults *userDefaults;
@end

/*
 * Constants
 */

#define VERBOSITY_DEBUG  0
#define VERBOSITY_INFO  10
#define VERBOSITY_WARN  20
#define VERBOSITY_ERROR 30

@implementation ShareViewController

@synthesize fileManager = _fileManager;
@synthesize verbosityLevel = _verbosityLevel;
@synthesize userDefaults = _userDefaults;

- (void) log:(int)level message:(NSString*)message {
    if (level >= self.verbosityLevel) {
        NSLog(@"[ShareViewController.m]%@", message);
    }
}
- (void) debug:(NSString*)message { [self log:VERBOSITY_DEBUG message:message]; }
- (void) info:(NSString*)message { [self log:VERBOSITY_INFO message:message]; }
- (void) warn:(NSString*)message { [self log:VERBOSITY_WARN message:message]; }
- (void) error:(NSString*)message { [self log:VERBOSITY_ERROR message:message]; }

- (void) setup {
    [self debug:@"[setup]"];

    self.fileManager = [NSFileManager defaultManager];
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:SHAREEXT_GROUP_IDENTIFIER];
    self.verbosityLevel = [self.userDefaults integerForKey:@"verbosityLevel"];
}

- (BOOL) isContentValid {
    return YES;
}

- (void) openURL:(nonnull NSURL *)url {

    SEL selector = NSSelectorFromString(@"openURL:options:completionHandler:");

    UIResponder* responder = self;
    while ((responder = [responder nextResponder]) != nil) {
        NSLog(@"responder = %@", responder);
        if([responder respondsToSelector:selector] == true) {
            NSMethodSignature *methodSignature = [responder methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];

            // Arguments
            void (^completion)(BOOL success) = ^void(BOOL success) {
                NSLog(@"Completions block: %i", success);
            };
            if (@available(iOS 13.0, *)) {
                UISceneOpenExternalURLOptions * options = [[UISceneOpenExternalURLOptions alloc] init];
                options.universalLinksOnly = false;
                
                [invocation setTarget: responder];
                [invocation setSelector: selector];
                [invocation setArgument: &url atIndex: 2];
                [invocation setArgument: &options atIndex:3];
                [invocation setArgument: &completion atIndex: 4];
                [invocation invoke];
                break;
            } else {
                NSDictionary<NSString *, id> *options = [NSDictionary dictionary];
                
                [invocation setTarget: responder];
                [invocation setSelector: selector];
                [invocation setArgument: &url atIndex: 2];
                [invocation setArgument: &options atIndex:3];
                [invocation setArgument: &completion atIndex: 4];
                [invocation invoke];
                break;
            }
        }
    }
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.view.hidden = YES;
}

- (void) viewDidAppear:(BOOL)animated {
    [self.view endEditing:YES];

    [self setup];
    [self debug:@"[viewDidAppear]"];
    NSArray<NSItemProvider *> *attachments = ((NSExtensionItem*)self.extensionContext.inputItems[0]).attachments;
    __block unsigned long remainingAttachments = attachments.count;
    NSMutableArray *items = [[NSMutableArray alloc] init];
    NSDictionary *results = @{
        @"items": items,
    };

    for (NSItemProvider* itemProvider in attachments) {
        [self debug:[NSString stringWithFormat:@"item provider registered indentifiers = %@", itemProvider.registeredTypeIdentifiers]];

        // IMAGE
        if ([itemProvider hasItemConformingToTypeIdentifier:@"public.image"]) {
            [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];

            [itemProvider loadItemForTypeIdentifier:@"public.image" options:nil completionHandler: ^(id<NSSecureCoding> data, NSError *error) {
                NSString *fileUrl = @"";
                NSString *path = @"";
                NSString *uti = @"public.image";
                NSString *mimeType = @"";

                if([(NSObject*)data isKindOfClass:[UIImage class]]) {
                    UIImage* image = (UIImage*) data;

                    if (image != nil) {
                        NSURL *targetUrl = [[self.fileManager containerURLForSecurityApplicationGroupIdentifier:SHAREEXT_GROUP_IDENTIFIER] URLByAppendingPathComponent:@"share.png"];
                        NSData *binaryImageData = UIImagePNGRepresentation(image);

                        [binaryImageData writeToFile:[targetUrl.absoluteString substringFromIndex:6] atomically:YES];
                        fileUrl = targetUrl.absoluteString;
                        path = targetUrl.path;
                        mimeType = @"image/png";
                    }
                }

                if ([(NSObject*)data isKindOfClass:[NSURL class]]) {
                    NSURL* item = (NSURL*) data;
                    NSString *registeredType = nil;

                    NSURL* fileUrlObject = [self saveFileToAppGroupFolder:item];
                    fileUrl = [fileUrlObject absoluteString];
                    path = item.path;

                    if ([itemProvider.registeredTypeIdentifiers count] > 0) {
                        registeredType = itemProvider.registeredTypeIdentifiers[0];
                    } else {
                        registeredType = uti;
                    }

                    mimeType = [self mimeTypeFromUti:registeredType];
                }

                NSDictionary *dict = @{
                    @"text" : self.contentText,
                    @"uri" : fileUrl,
                    @"path" : path,
                    @"type" : mimeType
                };

                [items addObject:dict];

                --remainingAttachments;
                if (remainingAttachments == 0) {
                    [self sendResults:results];
                }
            }];
        }
        // FILE
        else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.url"]) {
            [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];

            [itemProvider loadItemForTypeIdentifier:@"public.url" options:nil completionHandler: ^(NSURL* item, NSError *error) {
                [self debug:[NSString stringWithFormat:@"public.url = %@", item]];
                NSString *uti = @"public.url";

                if ([itemProvider.registeredTypeIdentifiers count] > 0) {
                    uti = itemProvider.registeredTypeIdentifiers[0];
                }

                NSString* uri = @"";
                NSString* path = @"";
                NSString* text = @"";

                NSString *mimeType =  [self mimeTypeFromUti:uti];
                
                if ([self.contentText length] == 0) {
                    NSURL* fileUrlObject = [self saveFileToAppGroupFolder:item];
                    path = item.path;
                    uri = [fileUrlObject absoluteString];
                } else if (![self.contentText isEqualToString:[item absoluteString]]) {
                    text = [NSString stringWithFormat:@"%@ %@", self.contentText, [item absoluteString]];
                }
                NSDictionary *dict = @{
                    @"type" : mimeType,
                    @"path" : path,
                    @"text" : text,
                    @"uri" : uri
                };

                [items addObject:dict];

                --remainingAttachments;
                if (remainingAttachments == 0) {
                    [self sendResults:results];
                }
            }];
        }
        // TEXT
        else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.plain-text"]) {
            [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];

            [itemProvider loadItemForTypeIdentifier:@"public.plain-text" options:nil completionHandler: ^(NSString* item, NSError *error) {
                [self debug:[NSString stringWithFormat:@"public.plain-text = %@", item]];
                NSString *uti = @"public.plain-text";

                if ([itemProvider.registeredTypeIdentifiers count] > 0) {
                    uti = itemProvider.registeredTypeIdentifiers[0];
                }

                NSString *mimeType =  [self mimeTypeFromUti:uti];
                NSDictionary *dict = @{
                    @"type" : mimeType,
                    @"path" : @"",
                    @"text" : self.contentText,
                    @"uri" : @""
                };

                [items addObject:dict];

                --remainingAttachments;
                if (remainingAttachments == 0) {
                    [self sendResults:results];
                }
            }];
        }
        // Unhandled data type
        else {
            [self debug:[NSString stringWithFormat:@"Unhandled data type provider = %@", itemProvider]];
            --remainingAttachments;
            if (remainingAttachments == 0) {
                [self sendResults:results];
            }
        }
    }
}

- (void) sendResults: (NSDictionary*)results {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self debug:[NSString stringWithFormat:@"Result sending %li items", [results[@"items"] count]]];
        [self.userDefaults setObject:results forKey:@"shared"];
        [self.userDefaults synchronize];

        // Emit a URL that opens the cordova app
        NSString *url = [NSString stringWithFormat:@"%@://shared", SHAREEXT_URL_SCHEME];

        [self openURL:[NSURL URLWithString:url]];

        // Inform the host that we're done, so it un-blocks its UI.
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
    });
}

- (void) didSelectPost {
    [self debug:@"[didSelectPost]"];
}

- (NSArray*) configurationItems {
    // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
    return @[];
}

- (NSString *) mimeTypeFromUti: (NSString*)uti {
    if (uti == nil) { return nil; }
    NSString *ret = [UTType typeWithIdentifier:uti].preferredMIMEType;
    return ret == nil ? uti : ret;
}

- (NSURL *) saveFileToAppGroupFolder: (NSURL*)url {
    NSURL *targetUrl = [[self.fileManager containerURLForSecurityApplicationGroupIdentifier:SHAREEXT_GROUP_IDENTIFIER] URLByAppendingPathComponent:url.lastPathComponent];
    [self.fileManager copyItemAtURL:url toURL:targetUrl error:nil];
    return targetUrl;
}

@end
