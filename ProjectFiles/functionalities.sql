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

CREATE OR REPLACE PROCEDURE add_department
(IN did INT, IN dname TEXT)
AS $$

BEGIN
    INSERT INTO Departments VALUES (did, dname);
END;
    
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE add_room
(IN room INT, IN floor INT, IN rname TEXT, IN room_capacity INT, IN did INT)
AS $$

BEGIN
    INSERT INTO meetingRooms VALUES (room, floor, rname);
    INSERT INTO locatedIn VALUES (room, floor, did);
    INSERT INTO Updates VALUES (CURRENT_DATE, room_capacity, room, floor);
END;

$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE remove_employee
(IN eid_input INTEGER, IN resignedDate_input DATE)
AS $$
BEGIN
    -- Dont actually delete anything, simply change isResigned field to TRUE and record resignedDate
    UPDATE Employees
    SET resignedDate = resignedDate_input, isResigned = TRUE
    WHERE eid = eid_input;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE remove_department
(IN did_input INTEGER)
AS $$
BEGIN
    DELETE FROM Departments
    WHERE did = did_input;
END;
$$ LANGUAGE plpgsql
