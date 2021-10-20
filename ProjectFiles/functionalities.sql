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


CREATE OR REPLACE PROCEDURE book_room
(IN floorNumber INT, IN roomNumber INT, IN requestedDate DATE, IN startHour INT, IN endHour INT, IN employeeID INT)
AS $$
DECLARE startHourTracker INT := startHour;
DECLARE doesEmployeeHaveFever BOOLEAN;
DECLARE employeeBookerQuery INTEGER;
DECLARE sessionsInserted INTEGER;
BEGIN
    doesEmployeeHaveFever := (
        SELECT fever
        FROM healthDeclaration
        WHERE (healthDeclaration.eid = employeeID)
    );

    employeeBookerQuery := (
        SELECT COUNT(*)
        FROM Booker 
        WHERE (bookerID = employeeID)
    );

    IF doesEmployeeHaveFever = TRUE
        THEN RAISE EXCEPTION 'Employee has fever, not allowed to perform a booking.';
        RETURN;

    ELSIF employeeBookerQuery <> 1
        THEN RAISE EXCEPTION 'Employee type is not authorized to perform a booking.';
        RETURN;
    END IF;

    WHILE startHourTracker < endHour LOOP
        INSERT INTO Sessions VALUES (roomNumber, floornumber, requestedDate, startHourTracker);
        GET DIAGNOSTICS sessionsInserted := ROW_COUNT;

        IF sessionsInserted = 1
            THEN INSERT INTO Books VALUES (employeeID, roomNumber, floorNumber, requestedDate, startHourTracker, 0);
                 INSERT INTO Joins VALUES (employeeID, roomNumber, floorNumber, requestedDate, startHourTracker);
        END IF;
        startHourTracker := startHourTracker + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
