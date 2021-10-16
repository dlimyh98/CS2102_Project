CREATE OR REPLACE PROCEDURE add_employee
(IN e_name TEXT, IN e_type TEXT, IN e_did INTEGER, IN e_mobilePhoneContact NUMERIC(8), IN e_homePhoneContact NUMERIC(8) DEFAULT 00000000, IN e_officePhoneContact NUMERIC(8) DEFAULT 00000000)
AS $$
DECLARE new_employee_id INTEGER;

BEGIN
    INSERT INTO Employees (ename, mobilePhoneContact, homePhoneContact, officePhoneContact) VALUES (e_name, e_mobilePhoneContact, e_homePhoneContact, e_officePhoneContact)
        RETURNING eid INTO new_employee_id;

    CASE e_type
        WHEN 'Junior' THEN INSERT INTO Junior VALUES (new_employee_id);
        WHEN 'Senior' THEN INSERT INTO Booker VALUES (new_employee_id); INSERT INTO Senior VALUES (new_employee_id);
        WHEN 'Manager' THEN INSERT INTO Booker VALUES (new_employee_id); INSERT INTO Manager VALUES (new_employee_id);
    END CASE;

    INSERT INTO worksIn VALUES (new_employee_id, e_did);
END;
$$ LANGUAGE plpgsql;
