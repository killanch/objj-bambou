/*
*   Filename:         NURESTPushCenter.j
*   Created:          Tue Oct  9 11:52:21 PDT 2012
*   Author:           Antoine Mercadal <antoine.mercadal@alcatel-lucent.com>
*   Description:      CNA Dashboard
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

NURESTPushCenterPushReceived        = @"NURESTPushCenterPushReceived";
NURESTPushCenterServerUnreachable   = @"NURESTPushCenterServerUnreachable";
NURESTPushCenterServerReachable     = @"NURESTPushCenterServerReachable";

NUPushEventTypeCreate = @"CREATE";
NUPushEventTypeUpdate = @"UPDATE";
NUPushEventTypeDelete = @"DELETE";
NUPushEventTypeRevoke = @"REVOKE";
NUPushEventTypeGrant  = @"GRANT";

var NURESTPushCenterDefault,
    NURESTPushCenterConnectionRetryDelay = 5000,
    NURESTPushCenterConnectionMaxTrials = 10;

_DEBUG_NUMBER_OF_RECEIVED_EVENTS_ = 0;

/*! This is the default push center
    Use it by calling [NURESTPushCenter defaultCenter];
*/
@implementation NURESTPushCenter : CPObject
{
    CPURL               _URL                    @accessors(property=URL);

    BOOL                _isRunning;
    BOOL                _isServerUnreachable;
    id                  _lastEventIDBeforeDisconnection;
    NURESTConnection    _currentConnexion;
    CPNumber            _currentConnectionTrialNumber;
}


#pragma mark -
#pragma mark Class methods

/*! Returns the defaultCenter. Initialize it if needed
    @returns default NURESTPushCenter
*/
+ (void)defaultCenter
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
    _isServerUnreachable = NO;
    _currentConnectionTrialNumber = 0;

     [self _listenToNextEvent:nil];
}

/*! Stops listening for push notification
*/
- (void)stop
{
    if (!_isRunning)
        return;

     _isRunning = NO;
     _currentConnectionTrialNumber = 0;
     if (_currentConnexion)
         [_currentConnexion cancel];
}


#pragma mark -
#pragma mark Server health check

/*! This start the life checking of the server.
    This is automtically sent if any connection problem
    occurs with event URL.
*/
- (void)_waitUntilServerIsBack
{
    if (!_isRunning)
        return;

    _isServerUnreachable = YES;
    [[CPNotificationCenter defaultCenter] postNotificationName:NURESTPushCenterServerUnreachable
                                                        object:self
                                                     userInfo:nil];

    var request = [CPURLRequest requestWithURL:[CPURL URLWithString:@"me" relativeToURL:_URL]];

    _currentConnectionTrialNumber++;
    _currentConnexion = [NURESTConnection connectionWithRequest:request target:self selector:@selector(_didReceiveAliveCheckResponse:)];
    [_currentConnexion setTimeout:0];
    [_currentConnexion start];
}

/*! @ignore
*/
- (void)_didReceiveAliveCheckResponse:(NURESTConnection)aConnection
{
    if (!_isRunning)
        return;

    switch ([aConnection responseCode])
    {
        case 200:
            _currentConnectionTrialNumber = 0;
            [self _listenToNextEvent:_lastEventIDBeforeDisconnection];
            _lastEventIDBeforeDisconnection = nil;
            _isServerUnreachable = NO;
            [[CPNotificationCenter defaultCenter] postNotificationName:NURESTPushCenterServerReachable
                                                                object:self
                                                             userInfo:nil];
            break;

        default:
            setTimeout(function(){
                if (_currentConnectionTrialNumber < NURESTPushCenterConnectionMaxTrials)
                {
                    CPLog.warn("PUSH CENTER: Trying to reconnect... (retry #%@ / %@)", _currentConnectionTrialNumber, NURESTPushCenterConnectionMaxTrials);
                    [self _waitUntilServerIsBack];
                }
                else
                {
                    CPLog.error("PUSH CENTER: Maximum number of retry reached. logging out");
                    [[CPApp delegate] logOut:nil];
                }
            }, NURESTPushCenterConnectionRetryDelay);
            break;
    }
}


#pragma mark -
#pragma mark Privates

/*! @ignore
    manage the connection
*/
- (void)_listenToNextEvent:(CPString)anUUID
{
    if (!_URL)
        [CPException raise:CPInternalInconsistencyException reason:@"NURESTPushCenter needs to have a valid URL. please use setURL: before starting it."];

    var eventURL =  anUUID ? @"events?uuid=" + anUUID : @"events",
        request = [CPURLRequest requestWithURL:[CPURL URLWithString:eventURL relativeToURL:_URL]];

    _currentConnexion = [NURESTConnection connectionWithRequest:request target:self selector:@selector(_didReceiveEvent:)];
    [_currentConnexion setTimeout:0];
    [_currentConnexion start];
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
        CPLog.error("PUSH CENTER: Connexion failure URL %s. Error Code: %s, (%s) ", _URL, [aConnection responseCode], [aConnection errorMessage]);
        CPLog.error("PUSH CENTER: Trying to reconnect in 5 seconds")

        _lastEventIDBeforeDisconnection = JSONObject ? JSONObject.uuid : nil;

        [self _waitUntilServerIsBack];

        return;
    }

    if (JSONObject)
    {
        var numberOfIndividualEvents = JSONObject.events.length;

        try
        {
            CPLog.debug(" >>> Received event from server: " + [[aConnection responseData] rawString]);
            _DEBUG_NUMBER_OF_RECEIVED_EVENTS_ += numberOfIndividualEvents;
            console.warn("_DEBUG_NUMBER_OF_RECEIVED_EVENTS_: " + _DEBUG_NUMBER_OF_RECEIVED_EVENTS_ + " - latest push contains " + numberOfIndividualEvents + " event(s)");

            [[CPNotificationCenter defaultCenter] postNotificationName:NURESTPushCenterPushReceived object:self userInfo:JSONObject];
        }
        catch (e)
        {
            CPLog.error("PUSH CENTER: An error occured while processing a push event: " + e);
        }
    }

    if (_isRunning)
        [self _listenToNextEvent:JSONObject ? JSONObject.uuid : nil];
}

@end
