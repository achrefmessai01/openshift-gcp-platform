*** Settings ***
Documentation     Functional acceptance of subscriber-api. Test ids (RT-xxx) match the
...               technical acceptance book in docs/acceptance.md. Run against a local
...               container or an OpenShift Route by setting BASE_URL (and API_KEY).
Resource          resources/api.resource
Suite Setup       Run Keywords    Open API Session    AND    Cleanup Test Subscribers
Suite Teardown    Cleanup Test Subscribers
Test Tags         subscriber-api


*** Variables ***
${MSISDN}         +21650123456
${MSISDN_2}       +21650123457


*** Test Cases ***
RT-001 Liveness endpoint answers 200
    [Tags]    smoke
    ${resp}=    GET On Session    api    /healthz
    Should Be Equal As Strings    ${resp.json()}[status]    ok

RT-002 Readiness endpoint answers 200
    [Tags]    smoke
    ${resp}=    GET On Session    api    /readyz
    Should Be Equal As Strings    ${resp.json()}[status]    ready

RT-003 Info endpoint identifies the service and its environment
    [Tags]    smoke
    ${resp}=    GET On Session    api    /api/v1/info
    ${info}=    Set Variable    ${resp.json()}
    Should Be Equal    ${info}[service]    subscriber-api
    Should Not Be Empty    ${info}[version]
    Should Not Be Empty    ${info}[hostname]
    IF    '${EXPECTED_ENV}' != ''
        Should Be Equal    ${info}[environment]    ${EXPECTED_ENV}
    END

RT-010 Creating a subscriber returns 201 and an ACTIVE record
    [Tags]    functional
    ${resp}=    Create Subscriber    ${MSISDN}    PREPAID_5GB
    Should Be Equal    ${resp.json()}[msisdn]    ${MSISDN}
    Should Be Equal    ${resp.json()}[plan]    PREPAID_5GB
    Should Be Equal    ${resp.json()}[status]    ACTIVE
    Should Not Be Empty    ${resp.json()}[created_at]

RT-011 Creating the same subscriber twice is rejected with 409
    [Tags]    functional
    ${resp}=    Create Subscriber    ${MSISDN}    PREPAID_5GB    expected_status=409
    Should Be Equal    ${resp.json()}[title]    subscriber already exists
    Should Be Equal As Integers    ${resp.json()}[status]    409

RT-012 A created subscriber can be read back
    [Tags]    functional
    ${resp}=    Get Subscriber    ${MSISDN}
    Should Be Equal    ${resp.json()}[plan]    PREPAID_5GB

RT-013 Listing supports filtering by status
    [Tags]    functional
    Create Subscriber    ${MSISDN_2}    POSTPAID_UNLIMITED
    Change Subscriber Status    ${MSISDN_2}    suspend
    ${all}=    GET On Session    api    /api/v1/subscribers
    Should Be True    ${all.json()}[total] >= 2
    ${suspended}=    GET On Session    api    /api/v1/subscribers    params=status=SUSPENDED
    ${msisdns}=    Evaluate    [s["msisdn"] for s in $suspended.json()["items"]]
    List Should Contain Value    ${msisdns}    ${MSISDN_2}
    List Should Not Contain Value    ${msisdns}    ${MSISDN}

RT-014 Suspending then re-activating updates the status and timestamp
    [Tags]    functional
    ${before}=    Get Subscriber    ${MSISDN}
    ${suspended}=    Change Subscriber Status    ${MSISDN}    suspend
    Should Be Equal    ${suspended.json()}[status]    SUSPENDED
    Should Not Be Equal    ${suspended.json()}[updated_at]    ${before.json()}[updated_at]
    ${active}=    Change Subscriber Status    ${MSISDN}    activate
    Should Be Equal    ${active.json()}[status]    ACTIVE

RT-015 Deleting a subscriber returns 204 and the record disappears
    [Tags]    functional
    Delete Subscriber    ${MSISDN}
    Get Subscriber    ${MSISDN}    expected_status=404
    Delete Subscriber    ${MSISDN}    expected_status=404

RT-020 Invalid MSISDN or plan is rejected with 422
    [Tags]    functional    security
    Create Subscriber    0021650123456    PREPAID_5GB    expected_status=422
    Create Subscriber    +21650123458    prepaid    expected_status=422

RT-021 Write operations without a valid API key are rejected with 401
    [Tags]    security
    Skip If    '${API_KEY}' == ''    API_KEY not set: the target runs without API-key protection
    ${body}=    Create Dictionary    msisdn=+21650123458    plan=PREPAID_5GB
    ${resp}=    POST On Session    api    /api/v1/subscribers    json=${body}    expected_status=401
    Should Be Equal    ${resp.headers}[WWW-Authenticate]    ApiKey
    ${wrong}=    Create Dictionary    X-API-Key=not-the-key
    POST On Session    api    /api/v1/subscribers    json=${body}    headers=${wrong}    expected_status=401

RT-030 Metrics endpoint exposes Prometheus counters for the API
    [Tags]    observability
    GET On Session    api    /healthz
    ${resp}=    GET On Session    api    /metrics
    Should Contain    ${resp.headers}[Content-Type]    text/plain
    Should Contain    ${resp.text}    http_requests_total{method="GET",route="/healthz",status="200"}
    Should Contain    ${resp.text}    http_request_duration_seconds_bucket
    Should Contain    ${resp.text}    subscriber_api_build_info

RT-031 Error responses use the problem format
    [Tags]    functional
    ${resp}=    Get Subscriber    +21699999999    expected_status=404
    Should Be Equal    ${resp.json()}[title]    subscriber not found
    Should Be Equal As Integers    ${resp.json()}[status]    404
