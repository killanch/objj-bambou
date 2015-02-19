/*
*   Filename:         NURESTPushCenter.j
*   Created:          Tue Oct  9 11:52:21 PDT 2012
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
@import "NURESTLoginController.j"

@global CPApp
@global _format_log_json;

NURESTPushCenterPushReceived      = @"NURESTPushCenterPushReceived";
NURESTPushCenterServerUnreachable = @"NURESTPushCenterServerUnreachable";

NUPushEventTypeCreate = @"CREATE";
NUPushEventTypeUpdate = @"UPDATE";
NUPushEventTypeDelete = @"DELETE";
NUPushEventTypeRevoke = @"REVOKE";
NUPushEventTypeGrant  = @"GRANT";

var NURESTPushCenterDefault;

_DEBUG_NUMBER_OF_RECEIVED_EVENTS_ = 0;
_DEBUG_NUMBER_OF_RECEIVED_PUSH_SESSION_ = 0;


/*! This is the default push center
    Use it by calling [NURESTPushCenter defaultCenter];
*/
@implementation NURESTPushCenter : CPObject
{
    BOOL                _isRunning;
    NURESTConnection    _currentConnection;
}


#pragma mark -
#pragma mark Class methods

/*! Returns the defaultCenter. Initialize it if needed
    @returns default NURESTPushCenter
*/
+ (NURESTPushCenter)defaultCenter
{
    if (!NURESTPushCenterDefault)
        NURESTPushCenterDefault = [[NURESTPushCenter alloc] init];

    return NURESTPushCenterDefault;
}


#pragma mark -
#pragma mark Push Center Controls

/*! Start to listen for push notification
*/
- (void)start
{
    if (_isRunning)
        return;

     _isRunning = YES;

     [self _listenToNextEvent:nil];
}

/*! Stops listening for push notification
*/
- (void)stop
{
    if (!_isRunning)
        return;

     _isRunning = NO;

     if (_currentConnection)
         [_currentConnection cancel];
}


#pragma mark -
#pragma mark Privates

/*! @ignore
    manage the connection
*/
- (void)_listenToNextEvent:(CPString)anUUID
{
    var URL = [[NURESTLoginController defaultController] URL];

    if (!URL)
        [CPException raise:CPInternalInconsistencyException reason:@"NURESTPushCenter needs to have a valid URL set in the default NURESTLoginController"];

    var eventURL =  anUUID ? @"events?uuid=" + anUUID : @"events",
        request = [CPURLRequest requestWithURL:[CPURL URLWithString:eventURL relativeToURL:URL]];

    _currentConnection = [NURESTConnection connectionWithRequest:request target:self selector:@selector(_didReceiveEvent:)];
    [_currentConnection setTimeout:0];
    [_currentConnection setIgnoreRequestIdle:YES];
    [_currentConnection start];
}

/*! @ignore
    manage the connection response
*/
- (void)_didReceiveEvent:(NURESTConnection)aConnection
{
    if (!_isRunning)
        return;

    var JSONObject = [[aConnection responseData] JSONObject];

    if ([aConnection responseCode] !== 200)
    {
        CPLog.error("RESTCAPPUCCINO PUSHCENTER: Connection failure URL %s. Error Code: %s, (%s) ", [[NURESTLoginController defaultController] URL], [aConnection responseCode], [aConnection errorMessage]);

        [[CPNotificationCenter defaultCenter] postNotificationName:NURESTPushCenterServerUnreachable
                                                            object:self
                                                          userInfo:nil];

        return;
    }

    if (JSONObject)
    {
        var numberOfIndividualEvents = JSONObject.events.length;

        _DEBUG_NUMBER_OF_RECEIVED_EVENTS_ += numberOfIndividualEvents;
        _DEBUG_NUMBER_OF_RECEIVED_PUSH_SESSION_++;

        CPLog.debug("RESTCAPPUCCINO PUSHCENTER:\n\nReceived Push #%d (total: %d, latest: %d):\n\n%@\n\n",
                        _DEBUG_NUMBER_OF_RECEIVED_PUSH_SESSION_, _DEBUG_NUMBER_OF_RECEIVED_EVENTS_,
                        numberOfIndividualEvents, _format_log_json([[aConnection responseData] rawString]));

        [[CPNotificationCenter defaultCenter] postNotificationName:NURESTPushCenterPushReceived object:self userInfo:JSONObject];
    }

    _currentConnection = nil;

    if (_isRunning)
        [self _listenToNextEvent:JSONObject ? JSONObject.uuid : nil];
}

@end
