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

    -- Delete corresponding booking requests made by Employee
    DELETE FROM Books
    WHERE bookerID = OLD.eid AND date > NEW.resignedDate;

    -- Delete corresponding Approve records done by Employee
    -- Update corresponding Bookings to isApprove = 0 (pending), DO NOT DELETE BOOKINGS
    CREATE TEMP TABLE approvedBookingsToDelete ON COMMIT DROP AS (
        SELECT room, floor, date, time
        FROM Approves 
        WHERE managerID = OLD.eid AND date > NEW.resignedDate
    );

    DELETE FROM Approves
    WHERE managerID = OLD.eid AND date > NEW.resignedDate;

    UPDATE Books
    SET approveStatus = 0
    FROM approvedBookingsToDelete
    WHERE (
        Books.room = approvedBookingsToDelete.room AND
        Books.floor = approvedBookingsToDelete.floor AND
        Books.date = approvedBookingsToDelete.date AND
        Books.time = approvedBookingsToDelete.time
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
    WHERE CTID IN (SELECT Sessions.CTID
                    FROM Sessions JOIN meetingsToBeRemoved 
                    ON (Sessions.room = meetingsToBeRemoved.room AND
                        Sessions.floor = meetingsToBeRemoved.floor AND 
                        Sessions.date = meetingsToBeRemoved.date AND 
                        Sessions.time = meetingsToBeRemoved.time)
                    );
    RETURN NEW;
    
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER change_capacity_remove_bookings
BEFORE INSERT ON Updates
FOR EACH ROW EXECUTE FUNCTION change_capacity_remove_bookings_func();
