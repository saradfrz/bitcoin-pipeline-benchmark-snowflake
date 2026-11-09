DECLARE
    scope OBJECT;
    summary_hi DATE;
    payload VARCHAR;
BEGIN
    CALL BTC_TRADING.ORCHESTRATION.DQ_LANDING_SCOPE() INTO :scope;
    summary_hi := GET(scope, 'hi')::DATE;
    payload := TO_JSON(OBJECT_INSERT(scope, 'summary_hi', TO_CHAR(summary_hi, 'YYYY-MM-DD')));
    CALL SYSTEM$SET_RETURN_VALUE(:payload);
END;

