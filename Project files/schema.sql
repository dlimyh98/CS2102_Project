DROP TABLE IF EXISTS
    meetingRooms, locatedIn, Updates CASCADE;

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