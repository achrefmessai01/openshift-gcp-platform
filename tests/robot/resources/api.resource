*** Settings ***
Documentation     Shared keywords for the subscriber-api acceptance suites.
Library           RequestsLibrary
Library           Collections


*** Variables ***
${BASE_URL}       http://localhost:8080
${API_KEY}        ${EMPTY}
${VERIFY_TLS}     ${True}
${EXPECTED_ENV}   ${EMPTY}
@{TEST_MSISDNS}   +21650123456    +21650123457    +21650123458


*** Keywords ***
Open API Session
    [Documentation]    Opens the HTTP session used by every test (BASE_URL may be the OpenShift Route).
    Create Session    api    ${BASE_URL}    verify=${VERIFY_TLS}    timeout=10

Auth Headers
    [Documentation]    Returns the headers for write operations; empty when the API runs without a key.
    ${headers}=    Create Dictionary    Content-Type=application/json
    IF    '${API_KEY}' != ''
        Set To Dictionary    ${headers}    X-API-Key=${API_KEY}
    END
    RETURN    ${headers}

Create Subscriber
    [Arguments]    ${msisdn}    ${plan}=PREPAID_5GB    ${expected_status}=201
    ${headers}=    Auth Headers
    ${body}=    Create Dictionary    msisdn=${msisdn}    plan=${plan}
    ${resp}=    POST On Session    api    /api/v1/subscribers    json=${body}    headers=${headers}
    ...    expected_status=${expected_status}
    RETURN    ${resp}

Get Subscriber
    [Arguments]    ${msisdn}    ${expected_status}=200
    ${resp}=    GET On Session    api    /api/v1/subscribers/${msisdn}    expected_status=${expected_status}
    RETURN    ${resp}

Change Subscriber Status
    [Arguments]    ${msisdn}    ${action}    ${expected_status}=200
    ${headers}=    Auth Headers
    ${resp}=    POST On Session    api    /api/v1/subscribers/${msisdn}/${action}    headers=${headers}
    ...    expected_status=${expected_status}
    RETURN    ${resp}

Delete Subscriber
    [Arguments]    ${msisdn}    ${expected_status}=204
    ${headers}=    Auth Headers
    ${resp}=    DELETE On Session    api    /api/v1/subscribers/${msisdn}    headers=${headers}
    ...    expected_status=${expected_status}
    RETURN    ${resp}

Delete Subscriber If Exists
    [Arguments]    ${msisdn}
    ${headers}=    Auth Headers
    DELETE On Session    api    /api/v1/subscribers/${msisdn}    headers=${headers}    expected_status=any

Cleanup Test Subscribers
    [Documentation]    Leaves the environment as it was found.
    FOR    ${msisdn}    IN    @{TEST_MSISDNS}
        Delete Subscriber If Exists    ${msisdn}
    END
