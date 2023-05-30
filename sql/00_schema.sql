CREATE TABLE IF NOT EXISTS "string" (
	"identifier"	TEXT,
	"string_en"	TEXT,
	PRIMARY KEY("identifier")
);
CREATE TABLE IF NOT EXISTS "user" (
	"id"	INTEGER PRIMARY KEY AUTOINCREMENT,
	"telegram_id"	TEXT,
	"telegram_username"	TEXT,
	"banned"	INTEGER DEFAULT 0,
	"admin"	INTEGER DEFAULT 0,
	"privacy_contact" INTEGER DEFAULT 0,
	"seen_intro"  INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS "request" (
	"id"	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
	"sender"	INTEGER NOT NULL,
	"text"	TEXT,
	"received"	INTEGER NOT NULL,
	"responded"	INTEGER NOT NULL DEFAULT 0,
	FOREIGN KEY (sender) REFERENCES user(id)
);