-- Wipes all rows from all tables (but still keeps schema intact)
-- Reset Employee BIG SERIAL to 1
do
$$
declare
  l_stmt text;
begin
  select 'truncate ' || string_agg(format('%I.%I', schemaname, tablename), ',')
    into l_stmt
  from pg_tables
  where schemaname in ('public');

  execute l_stmt;
end;
$$;
ALTER SEQUENCE employees_eid_seq RESTART WITH 1;


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


CALL add_employee('Ong Wei Sheng', 'Junior', 0, 91799746, NULL, NULL);
CALL add_employee('Jair Bates', 'Senior', 0, 98571827, 63830012, 96307738);
CALL add_employee('Yael Morrison', 'Junior', 1, 97591342, NULL, 97076933);
CALL add_employee('Abby Schmitt', 'Senior', 1, 90675128, 68110273, NULL);
CALL add_employee('Jason Peterson', 'Senior', 2, 81629921, 62910937, 87217831);
CALL add_employee('Charlie White', 'Manager', 2, 85916632, NULL, 97217361);
CALL add_employee('Hiong Kai Han', 'Junior', 3, 90867725, 64912382, 81923716);
CALL add_employee('Peter Larsen', 'Manager', 3, 90768862, 64018764, 93721028);
CALL add_employee('Rohan Schmidt', 'Manager', 3, 89007652, 64018764, 92842203);
CALL add_employee('Felix Walters', 'Junior', 4, 90877651, NULL, 93201294);
CALL add_employee('Rayna Johnson', 'Junior', 4, 93647320, 64729182, 88320123);
CALL add_employee('Damien Lim Yu Hao', 'Manager', 5, 91440293, NULL, 84938273);
CALL add_employee('Bernie Sanders', 'Junior', 5, 99830204, NULL, 94028172);
CALL add_employee('Andrea Sanders', 'Manager', 6, 80109828, NULL, NULL);
CALL add_employee('Tom Cruise', 'Junior', 7, 98980127, 64918283, NULL);
CALL add_employee('Tan Le Jun', 'Manager', 7, 94821049, NULL, 84921200);
CALL add_employee('Bobby Shmurda', 'Senior', 8, 94721204, NULL, NULL);
CALL add_employee('George Lee', 'Manager', 9, 90192837, NULL, NULL);
CALL add_employee('Freddy Ramirez', 'Junior', 3, 94819023, NULL, 84910231);
CALL add_employee('Branson McGuire', 'Junior', 8, 92010238, NULL, 8741277);
CALL add_employee('Valery Michael', 'Junior', 4, 92018471, 60981033, 9394214);
CALL add_employee('Eden Sullivan', 'Manager', 0, 99098721, NULL, NULL);
CALL add_employee('Willow Riley', 'Manager', 1, 96721391, 60229375, NULL);
CALL add_employee('Pablo Escobar', 'Manager', 8, 84920190, NULL, NULL);
CALL add_employee('Zayden Vega', 'Senior', 0, 90988123, NULL, NULL);
CALL add_employee('Krillin', 'Senior', 7, 98280001, NULL, 87110932);
CALL add_employee('Damari Booker', 'Senior', 3, 85904741, 62101194, 84975501);
CALL add_employee('Drew House', 'Senior', 4, 80918243, NULL, 94231780);
CALL add_employee('Cassius Clay', 'Senior', 9, 99120912, NULL, NULL);
CALL add_employee('Alvaro Daniels', 'Senior', 9, 91029514, NULL, NULL);


CALL add_room(1, 1, 'Noggin Chamber', 5, 6);
CALL add_room(1, 2, 'Cranium Focus', 7, 8);
CALL add_room(1, 3, 'Ideation Zone', 7, 8);
CALL add_room(2, 1, 'Team Territory', 10, 9);
CALL add_room(2, 2, 'Creative Arena', 5, 18);
CALL add_room(2, 3, 'Inspiration Station', 6, 14);
CALL add_room(3, 1, 'Learning Loft', 11, 14);
CALL add_room(3, 2, 'Crown Down', 5, 6);
CALL add_room(3, 3, 'Alpha Mind', 5, 6);
CALL add_room(4, 1, 'Discussion Hub', 5, 8);

CALL book_room(1, 1, '2022-10-29', 0, 3, 5);
CALL book_room(1, 1, '2022-10-29', 7, 8, 5);
CALL book_room(1, 2, '2022-10-30', 11, 14, 8);
CALL book_room(1, 3, '2022-10-30', 10, 13, 9);
CALL book_room(2, 1, '2022-10-30', 15, 17, 9);
CALL book_room(2, 2, '2022-10-29', 7, 10, 29);
CALL book_room(3, 1, '2022-10-29', 18, 23, 14);
CALL book_room(3, 1, '2022-10-30', 4, 9, 14);
CALL book_room(3, 3, '2022-10-29', 19, 21, 5);
CALL book_room(4, 1, '2022-10-29', 2, 4, 9);
CALL book_room(4, 1, '2022-10-29', 14, 16, 9);

CALL join_meeting(1, 1, '2022-10-29', 0, 3, 12);
CALL join_meeting(1, 1, '2022-10-29', 0, 3, 13);
CALL join_meeting(1, 1, '2022-10-29', 0, 3, 14);
CALL join_meeting(1, 1, '2022-10-29', 0, 2, 15);
CALL join_meeting(1, 1, '2022-10-29', 2, 3, 16);

CALL join_meeting(1, 2, '2022-10-30', 11, 12, 4);

CALL approve_meeting(1, 1, '2022-10-29', 0, 3, 6);
CALL approve_meeting (1, 2, '2022-10-30', 12, 13, 8);
CALL approve_meeting (2, 1, '2022-10-30', 15, 17, 9);
CALL approve_meeting (2, 2, '2022-10-29', 8, 10, 18);
CALL approve_meeting (3, 1, '2022-10-29', 18, 20, 14);
CALL approve_meeting (3, 1, '2022-10-30', 4, 9, 14);
CALL approve_meeting (3, 3, '2022-10-29', 19, 21, 6);
CALL approve_meeting (4, 1, '2022-10-29', 14, 16, 8);

CALL declare_health(1, '2022-10-24', 36.0);
CALL declare_health(1, '2022-10-25', 37.1);
CALL declare_health(1, '2022-10-26', 36.2);
CALL declare_health(1, '2022-10-27', 36.7);
CALL declare_health(1, '2022-10-28', 37.0);
CALL declare_health(1, '2022-10-29', 36.6);
CALL declare_health(1, '2022-10-30', 36.9);
CALL declare_health(1, '2022-10-31', 36.8);
CALL declare_health(1, '2022-11-01', 36.3);
CALL declare_health(1, '2022-11-02', 36.5);

CALL declare_health(2, '2022-10-24', 36.3);
CALL declare_health(2, '2022-10-25', 37.2);
CALL declare_health(2, '2022-10-26', 36.5);
CALL declare_health(2, '2022-10-27', 36.6);
CALL declare_health(2, '2022-10-28', 37.0);
CALL declare_health(2, '2022-10-29', 36.2);
CALL declare_health(2, '2022-10-30', 36.4);

CALL declare_health(3, '2022-10-24', 36.2);
CALL declare_health(3, '2022-10-25', 36.3);
CALL declare_health(3, '2022-10-26', 36.1);

CALL declare_health(4, '2022-10-24', 36.7);
CALL declare_health(4, '2022-10-25', 37.3);
CALL declare_health(4, '2022-10-26', 36.6);
CALL declare_health(4, '2022-10-27', 36.8);
CALL declare_health(4, '2022-10-28', 37.4);
CALL declare_health(4, '2022-10-29', 36.9);
