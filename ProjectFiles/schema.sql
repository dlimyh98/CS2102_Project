CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
DROP TRIGGER IF EXISTS unique_email ON Employees CASCADE;
DROP TRIGGER IF EXISTS check_Employee_has_Department ON Employees CASCADE;
DROP TRIGGER IF EXISTS check_Employee_ISA_covering ON Employees CASCADE;
DROP TRIGGER IF EXISTS check_Booker_ISA_covering ON Booker CASCADE;
DROP TRIGGER IF EXISTS check_Sessions_to_Books ON Sessions CASCADE;
DROP TRIGGER IF EXISTS check_Sessions_to_Joins ON Sessions CASCADE;
DROP TRIGGER IF EXISTS insert_Junior_ISA_overlap_check ON Junior CASCADE;
DROP TRIGGER IF EXISTS insert_Booker_ISA_overlap_check ON Booker CASCADE;
DROP TRIGGER IF EXISTS insert_Manager_ISA_overlap_check ON Manager CASCADE;
DROP TRIGGER IF EXISTS insert_Senior_ISA_overlap_check ON Senior CASCADE;
DROP TRIGGER IF EXISTS employee_resign ON Employees CASCADE;
DROP TRIGGER IF EXISTS check_sessions_availability ON Sessions CASCADE;
DROP TRIGGER IF EXISTS booker_joins_booked_room ON Books CASCADE;
DROP TRIGGER IF EXISTS approve_bookings ON Approves CASCADE;
DROP TRIGGER IF EXISTS change_capacity_remove_bookings ON Updates CASCADE;
DROP TRIGGER IF EXISTS join_meeting_availability ON Joins CASCADE;
DROP TRIGGER IF EXISTS declare_health_check ON healthDeclaration CASCADE;
DROP TRIGGER IF EXISTS check_MeetingRoom_has_Department ON MeetingRooms CASCADE;
DROP TRIGGER IF EXISTS check_MeetingRoom_has_Capacity ON MeetingRooms CASCADE;
DROP TABLE IF EXISTS Approves CASCADE;
DROP TABLE IF EXISTS Books CASCADE;
DROP TABLE IF EXISTS Joins CASCADE;
DROP TABLE IF EXISTS Sessions CASCADE;
DROP TABLE IF EXISTS Updates CASCADE;
DROP TABLE IF EXISTS locatedIn CASCADE;
DROP TABLE IF EXISTS meetingRooms CASCADE;
DROP TABLE IF EXISTS Junior CASCADE;
DROP TABLE IF EXISTS Senior CASCADE;
DROP TABLE IF EXISTS Manager CASCADE;
DROP TABLE IF EXISTS Booker CASCADE;
DROP TABLE IF EXISTS healthDeclaration CASCADE;
DROP TABLE IF EXISTS worksIn CASCADE;
DROP TABLE IF EXISTS Employees CASCADE;
DROP TABLE IF EXISTS Departments CASCADE;
DROP FUNCTION IF EXISTS gen_unique_email CASCADE;
DROP FUNCTION IF EXISTS check_Employee_has_Department_func CASCADE;
DROP FUNCTION IF EXISTS check_Employee_ISA_covering_func CASCADE;
DROP FUNCTION IF EXISTS check_Booker_ISA_covering_func CASCADE;
DROP FUNCTION IF EXISTS Junior_Booker_ISA_overlap_func CASCADE;
DROP FUNCTION IF EXISTS Senior_Manager_ISA_overlap_func CASCADE;
DROP FUNCTION IF EXISTS employee_resign_func CASCADE;
DROP FUNCTION IF EXISTS check_sessions_availability_func CASCADE;
DROP FUNCTION IF EXISTS booker_joins_booked_room_func CASCADE;
DROP FUNCTION IF EXISTS check_Sessions_to_Books_func CASCADE;
DROP FUNCTION IF EXISTS check_Sessions_to_Joins_func CASCADE;
DROP FUNCTION IF EXISTS approve_bookings_func CASCADE;
DROP FUNCTION IF EXISTS change_capacity_remove_bookings_func CASCADE;
DROP FUNCTION IF EXISTS join_meeting_availability_func CASCADE;
DROP FUNCTION IF EXISTS declare_health_check_func CASCADE;
DROP FUNCTION IF EXISTS check_MeetingRoom_has_Department_func CASCADE;
DROP FUNCTION IF EXISTS check_MeetingRoom_has_Capacity_func CASCADE;
DROP PROCEDURE IF EXISTS add_employee CASCADE;
DROP PROCEDURE IF EXISTS add_department CASCADE;
DROP PROCEDURE IF EXISTS add_room CASCADE;
DROP PROCEDURE IF EXISTS remove_employee CASCADE;
DROP PROCEDURE IF EXISTS book_room CASCADE;
DROP PROCEDURE IF EXISTS remove_department CASCADE;
DROP PROCEDURE IF EXISTS declare_health CASCADE;
DROP PROCEDURE IF EXISTS approve_meeting CASCADE;
DROP PROCEDURE IF EXISTS change_capacity CASCADE;
DROP PROCEDURE IF EXISTS unbook_room CASCADE;
DROP PROCEDURE IF EXISTS join_meeting CASCADE;
DROP PROCEDURE IF EXISTS leave_meeting CASCADE;
DROP FUNCTION IF EXISTS contact_tracing CASCADE;
DROP FUNCTION IF EXISTS search_room CASCADE;
DROP FUNCTION IF EXISTS view_manager_report CASCADE;
DROP FUNCTION IF EXISTS view_future_meeting CASCADE;
DROP FUNCTION IF EXISTS non_compliance CASCADE;
DROP FUNCTION IF EXISTS view_booking_report CASCADE;


CREATE TABLE Employees (
    eid BIGSERIAL,
    ename TEXT NOT NULL,
    mobilePhoneContact NUMERIC(8) NOT NULL UNIQUE,
    homePhoneContact NUMERIC(8),
    officePhoneContact NUMERIC(8),
    email TEXT NOT NULL UNIQUE,
    resignedDate DATE DEFAULT '1001-01-01',
    isResigned BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (eid)
);

CREATE TABLE Junior (
    juniorID INTEGER,
    PRIMARY KEY (juniorID),
    FOREIGN KEY (juniorID) REFERENCES Employees (eid) ON DELETE CASCADE
);

CREATE TABLE Booker (
    bookerID INTEGER,
    PRIMARY KEY (bookerID),
    FOREIGN KEY (bookerID) REFERENCES Employees (eid) ON DELETE CASCADE
);
CREATE TABLE Senior (
    seniorID INTEGER,
    PRIMARY KEY (seniorID),
    FOREIGN KEY (seniorID) REFERENCES Booker (bookerID) ON DELETE CASCADE
);

CREATE TABLE Manager (
    managerID INTEGER,
    PRIMARY KEY (managerID),
    FOREIGN KEY (managerID) REFERENCES Booker (bookerID) ON DELETE CASCADE
);

CREATE TABLE healthDeclaration (
    date DATE NOT NULL,
    temp NUMERIC(3,1) NOT NULL CHECK (34.0 <= temp AND temp <= 43.0),
    fever BOOLEAN,
    eid INTEGER,
    PRIMARY KEY (date, eid),
    FOREIGN KEY (eid) REFERENCES Employees (eid) ON DELETE CASCADE
);

CREATE TABLE Departments (
    did INTEGER,
    dname TEXT NOT NULL,
    PRIMARY KEY (did)
);

CREATE TABLE worksIn (
    eid INTEGER,
    did INTEGER,
    PRIMARY KEY (eid),
    FOREIGN KEY (eid) REFERENCES Employees (eid),
    FOREIGN KEY (did) REFERENCES Departments (did)
);

CREATE TABLE meetingRooms (
	room INTEGER,
	floor INTEGER,
	rname TEXT NOT NULL,
	PRIMARY KEY (room, floor)
);

CREATE TABLE locatedIn (
	room INTEGER,
	floor INTEGER,
	did INTEGER NOT NULL,
	PRIMARY KEY (room, floor),
	FOREIGN KEY (room, floor) REFERENCES meetingRooms (room, floor) ON DELETE CASCADE,
	FOREIGN KEY (did) REFERENCES Departments (did)
);

CREATE TABLE Updates (
    managerID INTEGER,
	date DATE DEFAULT '1001-01-01',
	newCap INTEGER NOT NULL CHECK (newCap >= 0),
	room INTEGER,
	floor INTEGER,
	PRIMARY KEY (date, room, floor),
	FOREIGN KEY (room, floor) REFERENCES meetingRooms (room, floor) ON DELETE CASCADE,
    FOREIGN KEY (managerID) REFERENCES Manager (managerID) 
);

CREATE TABLE Sessions (
    room INTEGER,
    floor INTEGER,
    date DATE,
    time INTEGER CHECK (time>=0 AND time<24),
    PRIMARY KEY (room, floor, date, time),
    FOREIGN KEY (room, floor) REFERENCES meetingRooms (room,floor) ON DELETE CASCADE
);

CREATE TABLE Approves (
    managerID INTEGER,
    room INTEGER,
    floor INTEGER,
    date DATE,
    time INTEGER CHECK (time>=0 AND time<24),
    PRIMARY KEY (room, floor, date, time),
    FOREIGN KEY (managerID) REFERENCES Manager (managerID),
    FOREIGN KEY (room, floor, date, time) REFERENCES Sessions (room, floor, date, time) ON DELETE CASCADE
);

CREATE TABLE Books (
    bookerID INTEGER NOT NULL,
    room INTEGER,
    floor INTEGER,
    date DATE,
    time INTEGER CHECK (time>=0 AND time<24),
    approveStatus INTEGER DEFAULT 0 CHECK (approveStatus >= 0 AND approveStatus <= 2),
    /* 0 -> pending approval, 1 -> disapproved, 2 -> approved */
    PRIMARY KEY (room, floor, date, time),
    FOREIGN KEY (bookerID) REFERENCES Booker (bookerID) ON DELETE CASCADE,
    FOREIGN KEY (room, floor, date, time) REFERENCES Sessions (room, floor, date, time) ON DELETE CASCADE
);

CREATE TABLE Joins (
    eid INTEGER NOT NULL,
    room INTEGER,
    floor INTEGER,
    date DATE,
    time INTEGER CHECK (time>=0 AND time<24),
    PRIMARY KEY (eid, room, floor, date, time),
    FOREIGN KEY (eid) REFERENCES Employees (eid) ON DELETE CASCADE,
    FOREIGN KEY (room, floor, date, time) REFERENCES Sessions (room, floor, date, time) ON DELETE CASCADE
);
