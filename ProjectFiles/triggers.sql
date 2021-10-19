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


CREATE OR REPLACE FUNCTION employee_resign_func() RETURNS TRIGGER AS $$
BEGIN
    -- Delete corresponding employee, numPax in Joins will decrease (but Meeting Room capacity not affected)
    DELETE FROM Joins
    WHERE eid = OLD.eid AND date > NEW.resignedDate;

    -- Delete corresponding booking requests made by Employee
    DELETE FROM Books
    WHERE bookerID = OLD.eid AND date > NEW.resignedDate;

    -- Delete corresponding Approve records done by Employee
    -- Update corresponding Bookings to isApprove=0, DO NOT DELETE BOOKINGS
    CREATE TEMP TABLE approvedBookingsToDelete ON COMMIT DROP AS (
        SELECT room, floor, date, time
        FROM Approves 
        WHERE managerID = OLD.eid AND date > NEW.resignedDate
    );

    DELETE FROM Approves
    WHERE managerID = OLD.eid AND date > NEW.resignedDate;

    UPDATE Books
    SET isApproved = FALSE
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
