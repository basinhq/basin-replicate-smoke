CREATE DATABASE `${mysql_database}`;

CREATE TABLE `${mysql_database}`.orders (
    id bigint PRIMARY KEY,
    note varchar(200) NOT NULL,
    updated datetime NOT NULL
);
