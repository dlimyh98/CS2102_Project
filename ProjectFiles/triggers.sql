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