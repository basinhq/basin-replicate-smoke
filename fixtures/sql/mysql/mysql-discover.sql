CREATE DATABASE `${mysql_database}`;

CREATE TABLE `${mysql_database}`.orders (
    id bigint unsigned PRIMARY KEY,
    amount decimal(10, 2),
    note varchar(64)
);

CREATE TABLE `${mysql_database}`.audit (
    ts datetime NOT NULL,
    message text
);

CREATE TABLE `${mysql_database}`.geo (
    id bigint PRIMARY KEY,
    shape geometry NOT NULL
);
