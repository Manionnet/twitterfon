#import "Message.h"
#import "sqlite3.h"
#import "DBConnection.h"

static sqlite3_stmt* insert_statement = nil;
static sqlite3_stmt* select_statement = nil;

@interface Message (Private)
- (void)insertDB;
- (void)updateAttribute;
@end

@implementation Message

@synthesize messageId;
@synthesize user;
@synthesize text;
@synthesize createdAt;
@synthesize source;
@synthesize favorited;
@synthesize timestamp;

@synthesize unread;
@synthesize type;
@synthesize hasReply;
@synthesize textBounds;
@synthesize textHeight;
@synthesize cellHeight;
@synthesize accessoryType;
@synthesize page;

- (void)dealloc
{
    [text release];
    [user release];
    [source release];
    [timestamp release];
  	[super dealloc];
}

- (Message*)initWithJsonDictionary:(NSDictionary*)dic type:(MessageType)aType
{
	self = [super init];
    
    type = aType;
    
	messageId           = [[dic objectForKey:@"id"] longLongValue];
	text                = [[dic objectForKey:@"text"] retain];
    stringOfCreatedAt   = [dic objectForKey:@"created_at"];
    favorited           = [[dic objectForKey:@"favorited"] isKindOfClass:[NSNull class]] ? 0 : 1;

    if ((id)text == [NSNull null]) text = @"";

    // parse source parameter
    NSString *src = [dic objectForKey:@"source"];
    if (src == nil) {
        source = @"";
    }
    else if ((id)src == [NSNull null]) {
        source = @"";
    }
    else {
        NSRange r = [src rangeOfString:@"<a href"];
        if (r.location != NSNotFound) {
            NSRange start = [src rangeOfString:@"\">"];
            NSRange end   = [src rangeOfString:@"</a>"];
            if (start.location != NSNotFound && end.location != NSNotFound) {
                r.location = start.location + start.length;
                r.length = end.location - r.location;
                source = [[src substringWithRange:r] retain];
            }
        }
        else {
            source = [src retain];
        }
    }
	
	NSDictionary* userDic = [dic objectForKey:@"user"];
	if (userDic) {
        user = [[User alloc] initWithJsonDictionary:userDic];
    }
    else {
        userDic = [dic objectForKey:@"sender"];
        user = [[User alloc] initWithJsonDictionary:userDic];
    }

    [self updateAttribute];
    if (type != MSG_TYPE_USER) {
        [self insertDB];
    }
    unread = true;

	return self;
}


+ (Message*)messageWithLoadMessage:(MessageType)aType page:(int)page
{
    Message *m = [[[Message alloc] init] autorelease];
    m.type = aType;
    m.cellHeight = 48;
    m.page = page;
    m.textBounds = CGRectMake(0, 0, 320, 48);
    m.accessoryType = UITableViewCellAccessoryNone;
    return m;
}

+ (Message*)messageWithJsonDictionary:(NSDictionary*)dic type:(MessageType)type
{
	return [[[Message alloc] initWithJsonDictionary:dic type:type] autorelease];
}

- (id)copyWithZone:(NSZone *)zone
{
    Message *dist = [[Message allocWithZone:zone] init];
    
	dist.messageId  = messageId;
	dist.user       = [user copy];
	dist.text       = text;
    dist.createdAt  = createdAt;
    dist.source     = source;
    dist.favorited  = favorited;
    dist.timestamp  = timestamp;
    
    dist.unread     = unread;
    dist.hasReply   = hasReply;
    dist.type       = type;
    
    // Do not copy following members because they need re-calculate
    //
    //dist.textBounds = textBounds;
    //dist.cellHeight = cellHeight;
    //dist.textHeight = textHeight;
    
    dist.accessoryType = accessoryType;    
    
    return dist;
}

- (void)updateAttribute
{
    // Set accessoryType and bounds width
    //
    NSRange r = [text rangeOfString:@"http://"];
    int textWidth = (type == MSG_TYPE_USER) ? USER_CELL_WIDTH : CELL_WIDTH;
    if (r.location != NSNotFound) {    
        accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
        textWidth -= (type == MSG_TYPE_USER) ? DETAIL_BUTTON_USER : DETAIL_BUTTON_OTHER;
    }
    else {
        accessoryType = (type == MSG_TYPE_USER) ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    }

    // If tweet has @yourname, set flag for change cell color later
    //
    static NSString *username = nil;
    if (username == nil) {
        username = [[NSString stringWithFormat:@"@%@", [[NSUserDefaults standardUserDefaults] stringForKey:@"username"]] retain];
    }
    r = [text rangeOfString:username];
    hasReply = (r.location != NSNotFound) ? true : false;

    // Calculate text bounds and cell height here
    //
    [Message calcTextBounds:self textWidth:textWidth];

    // Calculate distance time and create timestamp
    //
    struct tm created;
    setenv("TZ", "GMT", 1);
    time_t now;
    time(&now);
    
    if (!createdAt) {
        if (stringOfCreatedAt) {
            strptime([stringOfCreatedAt UTF8String], "%a %b %d %H:%M:%S %z %Y", &created);
            createdAt = mktime(&created);
        }
    }
    int distance = (int)difftime(now, createdAt);
    if (distance < 0) distance = 0;

    if (distance < 60) {
        self.timestamp = [NSString stringWithFormat:@"%d %s", distance, (distance == 1) ? "second ago" : "seconds ago"];
    }
    else if (distance < 60 * 60) {  
        distance = distance / 60;
        self.timestamp = [NSString stringWithFormat:@"%d %s", distance, (distance == 1) ? "minute ago" : "minutes ago"];
    }  
    else if (distance < 60 * 60 * 24) {
        distance = distance / 60 / 60;
        self.timestamp = [NSString stringWithFormat:@"%d %s", distance, (distance == 1) ? "hour ago" : "hours ago"];
    }
    else if (distance < 60 * 60 * 24 * 7) {
        distance = distance / 60 / 60 / 24;
        self.timestamp = [NSString stringWithFormat:@"%d %s", distance, (distance == 1) ? "day ago" : "days ago"];
    }
    else if (distance < 60 * 60 * 24 * 7 * 4) {
        distance = distance / 60 / 60 / 24 / 7;
        self.timestamp = [NSString stringWithFormat:@"%d %s", distance, (distance == 1) ? "week ago" : "weeks ago"];
    }
    else {
        NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init]  autorelease];
        [dateFormatter setDateStyle:NSDateFormatterShortStyle];
        [dateFormatter setTimeStyle:NSDateFormatterNoStyle];
        
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:mktime(&created)];        
        self.timestamp = [dateFormatter stringFromDate:date];
    }
    if ([source length]) {
        self.timestamp = [self.timestamp stringByAppendingFormat:@" from %@", source];
    }

}

+ (void)calcTextBounds:(Message*)message textWidth:(int)textWidth
{
    static UILabel *sLabel = nil;
    static CGRect bounds, result;

    if (message.type == MSG_TYPE_USER) {
        bounds = CGRectMake(USER_CELL_PADDING, 3, textWidth, 200);
    }
    else {
        bounds = CGRectMake(LEFT, TOP, textWidth, 200);
    }
    
    if (message.textHeight) {
        result = CGRectMake(bounds.origin.x, bounds.origin.y, textWidth, message.textHeight);
    }
    else {
        if (sLabel == nil) {
            sLabel = [[UILabel alloc] initWithFrame: CGRectZero];        
            sLabel.font = [UIFont systemFontOfSize:13];
            sLabel.numberOfLines = 10;
        }
        
        sLabel.text = message.text;
        result = [sLabel textRectForBounds:bounds limitedToNumberOfLines:10];
    }

    message.textBounds = CGRectMake(bounds.origin.x, bounds.origin.y, textWidth, result.size.height);
    message.textHeight = result.size.height;
    
    if (message.type == MSG_TYPE_USER) {
        result.size.height += 22;
    }
    else {
        result.size.height += 18;
        if (result.size.height < IMAGE_WIDTH + 1) result.size.height = IMAGE_WIDTH + 1;
    }
    message.cellHeight = result.size.height;
}

+ (Message*)initWithDB:(sqlite3_stmt*)statement type:(MessageType)type
{
    // sqlite3 statement should be:
    //  SELECT * FROM messsages
    //
    Message *m              = [[[Message alloc] init] autorelease];
    m.user                  = [[User alloc] init];
    
    m.messageId             = (sqlite_int64)sqlite3_column_int64(statement, 0);
    m.text                  = [NSString stringWithUTF8String:(char*)sqlite3_column_text(statement, 2)];
    m.createdAt             = (time_t)sqlite3_column_int(statement, 3);
    m.source                = [NSString stringWithUTF8String:(char*)sqlite3_column_text(statement, 4)];
    m.favorited             = (BOOL)sqlite3_column_int(statement, 5);
    
    m.user.userId           = (uint32_t)sqlite3_column_int(statement, 6);
    m.user.name             = [NSString stringWithUTF8String:(char*)sqlite3_column_text(statement, 7)];
    m.user.screenName       = [NSString stringWithUTF8String:(char*)sqlite3_column_text(statement, 8)];
    m.user.location         = [NSString stringWithUTF8String:(char*)sqlite3_column_text(statement, 9)];
    m.user.description      = [NSString stringWithUTF8String:(char*)sqlite3_column_text(statement, 10)];
    m.user.url              = [NSString stringWithUTF8String:(char*)sqlite3_column_text(statement, 11)];
    m.user.followersCount   = (uint32_t)sqlite3_column_int(statement, 12);
    m.user.profileImageUrl  = [NSString stringWithUTF8String:(char*)sqlite3_column_text(statement, 13)];
    m.user.protected        = (uint32_t)sqlite3_column_int(statement, 14) ? true : false;
    m.textHeight            = (uint32_t)sqlite3_column_int(statement, 15);
    m.unread                = false;
    [m updateAttribute];
    
    return m;
}

+ (BOOL)isExist:(sqlite_int64)aMessageId type:(MessageType)aType
{
    // return always false if the message is for user timeline
    if (aType == MSG_TYPE_USER) return false;

    sqlite3* database = [DBConnection getSharedDatabase];
    
    if (select_statement== nil) {
        static char *sql = "SELECT id FROM messages WHERE id=? and type=?";
        if (sqlite3_prepare_v2(database, sql, -1, &select_statement, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(database));
        }
    }
    
    sqlite3_bind_int64(select_statement, 1, aMessageId);
    sqlite3_bind_int(select_statement, 2, aType);
    BOOL result = (sqlite3_step(select_statement) == SQLITE_ROW) ? true : false;
    sqlite3_reset(select_statement);
    return result;
}

- (void)insertDB
{
#if 0
    if ([Message isExist:messageId type:type]) {
        return;
    }
#endif
    sqlite3* database = [DBConnection getSharedDatabase];

    if (insert_statement == nil) {
        static char *sql = "INSERT INTO messages VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        if (sqlite3_prepare_v2(database, sql, -1, &insert_statement, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(database));
        }
    }
    sqlite3_bind_int64(insert_statement, 1, messageId);
    sqlite3_bind_int(insert_statement,   2, type);

    sqlite3_bind_text(insert_statement,  3, [text UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(insert_statement,   4, createdAt);
    sqlite3_bind_text(insert_statement,  5, [source UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(insert_statement,   6, favorited);
    
    sqlite3_bind_int(insert_statement,   7, user.userId);
    sqlite3_bind_text(insert_statement,  8, [user.name UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(insert_statement,  9, [user.screenName UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(insert_statement, 10, [user.location UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(insert_statement, 11, [user.description UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(insert_statement, 12, [user.url UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(insert_statement,  13, user.followersCount);
    sqlite3_bind_text(insert_statement, 14, [user.profileImageUrl UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(insert_statement,  15, user.protected);
    sqlite3_bind_int(insert_statement,  16, (uint32_t)textHeight);
    
    int success = sqlite3_step(insert_statement);
    // Because we want to reuse the statement, we "reset" it instead of "finalizing" it.
    sqlite3_reset(insert_statement);
    if (success == SQLITE_ERROR) {
        NSAssert1(0, @"Error: failed to insert into the database with message '%s'.", sqlite3_errmsg(database));
    }

}

@end
