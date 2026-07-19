CREATE DATABASE `${mysql_database}`;

CREATE TABLE `${mysql_database}`.customers (
    id bigint PRIMARY KEY,
    name varchar(100) NOT NULL,
    region varchar(20) NOT NULL
);

CREATE TABLE `${mysql_database}`.order_items (
    order_id integer NOT NULL,
    line_no integer NOT NULL,
    sku varchar(40) NOT NULL,
    qty integer NOT NULL,
    PRIMARY KEY (order_id, line_no)
);

INSERT INTO `${mysql_database}`.customers (id, name, region) VALUES
    (1, 'Ada', 'emea'),
    (2, 'Bela', 'apac'),
    (3, 'Chidi', 'amer');

INSERT INTO `${mysql_database}`.order_items (order_id, line_no, sku, qty) VALUES
    (100, 1, 'sku-a', 2),
    (100, 2, 'sku-b', 1),
    (101, 1, 'sku-c', 5);
