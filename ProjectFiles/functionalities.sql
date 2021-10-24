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
(IN did_input INT, IN dname_input TEXT)
AS $$
BEGIN
    INSERT INTO Departments VALUES (did_input, dname_input);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE add_room
(IN room_input INT, IN floor_input INT, IN rname_input TEXT, IN roomCapacity_input INT, IN did_input INT)
AS $$
BEGIN
    INSERT INTO meetingRooms VALUES (room_input, floor_input, rname_input);
    INSERT INTO locatedIn VALUES (room_input, floor_input, did_input);
    INSERT INTO Updates VALUES (CURRENT_DATE, roomCapacity_input, room_input, floor_input);
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
DECLARE numClashingBookings INTEGER;
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

        -- have to do for EACH 1hr block
        numClashingBookings := (
            SELECT COUNT(*)
            FROM Books
            WHERE (room = roomNumber AND floor = floorNumber AND date = requestedDate AND startHour = time AND approveStatus <> 1)
        );

        -- check Session availability first, it is easier
        INSERT INTO Sessions VALUES (roomNumber, floornumber, requestedDate, startHourTracker);
        GET DIAGNOSTICS sessionsInserted := ROW_COUNT;

        IF sessionsInserted = 1
            THEN INSERT INTO Books VALUES (employeeID, roomNumber, floorNumber, requestedDate, startHourTracker, 0);
            INSERT INTO Joins VALUES (employeeID, roomNumber, floorNumber, requestedDate, startHourTracker);

        ELSIF sessionsInserted = 0
            -- need to check if there is clashing Booking
            THEN IF numClashingBookings = 0 THEN
            INSERT INTO Books VALUES (employeeID, roomNumber, floorNumber, requestedDate, startHourTracker, 0);
            INSERT INTO Joins VALUES (employeeID, roomNumber, floorNumber, requestedDate, startHourTracker);
        ELSE
            RAISE NOTICE 'Clashing booking detected for THIS hour, no booking made.';
        END IF;
    END IF;
    startHourTracker := startHourTracker + 1;

END LOOP;
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


CREATE OR REPLACE PROCEDURE declare_health
(IN eid_input INTEGER, IN date_input DATE, IN temperature_input NUMERIC(3,1))
AS $$
DECLARE fever BOOLEAN := FALSE;
BEGIN
    -- Checks if employee has fever
    IF temperature_input > 37.5
        THEN fever = TRUE;
    END IF;
    
    INSERT INTO healthDeclaration VALUES (date_input, temperature_input, fever, eid_input);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE approve_meeting
(IN floor_number INTEGER, IN room_number INTEGER, IN bookingDate DATE, IN startHour INTEGER, IN endHour INTEGER, IN employeeID INTEGER)
AS $$
DECLARE employeeManagerQuery INTEGER;
DECLARE employeeDepartmentQuery INTEGER;
DECLARE startHourTracker INTEGER := startHour;
BEGIN
    employeeManagerQuery := (
        SELECT COUNT(*)
        FROM Manager 
        WHERE (managerID = employeeID)
    );

    employeeDepartmentQuery := (
        SELECT COUNT(t1.did)
        FROM (SELECT did FROM locatedIn WHERE room = room_number AND floor = floor_number) AS t1
        JOIN (SELECT did FROM worksIn WHERE eid = employeeID) AS t2
        ON t1.did = t2.did
    );

    IF employeeManagerQuery <> 1
        THEN RAISE EXCEPTION 'Employee is not authorized to make an Approval.';
        RETURN;
    ELSIF employeeDepartmentQuery = 0
        THEN RAISE EXCEPTION 'Manager does not belong to same department as Meeting Room.';
        RETURN;
    END IF;

    WHILE startHourTracker < endHour LOOP
        INSERT INTO Approves VALUES (employeeID, room_number, floor_number, bookingDate, startHourTracker);
        startHourTracker := startHourTracker + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_future_meeting
(IN startDate DATE, IN employeeID INT)
RETURNS TABLE(floorNumber INT, roomNumber INT, date DATE, startHour INT)
AS $$
BEGIN
    RETURN QUERY
        SELECT Approves.floor, Approves.room, Approves.date, Approves.time 
        FROM
        (SELECT * FROM Joins
        WHERE Joins.eid = employeeID) AS employeeInMeetings,
        Approves
        WHERE employeeInMeetings.room = Approves.room
        AND employeeInMeetings.floor = Approves.floor
        AND employeeInMeetings.date = Approves.date
        AND employeeInMeetings.time = Approves.time
        AND startDate > employeeInMeetings.date
        ORDER BY Approves.date ASC, Approves.time ASC
    ;   
END;
$$ LANGUAGE plpgsql;