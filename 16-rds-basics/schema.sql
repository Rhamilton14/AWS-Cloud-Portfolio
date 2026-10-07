-- Run after connecting: mysql -h <endpoint> -u admin -p
CREATE DATABASE cloudcolosseum;
USE cloudcolosseum;

CREATE TABLE students (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100),
  enrolled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

SHOW TABLES;
DESCRIBE students;
