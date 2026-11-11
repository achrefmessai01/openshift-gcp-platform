*** Settings ***
Documentation     Platform-level acceptance (RP-xxx): OpenShift Route behaviour, TLS and
...               API server reachability. Only meaningful against a real cluster; every test
...               skips itself when the related variable is not provided.
...
...               robot --variable ROUTE_HOST:subscriber-api-dev.apps.ocp.example.com
...               ...   --variable API_URL:https://api.ocp.example.com:6443 tests/robot/platform.robot
Library           RequestsLibrary
Library           libraries/TlsChecks.py
Test Tags         platform


*** Variables ***
${ROUTE_HOST}     ${EMPTY}
${API_URL}        ${EMPTY}
${MIN_CERT_DAYS}  ${14}


*** Test Cases ***
RP-001 Plain HTTP on the Route is redirected to HTTPS
    Skip If    '${ROUTE_HOST}' == ''    ROUTE_HOST not set
    ${resp}=    GET    http://${ROUTE_HOST}/healthz    allow_redirects=${False}    expected_status=any
    Should Be True    ${resp.status_code} in (301, 302, 308)
    Should Start With    ${resp.headers}[Location]    https://${ROUTE_HOST}

RP-002 HTTPS responses carry an HSTS header
    Skip If    '${ROUTE_HOST}' == ''    ROUTE_HOST not set
    ${resp}=    GET    https://${ROUTE_HOST}/healthz
    Should Contain    ${resp.headers}[Strict-Transport-Security]    max-age=

RP-003 Route certificate is valid for more than ${MIN_CERT_DAYS} days
    Skip If    '${ROUTE_HOST}' == ''    ROUTE_HOST not set
    ${days}=    Days Until Certificate Expiry    ${ROUTE_HOST}
    Should Be True    ${days} > ${MIN_CERT_DAYS}    certificate expires in ${days} days

RP-004 Route serves the application over HTTPS
    Skip If    '${ROUTE_HOST}' == ''    ROUTE_HOST not set
    ${resp}=    GET    https://${ROUTE_HOST}/api/v1/info
    Should Be Equal    ${resp.json()}[service]    subscriber-api

RP-010 OpenShift API server is reachable and healthy
    Skip If    '${API_URL}' == ''    API_URL not set
    ${resp}=    GET    ${API_URL}/healthz    verify=${False}
    Should Be Equal    ${resp.text}    ok

RP-011 OpenShift API server rejects anonymous access to cluster resources
    Skip If    '${API_URL}' == ''    API_URL not set
    GET    ${API_URL}/api/v1/namespaces    verify=${False}    expected_status=403
