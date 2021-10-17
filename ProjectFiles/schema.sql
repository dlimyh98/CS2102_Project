CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE Employees (
    eid BIGSERIAL,
    ename TEXT NOT NULL,
    mobilePhoneContact NUMERIC(8) NOT NULL UNIQUE,
    homePhoneContact NUMERIC(8),
    officePhoneContact NUMERIC(8),
    email TEXT UNIQUE,
    resignedDate DATE DEFAULT '1001-01-01',
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
    fever BOOLEAN CHECK ((temp > 37.5 AND fever = TRUE) OR (temp <= 37.5 AND fever = FALSE)),
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
	date DATE DEFAULT '1001-01-01',
	new_cap INTEGER NOT NULL 
		CHECK (new_cap >= 0),
	room INTEGER,
	floor INTEGER,
	PRIMARY KEY (date, room, floor),
	FOREIGN KEY (room, floor) REFERENCES meetingRooms (room, floor) ON DELETE CASCADE
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
