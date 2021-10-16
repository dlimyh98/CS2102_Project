CREATE TABLE Employees (
    eid INTEGER,
    ename TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    homePhoneContact TEXT NOT NULL,
    mobilePhoneContact TEXT NOT NULL,
    officePhoneContact TEXT NOT NULL,
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
