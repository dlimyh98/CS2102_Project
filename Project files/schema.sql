CREATE TABLE Sessions (
    room INTEGER,
    floor INTEGER,
    date DATE,
    time TIME WITHOUT TIME ZONE, /* Not sure what data type to use */
    PRIMARY KEY (room, floor, date, time),
    FOREIGN KEY (room) REFERENCES meetingRooms (room) ON DELETE CASCADE,
    FOREIGN KEY (floor) REFERENCES meetingRooms (floor) ON DELETE CASCADE,
);

CREATE TABLE Approves (
    managerID INTEGER,
    room INTEGER,
    floor INTEGER,
    date DATE,
    time TIME WITHOUT TIME ZONE,
    PRIMARY KEY (room, floor, date, time),
    FOREIGN KEY (managerID) REFERENCES Manager (managerID),
    FOREIGN KEY (room) REFERENCES Sessions (room) ON DELETE CASCADE,
    FOREIGN KEY (floor) REFERENCES Sessions (floor) ON DELETE CASCADE,
    FOREIGN KEY (date) REFERENCES Sessions (date) ON DELETE CASCADE,
    FOREIGN KEY (time) REFERENCES Sessions (time) ON DELETE CASCADE,
);

CREATE TABLE Books (
    bookerID INTEGER NOT NULL,
    room INTEGER,
    floor INTEGER,
    date DATE,
    time TIME WITHOUT TIME ZONE,
    PRIMARY KEY (room, floor, date, time),
    FOREIGN KEY (bookerID) REFERENCES Booker (bookerID) ON DELETE CASCADE,
    FOREIGN KEY (room) REFERENCES Sessions (room) ON DELETE CASCADE,
    FOREIGN KEY (floor) REFERENCES Sessions (floor) ON DELETE CASCADE,
    FOREIGN KEY (date) REFERENCES Sessions (date) ON DELETE CASCADE,
    FOREIGN KEY (time) REFERENCES Sessions (time) ON DELETE CASCADE,
);

CREATE TABLE Joins (
    eid INTEGER NOT NULL,
    room INTEGER,
    floor INTEGER,
    date DATE,
    time TIME WITHOUT TIME ZONE,
    PRIMARY KEY (eid, room, floor, date, time),
    FOREIGN KEY (eid) REFERENCES Employees (eid) ON DELETE CASCADE,
    FOREIGN KEY (room) REFERENCES Sessions (room) ON DELETE CASCADE,
    FOREIGN KEY (floor) REFERENCES Sessions (floor) ON DELETE CASCADE,
    FOREIGN KEY (date) REFERENCES Sessions (date) ON DELETE CASCADE,
    FOREIGN KEY (time) REFERENCES Sessions (time) ON DELETE CASCADE,

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
	FOREIGN KEY (room, floor) REFERENCES meetingRooms (room, floor),
	FOREIGN KEY (did) REFERENCES Departments (did)
);

CREATE TABLE Updates (
	date DATE DEFAULT '1001-01-01',
	new_cap INTEGER NOT NULL 
		CHECK (new_cap >= 0),
	room INTEGER,
	floor INTEGER,
	PRIMARY KEY (date, room, floor),
	FOREIGN KEY (room, floor) REFERENCES meetingRooms (room, floor)
);