//
//  PostViewController.m
//  TwitterFon
//
//  Created by kaz on 7/16/08.
//  Copyright 2008 naan studio. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "PostViewController.h"
#import "TwitterFonAppDelegate.h"
#import "TinyURL.h"

#define kShowAnimationkey @"showAnimation"
#define kHideAnimationKey @"hideAnimation"

@interface NSObject (PostTweetDelegate)
- (void)postTweetDidSucceed:(NSDictionary*)message;
- (void)postViewAnimationDidFinish:(BOOL)didPost;
@end

@implementation PostViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
	if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
		// Initialization code
	}
	return self;
}

- (void)viewDidLoad {
    charCount.font = [UIFont boldSystemFontOfSize:16];
    text.font = [UIFont systemFontOfSize:16];
    self.view.hidden = true;
    textRange.location = 0;
    textRange.length = 0;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
}

- (void)viewDidDisappear:(BOOL)animated 
{
}

- (void)startEditWithString:(NSString*)message setDelegate:(id)aDelegate
{
    NSMutableString *str = [NSMutableString stringWithString:text.text];
    [str insertString:message atIndex:textRange.location];
    textRange.location += [message length];

    self.view.hidden = false;
    textRange.length = 0;
    text.text = str;
    [text becomeFirstResponder];
    text.selectedRange = textRange;
    [self startEditWithDelegate:aDelegate];
}

- (void)startEditWithURL:(NSString*)URL setDelegate:(id)aDelegate
{
    if ([TinyURL needToDecode:URL]) {
        TinyURL *encoder = [[TinyURL alloc] initWithDelegate:self];
        [encoder encode:URL];
    }

    // Always append the URL to tail
    NSString *str = [NSString stringWithFormat:@"%@ %@", text.text, URL];
    
    self.view.hidden = false;
    textRange.length = 0;
    text.text = str;
    [text becomeFirstResponder];
    text.selectedRange = textRange;
    [self startEditWithDelegate:aDelegate];
}

- (void)startEditWithDelegate:(id)aDelegate
{
    delegate = aDelegate;
    [self setCharCount];
    self.view.hidden = false;
    didPost = false;
    [text becomeFirstResponder];

    CATransition *animation = [CATransition animation];
//    [animation setDelegate:self];
    [animation setType:kCATransitionMoveIn];
    [animation setSubtype:kCATransitionFromBottom];
    [animation setDuration:0.5];
    [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    [[self.view layer] addAnimation:animation forKey:kShowAnimationkey];

}

- (IBAction) cancel: (id) sender
{
    textRange = text.selectedRange;
    [text resignFirstResponder];
    self.view.hidden = true;
    
	CATransition *animation = [CATransition animation];
  	[animation setDelegate:self];
    [animation setType:kCATransitionPush];
    [animation setSubtype:kCATransitionFromTop];
	[animation setDuration:0.5];
	[animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
	
	[[self.view layer] addAnimation:animation forKey:kHideAnimationKey];
}

- (IBAction) send: (id) sender
{
    post = [[TwitterClient alloc] initWithDelegate:self];
    [post post:text.text];
    [sendingWindow show];
}

- (IBAction) clear: (id) sender
{
    text.text = @"";
    sendButton.enabled = false;
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning]; // Releases the view if it doesn't have a superview
	// Release anything that's not essential, such as cached data
}


- (void)dealloc {
    [post release];
	[super dealloc];
}

- (void)twitterClientDidSucceed:(TwitterClient*)sender messages:(NSObject*)obj;
{
    NSDictionary *dic = nil;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        dic = (NSDictionary*)obj;    
    }
    
    [sendingWindow hide];
    
    if ([delegate respondsToSelector:@selector(postTweetDidSucceed:)]) {
        if (dic) {
            [delegate postTweetDidSucceed:dic];
        }
    }       
    
    text.text = @"";
    [post autorelease];
    [self cancel:self];
    didPost = (dic) ? true : false;
}

- (void)twitterClientDidFail:(TwitterClient*)sender error:(NSString*)error
{
    [sendingWindow fail:error];
    [post autorelease];

    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:3 target:sendingWindow selector:@selector(hide) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
}

- (void)setCharCount
{
    int length = [text.text length];
    length = 140 - length;
    if (length == 140) {
        sendButton.enabled = false;
    }
    else if (length < 0) {
        sendButton.enabled = false;
        charCount.textColor = [UIColor redColor];
    }
    else {
        sendButton.enabled = true;
        charCount.textColor = [UIColor whiteColor];
    }
    charCount.text = [NSString stringWithFormat:@"%d", length];
}

//
// TinyURLDelegate
//
- (void)encodeTinyURLDidSucceed:(NSString*)tinyURL URL:(NSString*)URL
{
    NSRange r = [text.text rangeOfString:URL];
    if (r.location != NSNotFound) {
        NSMutableString *str = [NSMutableString stringWithString:text.text];
        [str replaceCharactersInRange:r withString:tinyURL];
        text.text = str;
        if (--r.location < 0) r.location = 0;
        r.length = 0;
        text.selectedRange = r;
    }
}

- (void)tinyURLDidFail:(TinyURL*)sender error:(NSString*)error
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"encode tinyURL error"
                                                    message:error
                                                   delegate:self
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles: nil];
    [alert show];	
    [alert release];
}

//
// UITextViewDelegate
//
- (void)textViewDidChange:(UITextView *)textView
{
    [self setCharCount];
}

//
// CAAnimationDelegate
//
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished 
{
    [self.view removeFromSuperview];
	
    if (finished) {
        if ([delegate respondsToSelector:@selector(postViewAnimationDidFinish:)]) {
            [delegate postViewAnimationDidFinish:didPost];
        }
    }

}
@end
