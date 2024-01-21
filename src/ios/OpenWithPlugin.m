#import <Cordova/CDV.h>
#import "ShareViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>

/*
 * Constants
 */

#define VERBOSITY_DEBUG  0
#define VERBOSITY_INFO  10
#define VERBOSITY_WARN  20
#define VERBOSITY_ERROR 30

/*
 * State variables
 */

static NSDictionary* launchOptions = nil;

/*
 * OpenWithPlugin definition
 */

@interface OpenWithPlugin : CDVPlugin {
    NSString* _loggerCallback;
    NSString* _handlerCallback;
    NSUserDefaults *_userDefaults;
    long _verbosityLevel;
}

@property (nonatomic,retain) NSString* loggerCallback;
@property (nonatomic,retain) NSString* handlerCallback;
@property (nonatomic) long verbosityLevel;
@property (nonatomic,retain) NSUserDefaults *userDefaults;
@end

/*
 * OpenWithPlugin implementation
 */

@implementation OpenWithPlugin

@synthesize loggerCallback = _loggerCallback;
@synthesize handlerCallback = _handlerCallback;
@synthesize verbosityLevel = _verbosityLevel;
@synthesize userDefaults = _userDefaults;

//
// Retrieve launchOptions
//
// The plugin mechanism doesn’t provide an easy mechanism to capture the
// launchOptions which are passed to the AppDelegate’s didFinishLaunching: method.
//
// Therefore we added an observer for the
// UIApplicationDidFinishLaunchingNotification notification when the class is loaded.
//
// Source: https://www.plotprojects.com/blog/developing-a-cordova-phonegap-plugin-for-ios/
//
+ (void) load {
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(didFinishLaunching:)
                                               name:UIApplicationDidFinishLaunchingNotification
                                             object:nil];
}

+ (void) didFinishLaunching:(NSNotification*)notification {
    launchOptions = notification.userInfo;
}

- (void) log:(long)level message:(NSString*)message {
    if (level >= self.verbosityLevel) {
        NSLog(@"[OpenWithPlugin.m]%@", message);
        if (self.loggerCallback != nil) {
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:message];
            pluginResult.keepCallback = [NSNumber  numberWithBool:YES];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self.loggerCallback];
        }
    }
}
- (void) debug:(NSString*)message { [self log:VERBOSITY_DEBUG message:message]; }
- (void) info:(NSString*)message { [self log:VERBOSITY_INFO message:message]; }
- (void) warn:(NSString*)message { [self log:VERBOSITY_WARN message:message]; }
- (void) error:(NSString*)message { [self log:VERBOSITY_ERROR message:message]; }

- (void) pluginInitialize {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onResume) name:UIApplicationWillEnterForegroundNotification object:nil];
    [self onReset];
    [self info:@"[pluginInitialize] OK"];
}

- (void) onReset {
    [self info:@"[onReset]"];
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:SHAREEXT_GROUP_IDENTIFIER];
    self.verbosityLevel = VERBOSITY_INFO;
    self.loggerCallback = nil;
    self.handlerCallback = nil;
}

- (void) onResume {
    [self debug:@"[onResume]"];
    [self checkForFileToShare];
}

- (void) setVerbosity:(CDVInvokedUrlCommand*)command {
    NSNumber *value = [command argumentAtIndex:0
                                   withDefault:[NSNumber numberWithInt: VERBOSITY_INFO]
                                      andClass:[NSNumber class]];
    self.verbosityLevel = value.integerValue;
    [self.userDefaults setInteger:self.verbosityLevel forKey:@"verbosityLevel"];
    [self.userDefaults synchronize];
    [self debug:[NSString stringWithFormat:@"[setVerbosity] %li", self.verbosityLevel]];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setLogger:(CDVInvokedUrlCommand*)command {
    self.loggerCallback = command.callbackId;
    [self debug:[NSString stringWithFormat:@"[setLogger] %@", self.loggerCallback]];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_NO_RESULT];
    pluginResult.keepCallback = [NSNumber  numberWithBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setHandler:(CDVInvokedUrlCommand*)command {
    self.handlerCallback = command.callbackId;
    [self debug:[NSString stringWithFormat:@"[setHandler] %@", self.handlerCallback]];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_NO_RESULT];
    pluginResult.keepCallback = [NSNumber  numberWithBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) checkForFileToShare {
    [self debug:@"[checkForFileToShare]"];
    if (self.handlerCallback == nil) {
        [self debug:@"[checkForFileToShare] javascript not ready yet."];
        return;
    }

    [self.userDefaults synchronize];
    NSObject *object = [self.userDefaults objectForKey:@"shared"];
    if (object == nil) {
        [self debug:@"[checkForFileToShare] Nothing to share"];
        return;
    }

    // Clean-up the object, assume it's been handled from now, prevent double processing
    [self.userDefaults removeObjectForKey:@"shared"];

    // Extract sharing data, make sure that it is valid
    if (![object isKindOfClass:[NSDictionary class]]) {
        [self debug:@"[checkForFileToShare] Data object is invalid"];
        return;
    }
    NSDictionary *dict = (NSDictionary*)object;

    NSArray *items = dict[@"items"];

    NSArray *processedItems = [self processSharedItems:items];

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{
        @"action": @"SEND",
        @"exit": @YES,
        @"items": processedItems
    }];

    pluginResult.keepCallback = [NSNumber numberWithBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.handlerCallback];
}

- (NSMutableArray*) processSharedItems:(NSArray*)items {
    NSMutableArray *processedItems = [[NSMutableArray alloc] init];
    for (NSDictionary *item in items) {
        NSMutableDictionary *processedItem = [NSMutableDictionary dictionaryWithDictionary:item];
        [processedItems addObject:processedItem];
    }
    return processedItems;
}

// Initialize the plugin
- (void) init:(CDVInvokedUrlCommand*)command {
    [self debug:@"[init]"];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    [self checkForFileToShare];
}

// Load data from URL
- (void) load:(CDVInvokedUrlCommand*)command {
    [self debug:@"[load]"];
    NSDictionary *item = [command argumentAtIndex:0];
    [self.commandDelegate runInBackground:^{
        NSError* error = nil;
        NSURL *url = [NSURL URLWithString:item[@"uri"]];
        NSData* data = [NSData dataWithContentsOfFile:url.path options:0 error:&error];
        NSString* payload = [data base64EncodedStringWithOptions:0];
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:payload];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

// Exit after sharing
- (void) exit:(CDVInvokedUrlCommand*)command {
    [self debug:@"[exit]"];

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

@end
// vim: ts=4:sw=4:et
