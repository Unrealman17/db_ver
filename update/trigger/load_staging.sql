DROP TRIGGER IF EXISTS load_staging ON reclada.staging;
CREATE TRIGGER load_staging
    AFTER INSERT ON reclada.staging
    REFERENCING NEW TABLE AS NEW_TABLE
    FOR EACH STATEMENT EXECUTE FUNCTION load_staging();