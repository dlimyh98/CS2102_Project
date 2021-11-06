/* TRIGGERS START */


/**************************************** add_employee triggers ****************************************/
CREATE OR REPLACE FUNCTION gen_unique_email() RETURNS TRIGGER AS $$
DECLARE uuid_email UUID := (SELECT * FROM uuid_generate_v4());
BEGIN
    NEW.email := (SELECT left(TEXT(uuid_email), 8) || '@workplace.com');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER unique_email
BEFORE INSERT ON Employees
FOR EACH ROW EXECUTE FUNCTION gen_unique_email();

-------------------------------- ensure Employee has Department (inserted into WorksIn) --------------------------------
CREATE OR REPLACE FUNCTION check_Employee_has_Department_func() RETURNS TRIGGER AS $$
DECLARE numWorksIn INTEGER;
BEGIN
    numWorksIn := (
        SELECT COUNT(*)
        FROM worksIn
        WHERE worksIn.eid = NEW.eid
    );

    IF numWorksIn <> 1
        THEN RAISE EXCEPTION 'Employee does not belong to any Department';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Trigger fires together with check_Employee_ISA (order is indeterminate), but it's ok
CREATE CONSTRAINT TRIGGER check_Employee_has_Department
AFTER INSERT ON Employees
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_Employee_has_Department_func();

-------------------------------- ensure participation for Employees -> Junior/Booker (ISA COVERING) --------------------------------
CREATE OR REPLACE FUNCTION check_Employee_ISA_covering_func() RETURNS TRIGGER AS $$
    -- check that for the Employee just inserted, it will have a corresponding entry in Junior/Booker(Senior/Manager)
    -- cannot belong to BOTH at the same time (already handled by another Trigger)
DECLARE numJunior INTEGER;
DECLARE numBooker INTEGER;
BEGIN
    numJunior := (
        SELECT COUNT(*)
        FROM Junior
        WHERE Junior.juniorID = NEW.eid
    );

    numBooker := (
        SELECT COUNT(*)
        FROM Booker
        WHERE Booker.bookerID = NEW.eid
    );

    IF (numJunior = 0 AND numBooker = 0)
        THEN RAISE EXCEPTION 'Employee has been added, but it is not classified under Junior or Booker.';
        RETURN NULL;

    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER check_Employee_ISA_covering
AFTER INSERT ON Employees
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_Employee_ISA_covering_func();

-------------------------------- ensure participation for Booker -> Senior/Manager (ISA COVERING) --------------------------------
CREATE OR REPLACE FUNCTION check_Booker_ISA_covering_func() RETURNS TRIGGER AS $$
    -- check that for the Booker just inserted, it will have a corresponding entry in Senior/Manager
    -- cannot belong to BOTH at the same time (already handled by another Trigger)
DECLARE numSenior INTEGER;
DECLARE numManager INTEGER;
BEGIN
    numSenior := (
        SELECT COUNT(*)
        FROM Senior
        WHERE Senior.seniorID = NEW.bookerID
    );

    numManager := (
        SELECT COUNT(*)
        FROM Manager
        WHERE Manager.managerID = NEW.bookerID
    );

    IF (numSenior = 0 AND numManager = 0)
        THEN RAISE EXCEPTION 'Booker has been added, but it is not classified under Senior or Manager.';
        RETURN NULL;

    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER check_Booker_ISA_covering
AFTER INSERT ON Booker
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_Booker_ISA_covering_func();

------------------------------------- Employee cannot be in both Junior and Booker (ISA OVERLAP) -------------------------------------
CREATE OR REPLACE FUNCTION Junior_Booker_ISA_overlap_func() RETURNS TRIGGER AS $$
DECLARE numExistingJunior INTEGER;
DECLARE numExistingBooker INTEGER;
BEGIN
    IF TG_TABLE_NAME = 'booker'
        THEN numExistingJunior := (
            SELECT COUNT(*)
            FROM Junior
            WHERE Junior.juniorID = NEW.bookerID
        );
    ELSIF TG_TABLE_NAME = 'junior'
        THEN numExistingBooker := (
            SELECT COUNT(*)
            FROM Booker
            WHERE Booker.bookerID = NEW.juniorID
        );
    END IF;

    IF (TG_TABLE_NAME = 'booker' AND numExistingJunior <> 0)
        THEN RAISE EXCEPTION 'This employee is already a Junior, and thus not able to be a Booker.';
        RETURN NULL;
    ELSIF (TG_TABLE_NAME = 'junior' AND numExistingBooker <> 0)
        THEN RAISE EXCEPTION 'This employee is already a Booker, and thus not able to be a Junior.';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER insert_Junior_ISA_overlap_check
BEFORE INSERT ON Junior
FOR EACH ROW EXECUTE FUNCTION Junior_Booker_ISA_overlap_func();

CREATE TRIGGER insert_Booker_ISA_overlap_check
BEFORE INSERT ON Booker
FOR EACH ROW EXECUTE FUNCTION Junior_Booker_ISA_overlap_func();

------------------------------------- Employee cannot be in both Senior and Manager (ISA OVERLAP) -------------------------------------
CREATE OR REPLACE FUNCTION Senior_Manager_ISA_overlap_func() RETURNS TRIGGER AS $$
DECLARE numExistingSenior INTEGER;
DECLARE numExistingManager INTEGER;
BEGIN
    IF TG_TABLE_NAME = 'senior'
        THEN numExistingManager := (
            SELECT COUNT(*)
            FROM Manager
            WHERE Manager.managerID = NEW.seniorID
        );

    ELSIF TG_TABLE_NAME = 'manager'
        THEN numExistingSenior := (
            SELECT COUNT(*)
            FROM Senior
            WHERE Senior.seniorID = NEW.managerID
        );
END IF;

    IF (TG_TABLE_NAME = 'senior' AND numExistingManager <> 0)
        THEN RAISE EXCEPTION 'This employee is already classified as a Manager.';
        RETURN NULL;
    ELSIF (TG_TABLE_NAME = 'manager' AND numExistingSenior <> 0)
        THEN RAISE EXCEPTION 'This employee is already classified as a Senior';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER insert_Manager_ISA_overlap_check
BEFORE INSERT ON Manager
FOR EACH ROW EXECUTE FUNCTION Senior_Manager_ISA_overlap_func();

CREATE TRIGGER insert_Senior_ISA_overlap_check
BEFORE INSERT ON Senior
FOR EACH ROW EXECUTE FUNCTION Senior_Manager_ISA_overlap_func();

/**************************************** remove_employee triggers ****************************************/
CREATE OR REPLACE FUNCTION employee_resign_func() RETURNS TRIGGER AS $$
BEGIN
    -- Delete corresponding employee, numPax in Joins will decrease (but Meeting Room capacity not affected)
    DELETE FROM Joins
    WHERE eid = OLD.eid AND date > NEW.resignedDate;

    -- Find out all FUTURE Sessions that the Employee booked
    CREATE TEMP TABLE employeeBookedMeetings ON COMMIT DROP AS (
        SELECT room, floor, date, time
        FROM Books
        WHERE Books.bookerID = OLD.eid AND Books.date > NEW.resignedDate
    );  

    -- Find out all FUTURE Approvals that the Employee made
    CREATE TEMP TABLE approvedBookingsToReset ON COMMIT DROP AS (
        SELECT room, floor, date, time
        FROM Approves 
        WHERE managerID = OLD.eid AND date > NEW.resignedDate
    );  

    -- Removes all FUTURE Sessions that resignedEmployee made
    -- Removes all FUTURE Bookings that resignedEmployee made (cascaded down)
    -- Removes all Approvals that reference FUTURE Bookings that the resignedEmployee made (cascaded down)
    DELETE FROM Sessions
    USING employeeBookedMeetings
    WHERE Sessions.room = employeeBookedMeetings.room
    AND Sessions.floor = employeeBookedMeetings.floor
    AND Sessions.date = employeeBookedMeetings.date
    AND Sessions.time = employeeBookedMeetings.time;

    -- Delete all FUTURE Approvals done by resignedEmployee
    DELETE FROM Approves
    WHERE managerID = OLD.eid AND date > NEW.resignedDate;

    -- Whatever Bookings the resigned Employee approved, is now reset back to NOT APPROVED in Books table
    -- Update corresponding FUTURE approved Bookings to isApprove = 0 (pending), DO NOT DELETE BOOKINGS
    UPDATE Books
    SET approveStatus = 0
    FROM approvedBookingsToReset
    WHERE (
        Books.room = approvedBookingsToReset.room AND
        Books.floor = approvedBookingsToReset.floor AND
        Books.date = approvedBookingsToReset.date AND
        Books.time = approvedBookingsToReset.time
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER employee_resign
BEFORE UPDATE ON Employees
FOR EACH ROW EXECUTE FUNCTION employee_resign_func();

/**************************************** book_room triggers ****************************************/
CREATE OR REPLACE FUNCTION check_sessions_availability_func() RETURNS TRIGGER AS $$
DECLARE numPreExistingSessions INTEGER;
BEGIN
    numPreExistingSessions := (
        SELECT COUNT(*) AS preExistingSessions
        FROM Sessions
        WHERE(room = NEW.room AND floor = NEW.floor AND date = NEW.date AND time = NEW.time)
    );

    IF numPreExistingSessions <> 0 
        THEN RAISE NOTICE 'Session with this (room,floor,date,time) already exists, there MAY be a conflicting booking.';
        RETURN NULL;
    ELSE 
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_sessions_availability
BEFORE INSERT ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_sessions_availability_func();

--------------------------- Employee booking the room immediately joins booked meeting ---------------------------
CREATE OR REPLACE FUNCTION booker_joins_booked_room_func() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO Joins VALUES (NEW.bookerID, NEW.room, NEW.floor, NEW.date, NEW.time);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER booker_joins_booked_room 
AFTER INSERT ON Books
FOR EACH ROW EXECUTE FUNCTION booker_joins_booked_room_func();

--------------------------- ensure 'exactly one' participation from Sessions to Books ---------------------------
CREATE OR REPLACE FUNCTION check_Sessions_to_Books_func() RETURNS TRIGGER AS $$
DECLARE numBookings INTEGER;
BEGIN
    numBookings := (
        SELECT COUNT(*)
        FROM Books
        WHERE Books.room = NEW.room AND Books.floor = NEW.floor AND Books.date = NEW.date AND Books.time = NEW.time
    );

    IF numBookings <> 1
        THEN RAISE EXCEPTION 'There is no accompanying Books for this Sessions record';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER check_Sessions_to_Books
AFTER INSERT ON Sessions
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_Sessions_to_Books_func();

--------------------------- ensure 'at least one' participation from Sessions to Joins ---------------------------
CREATE OR REPLACE FUNCTION check_Sessions_to_Joins_func() RETURNS TRIGGER AS $$
DECLARE numJoins INTEGER;
BEGIN
    numJoins := (
        SELECT COUNT(*)
        FROM Joins
        WHERE Joins.room = NEW.room AND Joins.floor = NEW.floor AND Joins.date = NEW.date AND Joins.time = NEW.time
    );

    IF numJoins = 0
        THEN RAISE EXCEPTION 'This Session is not participating at least once in Joins';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Trigger fires together with check_Sessions_to_Books (order is indeterminate), but it's ok
CREATE CONSTRAINT TRIGGER check_Sessions_to_Joins
AFTER INSERT ON Sessions
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_Sessions_to_Joins_func();

/**************************************** approve_meeting triggers ****************************************/
CREATE OR REPLACE FUNCTION approve_bookings_func() RETURNS TRIGGER AS $$
DECLARE numOfCorrespondingBookings INTEGER;
BEGIN
    -- per 1hr block
    numOfCorrespondingBookings := (
        SELECT COUNT(*)
        FROM Books
        WHERE (room = NEW.room AND floor = NEW.floor AND date = NEW.date AND time = NEW.time)
    );

    -- checking if whatever the Manager approves really exists in Books
    IF numOfCorrespondingBookings = 0 THEN
        RAISE NOTICE 'Manager is trying to approve a Booking that doesnt exist for this hour, no approval made.';
        RETURN NULL;
    ELSE
        UPDATE Books
        SET approveStatus = 2
        WHERE room = NEW.room AND floor = NEW.floor AND date = NEW.date AND time = NEW.time;
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER approve_bookings
BEFORE INSERT ON Approves
FOR EACH ROW EXECUTE FUNCTION approve_bookings_func();

/**************************************** change_capacity triggers ****************************************/
CREATE OR REPLACE FUNCTION change_capacity_remove_bookings_func() RETURNS TRIGGER AS $$
BEGIN
    
    -- List of future meetings that have lower capacity and needed to be removed
    CREATE TEMP TABLE meetingsToBeRemoved ON COMMIT DROP AS (
        SELECT room, floor, date, time, COUNT(*)
        FROM Joins
        WHERE (room = NEW.room AND floor = NEW.floor AND date >= NEW.date)
        GROUP BY room, floor, date, time
        HAVING COUNT(*) > NEW.newCap
    );
    -- Delete future meetings that have lower capacity
    DELETE FROM Sessions
    USING meetingsToBeRemoved
    WHERE (
        Sessions.room = meetingsToBeRemoved.room AND
        Sessions.floor = meetingsToBeRemoved.floor AND 
        Sessions.date = meetingsToBeRemoved.date AND 
        Sessions.time = meetingsToBeRemoved.time
    );
    RETURN NEW;
    
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER change_capacity_remove_bookings
BEFORE INSERT ON Updates
FOR EACH ROW EXECUTE FUNCTION change_capacity_remove_bookings_func();

/*********************************** join_meeting triggers ********************************/
CREATE OR REPLACE FUNCTION join_meeting_availability_func() RETURNS TRIGGER AS $$
DECLARE employeeInMeetingQuery INT;
DECLARE isMeetingApproved INT;
DECLARE participantCount INT;
DECLARE capacityCount INT;
BEGIN
    employeeInMeetingQuery := (
            SELECT COUNT(*)
            FROM Joins
            WHERE Joins.eid = NEW.eid
            AND Joins.date = NEW.date
            AND Joins.time = NEW.time
        );
    isMeetingApproved := ( -- checks if meeting exists and if it is approved or not
            SELECT COUNT(*)
            FROM Books
            WHERE NEW.floor = Books.floor
            AND NEW.room = Books.room
            AND NEW.date = Books.date
            AND NEW.time = Books.time
            AND Books.approveStatus = 2
        );
    participantCount := (
            SELECT COUNT(*)
            FROM Joins
            WHERE Joins.floor = NEW.floor
            AND Joins.room = NEW.room
            AND Joins.date = NEW.date
            AND Joins.time = NEW.time
        );
    capacityCount :=  (
            SELECT newCap
            From Updates
            WHERE NEW.date >= Updates.date
            AND Updates.room = NEW.room
            AND Updates.floor = NEW.floor
            ORDER BY Updates.date DESC
            LIMIT 1
        );
    IF employeeInMeetingQuery <> 1 AND isMeetingApproved <> 1 AND participantCount < capacityCount
        THEN RETURN NEW;
    ELSE
        RAISE WARNING 'Employee is not allowed to join the meeting';
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER join_meeting_availability
BEFORE INSERT ON Joins
FOR EACH ROW EXECUTE FUNCTION join_meeting_availability_func();


/*************************************** declare_health triggers **************************************/
CREATE OR REPLACE FUNCTION declare_health_check_func() RETURNS TRIGGER AS $$
DECLARE startDate DATE := NEW.date;
DECLARE endDate DATE := NEW.date + 7;
BEGIN
    IF NEW.fever = FALSE 
        THEN RETURN NEW;
    END IF;
    -- Employees in close contact with employee with fever
    CREATE TEMP TABLE employeesToBeRemoved ON COMMIT DROP AS (
        SELECT * FROM contact_tracing(NEW.eid, NEW.date)
    );
    -- All future meetings booked by employee with fever
    CREATE TEMP TABLE bookedMeetingsToBeRemoved ON COMMIT DROP AS (
        SELECT room, floor, date, time
        FROM Books
        WHERE bookerID = NEW.eid AND date >= startDate
    );
    -- Meetings booked by close contact employees in the next 7 days
    CREATE TEMP TABLE closeContactBookedMeetingsToBeRemoved ON COMMIT DROP AS (
        SELECT room, floor, date, time
        FROM Books JOIN employeesToBeRemoved
        ON Books.bookerID = employeesToBeRemoved.employeeID
        WHERE Books.date >= startDate AND Books.date <= endDate
    );
    -- Deletes close contact employees from future meetings in the next 7 days
    DELETE FROM Joins
    WHERE eid IN (SELECT employeeID FROM employeesToBeRemoved) AND 
    date >= startDate AND 
    date <= endDate;
    -- Deletes employee with fever from all future meeting room bookings
    DELETE FROM Joins
    WHERE eid = NEW.eid AND date >= startDate;
    -- Deletes all meetings booked by close contact employees in the next 7 days
    DELETE FROM Sessions
    USING closeContactBookedMeetingsToBeRemoved
    WHERE (
        Sessions.room = closeContactBookedMeetingsToBeRemoved.room AND
        Sessions.floor = closeContactBookedMeetingsToBeRemoved.floor AND 
        Sessions.date = closeContactBookedMeetingsToBeRemoved.date AND 
        Sessions.time = closeContactBookedMeetingsToBeRemoved.time
    );
    -- Deletes all future meetings booked by employee with fever    
    DELETE FROM Sessions
    USING bookedMeetingsToBeRemoved
    WHERE  (
        Sessions.room = bookedMeetingsToBeRemoved.room AND
        Sessions.floor = bookedMeetingsToBeRemoved.floor AND 
        Sessions.date = bookedMeetingsToBeRemoved.date AND 
        Sessions.time = bookedMeetingsToBeRemoved.time
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER declare_health_check
BEFORE INSERT ON healthDeclaration
FOR EACH ROW EXECUTE FUNCTION declare_health_check_func();


/*************************************** add_room trigger **************************************/

------ ensure Meeting Room has exactly one Department (cannot INSERT into MeetingRooms without locatedIn) -----
CREATE OR REPLACE FUNCTION check_MeetingRoom_has_Department_func() RETURNS TRIGGER AS $$
DECLARE departmentQuery INTEGER;
BEGIN
    departmentQuery := (
        SELECT COUNT(*)
        FROM locatedIn
        WHERE locatedIn.room = NEW.room AND locatedIn.floor = NEW.floor
    );

    IF departmentQuery <> 1
        THEN RAISE EXCEPTION 'Meeting Room has no corresponding Department attached to it, not allowed to add.';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Trigger fires together with check_Employee_ISA (order is indeterminate), but it's ok
CREATE CONSTRAINT TRIGGER check_MeetingRoom_has_Department
AFTER INSERT ON MeetingRooms
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_MeetingRoom_has_Department_func();


------ ensure Meeting Room has at least one capacity (cannot INSERT into MeetingRooms without Updates) -----
CREATE OR REPLACE FUNCTION check_MeetingRoom_has_Capacity_func() RETURNS TRIGGER AS $$
DECLARE numCapacityRecords INTEGER;
BEGIN
    numCapacityRecords := (
        SELECT COUNT(*)
        FROM Updates
        WHERE Updates.room = NEW.room AND Updates.floor = NEW.floor
    );

    IF numCapacityRecords = 0
        THEN RAISE EXCEPTION 'Meeting Room has no capacity, not allowed to add.';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Trigger fires together with check_Employee_ISA (order is indeterminate), but it's ok
CREATE CONSTRAINT TRIGGER check_MeetingRoom_has_Capacity
AFTER INSERT ON meetingRooms
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_MeetingRoom_has_Capacity_func();


/* TRIGGER ENDS */


/* FUNCTIONS STARTS */


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
RETURNS TABLE (employeeID INT, numberOfDays BIGINT) AS $$
-- Number of days inclusive of start date and end date
DECLARE numberOfDays INT := (end_date - start_date) + 1;
BEGIN
    -- List of employees and the number of days non-compliant
    RETURN QUERY
    SELECT eid, (numberOfDays-COUNT(*))
    FROM healthDeclaration 
    WHERE (date >= start_date AND date <= end_date)
    GROUP BY eid
    HAVING (numberOfDays-COUNT(*)) > 0
    ORDER BY (numberOfDays-COUNT(*)) DESC;
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


/* FUNCTIONS END */