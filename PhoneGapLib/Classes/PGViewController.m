//
//  PGViewController.m
//
//  Created by Jesse MacFadyen on 11-12-08.
//  Copyright 2011 Nitobi. All rights reserved.
//

#import "PGViewController.h"
#import "PGPlugin.h"
#import "Location.h"
#import "Connection.h"

#define SYMBOL_TO_NSSTRING_HELPER(x) @#x
#define SYMBOL_TO_NSSTRING(x) SYMBOL_TO_NSSTRING_HELPER(x)
#define degreesToRadian(x) (M_PI * (x) / 180.0)

@interface PGViewController ()

@property (nonatomic, readwrite, retain) NSDictionary* settings;
@property (nonatomic, readwrite, retain) PGWhitelist* whitelist; 
@property (nonatomic, readwrite, retain) NSMutableDictionary* pluginObjects;
@property (nonatomic, readwrite, retain) NSDictionary* pluginsMap;
@property (nonatomic, readwrite, retain) NSArray* supportedOrientations;
@property (nonatomic, readwrite, copy)   NSString* sessionKey;
@property (nonatomic, readwrite, assign) BOOL loadFromString;

@property (nonatomic, readwrite, retain) IBOutlet UIActivityIndicatorView* activityView;
@property (nonatomic, readwrite, retain) UIImageView* imageView;


@end


@implementation PGViewController

@synthesize webView, supportedOrientations;
@synthesize pluginObjects, pluginsMap, whitelist;
@synthesize settings, sessionKey, loadFromString;
@synthesize imageView, activityView, useSplashScreen;

- (id) init
{
    self = [super init];
    if (self != nil) {
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receivedOrientationChange) name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
    }
    return self; 
}

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void) viewDidLoad 
{
    if (self.sessionKey == nil) {
        self.sessionKey = [NSString stringWithFormat:@"%d", arc4random()];
    }
    
    [super viewDidLoad];
	
    self.pluginObjects = [[[NSMutableDictionary alloc] initWithCapacity:4] autorelease];
    
	// read from UISupportedInterfaceOrientations (or UISupportedInterfaceOrientations~iPad, if its iPad) from -Info.plist
    self.supportedOrientations = [self parseInterfaceOrientations:
									  [[[NSBundle mainBundle] infoDictionary] objectForKey:@"UISupportedInterfaceOrientations"]];
    
    // read from PhoneGap.plist in the app bundle
    NSString* appPlistName = @"PhoneGap";
    NSDictionary* phonegapPlist = [[self class] getBundlePlist:appPlistName];
    if (phonegapPlist == nil) {
        NSLog(@"WARNING: %@.plist is missing.", appPlistName);
		return;
    }
    self.settings = [[[NSDictionary alloc] initWithDictionary:phonegapPlist] autorelease];
	
    // read from Plugins dict in PhoneGap.plist in the app bundle
    NSString* pluginsKey = @"Plugins";
    NSDictionary* pluginsDict = [self.settings objectForKey:@"Plugins"];
    if (pluginsDict == nil) {
        NSLog(@"WARNING: %@ key in %@.plist is missing! PhoneGap will not work, you need to have this key.", pluginsKey, appPlistName);
        return;
    }
    
    // set the whitelist
    self.whitelist = [[[PGWhitelist alloc] initWithArray:[self.settings objectForKey:@"ExternalHosts"]] autorelease];
	
    self.pluginsMap = [pluginsDict dictionaryWithLowercaseKeys];
    
    ///////////////////
    
	NSString* startFilePath = [[self class] pathForResource:[self startPage]];
	NSURL* appURL  = nil;
    NSString* loadErr = nil;
    
    if (startFilePath == nil) {
        loadErr = [NSString stringWithFormat:@"ERROR: Start Page at '%@/%@' was not found.", [[self class] wwwFolderName], [self startPage]];
        NSLog(@"%@", loadErr);
        self.loadFromString = YES;
        appURL = nil;
    } else {
        appURL = [NSURL fileURLWithPath:startFilePath];
    }

    ///////////////////
    
    NSNumber* enableLocation       = [settings objectForKey:@"EnableLocation"];
    NSString* enableViewportScale  = [settings objectForKey:@"EnableViewportScale"];
    NSNumber* allowInlineMediaPlayback = [settings objectForKey:@"AllowInlineMediaPlayback"];
    NSNumber* mediaPlaybackRequiresUserAction = [settings objectForKey:@"MediaPlaybackRequiresUserAction"];
    
    self.webView.scalesPageToFit = [enableViewportScale boolValue];
    
    /*
     * Fire up the GPS Service right away as it takes a moment for data to come back.
     */
    if ([allowInlineMediaPlayback boolValue] && [self.webView respondsToSelector:@selector(allowsInlineMediaPlayback)]) {
        self.webView.allowsInlineMediaPlayback = YES;
    }
    if ([mediaPlaybackRequiresUserAction boolValue] && [self.webView respondsToSelector:@selector(mediaPlaybackRequiresUserAction)]) {
        self.webView.mediaPlaybackRequiresUserAction = YES;
    }
    
    /*
     * This is for iOS 4.x, where you can allow inline <video> and <audio>, and also autoplay them
     */
    if ([enableLocation boolValue]) {
        [[self getCommandInstance:@"com.phonegap.geolocation"] startLocation:nil withDict:nil];
    }
    
    ///////////////////
    
    [ self createGapView];
    
    if (!loadErr) {
        NSURLRequest *appReq = [NSURLRequest requestWithURL:appURL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:20.0];
        [self.webView loadRequest:appReq];
    } else {
        NSString* html = [NSString stringWithFormat:@"<html><body> %@ </body></html>", loadErr];
        [self.webView loadHTMLString:html baseURL:nil];
    }
    
	//[self loadingStart];
}

- (NSArray*) parseInterfaceOrientations:(NSArray*)orientations
{
    NSMutableArray* result = [[[NSMutableArray alloc] init] autorelease];
	
    if (orientations != nil) 
    {
        NSEnumerator* enumerator = [orientations objectEnumerator];
        NSString* orientationString;
        
        while (orientationString = [enumerator nextObject]) 
        {
            if ([orientationString isEqualToString:@"UIInterfaceOrientationPortrait"]) {
                [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationPortrait]];
            } else if ([orientationString isEqualToString:@"UIInterfaceOrientationPortraitUpsideDown"]) {
                [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationPortraitUpsideDown]];
            } else if ([orientationString isEqualToString:@"UIInterfaceOrientationLandscapeLeft"]) {
                [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationLandscapeLeft]];
            } else if ([orientationString isEqualToString:@"UIInterfaceOrientationLandscapeRight"]) {
                [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationLandscapeRight]];
            }
        }
    }
    
    // default
    if ([result count] == 0) {
        [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationPortrait]];
    }
    
    return result;
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	// First ask the webview via JS if it wants to support the new orientation -jm
	int i = 0;
	
	switch (interfaceOrientation){
            
		case UIInterfaceOrientationPortraitUpsideDown:
			i = 180;
			break;
		case UIInterfaceOrientationLandscapeLeft:
			i = -90;
			break;
		case UIInterfaceOrientationLandscapeRight:
			i = 90;
			break;
		default:
		case UIInterfaceOrientationPortrait:
			// noop
			break;
	}
	
	NSString* jsCall = [ NSString stringWithFormat:@"shouldRotateToOrientation(%d);",i];
	NSString* res = [webView stringByEvaluatingJavaScriptFromString:jsCall];
	
	if([res length] > 0)
	{
		return [res boolValue];
	}
	
	// if js did not handle the new orientation ( no return value ) we will look it up in the plist -jm
	
	BOOL autoRotate = [self.supportedOrientations count] > 0; // autorotate if only more than 1 orientation supported
	if (autoRotate)
	{
		if ([self.supportedOrientations containsObject:
			 [NSNumber numberWithInt:interfaceOrientation]]) {
			return YES;
		}
    }
	
	// default return value is NO! -jm
	
	return NO;
}


- (void) createGapView
{
    CGRect webViewBounds = self.view.bounds;
    webViewBounds.origin = self.view.bounds.origin;
	
    if (!self.webView) 
	{
        self.webView = [[ [ UIGapView alloc ] initWithFrame:webViewBounds] autorelease];
		self.webView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
		
		[self.view addSubview:self.webView];
		[self.view sendSubviewToBack:self.webView];
		
		self.webView.delegate = self;
    }
}

- (void) didReceiveMemoryWarning {
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
	
	// Release any cached data, images, etc. that aren't in use.
}


- (void) viewDidUnload {
	// Release any retained subviews of the main view.
	// e.g. self.myOutlet = nil;
}


#pragma mark UIWebViewDelegate

/**
 When web application loads Add stuff to the DOM, mainly the user-defined settings from the Settings.plist file, and
 the device's data such as device ID, platform version, etc.
 */
- (void) webViewDidStartLoad:(UIWebView*)theWebView 
{
    
}

/**
 Called when the webview finishes loading.  This stops the activity view and closes the imageview
 */
- (void) webViewDidFinishLoad:(UIWebView*)theWebView 
{
    // Share session key with the WebView by setting PhoneGap.sessionKey
    NSString *sessionKeyScript = [NSString stringWithFormat:@"PhoneGap.sessionKey = \"%@\";", self.sessionKey];
    [theWebView stringByEvaluatingJavaScriptFromString:sessionKeyScript];
	
    
    NSDictionary *deviceProperties = [ self deviceProperties];
    NSMutableString *result = [[NSMutableString alloc] initWithFormat:@"DeviceInfo = %@;", [deviceProperties JSONString]];
    
    /* Settings.plist
     * Read the optional Settings.plist file and push these user-defined settings down into the web application.
     * This can be useful for supplying build-time configuration variables down to the app to change its behaviour,
     * such as specifying Full / Lite version, or localization (English vs German, for instance).
     */
    
    NSDictionary *temp = [[self class] getBundlePlist:@"Settings"];
    if ([temp respondsToSelector:@selector(JSONString)]) {
        [result appendFormat:@"\nwindow.Settings = %@;", [temp JSONString]];
    }
    
    NSLog(@"Device initialization: %@", result);
    [theWebView stringByEvaluatingJavaScriptFromString:result];
    [result release];
    
    /*
     * Hide the Top Activity THROBBER in the Battery Bar
     */
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
	
    id autoHideSplashScreenValue = [self.settings objectForKey:@"AutoHideSplashScreen"];
    // if value is missing, default to yes
    if (autoHideSplashScreenValue == nil || [autoHideSplashScreenValue boolValue]) {
        self.imageView.hidden = YES;
        self.activityView.hidden = YES;    
        [self.view.superview bringSubviewToFront:self.webView];
    }
    
    [self didRotateFromInterfaceOrientation:(UIInterfaceOrientation)[[UIDevice currentDevice] orientation]];
}

- (void) webView:(UIWebView*)webView didFailLoadWithError:(NSError*)error 
{
    NSLog(@"Failed to load webpage with error: %@", [error localizedDescription]);
    /*
	 if ([error code] != NSURLErrorCancelled)
	 alert([error localizedDescription]);
     */
}

- (BOOL) webView:(UIWebView*)theWebView shouldStartLoadWithRequest:(NSURLRequest*)request navigationType:(UIWebViewNavigationType)navigationType
{
	NSURL* url = [request URL];
    
    /*
     * Execute any commands queued with PhoneGap.exec() on the JS side.
     * The part of the URL after gap:// is irrelevant.
     */
	if ([[url scheme] isEqualToString:@"gap"]) {
        [self flushCommandQueue];
        return NO;
	}
    /*
     * If a URL is being loaded that's a file/http/https URL, just load it internally
     */
    else if ([url isFileURL])
    {
        return YES;
    }
    else if ([self.whitelist schemeIsAllowed:[url scheme]])
    {            
        if ([self.whitelist URLIsAllowed:url] == YES)
        {
            NSNumber *openAllInWhitelistSetting = [self.settings objectForKey:@"OpenAllWhitelistURLsInWebView"];
            if ((nil != openAllInWhitelistSetting) && [openAllInWhitelistSetting boolValue]) {
                NSLog(@"OpenAllWhitelistURLsInWebView set: opening in webview");
                return YES;
            }
			
            // mainDocument will be nil for an iFrame
            NSString* mainDocument = [theWebView.request.mainDocumentURL absoluteString];
			
            // anchor target="_blank" - load in Mobile Safari
            if (navigationType == UIWebViewNavigationTypeOther && mainDocument != nil)
            {
                [[UIApplication sharedApplication] openURL:url];
                return NO;
            }
            // other anchor target - load in PhoneGap webView
            else
            {
                return YES;
            }
        }
        
        return NO;
    }
    /*
     *    If we loaded the HTML from a string, we let the app handle it
     */
    else if (self.loadFromString == YES)
    {
        self.loadFromString = NO;
        return YES;
    }
    /*
     * all tel: scheme urls we let the UIWebview handle it using the default behaviour
     */
    else if ([[url scheme] isEqualToString:@"tel"])
    {
        return YES;
    }
    /*
     * all about: scheme urls are not handled
     */
    else if ([[url scheme] isEqualToString:@"about"])
    {
        return NO;
    }
    /*
     * We don't have a PhoneGap or web/local request, load it in the main Safari browser.
     * pass this to the application to handle.  Could be a mailto:dude@duderanch.com or a tel:55555555 or sms:55555555 facetime:55555555
     */
    else
    {
        NSLog(@"PhoneGapDelegate::shouldStartLoadWithRequest: Received Unhandled URL %@", url);
		
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url];
        } else { // handle any custom schemes to plugins
            [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:PGPluginHandleOpenURLNotification object:url]];
        }
		
        return NO;
    }
    
    return YES;
}

#pragma mark GapHelpers

- (void) javascriptAlert:(NSString*)text
{
    NSString* jsString = [NSString stringWithFormat:@"alert('%@');", text];
    [webView stringByEvaluatingJavaScriptFromString:jsString];
}

+ (NSString*) wwwFolderName
{
    return @"www";
}

- (NSString*) startPage
{
    return @"index.html";
}

+ (BOOL) isIPad 
{
#ifdef UI_USER_INTERFACE_IDIOM
    return (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
#else
    return NO;
#endif
}

+ (NSString*) resolveImageResource:(NSString*)resource
{
    NSString* systemVersion = [[UIDevice currentDevice] systemVersion];
    BOOL isLessThaniOS4 = ([systemVersion compare:@"4.0" options:NSNumericSearch] == NSOrderedAscending);
    
    // the iPad image (nor retina) differentiation code was not in 3.x, and we have to explicitly set the path
    if (isLessThaniOS4)
    {
        if ([[self class] isIPad]) {
            return [NSString stringWithFormat:@"%@~ipad.png", resource];
        } else {
            return [NSString stringWithFormat:@"%@.png", resource];
        }
    }
    
    return resource;
}

+ (NSString*) pathForResource:(NSString*)resourcepath
{
    NSBundle * mainBundle = [NSBundle mainBundle];
    NSMutableArray *directoryParts = [NSMutableArray arrayWithArray:[resourcepath componentsSeparatedByString:@"/"]];
    NSString       *filename       = [directoryParts lastObject];
    [directoryParts removeLastObject];
    
    NSString* directoryPartsJoined =[directoryParts componentsJoinedByString:@"/"];
    NSString* directoryStr = [self wwwFolderName];
    
    if ([directoryPartsJoined length] > 0) {
        directoryStr = [NSString stringWithFormat:@"%@/%@", [self wwwFolderName], [directoryParts componentsJoinedByString:@"/"]];
    }
    
    return [mainBundle pathForResource:filename ofType:@"" inDirectory:directoryStr];
}

+ (NSString*) applicationDocumentsDirectory 
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}

- (void) showSplashScreen
{
    NSString* launchImageFile = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"UILaunchImageFile"];
    if (launchImageFile == nil) { // fallback if no launch image was specified
        launchImageFile = @"Default"; 
    }
    
    NSString* orientedLaunchImageFile = nil;    
    CGAffineTransform startupImageTransform = CGAffineTransformIdentity;
    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
    BOOL isIPad = [[self class] isIPad];
    UIImage* launchImage = nil;
    
    if (isIPad)
    {
        if (!UIDeviceOrientationIsValidInterfaceOrientation(deviceOrientation)) {
            deviceOrientation = (UIDeviceOrientation)statusBarOrientation;
        }
        
        switch (deviceOrientation) 
        {
            case UIDeviceOrientationLandscapeLeft: // this is where the home button is on the right (yeah, I know, confusing)
            {
                orientedLaunchImageFile = [NSString stringWithFormat:@"%@-Landscape", launchImageFile];
                startupImageTransform = CGAffineTransformMakeRotation(degreesToRadian(90));
            }
                break;
            case UIDeviceOrientationLandscapeRight: // this is where the home button is on the left (yeah, I know, confusing)
            {
                orientedLaunchImageFile = [NSString stringWithFormat:@"%@-Landscape", launchImageFile];
                startupImageTransform = CGAffineTransformMakeRotation(degreesToRadian(-90));
            } 
                break;
            case UIDeviceOrientationPortraitUpsideDown:
            {
                orientedLaunchImageFile = [NSString stringWithFormat:@"%@-Portrait", launchImageFile];
                startupImageTransform = CGAffineTransformMakeRotation(degreesToRadian(180));
            } 
                break;
            case UIDeviceOrientationPortrait:
            default:
            {
                orientedLaunchImageFile = [NSString stringWithFormat:@"%@-Portrait", launchImageFile];
                startupImageTransform = CGAffineTransformIdentity;
            }
                break;
        }
        
        launchImage = [UIImage imageNamed:[[self class] resolveImageResource:orientedLaunchImageFile]];
    }
    else // not iPad
    {
        orientedLaunchImageFile = @"Default";
        launchImage = [UIImage imageNamed:[[self class] resolveImageResource:orientedLaunchImageFile]];
    }
    
    if (launchImage == nil) {
        NSLog(@"WARNING: Splash-screen image '%@' was not found. Orientation: %d, iPad: %d", orientedLaunchImageFile, deviceOrientation, isIPad);
    }
    
    self.imageView = [[[UIImageView alloc] initWithImage:launchImage] autorelease];    
    self.imageView.tag = 1;
    self.imageView.center = CGPointMake((screenBounds.size.width / 2), (screenBounds.size.height / 2));
    
    self.imageView.autoresizingMask = (UIViewAutoresizingFlexibleWidth & UIViewAutoresizingFlexibleHeight & UIViewAutoresizingFlexibleLeftMargin & UIViewAutoresizingFlexibleRightMargin);    
    [self.imageView setTransform:startupImageTransform];
    [self.view.superview addSubview:self.imageView];
    
    
    /*
     * The Activity View is the top spinning throbber in the status/battery bar. We init it with the default Grey Style.
     *
     *     whiteLarge = UIActivityIndicatorViewStyleWhiteLarge
     *     white      = UIActivityIndicatorViewStyleWhite
     *     gray       = UIActivityIndicatorViewStyleGray
     *
     */
    NSString* topActivityIndicator = [self.settings objectForKey:@"TopActivityIndicator"];
    UIActivityIndicatorViewStyle topActivityIndicatorStyle = UIActivityIndicatorViewStyleGray;
    
    if ([topActivityIndicator isEqualToString:@"whiteLarge"]) {
        topActivityIndicatorStyle = UIActivityIndicatorViewStyleWhiteLarge;
    } else if ([topActivityIndicator isEqualToString:@"white"]) {
        topActivityIndicatorStyle = UIActivityIndicatorViewStyleWhite;
    } else if ([topActivityIndicator isEqualToString:@"gray"]) {
        topActivityIndicatorStyle = UIActivityIndicatorViewStyleGray;
    }
    
    self.activityView = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:topActivityIndicatorStyle] autorelease];
    self.activityView.tag = 2;
    
    id showSplashScreenSpinnerValue = [self.settings objectForKey:@"ShowSplashScreenSpinner"];
    // backwards compatibility - if key is missing, default to true
    if (showSplashScreenSpinnerValue == nil || [showSplashScreenSpinnerValue boolValue]) {
        [self.view.superview addSubview:self.activityView];
    }
    
    self.activityView.center = self.view.center;
    [self.activityView startAnimating];
    
    [self.view.superview layoutSubviews];
}    

BOOL gSplashScreenShown = NO;
- (void) receivedOrientationChange
{
    if (self.imageView == nil) {
        gSplashScreenShown = YES;
        if (self.useSplashScreen) {
            [self showSplashScreen];
        }
    }
}

#pragma mark PhoneGapCommands

/**
 * Fetches the command queue and executes each command. It is possible that the
 * queue will not be empty after this function has completed since the executed
 * commands may have run callbacks which queued more commands.
 *
 * Returns the number of executed commands.
 */
- (int) executeQueuedCommands
{
    // Grab all the queued commands from the JS side.
    NSString* queuedCommandsJSON = [self.webView stringByEvaluatingJavaScriptFromString:
									@"PhoneGap.getAndClearQueuedCommands()"];
	
	
    // Parse the returned JSON array.
    //PG_SBJsonParser* jsonParser = [[[PG_SBJsonParser alloc] init] autorelease];
    NSArray* queuedCommands =
	[queuedCommandsJSON objectFromJSONString];
	
    // Iterate over and execute all of the commands.
    for (NSString* commandJson in queuedCommands) {
		
        if(![self execute:
		 [InvokedUrlCommand commandFromObject:
		  [commandJson mutableObjectFromJSONString]]])
		{
			NSLog(@"FAILED pluginJSON = %@",commandJson);
		}
    }
	
    return [queuedCommands count];
}

/**
 * Repeatedly fetches and executes the command queue until it is empty.
 */
- (void) flushCommandQueue
{
    [self.webView stringByEvaluatingJavaScriptFromString:
	 @"PhoneGap.commandQueueFlushing = true"];
	
    // Keep executing the command queue until no commands get executed.
    // This ensures that commands that are queued while executing other
    // commands are executed as well.
    int numExecutedCommands = 0;
    do {
        numExecutedCommands = [self executeQueuedCommands];
    } while (numExecutedCommands != 0);
	
    [self.webView stringByEvaluatingJavaScriptFromString:
	 @"PhoneGap.commandQueueFlushing = false"];
}

- (BOOL) execute:(InvokedUrlCommand*)command
{
    if (command.className == nil || command.methodName == nil) {
        return NO;
    }
    
    // Fetch an instance of this class
    PGPlugin* obj = [self getCommandInstance:command.className];
    
    if (!([obj isKindOfClass:[PGPlugin class]])) { // still allow deprecated class, until 1.0 release
        NSLog(@"ERROR: Plugin '%@' not found, or is not a PGPlugin. Check your plugin mapping in PhoneGap.plist.", command.className);
        return NO;
    }
    BOOL retVal = YES;
    
    // construct the fill method name to ammend the second argument.
    NSString* fullMethodName = [[NSString alloc] initWithFormat:@"%@:withDict:", command.methodName];
    if ([obj respondsToSelector:NSSelectorFromString(fullMethodName)]) {
        [obj performSelector:NSSelectorFromString(fullMethodName) withObject:command.arguments withObject:command.options];
    } else {
        // There's no method to call, so throw an error.
        NSLog(@"ERROR: Method '%@' not defined in Plugin '%@'", fullMethodName, command.className);
        retVal = NO;
    }
    [fullMethodName release];
    
    return retVal;
}

/**
 Returns an instance of a PhoneGapCommand object, based on its name.  If one exists already, it is returned.
 */
- (id) getCommandInstance:(NSString*)pluginName
{
    // first, we try to find the pluginName in the pluginsMap 
    // (acts as a whitelist as well) if it does not exist, we return nil
    // NOTE: plugin names are matched as lowercase to avoid problems - however, a 
    // possible issue is there can be duplicates possible if you had:
    // "com.phonegap.Foo" and "com.phonegap.foo" - only the lower-cased entry will match
    NSString* className = [self.pluginsMap objectForKey:[pluginName lowercaseString]];
    if (className == nil) {
        return nil;
    }
    
    id obj = [self.pluginObjects objectForKey:className];
    if (!obj) 
    {
        // attempt to load the settings for this command class
        NSDictionary* classSettings = [self.settings objectForKey:className];
		
        if (classSettings) {
            obj = [[NSClassFromString(className) alloc] initWithWebView:webView settings:classSettings];
        } else {
            obj = [[NSClassFromString(className) alloc] initWithWebView:webView];
        }
        
        if (obj != nil) {
            [self.pluginObjects setObject:obj forKey:className];
            [obj release];
        } else {
            NSLog(@"PGPlugin class %@ (pluginName: %@) does not exist.", className, pluginName);
        }
    }
    return obj;
}


#pragma mark PhoneGapDelegate?

- (NSDictionary*) deviceProperties
{
    UIDevice *device = [UIDevice currentDevice];
    NSMutableDictionary *devProps = [NSMutableDictionary dictionaryWithCapacity:4];
    [devProps setObject:[device model] forKey:@"platform"];
    [devProps setObject:[device systemVersion] forKey:@"version"];
    [devProps setObject:[device uniqueIdentifier] forKey:@"uuid"];
    [devProps setObject:[device name] forKey:@"name"];
    [devProps setObject:[[self class] phoneGapVersion ] forKey:@"gap"];
    
    id cmd = [self getCommandInstance:@"com.phonegap.connection"];
    if (cmd && [cmd isKindOfClass:[PGConnection class]]) 
    {
        NSMutableDictionary *connProps = [NSMutableDictionary dictionaryWithCapacity:3];
        if ([cmd respondsToSelector:@selector(connectionType)]) {
            [connProps setObject:[cmd connectionType] forKey:@"type"];
        }
        [devProps setObject:connProps forKey:@"connection"];
    }
    
    NSDictionary *devReturn = [NSDictionary dictionaryWithDictionary:devProps];
    return devReturn;
}

- (NSString*) appURLScheme
{
    NSString* URLScheme = nil;
    
    NSArray *URLTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleURLTypes"];
    if(URLTypes != nil ) {
        NSDictionary* dict = [URLTypes objectAtIndex:0];
        if(dict != nil ) {
            NSArray* URLSchemes = [dict objectForKey:@"CFBundleURLSchemes"];
            if( URLSchemes != nil ) {    
                URLScheme = [URLSchemes objectAtIndex:0];
            }
        }
    }
    
    return URLScheme;
}



/**
 Returns the contents of the named plist bundle, loaded as a dictionary object
 */
+ (NSDictionary*) getBundlePlist:(NSString*)plistName
{
    NSString *errorDesc = nil;
    NSPropertyListFormat format;
    NSString *plistPath = [[NSBundle mainBundle] pathForResource:plistName ofType:@"plist"];
    NSData *plistXML = [[NSFileManager defaultManager] contentsAtPath:plistPath];
    NSDictionary *temp = (NSDictionary *)[NSPropertyListSerialization
                                          propertyListFromData:plistXML
                                          mutabilityOption:NSPropertyListMutableContainersAndLeaves              
                                          format:&format errorDescription:&errorDesc];
    return temp;
}

/**
 Returns the current version of phoneGap as read from the VERSION file
 This only touches the filesystem once and stores the result in the class variable gapVersion
 */
static NSString *gapVersion;
+ (NSString*) phoneGapVersion
{
#ifdef PG_VERSION
    gapVersion = SYMBOL_TO_NSSTRING(PG_VERSION);
#else
	
    if (gapVersion == nil) {
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *filename = [mainBundle pathForResource:@"VERSION" ofType:nil];
        // read from the filesystem and save in the variable
        // first, separate by new line
        NSString* fileContents = [NSString stringWithContentsOfFile:filename encoding:NSUTF8StringEncoding error:NULL];
        NSArray* all_lines = [fileContents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSString* first_line = [all_lines objectAtIndex:0];        
        
        gapVersion = [first_line retain];
    }
#endif
    
    return gapVersion;
}

- (void)dealloc {
    [super dealloc];
}

@end

#pragma mark -

@implementation NSDictionary (LowercaseKeys)

- (NSDictionary*) dictionaryWithLowercaseKeys 
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:self.count];
    NSString* key;
    
    for (key in self) {
        [result setObject:[self objectForKey:key] forKey:[key lowercaseString]];
    }
    
    return result;
}

@end
