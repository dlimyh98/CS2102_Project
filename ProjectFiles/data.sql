-- DELETE FROM worksIn;
-- DELETE FROM Departments; Not needed if starting from a fresh DB

CALL add_department(0, 'Backend');
CALL add_department(1, 'Frontend');
CALL add_department(2, 'HR');
CALL add_department(3, 'Facilities');
CALL add_department(4, 'Security');
CALL add_department(5, 'Finance');
CALL add_department(6, 'Marketing');
CALL add_department(7, 'Research');
CALL add_department(8, 'Audit');
CALL add_department(9, 'Operations');


DELETE FROM Employees;

CALL add_employee('Ong Wei Sheng', 'Junior', 0, 91799746, NULL, NULL);
CALL add_employee('Hiong Kai Han', 'Senior', 1, 81866942, NULL, NULL);
CALL add_employee('Damien Lim Yu Hao', 'Manager', 2, 00000000, NULL, NULL);
CALL add_employee('Tan Le Jun', 'Manager', 3, 00000001, NULL, NULL);


DELETE FROM meetingRooms;
DELETE FROM locatedIn;
DELETE FROM Updates;

--Need to add one by one cause of some bug
CALL add_room(1, 1, 'firstRoom', 5, 3, 2);
CALL add_room(1, 2, 'secondRoom', 5, 3, 2);
CALL add_room(1, 3, 'thirdRoom', 5, 3, 2);
CALL add_room(2, 1, 'forthRoom', 5, 4, 3);
CALL add_room(2, 2, 'fifthRoom', 5, 4, 3);
CALL add_room(2, 3, 'sixthRoom', 5, 4, 3);

DELETE FROM Sessions

-- Creating one proper meeting
CALL book_room(1, 1, '2021-10-29', 0, 1, 2);
-- Haven't merge join meeting yet
-- Approve meeting here

CALL book_room(1, 2, '2021-10-29', 1, 3, 3);
-- Haven't merge join meeting yet
-- Approve meeting here

CALL book_room(1, 3, '2021-10-29', 3, 6, 4);
-- Haven't merge join meeting yet
-- Approve meeting here

CALL book_room(2, 1, '2021-10-29', 6, 7, 2);
-- Haven't merge join meeting yet
-- Approve meeting here

CALL book_room(2, 2, '2021-10-29', 7, 9, 3);
-- Haven't merge join meeting yet
-- Approve meeting here

CALL book_room(2, 3, '2021-10-29', 9, 12, 4);
-- Haven't merge join meeting yet
-- Approve meeting here