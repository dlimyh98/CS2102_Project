CREATE TRIGGER unique_email
AFTER INSERT ON Employees
FOR EACH STATEMENT EXECUTE FUNCTION gen_unique_email();

CREATE OR REPLACE FUNCTION gen_unique_email() RETURNS TRIGGER AS $$
BEGIN
    SELECT (LEFT(email,8) || '@workplace.com') FROM Employees AS new_email
    UPDATE Employees
    SET email = new_email
    WHERE eid = NEW.eid
END;
$$ LANGUAGE plpgsql;
