#import "RecordsManagerFMDB.h"
#import "FMDB.h"
#import "Record.h"
#import "DBHelper.h"


typedef NS_ENUM(NSInteger, SynchronizationType) {
    Insert,
    Delete,
    Update
};


@interface RecordsManagerFMDB()

@property (nonatomic, strong) NSMutableArray *mutableRecords;
@property (nonatomic, strong) NSString *dbPath;

/* List of dictionaries containing a record and a type of synchronization (INSERT, DELETE or
   UPDATE). Might be accessed by multiple threads. Use @synchronized block to access the property */
@property (nonatomic, strong) NSMutableArray *unsynchronizedRecordsQueue;

@end


@implementation RecordsManagerFMDB

#pragma mark - Initialization

- (id)init
{
    NSLog(@"Please use -initWithDbPath: instead.");
    [self doesNotRecognizeSelector:_cmd];
    
    return nil;
}

- (instancetype)initWithDbPath:(NSString *)dbPath
{
    self = [super init];
    if (self != nil) {
        _dbPath = dbPath;        
        _unsynchronizedRecordsQueue = [[NSMutableArray alloc] init];
        
        // Create database if not exists
        FMDatabase *database;
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if ([fileManager fileExistsAtPath:dbPath]) {
            NSLog(@"Database is already created.");
        }
        else {
            NSLog(@"Database is not created yet. Creating...");
            database = [FMDatabase databaseWithPath:_dbPath];
            NSLog(@"Database has been created.");
        }
        
        // Create 'records' table if not exists
        [DBHelper createRecordsTableInDatabase:database];
    }
    return self;
}

#pragma mark - Management of records

- (void)registerRecord:(NSDictionary *)record {
    if ([record count] > 0) {
        [self.mutableRecords addObject:record];
        NSMutableDictionary *recordToBeSynchronized = [record mutableCopy];
        recordToBeSynchronized[kSyncType] = @(Insert);
        @synchronized(self.unsynchronizedRecordsQueue) {
            [self.unsynchronizedRecordsQueue addObject:recordToBeSynchronized];
        }
    }
}

- (void)deleteRecord:(NSDictionary *)record {
    [self.mutableRecords removeObject:record];
    NSMutableDictionary *recordToBeSynchronized = [record mutableCopy];
    recordToBeSynchronized[kSyncType] = @(Delete);
    @synchronized(self.unsynchronizedRecordsQueue) {
        [self.unsynchronizedRecordsQueue addObject:recordToBeSynchronized];
    }
}

- (void)modifyRecord:(NSDictionary *)recordToBeModified byRecord:(NSDictionary *)newRecord {
    NSInteger recordIndex = [self.mutableRecords indexOfObject:recordToBeModified];
    self.mutableRecords[recordIndex] = newRecord;
    NSMutableDictionary *recordToBeSynchronized = [newRecord mutableCopy];
    recordToBeSynchronized[kSyncType] = @(Update);
    @synchronized(self.unsynchronizedRecordsQueue) {
        [self.unsynchronizedRecordsQueue addObject:recordToBeSynchronized];
    }
}

- (NSMutableArray *)mutableRecords
{
    if (!_mutableRecords) {
        _mutableRecords = [DBHelper allRecordsFromDbWithPath:self.dbPath];
    }
    return _mutableRecords;
}

- (NSArray *)records
{
    return [self.mutableRecords copy];
}

#pragma mark - Synchronisation

- (BOOL)synchronize {
    
    NSLog(@"Synchronization...");
    
    FMDatabaseQueue *queue = [[FMDatabaseQueue alloc] initWithPath:self.dbPath];
    [queue inDatabase:^(FMDatabase *db) {
        @synchronized(self.unsynchronizedRecordsQueue) {
            [db beginTransaction];
            for (NSDictionary *record in self.unsynchronizedRecordsQueue) {
                SynchronizationType syncType = [(NSNumber *)record[kSyncType] integerValue];
                switch (syncType) {
                    case Insert:
                        [DBHelper insertRecord:record intoDB:db];
                        break;
                    case Update:
                        [DBHelper updateRecord:record intoDB:db];
                        break;
                    case Delete:
                        [DBHelper deleteRecord:record intoDB:db];
                        break;
                    default:
                        break;
                }
            }
            [db commit];
            [self.unsynchronizedRecordsQueue removeAllObjects];
        }
    }];
    
    NSLog(@"Synchronization... DONE");
    
    return YES;
}

@end
