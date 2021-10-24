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
    CREATE TEMP TABLE meetingsToBeRemoved ON COMMIT DROP AS (
        SELECT room, floor, date, time, COUNT(*)
        FROM Joins
        WHERE (room = NEW.room AND floor = NEW.floor AND date >= NEW.date)
        GROUP BY room, floor, date, time
        HAVING COUNT(*) > NEW.newCap
    );

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
AFTER INSERT ON Updates
FOR EACH ROW EXECUTE FUNCTION change_capacity_remove_bookings_func();