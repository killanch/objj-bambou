/*
*   Filename:         NURESTFetcher.j
*   Created:          Tue Oct  9 11:49:36 PDT 2012
*   Author:           Antoine Mercadal <antoine.mercadal@alcatel-lucent.com>
*   Description:      VSA
*   Project:          Cloud Network Automation - Nuage - Data Center Service Delivery - IPD
*
* Copyright (c) 2011-2012 Alcatel, Alcatel-Lucent, Inc. All Rights Reserved.
*
* This source code contains confidential information which is proprietary to Alcatel.
* No part of its contents may be used, copied, disclosed or conveyed to any party
* in any manner whatsoever without prior written permission from Alcatel.
*
* Alcatel-Lucent is a trademark of Alcatel-Lucent, Inc.
*
*/

@import <Foundation/Foundation.j>
@import "NURESTConnection.j"

@global NURESTBasicUser
@global NURESTLoginController
@global NURESTConnectionMethodGet

@implementation NURESTFetcher : CPObject
{
    CPArray             _groupedBy              @accessors(property=groupedBy);
    CPNumber            _latestLoadedPage       @accessors(property=latestLoadedPage);
    CPNumber            _pageSize               @accessors(property=pageSize);
    CPNumber            _totalCount             @accessors(property=totalCount);
    CPString            _destinationKeyPath     @accessors(property=destinationKeyPath);
    CPString            _masterOrder            @accessors(property=masterOrder);
    CPString            _queryString            @accessors(property=queryString);
    CPString            _transactionID          @accessors(property=transactionID);
    id                  _entity                 @accessors(property=entity);
    NURESTConnection    _currentConnection      @accessors(property=currentConnection);

    CPString            _orderedBy;
}


#pragma mark -
#pragma mark Class Methods

+ (Class)managedObjectClass
{
    [CPException raise:CPInternalInconsistencyException reason:"NURESTFetcher subclasses must implement managedObjectClass"];
}

+ (CPString)managedObjectRESTName
{
    return [[self managedObjectClass] RESTName];
}

+ (NURESTFetcher)fetcherWithEntity:(NURESTObject)anEntity destinationKeyPath:(CPString)aDestinationKeyPath
{
    var fetcher = [[self class] new];
    [fetcher setEntity:anEntity];
    [fetcher setDestinationKeyPath:aDestinationKeyPath];

    [anEntity setValue:[] forKeyPath:aDestinationKeyPath];
    [anEntity registerChildrenList:[anEntity valueForKeyPath:aDestinationKeyPath] forRESTName:[self managedObjectRESTName]];

    return fetcher;
}


#pragma mark -
#pragma mark Initialization

- (void)flush
{
    _currentConnection = nil;
    [[_entity valueForKeyPath:_destinationKeyPath] removeAllObjects];
}

- (id)newManagedObject
{
    return [[[self class] managedObjectClass] new];
}


#pragma mark -
#pragma mark Utiltities

- (CPString)managedObjectClass
{
    return [[self class] managedObjectClass];
}

- (id)_RESTFilterFromFilter:(id)aFilter masterFilter:(id)aMasterFilter
{
    // if no filter is set, return nil
    if (!aFilter && !aMasterFilter)
        return nil;

    // if no user user is set  but we have a master filter, return the master filter
    if (!aFilter && aMasterFilter)
        return aMasterFilter;

    // if user filter is set, but no master filter, return the user filter as it is.
    if (aFilter && !aMasterFilter)
        return aFilter;

    if (aFilter && aMasterFilter)
    {
        // try to make a predicate from the given filter
        var userPredicate = [CPPredicate predicateWithFormat:aFilter];

        // if it didn't work, create full text search predicate
        if (!userPredicate)
            userPredicate = [[self newManagedObject] fullTextSearchPredicate:aFilter];

        return [[CPCompoundPredicate alloc] initWithType:CPAndPredicateType subpredicates:[aMasterFilter, userPredicate]];
    }

    // we should never reach here
    [CPException raise:CPInternalInconsistencyException reason:"NURESTFetcher cannot prepare filter"];
}


#pragma mark -
#pragma mark Request Management

- (void)_prepareHeadersForRequest:(CPURLRequest)aRequest withFilter:(id)aFilter masterFilter:(id)aMasterFilter page:(CPNumber)aPage
{
    var filter = [self _RESTFilterFromFilter:aFilter masterFilter:aMasterFilter];

    if (filter)
        [aRequest setValue:[filter isKindOfClass:CPPredicate] ? [filter predicateFormat] : filter forHTTPHeaderField:@"X-Nuage-Filter"];

    if (_masterOrder)
        [aRequest setValue:_masterOrder forHTTPHeaderField:@"X-Nuage-OrderBy"];

    if (aPage !== nil)
        [aRequest setValue:aPage forHTTPHeaderField:@"X-Nuage-Page"];

    if (_groupedBy)
    {
        var headerString = @"";
        for (var i = 0, c = [_groupedBy count]; i < c; i++)
        {
            headerString += _groupedBy[i];
            if (i + 1 < c)
                headerString += @", ";
        }

        [aRequest setValue:@"true" forHTTPHeaderField:@"X-Nuage-GroupBy"];
        [aRequest setValue:headerString forHTTPHeaderField:@"X-Nuage-Attributes"];
    }
}

- (CPURL)_prepareURL
{
    var url = [_entity RESTResourceURLForChildrenClass:[self managedObjectClass]];

    if (_queryString)
        url = [CPURL URLWithString:[url absoluteString] + "?" + _queryString];

    return url;
}

- (CPString)fetchObjectsAndCallSelector:(SEL)aSelector ofObject:(id)anObject
{
    return [self fetchObjectsMatchingFilter:nil masterFilter:nil page:nil andCallSelector:aSelector ofObject:anObject];
}

- (CPString)fetchObjectsMatchingFilter:(id)aFilter masterFilter:(id)aMasterFilter page:(CPNumber)aPage andCallSelector:(SEL)aSelector ofObject:(id)anObject
{
    var request = [CPURLRequest requestWithURL:[self _prepareURL]];
    [request setHTTPMethod:NURESTConnectionMethodGet];

    [self _prepareHeadersForRequest:request withFilter:aFilter masterFilter:aMasterFilter page:aPage];

    _transactionID = [CPString UUID];
    [_entity sendRESTCall:request performSelector:@selector(_didFetchObjects:) ofObject:self andPerformRemoteSelector:aSelector ofObject:anObject userInfo:nil];

    return _transactionID;
}

/*! @ignore
*/
- (void)_didFetchObjects:(NURESTConnection)aConnection
{
    _currentConnection = aConnection;

    if ([_currentConnection responseCode] != 200) // @TODO: server sends 200, but if there is an empty list we should have the empty code...
    {
        _totalCount = 0;
        _pageSize = 0;
        _latestLoadedPage = 0;
        _orderedBy = @"";
        [self _sendContent:nil usingConnection:_currentConnection];
        return;
    }

    var JSONObject = [[_currentConnection responseData] JSONObject],
        dest = [_entity valueForKey:_destinationKeyPath],
        newlyFetchedObjects = [CPArray array];

    _totalCount = parseInt([_currentConnection nativeRequest].getResponseHeader("X-Nuage-Count"));
    _pageSize = parseInt([_currentConnection nativeRequest].getResponseHeader("X-Nuage-PageSize"));
    _latestLoadedPage = parseInt([_currentConnection nativeRequest].getResponseHeader("X-Nuage-Page"));
    _orderedBy = [_currentConnection nativeRequest].getResponseHeader("X-Nuage-OrderBy");

    for (var i = 0, c = [JSONObject count]; i < c; i++)
    {
        var newObject = [self newManagedObject];

        [newObject objectFromJSON:JSONObject[i]];
        [newObject setParentObject:_entity];

        if (![dest containsObject:newObject])
            [dest addObject:newObject];

        [newlyFetchedObjects addObject:newObject];
    }

    // @TODO: wy sending a copy? I should be better to directly pass the dest. It should be working by now.
    // @EDIT: Actually, I'm not sure. This is used as datasource content, and removing stuff from datasource
    // will remove it from the RESTObject array, and that could cause some weird error. I need to deeply check
    // if it is safe or not to simply give the destination array... wait and see
    // @EDIT: I think the second message is right. using pagination will completely screw up things.
    [self _sendContent:newlyFetchedObjects usingConnection:_currentConnection];
}

- (CPString)countObjectsAndCallSelector:(SEL)aSelector ofObject:(id)anObject matchingFilter:(CPPredicate)aFilter
{
    var request = [CPURLRequest requestWithURL:[self _prepareURL]];
    [request setHTTPMethod:@"HEAD"];

    [self _prepareHeadersForRequest:request withFilter:aFilter masterFilter:nil page:nil];

    _transactionID = [CPString UUID];
    [_entity sendRESTCall:request performSelector:@selector(_didCountObjects:) ofObject:self andPerformRemoteSelector:aSelector ofObject:anObject userInfo:nil];

    return _transactionID;
}

- (void)_didCountObjects:(NURESTConnection)aConnection
{
    var count = parseInt([aConnection nativeRequest].getResponseHeader("X-Nuage-Count")),
        target = [aConnection internalUserInfo]["remoteTarget"],
        selector = [aConnection internalUserInfo]["remoteSelector"];

    // should be - (void)fetcher:ofObject:didCountContent: or something like that
    [target performSelector:selector withObjects:self, _entity, count];
}

- (void)_sendContent:(CPArray)someContent usingConnection:(NURESTConnection)aConnection
{
    if (aConnection)
    {
        var target = [aConnection internalUserInfo]["remoteTarget"],
            selector = [aConnection internalUserInfo]["remoteSelector"];

        // should be - (void)fetcher:ofObject:didCountContent: or something like that
        [target performSelector:selector withObjects:self, _entity, someContent];

        [_currentConnection reset];
        _currentConnection = nil;
    }
}

- (CPArray)latestSortDescriptors
{
    if (!_orderedBy)
        return;

    var descriptors = [CPArray array],
        elements = _orderedBy.split(",");

    for (var i = 0, c = [elements count]; i < c; i++)
    {
        var tokens = elements[i].split(" "),
            descriptor = [CPSortDescriptor sortDescriptorWithKey:tokens[0]
                                                       ascending:(tokens[1] == "ASC")
                                                        selector:@selector(caseInsensitiveCompare:)];

        [descriptors addObject:descriptor];
    }

    return descriptors;
}

- (void)countObjectsAndCallSelector:(SEL)aSelector ofObject:(id)anObject
{
    [self countObjectsAndCallSelector:aSelector ofObject:anObject matchingFilter:nil];
}

@end
