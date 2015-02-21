#import <objc/runtime.h>
#import "BIInflatedViewContainer.h"
#import "NSError+BIErrors.h"
#import "BISourceReference.h"
#import "UIView+BIAttributes.h"

@interface BIIdCacheDelegatedFinder : NSObject
- (instancetype)initWithCache:(NSMapTable *)viewsCache;
@end

@interface BIInflatedViewContainer ()
@property(nonatomic, strong) UIView *root;
@property(nonatomic, strong) NSMapTable *byIdsCache;
@property(nonatomic, strong) NSMutableDictionary *sourceCache;
@end

@implementation BIInflatedViewContainer {
    BIIdCacheDelegatedFinder *_delegatedTarget;
}
+ (instancetype)container:(UIView *)root {
    return [[self alloc] initWithRoot:root];
}

- (instancetype)initWithRoot:(UIView *)view {
    self = [super init];
    if (self) {
        _byIdsCache = [NSMapTable strongToWeakObjectsMapTable];
        _sourceCache = NSMutableDictionary.new;
        self.root = view;
        _delegatedTarget = [[BIIdCacheDelegatedFinder alloc] initWithCache:_byIdsCache];
    }
    return self;
}

- (UIView *)findViewById:(NSString *)viewId {
    return [self findElementById:viewId];
}

- (id)findElementById:(NSString *)elementId {
    id element = [_byIdsCache objectForKey:elementId];
    return element;
}

- (BOOL)tryAddingElement:(id)element withId:(NSString *)id fromSource:(BISourceReference *)source error:(NSError **)error {
    NSObject *existing = [_byIdsCache objectForKey:id];
    if (existing == nil) {
        [_byIdsCache setObject:element forKey:id];
        _sourceCache[id] = source;
        NSLog(@"New cache entry for key %@ is %@", id, element);
        return true;
    } else {
        BISourceReference *existingElement = _sourceCache[id];
        NSError *duplicateIdError = [NSError bi_error:@"Duplicate id found"
                                               reason:[NSString stringWithFormat:@"An id '%@' is used at \n%@\n\nand at\n\n%@", id, existingElement.sourceDescription, source.sourceDescription]];
        NSLog(@"BILayoutError: %@", duplicateIdError);
        *error = duplicateIdError;
        return false;
    }
}

- (BOOL)tryAddingElementsFrom:(BIInflatedViewContainer *)container error:(NSError **)error {
    NSMapTable *otherIdsCache = container.byIdsCache;
    NSMutableDictionary *otherSourceCache = container.sourceCache;
    for (NSString *id in otherIdsCache.keyEnumerator) {
        NSObject *element = [otherIdsCache objectForKey:id];
        if (element != nil) {
            BISourceReference *sourceReference = otherSourceCache[id];
            if (![self tryAddingElement:element withId:id fromSource:sourceReference error:error]) {
                return NO;
            }
        }
    }
    return YES;
}


- (id)forwardingTargetForSelector:(SEL)aSelector {
    NSString *propertyName = NSStringFromSelector(aSelector);
    UIView *view = [self findElementById:propertyName];
    if (view != nil) {
        return _delegatedTarget;
    }
    return [super forwardingTargetForSelector:aSelector];
}

- (void)setSuperviewAsCurrent {
    UIView *parent = self.current.superview;
    NSLog(@"Moving to %@ from %@", parent, self.current);
    self.current = parent;
}

- (void)setCurrentAsSubview:(UIView *)view {
    NSAssert(view != nil, @"Subview (view) must not be nil");
    if (self.root == nil) {
        self.root = view;
    }
    UIView *parent = self.current;
    NSLog(@"Adding %@ as child of %@", view, parent);
    [parent addSubview:view];
    view.bi_isPartOfLayout = YES;
    self.current = view;
}

- (void)clearRootToAvoidMemoryLeaks {
    self.root = nil;
}
@end

@implementation BIIdCacheDelegatedFinder {
    __weak NSMapTable *_cache;
}
- (instancetype)initWithCache:(NSMapTable *)viewsCache {
    self = [super init];
    if (self) {
        _cache = viewsCache;
    }

    return self;
}

+ (BOOL)resolveInstanceMethod:(SEL)aSelector {
    NSString *elementId = NSStringFromSelector(aSelector);
    IMP impl = imp_implementationWithBlock((UIView *) ^(BIIdCacheDelegatedFinder *self) {
        return [self findElementById:elementId];
    });
    NSString *methodType = [NSString stringWithFormat:@"%s%s%s", @encode(id), @encode(id), @encode(SEL)];
    class_addMethod([self class], aSelector, impl, [methodType cStringUsingEncoding:NSASCIIStringEncoding]);
    return true;
}

- (UIView *)findElementById:(NSString *)id {
    UIView *element = [_cache objectForKey:id];
    if (element == nil) {
        [self doesNotRecognizeSelector:NSSelectorFromString(id)];
    }
    return element;
}
@end
