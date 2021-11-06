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
(IN floor_input INT, IN room_input INT, IN rname_input TEXT, IN roomCapacity_input INT, IN employeeID INT)
AS $$
DECLARE employeeManagerQuery INT;
DECLARE isEmployeeResigned BOOLEAN;
DECLARE room_did INT;
BEGIN
    room_did := (
        SELECT did
        FROM worksIn
        WHERE worksIn.eid = employeeID
    );

    -- Checks if employee is a manager
    employeeManagerQuery := (
        SELECT COUNT(*)
        FROM Manager 
        WHERE (managerID = employeeID)
    );
    -- Checks if employee is resigned
    isEmployeeResigned := (
        SELECT isResigned
        FROM Employees
        WHERE Employees.eid = employeeID
    );

    IF employeeManagerQuery <> 1
        THEN RAISE WARNING 'Employee is not authorized to add a new room.';
        RETURN;
    ELSIF isEmployeeResigned = TRUE
        THEN RAISE WARNING 'Employee has resigned, is not able to make a booking.';
        RETURN;
    END IF;

    INSERT INTO meetingRooms VALUES (room_input, floor_input, rname_input);
    INSERT INTO locatedIn VALUES (room_input, floor_input, room_did);
    -- Insert room capacity in Updates with the date the room was added 
    INSERT INTO Updates VALUES (employeeID, CURRENT_DATE, roomCapacity_input, room_input, floor_input);
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
DECLARE isEmployeeResigned BOOLEAN;
DECLARE doesEmployeeHaveFever BOOLEAN;
DECLARE employeeBookerQuery INTEGER;
DECLARE sessionsInserted INTEGER;
DECLARE numClashingBookings INTEGER;
BEGIN
    doesEmployeeHaveFever := (
        SELECT fever
        FROM healthDeclaration
        WHERE healthDeclaration.eid = employeeID
        ORDER BY date DESC
        LIMIT 1
    );

    employeeBookerQuery := (
        SELECT COUNT(*)
        FROM Booker 
        WHERE (bookerID = employeeID)
    );

    isEmployeeResigned := (
        SELECT isResigned
        FROM Employees
        WHERE Employees.eid = employeeID
    );

    IF doesEmployeeHaveFever = TRUE
        THEN RAISE EXCEPTION 'Employee has fever, not allowed to perform a booking.';
        RETURN;
    ELSIF employeeBookerQuery <> 1
        THEN RAISE EXCEPTION 'Employee type is not authorized to perform a booking.';
        RETURN;
    ELSIF isEmployeeResigned = TRUE
        THEN RAISE EXCEPTION 'Employee has resigned, is not able to make a booking.';
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
        INSERT INTO Sessions VALUES (roomNumber, floorNumber, requestedDate, startHourTracker);
        GET DIAGNOSTICS sessionsInserted := ROW_COUNT;

        IF sessionsInserted = 1
            THEN INSERT INTO Books VALUES (employeeID, roomNumber, floorNumber, requestedDate, startHourTracker, 0);
        ELSIF sessionsInserted = 0
            -- need to check if there is clashing Booking
            THEN IF numClashingBookings = 0 THEN
            INSERT INTO Books VALUES (employeeID, roomNumber, floorNumber, requestedDate, startHourTracker, 0);
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
$$ LANGUAGE plpgsql;


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


CREATE OR REPLACE FUNCTION contact_tracing
(IN eid_input INTEGER, IN date_input DATE)
RETURNS TABLE (employeeID INT) AS $$
DECLARE startDate DATE := date_input - 3;
DECLARE endDate DATE := date_input - 1;
BEGIN
    -- Meetings with close contacts in past 3 days
    CREATE TEMP TABLE meetingCloseContacts ON COMMIT DROP AS (
        SELECT room, floor, date, time
        FROM Joins
        WHERE date >= startDate AND date <= endDate AND eid_input = eid
    );
    -- Approved meetings with close contacts in past 3 days
    CREATE TEMP TABLE approvedMeetingCloseContacts ON COMMIT DROP AS (
        SELECT meetingCloseContacts.room, meetingCloseContacts.floor, meetingCloseContacts.date, meetingCloseContacts.time
        FROM meetingCloseContacts JOIN Approves
        ON meetingCloseContacts.room = Approves.room AND
        meetingCloseContacts.floor = Approves.floor AND
        meetingCloseContacts.date = Approves.date AND
        meetingCloseContacts.time = Approves.time 
    );
    -- Return list of employees in close contact with employee with fever in past 3 days
    RETURN QUERY 
    SELECT DISTINCT eid
    FROM Joins JOIN approvedMeetingCloseContacts
    ON Joins.room = approvedMeetingCloseContacts.room AND 
    Joins.floor = approvedMeetingCloseContacts.floor AND
    Joins.date = approvedMeetingCloseContacts.date AND
    Joins.time = approvedMeetingCloseContacts.time
    WHERE eid <> eid_input;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE approve_meeting
(IN floor_number INTEGER, IN room_number INTEGER, IN bookingDate DATE, IN startHour INTEGER, IN endHour INTEGER, IN employeeID INTEGER)
AS $$
DECLARE isEmployeeResigned BOOLEAN;
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

    isEmployeeResigned := (
        SELECT isResigned
        FROM Employees
        WHERE Employees.eid = employeeID
    );

    IF employeeManagerQuery <> 1
        THEN RAISE EXCEPTION 'Employee is not authorized to make an Approval.';
        RETURN;
    ELSIF employeeDepartmentQuery = 0
        THEN RAISE EXCEPTION 'Manager does not belong to same department as Meeting Room.';
        RETURN;
    ELSIF isEmployeeResigned = TRUE
        THEN RAISE EXCEPTION 'Manager has resigned, is not able to approve a Booking.';
        RETURN;
    END IF;

    WHILE startHourTracker < endHour LOOP
        INSERT INTO Approves VALUES (employeeID, room_number, floor_number, bookingDate, startHourTracker);
        startHourTracker := startHourTracker + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION search_room
(IN capacity INT, IN requestedDate DATE, IN startHour INT, IN endHour INT)
RETURNS TABLE(floor INT, room INT, departmentID INT, room_capacity INT, availableTime INT)
AS $$
BEGIN
    CREATE TEMP TABLE searchDate(date DATE);
    INSERT INTO searchDate VALUES(requestedDate);
    CREATE TEMP TABLE timeslots(time INT);
    INSERT INTO timeslots VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12),
                                (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24);
    CREATE TEMP TABLE allSlots ON COMMIT DROP AS(
        SELECT meetingRooms.room, meetingRooms.floor, searchDate.date, timeslots.time
        FROM meetingRooms, searchDate, timeslots
    );
    CREATE TEMP TABLE bookedSlots ON COMMIT DROP AS(
        SELECT Books.room, Books.floor, Books.date, Books.time
        FROM Books
        WHERE Books.date = requestedDate
        AND Books.time >= startHour
        AND Books.time < endHour
    );
    CREATE TEMP TABLE availableSlots ON COMMIT DROP AS(
        SELECT * FROM allSlots
        WHERE allSlots.time >= startHour
        AND allSlots.time < endHour
        EXCEPT
        SELECT * FROM bookedSlots
    );
    CREATE TEMP TABLE latestCapacityUpdate ON COMMIT DROP AS(
        SELECT Updates.room, Updates.floor, MAX(Updates.date) AS date
        FROM Updates
        WHERE requestedDate >= Updates.date
        GROUP BY Updates.room, Updates.floor
    );
    CREATE TEMP TABLE correctLatestCapacity ON COMMIT DROP AS(
        SELECT Updates.room, Updates.floor, Updates.date, Updates.newCap
        FROM Updates, latestCapacityUpdate
        WHERE Updates.room = latestCapacityUpdate.room
        AND Updates.floor = latestCapacityUpdate.floor
        AND Updates.date = latestCapacityUpdate.date
    );

    RETURN QUERY
    SELECT correctLatestCapacity.floor, correctLatestCapacity.room, locatedIn.did, correctLatestCapacity.newCap AS room_capacity, availableSlots.time
    FROM availableSlots, locatedIn, correctLatestCapacity
    WHERE availableSlots.room = locatedIn.room
    AND availableSlots.floor = locatedIn.floor
    AND availableSlots.room = correctLatestCapacity.room
    AND availableSlots.floor = correctLatestCapacity.floor
    AND correctLatestCapacity.newCap <= capacity
    ORDER BY correctLatestCapacity.newCap ASC, correctLatestCapacity.floor ASC, correctLatestCapacity.room ASC, availableSlots.time ASC
    ;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_manager_report
(IN startDate DATE, IN employeeID INT)
RETURNS TABLE(floor INT, room INT, date DATE, startHour INT, bookerID int)
AS $$
DECLARE employeeManagerQuery INT;
DECLARE employeeDepartmentQuery INT;
BEGIN
    employeeManagerQuery := (
        SELECT COUNT(*) FROM Manager WHERE managerID = employeeID
    );

    IF employeeManagerQuery <> 1
        THEN RAISE EXCEPTION 'Employee is not authorized to make an Approval.';
        RETURN;
    END IF;

    RETURN QUERY
        SELECT Books.floor, Books.room, Books.date, Books.time, Books.bookerID 
        FROM Books, locatedIn, worksIn
        WHERE Books.approveStatus = 0
        AND Books.date >= startDate
        AND Books.room = locatedIn.room
        AND Books.floor = locatedIn.floor
        AND locatedIn.did = worksIn.did
        AND worksIn.eid = employeeID
        ORDER BY Books.date ASC, Books.time ASC
    ;
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
        AND Approves.date >= startDate
        ORDER BY Approves.date ASC, Approves.time ASC
    ;   
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE change_capacity
(IN floor_number INT, IN room_number INT, IN new_capacity INT, IN date DATE, IN employeeID INT)
AS $$
DECLARE employeeManagerQuery INT;
DECLARE employeeDepartmentQuery INT;
DECLARE isEmployeeResigned BOOLEAN;
BEGIN
    -- Checks if employee is a manager
    employeeManagerQuery := (
        SELECT COUNT(*)
        FROM Manager 
        WHERE (managerID = employeeID)
    );
    -- Checks if employee is from the correct department
    employeeDepartmentQuery := (
        SELECT COUNT(t1.did)
        FROM (SELECT did FROM locatedIn WHERE room = room_number AND floor = floor_number) AS t1
        JOIN (SELECT did FROM worksIn WHERE eid = employeeID) AS t2
        ON t1.did = t2.did
    );
    -- Checks if employee is resigned
    isEmployeeResigned := (
        SELECT isResigned
        FROM Employees
        WHERE Employees.eid = employeeID
    );

    IF employeeManagerQuery <> 1
        THEN RAISE EXCEPTION 'Employee is not authorized to make a change in room capacity.';
        RETURN;
    ELSIF employeeDepartmentQuery = 0
        THEN RAISE EXCEPTION 'Manager does not belong to same department as Meeting Room.';
        RETURN;
    ELSIF isEmployeeResigned = TRUE
        THEN RAISE EXCEPTION 'Manager has resigned, is not able to change room capacity.';
        RETURN;
    END IF;

    INSERT INTO Updates VALUES (employeeID, date, new_capacity, room_number, floor_number);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION non_compliance
(IN start_date DATE, IN end_date DATE)
RETURNS TABLE (employeeID BIGINT, numberOfDays BIGINT) AS $$
-- Number of days inclusive of start date and end date
DECLARE numberOfDays INT := (end_date - start_date) + 1;
DECLARE 
BEGIN
    -- List of employees and the number of days non-compliant
    RETURN QUERY 
    SELECT Employees.eid, (numberOfDays-COUNT(healthDeclaration.eid))
    FROM Employees LEFT JOIN healthDeclaration
    ON Employees.eid = healthDeclaration.eid
    WHERE (healthDeclaration.date >= start_date AND healthDeclaration.date <= end_date)
    GROUP BY Employees.eid
    ORDER BY (numberOfDays-COUNT(healthDeclaration.eid)) DESC;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_booking_report
(IN startDate DATE, IN employeeID INTEGER)
RETURNS TABLE (floorNumber INTEGER, roomNumber INTEGER, dateBooked DATE, startHour INTEGER, isApproved BOOLEAN) AS $$
BEGIN
    RETURN QUERY
    SELECT floor, room, date, time, CASE 
        WHEN approveStatus = 0 THEN FALSE
        WHEN approveStatus = 1 THEN FALSE
        WHEN approveStatus = 2 THEN TRUE
        END AS isApproved
    FROM Books
    WHERE Books.bookerID = employeeID AND Books.date >= startDate
    ORDER BY Books.date ASC, Books.time ASC;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE unbook_room
(IN floor_input INT, IN room_input INT, IN requestedDate DATE, IN startHour INT, IN endHour INT, IN employeeID INT)
AS $$
DECLARE startHourTracker INT := startHour;
DECLARE employeeBookerQuery INT;
BEGIN
    -- To make sure that condition to remove booking is met, e.g. employee making the booking, booking exist and booking status
    -- don't need to check if employee resigned as the booking will already been deleted and can't be found
    WHILE startHourTracker < endHour LOOP
        employeeBookerQuery :=(
            SELECT COUNT(*)
            FROM Books
            WHERE floor_input = Books.floor
            AND room_input = Books.room
            AND requestedDate = Books.date
            AND startHourTracker = Books.time
            AND employeeID = Books.bookerID
            AND Books.approveStatus = 0
        );
        -- Don't think need trigger or anything because Joins & Books table has ON DELETE CASCADE
        -- Therefore have to delete from Sessions table
        IF employeeBookerQuery = 1
            THEN DELETE FROM Sessions
            WHERE floor_input = Sessions.floor
            AND room_input = Sessions.room
            AND requestedDate = Sessions.date
            AND startHourTracker = Sessions.time;
        ELSE
            RAISE WARNING 'Employee not the booker or booking cannot be removed.';
        END IF;
        startHourTracker = startHourTracker  + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE join_meeting
(IN floor_input INT, IN room_input INT, IN requestedDate DATE, IN startHour INT, IN endHour INT, IN employeeID INT)
AS $$
DECLARE startHourTracker INT := startHour;
DECLARE employeeInMeetingQuery INT;
DECLARE isEmployeeResigned BOOLEAN;
DECLARE doesEmployeeHaveFever BOOLEAN;
BEGIN
    doesEmployeeHaveFever := (
        SELECT fever
        FROM healthDeclaration
        WHERE healthDeclaration.eid = employeeID
        ORDER BY date DESC
        LIMIT 1	
    );

    isEmployeeResigned := (
        SELECT isResigned
        FROM Employees
        WHERE Employees.eid  = employeeID
    );

    IF doesEmployeeHaveFever = TRUE
        THEN RAISE EXCEPTION 'Employee has fever, not allowed to join the meeting.';
        RETURN;
    ELSIF isEmployeeResigned = TRUE
        THEN RAISE EXCEPTION 'Employee has resigned, is not able join the meeting';
        RETURN;
    END IF;

    WHILE startHourTracker < endHour LOOP
        INSERT INTO Joins VALUES(employeeID, room_input, floor_input, requestedDate, startHourTracker);
        startHourTracker := startHourTracker + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE leave_meeting
(IN floor_input INT, IN room_input INT, IN requestedDate DATE, IN startHour INT, IN endHour INT, IN employeeID INT)
AS $$
DECLARE startHourTracker INT := startHour;
DECLARE isEmployeeBooker INT;
DECLARE isMeetingApproved INT;
DECLARE isEmployeeInMeeting INT;
BEGIN
    WHILE startHourTracker < endHour LOOP
        isEmployeeBooker := (
            SELECT COUNT(*)
            FROM Books
            WHERE Books.bookerID = employeeID
            AND Books.floor = floor_input
            AND Books.room = room_input
            AND Books.date = requestedDate
            AND Books.time = startHourTracker
        );
        isMeetingApproved := (
            SELECT COUNT(*)
            FROM Approves
            WHERE Approves.room = room_input
            AND Approves.floor = floor_input
            AND Approves.date = requestedDate
            AND Approves.time = startHourTracker
        );
        isEmployeeInMeeting := (
            SELECT COUNT(*)
            FROM Joins
            WHERE Joins.room = room_input
            AND Joins.floor = floor_input
            AND Joins.date = requestedDate
            AND Joins.time = startHourTracker
            AND Joins.eid = employeeID
        );
        -- Don't need check for resigned as it should have been removed already
        IF isEmployeeBooker <> 1 AND isMeetingApproved <> 1 AND isEmployeeInMeeting = 1
            THEN
                DELETE FROM Joins
                WHERE floor_input = Joins.floor
                AND room_input = Joins.room
                AND requestedDate = Joins.date
                AND startHourTracker = Joins.time
                AND employeeID = Joins.eid;
        ELSIF isEmployeeBooker = 1 AND isMeetingApproved <> 1
            -- Means employee leaving the meeting is booker, cancel the booking
            -- Hopefully deleting from Sessions cascade down to Joins & Books
            THEN
                DELETE FROM Sessions
                WHERE floor_input = Sessions.floor
                AND room_input = Sessions.room
                AND requestedDate = Sessions.date
                AND startHourTracker = Sessions.time;
        ELSE
            RAISE WARNING 'Employee unable to leave meeting or not in this meeting.';
        END IF;
        startHourTracker := startHourTracker + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
